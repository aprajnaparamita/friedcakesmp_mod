-- FriedcakeSMP — smp_stats / test.lua
-- In-game test suite (run by /smp test once the generic loader lands;
-- also executed headlessly by dev-tests/test_stats.lua).
-- Covers f14 §9 T6/T7/T8/T9 at the pure-function level; the hook-driven
-- tests (T1–T5, T10, T11) live in dev-tests/test_stats.lua, which
-- drives the real handlers over a stubbed engine.
-- Pure checks: no store mutation, no HUD, safe to run at any time.

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
		results.lines[#results.lines + 1] = "ok   " .. msg
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. msg
	end
	return cond
end

local function eq(got, want, msg)
	return ok(got == want, msg .. " (got " .. tostring(got)
		.. ", want " .. tostring(want) .. ")")
end

----------------------------------------------------------------------
-- T6: the third money convention — lower-case suffix, no `$`,
-- dollars with cents below $1,000.
do
	eq(smp_stats.fmt_scoreboard(75400000), "754k", "T6 F0287 reading 754k")
	eq(smp_stats.fmt_scoreboard(72300000), "723k", "T6 F0055 reading 723k")
	eq(smp_stats.fmt_scoreboard(120000000000), "1.2b", "T6 lower-case b")
	eq(smp_stats.fmt_scoreboard(1500000), "15k", "T6 $15k -> 15k")
	eq(smp_stats.fmt_scoreboard(100000000), "1m", "T6 trailing .0 stripped")
	eq(smp_stats.fmt_scoreboard(700), "7", "T6 whole dollars, no suffix")
	eq(smp_stats.fmt_scoreboard(550), "5.50", "T6 cents below $1")
	eq(smp_stats.fmt_scoreboard(150), "1.50", "T6 $1.50 -> 1.50")
	eq(smp_stats.fmt_scoreboard(0), "0", "T6 zero")
	eq(smp_stats.fmt_scoreboard(-500), "0", "T6 never negative")
	-- The HUD combines title + `$ ` + readout; no `$` inside fmt.
	local sample = smp_stats.fmt_scoreboard(75400000)
	ok(not sample:find("%$"), "T6 formatter carries no `$` (HUD adds it)")
	ok(type(smp_stats.hud_text) == "function",
		"hud_text exposed for the HUD seam")
end

----------------------------------------------------------------------
-- T7: the ten official categories, §4.2.1 order, exact key set.
do
	local WANT = {
		"brokenblocks", "deaths", "kills", "mobskilled", "money",
		"placedblocks", "playtime", "sell", "shards", "shop",
	}
	eq(#smp_stats.CATEGORIES, 10, "T7 exactly ten categories")
	for i, key in ipairs(WANT) do
		eq(smp_stats.CATEGORIES[i].key, key, "T7 category " .. i .. " key")
	end
	-- Every category has a claim-listed display label.
	local LABELS = {
		"Broken Blocks", "Deaths", "Kills", "Mob Kills", "Money",
		"Placed Blocks", "Playtime", "Money from Selling", "Shards",
		"Spent in Shop",
	}
	for i, label in ipairs(LABELS) do
		eq(smp_stats.CATEGORIES[i].label, label,
			"T7 category " .. i .. " label")
	end
end

----------------------------------------------------------------------
-- T8/T9: build_from — partial top-N ordering, cap, tie-break, offline
-- records, money/shards/sell/shop getters.
do
	local records = {
		{ name = "alice", money = 5000, shards = 3,
		  stats = { kills = 7, money_made_from_sell = 250 } },
		{ name = "bob",   money = 9000, shards = 3,
		  stats = { kills = 7, money_spent_on_shop = 100 } },
		{ name = "carl",  money = 1000, shards = 9, playtime = 60,
		  stats = { broken_blocks = 42 } },
	}
	local boards = smp_stats.build_from(records, 100)

	-- money desc; tie-free here
	eq(boards.money[1].name, "bob", "T8 money board top is bob")
	eq(boards.money[1].value, 9000, "T8 money board top value")
	eq(boards.money[3].name, "carl", "T8 money board bottom")
	eq(#boards.money, 3, "T8 every record lands on the board (T9: offline")
	-- records are just records — nobody needs to be online)

	-- kills: 7/7 tie -> name ascending
	eq(boards.kills[1].name, "alice", "T8 tie broken by name ascending")
	eq(boards.kills[2].name, "bob", "T8 tie keeps both")
	eq(boards.kills[3].value, 0, "T8 non-scorers rank with 0")

	-- the official sell/shop keys read the two economy counters
	eq(boards.sell[1].name, "alice", "T7 sell reads money_made_from_sell")
	eq(boards.sell[1].value, 250, "T7 sell value")
	eq(boards.shop[1].name, "bob", "T7 shop reads money_spent_on_shop")
	eq(boards.shop[1].value, 100, "T7 shop value")

	-- shards + playtime + brokenblocks
	eq(boards.shards[1].name, "carl", "T7 shards board")
	eq(boards.playtime[1].name, "carl", "T7 playtime board")
	eq(boards.brokenblocks[1].value, 42, "T7 brokenblocks board")
	eq(boards.mobskilled[1].value, 0, "T7 mobskilled board defaults 0")

	-- pending playtime counts toward the playtime board (unflushed
	-- seconds must not vanish from a reader's point of view)
	local saved_pending = smp_stats._pending_playtime
	smp_stats._pending_playtime = { alice = 30 }
	local boards2 = smp_stats.build_from(records, 100)
	eq(boards2.playtime[1].name, "carl", "stored playtime still ranks first")
	eq(boards2.playtime[2].name, "alice", "pending playtime ranks alice")
	eq(boards2.playtime[2].value, 30, "pending seconds added to 0 stored")
	smp_stats._pending_playtime = saved_pending

	-- cap: size 2 keeps the two best, no more
	local boards3 = smp_stats.build_from(records, 2)
	eq(#boards3.money, 2, "T8 board capped at leaderboards.size")
	eq(boards3.money[1].name, "bob", "T8 cap keeps the best")

	-- larger randomized set: sorted desc, capped, under the T8 budget
	math.randomseed(42)
	local big = {}
	for i = 1, 10000 do
		big[i] = {
			name = string.format("player%05d", i),
			money = math.random(0, 1000000000000),
			shards = math.random(0, 10000),
			playtime = math.random(0, 1000000),
			stats = {
				kills = math.random(0, 10000),
				deaths = math.random(0, 10000),
				mobs_killed = math.random(0, 10000),
				broken_blocks = math.random(0, 1000000),
				placed_blocks = math.random(0, 1000000),
				money_made_from_sell = math.random(0, 1000000000),
				money_spent_on_shop = math.random(0, 1000000000),
			},
		}
	end
	local t0 = os.clock()
	local big_boards = smp_stats.build_from(big, 100)
	local dt = os.clock() - t0
	ok(dt < 0.05, string.format(
		"T8 10,000 records rebuild in <50 ms (took %.1f ms)", dt * 1000))
	eq(#big_boards.money, 100, "T8 10k -> top 100 only")
	local sorted = true
	for i = 2, 100 do
		local a, b = big_boards.money[i - 1], big_boards.money[i]
		if a.value < b.value
		   or (a.value == b.value and a.name > b.name) then
			sorted = false
		end
	end
	ok(sorted, "T8 board sorted desc, ties by name")
end

----------------------------------------------------------------------
-- Paging (§4.2.4): 10 rows, clamped.
do
	local board = {}
	for i = 1, 25 do board[i] = { name = "p" .. i, value = 26 - i } end
	local rows, page, pages = smp_stats.board_page(board, 1)
	eq(#rows, 10, "page 1 holds 10 rows")
	eq(page, 1, "page 1 is page 1")
	eq(pages, 3, "25 rows -> 3 pages")
	rows = smp_stats.board_page(board, 99)
	local _, clamped = smp_stats.board_page(board, 99)
	eq(clamped, 3, "page clamps to the last page")
	eq(#rows, 5, "last page holds the remainder")
	rows = smp_stats.board_page(board, 0)
	local _, p0 = smp_stats.board_page(board, 0)
	eq(p0, 1, "page clamps to 1")
	local _, _, ep = smp_stats.board_page({}, 1)
	eq(ep, 1, "empty board is one (empty) page")
end

----------------------------------------------------------------------
-- Public surface contracts: name-or-player normalisation (f05 passes
-- an ObjectRef, f10 a name) and the fcsmp_ key form (T10).
do
	eq(smp_stats.name_of("alice"), "alice", "name_of accepts a name")
	eq(smp_stats.name_of(""), nil, "name_of rejects the empty string")
	eq(smp_stats.name_of(42), nil, "name_of rejects a number")
	local ref = { is_player = function() return true end,
		get_player_name = function() return "alice" end }
	eq(smp_stats.name_of(ref), "alice", "name_of accepts an ObjectRef")
	local not_player = { get_player_name = function() return "ghost" end }
	eq(smp_stats.name_of(not_player), nil,
		"name_of rejects a non-player table")

	local key = smp_stats.api.make_key("alice")
	ok(key:match("^fcsmp_[0-9a-f]+$") ~= nil,
		"T10 key is fcsmp_ + sha1 hex (got " .. tostring(key) .. ")")
	eq(#key, 6 + 40, "T10 key is 46 chars")
	local key2 = smp_stats.api.make_key("alice")
	ok(key2 ~= key, "T10 keys are unique per call")
end

return results
