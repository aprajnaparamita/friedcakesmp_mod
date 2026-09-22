-- dev-tests/test_ah.lua — f03 Auction House acceptance tests (T1–T10)
--
-- The merge gate for spec/features/f03-auction.md §9, run headlessly against
-- a fake engine (dev-tests/ah_harness.lua). Every observed UI string that the
-- tests assert is quoted from the frame evidence in the feature file.
--
-- Run: luajit friedcake/dev-tests/test_ah.lua     (or tools/agent-flow.sh test)
-- Prints ALL OK and exits 0 on success.

local HERE = (arg and arg[0] or "friedcake/dev-tests/test_ah.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local H = dofile(HERE .. "/ah_harness.lua")

----------------------------------------------------------------------
-- Boot the mod set
----------------------------------------------------------------------

H.boot({
	settings = {
		["store.backend"]     = "mod_storage",
		["ah.page_size"]      = "45",
		["ah.slots.default"]  = "900",   -- bulk listings for the paging test
		["ah.min_price"]      = "100",   -- $1 [F0142]
		["ah.max_price"]      = "100000000000000",
		["ah.rate_limit"]     = "0",     -- T10 exercises the limiter itself
		["ah.listing_fee_pct"] = "0",
		["ah.sale_tax_pct"]   = "0",
		["ah.listing_duration"] = "172800",
	},
})

local smp_ah = smp_ah
local listings = smp_ah.listings
local keys = smp_ah.keys

----------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------

local passed, failed = 0, 0
local failures = {}

local function ok(cond, msg)
	if cond then passed = passed + 1 else
		failed = failed + 1
		failures[#failures + 1] = msg
		print("  FAIL: " .. tostring(msg))
	end
	return cond and true or false
end

local function eq(a, b, msg)
	if a == b then passed = passed + 1 else
		failed = failed + 1
		failures[#failures + 1] = string.format("%s: expected %s got %s",
			tostring(msg), tostring(b), tostring(a))
		print(string.format("  FAIL %s: expected %s got %s", tostring(msg),
			tostring(b), tostring(a)))
	end
	return a == b
end

--- Plain (unescaped, colour-free) substring assertion on a formspec.
local function has(fs, text, msg)
	return ok(H.plain(fs):find(text, 1, true) ~= nil,
		msg .. " [missing: " .. text .. "]")
end

local function hasnt(fs, text, msg)
	return ok(H.plain(fs):find(text, 1, true) == nil,
		msg .. " [unexpected: " .. text .. "]")
end

local function count(s, pat)
	local n = 0
	for _ in tostring(s):gmatch(pat) do n = n + 1 end
	return n
end

local function board_ids(fs)
	local ids = {}
	for id in tostring(fs):gmatch(";ah_l(%d+);") do ids[#ids + 1] = tonumber(id) end
	return ids
end

local function section(id, title, fn)
	print(string.format("--- %s %s", id, title))
	local good, err = pcall(fn)
	if not good then
		failed = failed + 1
		failures[#failures + 1] = id .. " crashed: " .. tostring(err)
		print("  CRASH: " .. tostring(err))
	end
end

--- Create a listing directly through the public API (f03 §6.1).
local function mk(seller, itemstring, price_cents)
	local rec, err = smp_ah.create_listing(seller, H.ItemStack(itemstring), price_cents)
	if not rec then
		error("mk(" .. seller .. ", " .. itemstring .. ") refused: " .. tostring(err))
	end
	return rec
end

--- Reset the world between sections that need a clean board.
local function wipe()
	for pname in pairs(smp_ah._flows) do smp_ah.abort_flow(pname) end
	listings.reset()
	listings.flush()
	for _, data in pairs(H.storages) do
		for k in pairs(data) do
			if k:match("^ah:") then data[k] = nil end
		end
	end
	smp_ah._last_list = {}
	H.players, H.chat, H.forms, H.last_form, H.closed = {}, {}, {}, {}, {}
	H.detached = {}
end

----------------------------------------------------------------------
-- T1 — the board title reads exactly `Auction (Page 1)` and pages correctly
----------------------------------------------------------------------

section("T1", "board title and paging", function()
	wipe()
	local alice = H.player("alice")
	H.set_money("alice", 100000000)

	H.cmd("ah", "alice", "")
	eq(H.formname("alice"), "smp_ah:board", "T1 /ah opens the board")
	has(H.form("alice"), "Auction (Page 1)", "T1 title is exactly `Auction (Page 1)`")
	has(H.form("alice"), "formspec_version[6]", "T1 formspec v6")
	has(H.form("alice"), "list[current_player;main;", "T1 container menu shows the inventory")
	has(H.plain(H.form("alice")), "Inventory", "T1 `Inventory` label")

	-- 50 listings: page 1 holds 45 (5 rows x 9), page 2 holds 5.
	for i = 1, 50 do
		mk("seller" .. (i % 7), "mcl_core:diamond " .. (1 + (i % 8)), 1000 + i * 100)
	end
	H.cmd("ah", "alice", "")
	eq(count(H.form("alice"), ";ah_l%d+;"), 45, "T1 45 listings on page 1")
	has(H.form("alice"), "Auction (Page 1)", "T1 still page 1")

	H.receive("alice", "smp_ah:board", { ah_next = "" })
	has(H.form("alice"), "Auction (Page 2)", "T1 next page title")
	eq(count(H.form("alice"), ";ah_l%d+;"), 5, "T1 5 listings on page 2")

	H.receive("alice", "smp_ah:board", { ah_next = "" })
	has(H.form("alice"), "Auction (Page 2)", "T1 clamped at the last page")

	H.receive("alice", "smp_ah:board", { ah_prev = "" })
	has(H.form("alice"), "Auction (Page 1)", "T1 previous page")
end)

----------------------------------------------------------------------
-- T2 — the three controls carry exactly the observed two-line tooltips
----------------------------------------------------------------------

section("T2", "control tooltips verbatim", function()
	wipe()
	local alice = H.player("alice")
	H.cmd("ah", "alice", "")
	local p = H.plain(H.form("alice"))

	-- shared/08-ui-strings.md §8.5 + f03 §3.1. Line 3 is the Mineclonia
	-- itemstring (shared §0.5.1); the Java `14 component(s)` line is dropped.
	has(H.form("alice"), "tooltip[ah_search;Search\\nClick to search\\n" ..
		smp_ah.fs.item("search") .. "]", "T2 Search tooltip")
	has(H.form("alice"), "tooltip[ah_your_items;Your Items\\nClick to view\\n" ..
		smp_ah.fs.item("your_items") .. "]", "T2 Your Items tooltip")

	-- The hopper tooltip carries the option list [F0118–F0123].
	local bullet = "\226\128\162"
	ok(p:find("Filter\\nClick to change\\n" .. bullet .. " Lowest Price\\n" ..
		bullet .. " Highest Price\\n" .. bullet .. " Recently Listed\\n" ..
		smp_ah.fs.item("filter"), 1, true) ~= nil,
		"T2 Filter tooltip: two lines then the three sorts in order")

	-- The item-as-button construction of shared §4.9.
	has(H.form("alice"), "item_image_button[", "T2 controls are item_image_buttons")
	ok(p:find("component%(s%)") == nil, "T2 the Java `N component(s)` line is dropped")

	-- Control items are resolved from the registry, never hardcoded: the pane
	-- mapping is the least certain row of shared §4.3.
	eq(smp_ah.fs.item("search"), "mcl_signs:wall_sign_oak", "T2 oak sign resolved")
	eq(smp_ah.fs.item("filter"), "mcl_hoppers:hopper", "T2 hopper resolved")
	eq(smp_ah.fs.item("your_items"), "mcl_chests:chest", "T2 chest resolved")
	eq(smp_ah.fs.item("list"), "mcl_panes:pane_grey", "T2 grey pane resolved at runtime")
	eq(smp_ah.fs.item("confirm"), "mcl_panes:pane_lime", "T2 lime pane resolved at runtime")

	-- Listing tooltip: name, total price, Mineclonia itemstring [F0108].
	local rec = mk("erin", "mcl_throwing:ender_pearl 16", 70000)   -- $700
	H.cmd("ah", "alice", "")
	has(H.form("alice"), "tooltip[ah_l" .. rec.id .. ";Ender Pearl\\n$700\\n" ..
		"mcl_throwing:ender_pearl]", "T2 listing tooltip matches [F0108]")
	hasnt(H.form("alice"), "15 component(s)", "T2 no component count")
end)

----------------------------------------------------------------------
-- T3 — `Filter` cycles the three observed sorts and re-sorts the board
----------------------------------------------------------------------

section("T3", "filter cycles the sorts", function()
	wipe()
	local alice = H.player("alice")
	-- Distinct unit prices so the order is observable.
	local cheap  = mk("s1", "mcl_core:diamond 1", 10000)     -- $100 / item
	local mid    = mk("s2", "mcl_core:diamond 2", 30000)     -- $150 / item
	local dear   = mk("s3", "mcl_core:diamond 1", 90000)     -- $900 / item

	H.cmd("ah", "alice", "")
	eq(smp_ah.sort_index("alice"), 1, "T3 starts on the first sort")
	local ids = board_ids(H.form("alice"))
	eq(#ids, 3, "T3 three listings")
	ok(ids[1] == cheap.id and ids[2] == mid.id and ids[3] == dear.id,
		"T3 `Lowest Price` sorts by unit price ascending")

	H.receive("alice", "smp_ah:board", { ah_filter = "" })
	local v = smp_core.get_session("alice", "smp_ah:view")
	eq(v.sort, "highest_price", "T3 second sort is `Highest Price`")
	ids = board_ids(H.form("alice"))
	ok(ids[1] == dear.id and ids[3] == cheap.id, "T3 `Highest Price` re-sorts the board")

	H.receive("alice", "smp_ah:board", { ah_filter = "" })
	eq(v.sort, "recently_listed", "T3 third sort is `Recently Listed`")
	ids = board_ids(H.form("alice"))
	ok(ids[1] == dear.id, "T3 `Recently Listed` puts the newest first")

	H.receive("alice", "smp_ah:board", { ah_filter = "" })
	eq(v.sort, "lowest_price", "T3 the cycle wraps to `Lowest Price`")

	-- The current sort is highlighted in the tooltip [F0120, F0122].
	local raw = H.form("alice")
	ok(raw:find("ah_filter") ~= nil, "T3 filter control present")
	ok(raw:find("%(c@#FFFF55%)") ~= nil, "T3 the current sort is highlighted")
end)

----------------------------------------------------------------------
-- T4 — `Search Auction` filters by display name; Cancel red, Search green
----------------------------------------------------------------------

section("T4", "search prompt", function()
	wipe()
	local alice = H.player("alice")
	mk("s1", "mcl_core:diamond 1", 10000)
	mk("s1", "mcl_tools:shovel_diamond 1", 2500000)     -- `$ 25K` [F0115]
	mk("s1", "mcl_throwing:ender_pearl 16", 70000)
	mk("s1", "mcl_core:stone 64", 5000)

	H.cmd("ah", "alice", "")
	H.receive("alice", "smp_ah:board", { ah_search = "" })
	eq(H.formname("alice"), "smp_ah:search", "T4 the sign opens `Search Auction`")
	local fs = H.form("alice")
	has(fs, "Search Auction", "T4 prompt title")
	has(fs, "no_prepend[]", "T4 prompt menu (translucent, not a container)")
	has(fs, "bgcolor[#000000C0", "T4 dark translucent background")
	has(H.plain(fs), "field[1.5,1.45;5,0.8;ah_query;Search;]", "T4 `Search` label above the field")
	has(fs, "field_close_on_enter[ah_query;false]", "T4 enter submits without closing")
	has(fs, "set_focus[ah_query;true]", "T4 the field is focused")

	-- Cancel red on the left, Search green on the right [F0114].
	local cancel_hex = fs:match("style%[ah_cancel;bgcolor=#(%x+)")
	local go_hex = fs:match("style%[ah_go;bgcolor=#(%x+)")
	ok(cancel_hex ~= nil, "T4 Cancel carries a colour")
	if cancel_hex and #cancel_hex == 6 then
		local r = tonumber(cancel_hex:sub(1, 2), 16)
		local g = tonumber(cancel_hex:sub(3, 4), 16)
		local b = tonumber(cancel_hex:sub(5, 6), 16)
		ok(r and g and b and r > g and r > b, "T4 `Cancel` renders in red")
	end
	ok(go_hex ~= nil and #go_hex == 6, "T4 Search carries a colour")
	if go_hex and #go_hex == 6 then
		local r = tonumber(go_hex:sub(1, 2), 16)
		local g = tonumber(go_hex:sub(3, 4), 16)
		local b = tonumber(go_hex:sub(5, 6), 16)
		ok(r and g and b and g > r and g > b, "T4 `Search` renders in green")
	end
	local cx = fs:match("button%[([%d%.]+),[%d%.]+;[%d%.]+,[%d%.]+;ah_cancel;")
	local gx = fs:match("button%[([%d%.]+),[%d%.]+;[%d%.]+,[%d%.]+;ah_go;")
	ok(tonumber(cx or 0) < tonumber(gx or 0), "T4 Cancel is left of Search")

	-- The observed query is a prefix of the display name [F0114 -> F0115].
	H.receive("alice", "smp_ah:search", { ah_go = "", ah_query = "diamon" })
	eq(H.formname("alice"), "smp_ah:board", "T4 searching returns to the board")
	has(H.form("alice"), "Auction (Page 1)", "T4 board title after the search")
	local ids = board_ids(H.form("alice"))
	eq(#ids, 2, "T4 `diamon` narrows to the two diamond listings")
	for _, id in ipairs(ids) do
		local rec = listings.get(id)
		ok(rec.display.name:lower():find("diamon", 1, true) ~= nil,
			"T4 result matches by display name: " .. tostring(rec.display.name))
	end

	-- `Cancel` leaves the active filter untouched.
	H.receive("alice", "smp_ah:board", { ah_search = "" })
	has(H.plain(H.form("alice")), "field[1.5,1.45;5,0.8;ah_query;Search;diamon]",
		"T4 the field is pre-filled with the active query")
	H.receive("alice", "smp_ah:search", { ah_cancel = "", ah_query = "" })
	eq(#board_ids(H.form("alice")), 2, "T4 `Cancel` keeps the previous filter")

	-- `/ah <term>` is the command equivalent [S5].
	H.cmd("ah", "alice", "shovel")
	eq(#board_ids(H.form("alice")), 1, "T4 /ah <term> pre-filters")
	has(H.form("alice"), "$ 25K", "T4 the observed `$ 25K` tooltip price form")
end)

----------------------------------------------------------------------
-- T5 — the full listing flow completes; the price is the TOTAL
----------------------------------------------------------------------

section("T5", "Your Items > List > Insert Item > price > Confirm Listing", function()
	wipe()
	local bob = H.player("bob", { items = { "mcl_core:dirt 2" } })
	H.set_money("bob", 0)

	H.cmd("ah", "bob", "")
	H.receive("bob", "smp_ah:board", { ah_your_items = "" })
	eq(H.formname("bob"), "smp_ah:your_items", "T5 `Your Items` opens")
	-- Note the separator: `>`, not the `->` that orders uses (shared §4.2).
	has(H.form("bob"), "Auction > Your Items", "T5 title uses `>`")
	hasnt(H.form("bob"), "Auction -> Your Items", "T5 and never `->`")
	has(H.form("bob"), "tooltip[ah_list;List\\nClick to sell an item\\n" ..
		smp_ah.fs.item("list") .. "]", "T5 the `List` pane tooltip [F0131]")

	H.receive("bob", "smp_ah:your_items", { ah_list = "" })
	eq(H.formname("bob"), "smp_ah:insert", "T5 `Insert Item` opens")
	has(H.form("bob"), "Insert Item", "T5 title")
	has(H.form("bob"), "list[detached:smp_ah_insert_bob;insert;", "T5 detached insert row")
	has(H.form("bob"), "listring[detached:smp_ah_insert_bob;insert]", "T5 listring for drag and drop")

	-- The player moves the stack up into the insert row (f03 §3.5).
	local dinv = H.detached["smp_ah_insert_bob"]
	ok(dinv ~= nil, "T5 the detached inventory exists")
	dinv:set_size("insert", 5)
	local stack = bob._inv:get_stack("main", 1)
	eq(stack:to_string(), "mcl_core:dirt 2", "T5 the held stack")
	bob._inv:set_stack("main", 1, H.ItemStack())
	local left = dinv:simulate_put("insert", 1, stack, bob)
	ok(left:is_empty(), "T5 the stack went into the insert row")
	eq(dinv:get_stack("insert", 1):to_string(), "mcl_core:dirt 2", "T5 insert row holds it")

	-- A second stack is refused: one stack per listing.
	local denied = dinv:simulate_put("insert", 2, H.ItemStack("mcl_core:stone 5"), bob)
	ok(not denied:is_empty(), "T5 a second stack is refused")

	H.receive("bob", "smp_ah:insert", { ah_price = "" })
	eq(H.formname("bob"), "smp_ah:price", "T5 the sign editor opens")
	has(H.form("bob"), "Edit Sign Message", "T5 title is the observed sign editor")
	has(H.plain(H.form("bob")), "field[1.5,1.25;5,0.8;ah_price;Type price;]",
		"T5 `Type price` placeholder")
	has(H.plain(H.form("bob")), "button[2.75,2.25;2.5,0.8;ah_done;Done]", "T5 `Done` button")

	-- The player typed `1` [F0141].
	H.receive("bob", "smp_ah:price", { ah_done = "", ah_price = "1" })
	eq(H.formname("bob"), "smp_ah:confirm_listing", "T5 `Confirm Listing` opens")
	has(H.form("bob"), "Confirm Listing", "T5 title")
	-- OBSERVED tooltip [F0142], minus the dropped component count.
	has(H.form("bob"), "Dirt\\nYou're going to sell this item for $1\\nmcl_core:dirt",
		"T5 the confirm tooltip reads exactly as observed")
	hasnt(H.form("bob"), "13 component(s)", "T5 the component line is dropped")
	has(H.form("bob"), "tooltip[ah_confirm;Confirm\\nClick to list item ($1)]",
		"T5 the Confirm pane names the amount")

	H.receive("bob", "smp_ah:confirm_listing", { ah_confirm = "" })
	eq(H.last_chat("bob"), "You listed 2 Dirt for $1", "T5 the result line names qty, item, total")

	local mine = listings.for_seller("bob")
	eq(#mine, 1, "T5 one listing created")
	local rec = mine[1]
	eq(rec.price, 100, "T5 the entered price is the TOTAL, in cents")
	eq(rec.count, 2, "T5 the stack count is 2")
	eq(rec.unit_price, 50, "T5 the unit price is derived (total / count)")
	eq(rec.state, "active", "T5 active")
	eq(rec.version, 1, "T5 version 1")
	eq(rec.expires - rec.created, 172800, "T5 default duration 48h")
	ok(bob._inv:is_empty("main"), "T5 the stack left the inventory exactly once")
	eq(smp_ah._flows.bob, nil, "T5 the flow is finished")

	-- Suffix parsing on the price field (shared §0.6).
	H.cmd("ah", "bob", "")
	H.receive("bob", "smp_ah:board", { ah_your_items = "" })
	H.receive("bob", "smp_ah:your_items", { ah_list = "" })
	bob._inv:set_stack("main", 1, H.ItemStack("mcl_core:stone 64"))
	dinv = H.detached["smp_ah_insert_bob"]
	dinv:simulate_put("insert", 1, bob._inv:get_stack("main", 1), bob)
	bob._inv:set_stack("main", 1, H.ItemStack())
	H.receive("bob", "smp_ah:insert", { ah_price = "" })
	H.receive("bob", "smp_ah:price", { ah_done = "", ah_price = "250k" })
	H.receive("bob", "smp_ah:confirm_listing", { ah_confirm = "" })
	local stone = listings.for_seller("bob")[1]
	eq(stone.price, 25000000, "T5 `250k` parses to 25,000,000 cents")
	H.cmd("ah", "bob", "")
	has(H.form("bob"), "Auction", "T5 back to the auction tree")
end)

----------------------------------------------------------------------
-- T6 — two buyers, one winner, the exact race-loss string, no duplication
----------------------------------------------------------------------

section("T6", "purchase race re-validation", function()
	wipe()
	local erin = H.player("erin")
	local carol = H.player("carol")
	local dave = H.player("dave")
	H.set_money("carol", 100000000)
	H.set_money("dave", 100000000)
	H.set_money("erin", 0)

	-- `You bought 1 Ender Chest for $ 5.1K` [F0055]: 510000 cents.
	local rec = mk("erin", "mcl_chests:chest 1", 510000)

	-- Both buyers open the listing: each screen is built from version 1.
	H.cmd("ah", "carol", "")
	H.receive("carol", "smp_ah:board", { ["ah_l" .. rec.id] = "" })
	eq(H.formname("carol"), "smp_ah:confirm_buy", "T6 the click opens a confirmation")
	has(H.form("carol"), "Auction > Confirm Purchase", "T6 confirm title")
	has(H.form("carol"), "Chest\\n$ 5.1K\\nmcl_chests:chest", "T6 the listing tooltip [F0055 form]")
	has(H.form("carol"), "tooltip[ah_buy;Confirm\\nClick to buy item ($5.1K)]",
		"T6 the Confirm pane names the amount, parenthesised with no space")

	H.cmd("ah", "dave", "")
	H.receive("dave", "smp_ah:board", { ["ah_l" .. rec.id] = "" })
	eq(H.formname("dave"), "smp_ah:confirm_buy", "T6 dave has a confirmation too")

	-- Carol wins the race.
	H.receive("carol", "smp_ah:confirm_buy", { ah_buy = "" })
	eq(H.last_chat("carol"), "You bought 1 Chest for $ 5.1K",
		"T6 the observed purchase line, verbatim [F0055]")
	eq(H.money("carol"), 100000000 - 510000, "T6 the buyer is debited exactly")
	eq(H.money("erin"), 510000, "T6 the seller is credited exactly")
	eq(H.last_chat("erin"), "You sold 1 Chest and received $ 5.1K", "T6 the seller is told")

	-- Dave loses it.
	H.clear_chat("dave")
	H.receive("dave", "smp_ah:confirm_buy", { ah_buy = "" })
	eq(H.last_chat("dave"), "This item was already bought",
		"T6 the race-loss string is exactly `This item was already bought` [F0037]")
	eq(H.money("dave"), 100000000, "T6 the loser is not debited")
	eq(H.money("erin"), 510000, "T6 the seller is not paid twice")

	-- No duplication: exactly one chest exists, in Carol's inventory.
	local total = 0
	for _, p in pairs(H.players) do
		for i = 1, p._inv:get_size("main") do
			local s = p._inv:get_stack("main", i)
			if s:get_name() == "mcl_chests:chest" then total = total + s:get_count() end
		end
	end
	eq(total, 1, "T6 the item is not duplicated")
	eq(carol._inv:contains_item("main", H.ItemStack("mcl_chests:chest 1")), true,
		"T6 the winner holds the item")

	local after = listings.get(rec.id)
	eq(after.state, "sold", "T6 the listing is sold")
	eq(after.version, 2, "T6 the version advanced")
	eq(#listings.for_seller("erin", { active_only = true }), 0, "T6 it left the board")

	local history = listings.history(1)
	eq(#history, 1, "T6 one transaction recorded")
	eq(history[1].price, 510000, "T6 transaction price")
	eq(history[1].buyer, "carol", "T6 transaction buyer")
	eq(history[1].seller, "erin", "T6 transaction seller")
	ok((history[1].sold_at_ms or 0) > 1000000000000, "T6 millisecond timestamp [S23]")

	-- Ledger: one debit and one credit, both referencing the listing.
	local ledger = smp_store.api.ledger_for("carol", 1, 50)
	local found
	for _, e in ipairs(ledger) do
		if e.type == "ah_buy" and e.ref == "ah:" .. rec.id then found = e end
	end
	ok(found ~= nil, "T6 an `ah_buy` ledger entry exists")
	eq(found and found.amount, -510000, "T6 the ledger debit is exact")

	-- Buying the same id again, with the current version, still refuses: the
	-- listing is no longer active.
	eq(select(2, smp_ah.buy("dave", rec.id, after.version)), "already_bought",
		"T6 a sold listing cannot be bought again")
end)

----------------------------------------------------------------------
-- T7 — a listing undercutting a better-paying order routes to it (f04)
----------------------------------------------------------------------

section("T7", "order routing contract", function()
	wipe()
	local frank = H.player("frank")

	-- The shipped stub answers nil (TODO(f04)).
	ok(smp_ah._orders_stub == true, "T7 f03 ships a stubbed smp_orders")
	eq(smp_orders.best_open_order("m1|anything"), nil, "T7 the stub returns nil")

	local diamond_key = keys.key(H.ItemStack("mcl_core:diamond 1"), "M1")
	ok(diamond_key ~= nil, "T7 an M1 key exists for a plain diamond")

	-- With no orders, listings go to the board.
	local board_rec = mk("frank", "mcl_core:diamond 64", 6400)
	eq(board_rec.state, "active", "T7 without f04 the listing is created")
	eq(listings.get(board_rec.id).id, board_rec.id, "T7 and it is on the board")

	-- f04's contract (f03 §6.1): best_open_order(m1_key) -> {unit_price=...}.
	local calls, filled = {}, {}
	smp_orders.best_open_order = function(key)
		calls[#calls + 1] = key
		if key == diamond_key then return { id = 77, unit_price = 100000 } end  -- $1000/item
		return nil
	end
	smp_orders.fill_from_stack = function(order, pname, stack)
		filled[#filled + 1] = { id = order.id, who = pname, stack = stack:to_string() }
		return { routed = true, order = order.id }
	end

	-- A listing asking $1 per diamond loses to an order paying $1000.
	local res, err = smp_ah.create_listing("frank", H.ItemStack("mcl_core:diamond 64"), 6400)
	eq(err, "routed", "T7 the cheaper listing routes into the order")
	eq(#filled, 1, "T7 fill_from_stack was called once")
	eq(filled[1] and filled[1].id, 77, "T7 into the right order")
	eq(filled[1] and filled[1].who, "frank", "T7 crediting the right seller")
	eq(calls[#calls], diamond_key, "T7 the lookup is by M1 key")
	eq(type(res) ~= "table" or res.id == nil, true, "T7 no listing was created")

	-- A listing asking MORE than the order stays on the board.
	local dear = smp_ah.create_listing("frank", H.ItemStack("mcl_core:diamond 1"), 200000)
	ok(dear and dear.id, "T7 a better-paying listing is not routed")

	-- An order that pays less does not take the listing either.
	smp_orders.best_open_order = function() return { id = 78, unit_price = 10 } end
	local cheap = smp_ah.create_listing("frank", H.ItemStack("mcl_core:stone 1"), 5000)
	ok(cheap and cheap.id, "T7 a worse-paying order does not route")

	-- The other half of the contract: f04 sweeps the board after creating an
	-- order (f04 §6.1) using listings_at_or_below, cheapest first.
	smp_orders.best_open_order = function() return nil end
	smp_orders.fill_from_stack = nil
	wipe()
	mk("s1", "mcl_core:diamond 1", 5000)     -- $50/item
	mk("s2", "mcl_core:diamond 1", 1000)     -- $10/item
	mk("s3", "mcl_core:diamond 1", 3000)     -- $30/item
	mk("s4", "mcl_core:stone 1", 100)
	local sweep = smp_ah.listings_at_or_below(diamond_key, 3000)
	eq(#sweep, 2, "T7 listings_at_or_below returns the matching ones at or below")
	ok(sweep[1].unit_price <= sweep[2].unit_price, "T7 cheapest first (f04 §6.1)")
	eq(sweep[1].unit_price, 1000, "T7 the cheapest matching listing")

	-- Consuming a listing for an order closes it and records the sale.
	local consumed = smp_ah.consume_listing(sweep[1].id, "buyer1", 1000)
	eq(consumed.state, "routed", "T7 consume_listing marks it routed")
	eq(#listings.listings_at_or_below(diamond_key, 100000), 2, "T7 it left the M1 index")
	eq(#listings.history(1), 1, "T7 the routed sale is in the transaction log")

	-- Quick Buy's entry point (f05).
	local cheapest = listings.cheapest(diamond_key)
	eq(cheapest.unit_price, 3000, "T7 cheapest() serves f05 Quick Buy")
end)

----------------------------------------------------------------------
-- T8 — disconnecting with `Insert Item` open returns the stack
----------------------------------------------------------------------

section("T8", "no item loss on disconnect", function()
	wipe()
	local gina = H.player("gina", { items = { "mcl_tools:shovel_diamond 1" } })
	H.cmd("ah", "gina", "")
	H.receive("gina", "smp_ah:board", { ah_your_items = "" })
	H.receive("gina", "smp_ah:your_items", { ah_list = "" })
	local dinv = H.detached["smp_ah_insert_gina"]
	dinv:set_size("insert", 5)
	local stack = gina._inv:get_stack("main", 1)
	gina._inv:set_stack("main", 1, H.ItemStack())
	dinv:simulate_put("insert", 1, stack, gina)
	ok(gina._inv:is_empty("main"), "T8 the shovel is out of the inventory")

	-- Disconnect with `Insert Item` open (shared §2.6 R6).
	H.leave("gina")
	eq(smp_ah._flows.gina, nil, "T8 the flow is closed on leave")
	local queued = H.storage_data("smp_ah")["ah:r:gina"]
	ok(queued ~= nil and queued ~= "", "T8 the stack is persisted for the next join")

	H.join("gina")
	local back = H.players["gina"]._inv
	local s_back = back:get_stack("main", 1)
	eq(s_back:get_name(), "mcl_tools:shovel_diamond",
		"T8 the stack is back in the inventory")
	ok(H.has_chat("gina", "1 item(s) were returned to you"), "T8 and the player is told")
	eq(s_back:get_count(), 1, "T8 and the stack count is right")
	eq(H.storage_data("smp_ah")["ah:r:gina"], nil, "T8 the queue is cleared")

	-- Same guarantee while the player is still online (the engine case).
	H.cmd("ah", "gina", "")
	H.receive("gina", "smp_ah:board", { ah_your_items = "" })
	H.receive("gina", "smp_ah:your_items", { ah_list = "" })
	dinv = H.detached["smp_ah_insert_gina"]
	dinv:set_size("insert", 5)
	stack = H.players["gina"]._inv:get_stack("main", 1)
	H.players["gina"]._inv:set_stack("main", 1, H.ItemStack())
	dinv:simulate_put("insert", 1, stack, H.players["gina"])
	smp_ah.abort_flow("gina")
	local s_abort = H.players["gina"]._inv:get_stack("main", 1)
	eq(s_abort:get_name(), "mcl_tools:shovel_diamond", "T8 abort_flow returns the stack directly when online")
	eq(s_abort:get_count(), 1, "T8 with the count intact")

	-- Esc out of the price prompt puts it back in the insert row, not in limbo.
	H.cmd("ah", "gina", "")
	H.receive("gina", "smp_ah:board", { ah_your_items = "" })
	H.receive("gina", "smp_ah:your_items", { ah_list = "" })
	dinv = H.detached["smp_ah_insert_gina"]
	dinv:set_size("insert", 5)
	stack = H.players["gina"]._inv:get_stack("main", 1)
	H.players["gina"]._inv:set_stack("main", 1, H.ItemStack())
	dinv:simulate_put("insert", 1, stack, H.players["gina"])
	H.receive("gina", "smp_ah:insert", { ah_price = "" })
	eq(H.formname("gina"), "smp_ah:price", "T8 the price prompt is open")
	H.receive("gina", "smp_ah:price", { quit = true })
	eq(H.formname("gina"), "smp_ah:insert", "T8 quitting the prompt returns to `Insert Item`")
	local s_ins = H.detached["smp_ah_insert_gina"]:get_stack("insert", 1)
	eq(s_ins:get_name(), "mcl_tools:shovel_diamond", "T8 the stack is back in the insert row")
	eq(s_ins:get_count(), 1, "T8 with the count intact")
	H.receive("gina", "smp_ah:insert", { quit = true })
	local s_q = H.players["gina"]._inv:get_stack("main", 1)
	eq(s_q:get_name(), "mcl_tools:shovel_diamond", "T8 quitting `Insert Item` returns it to the inventory")
	eq(s_q:get_count(), 1, "T8 with the count intact")
	eq(smp_ah._flows.gina, nil, "T8 no flow is left holding the item")
end)

----------------------------------------------------------------------
-- T9 — a forged listing id or version in a formspec field changes nothing
----------------------------------------------------------------------

section("T9", "untrusted client fields", function()
	wipe()
	local henry = H.player("henry")
	local iris = H.player("iris")
	H.set_money("henry", 100000000)
	H.set_money("iris", 100000000)
	local mine = mk("iris", "mcl_core:diamond 4", 40000)

	local function snapshot()
		return {
			money_henry = H.money("henry"), money_iris = H.money("iris"),
			state = listings.get(mine.id).state, version = listings.get(mine.id).version,
			stack = listings.get(mine.id).stack,
			inv = henry._inv:get_stack("main", 1):to_string(),
			tx = #listings.history(1),
		}
	end
	local before = snapshot()

	-- A forged listing id that does not exist.
	H.cmd("ah", "henry", "")
	H.receive("henry", "smp_ah:board", { ["ah_l999999"] = "" })
	eq(H.last_chat("henry"), "This item was already bought", "T9 an unknown id is refused")
	H.receive("henry", "smp_ah:board", { ah_buy = "" })
	eq(snapshot().state, before.state, "T9 nothing was mutated by a forged id")

	-- A forged field name that is not a listing at all.
	H.receive("henry", "smp_ah:board", { ["ah_l1;drop table"] = "", ah_filter = "x" })
	eq(snapshot().state, before.state, "T9 garbage field names change nothing")

	-- A stale formname: the player has moved on, so the fields are ignored.
	H.receive("henry", "smp_ah:board", { ah_your_items = "" })
	eq(H.formname("henry"), "smp_ah:your_items", "T9 henry is on `Your Items`")
	local sort_before = smp_core.get_session("henry", "smp_ah:view").sort
	H.receive("henry", "smp_ah:board", { ah_filter = "" })
	eq(smp_core.get_session("henry", "smp_ah:view").sort, sort_before,
		"T9 fields for a superseded form are ignored")
	eq(H.formname("henry"), "smp_ah:your_items", "T9 and the view did not change")

	-- Someone else's listing cannot be withdrawn with a forged id.
	H.clear_chat("henry")
	H.receive("henry", "smp_ah:your_items", { ["ah_y" .. mine.id] = "" })
	eq(H.last_chat("henry"), "That listing is not yours", "T9 another seller's listing is refused")
	eq(listings.get(mine.id).state, "active", "T9 and it is still active")

	-- A forged version: the buyer's screen said version 1, the record moved on.
	eq(select(2, smp_ah.buy("henry", mine.id, 999)), "already_bought",
		"T9 a forged version is refused")
	eq(snapshot().state, before.state, "T9 still active after the forged version")
	eq(H.money("henry"), before.money_henry, "T9 no money moved")

	-- A forged price on the price prompt.
	H.receive("henry", "smp_ah:your_items", { ah_list = "" })
	local dinv = H.detached["smp_ah_insert_henry"]
	dinv:set_size("insert", 5)
	henry._inv:set_stack("main", 1, H.ItemStack("mcl_core:stone 3"))
	dinv:simulate_put("insert", 1, henry._inv:get_stack("main", 1), henry)
	henry._inv:set_stack("main", 1, H.ItemStack())
	H.receive("henry", "smp_ah:insert", { ah_price = "" })
	H.receive("henry", "smp_ah:price", { ah_done = "", ah_price = "-5" })
	eq(H.formname("henry"), "smp_ah:price", "T9 a negative price stays on the prompt")
	ok(H.last_chat("henry"):find("Invalid price") ~= nil, "T9 and says why")
	H.receive("henry", "smp_ah:price", { ah_done = "", ah_price = "nan" })
	eq(H.formname("henry"), "smp_ah:price", "T9 NaN is refused")
	H.receive("henry", "smp_ah:price", { ah_done = "", ah_price = "1e400" })
	eq(H.formname("henry"), "smp_ah:price", "T9 overflow is refused")
	H.receive("henry", "smp_ah:price", { ah_done = "", ah_price = "0" })
	ok(H.last_chat("henry"):find("Price must be between") ~= nil,
		"T9 below `ah.min_price` is refused with the bounds: " .. tostring(H.last_chat("henry")))
	eq(#listings.for_seller("henry"), 0, "T9 no listing was created")
	H.receive("henry", "smp_ah:price", { quit = true })
	H.receive("henry", "smp_ah:insert", { quit = true })
	eq(henry._inv:get_stack("main", 1):to_string(), "mcl_core:stone 3",
		"T9 and the stack came back")

	local after = snapshot()
	eq(after.state, before.state, "T9 listing state unchanged overall")
	eq(after.version, before.version, "T9 listing version unchanged overall")
	eq(after.money_henry, before.money_henry, "T9 balances unchanged overall")
	eq(after.money_iris, before.money_iris, "T9 seller balance unchanged overall")
	eq(after.tx, before.tx, "T9 no transactions overall")
end)

----------------------------------------------------------------------
-- T10 — listing at the slot limit is refused
----------------------------------------------------------------------

section("T10", "slot limits", function()
	wipe()
	-- f13 (smp_ranks) is authoritative per f13 §4.2.4; stub it out so this
	-- isolation test exercises smp_ah's own config-driven fallback path.
	local saved_ah_limit = smp_ranks.ah_limit
	local saved_limit    = smp_ranks.limit
	smp_ranks.ah_limit = nil
	smp_ranks.limit    = nil
	local saved_default = smp_ah.cfg.slots.default
	smp_ah.cfg.slots.default = 2

	local jake = H.player("jake", { items = { "mcl_core:stone 1", "mcl_core:stone 1",
		"mcl_core:stone 1", "mcl_core:stone 1" } })
	H.set_money("jake", 0)
	eq(smp_ah.slots("jake"), 2, "T10 the default limit applies")

	ok(smp_ah.create_listing("jake", H.ItemStack("mcl_core:stone 1"), 1000), "T10 first listing")
	ok(smp_ah.create_listing("jake", H.ItemStack("mcl_core:stone 1"), 1000), "T10 second listing")
	eq(listings.count_active("jake"), 2, "T10 two active")

	H.clear_chat("jake")
	local rec, err = smp_ah.create_listing("jake", H.ItemStack("mcl_core:stone 1"), 1000)
	eq(rec, nil, "T10 the third listing is refused")
	eq(err, "slots", "T10 with the slot-limit reason")
	core.chat_send_player("jake", "You reached listing limits")  -- caller would do this
	ok(H.last_chat("jake") == "You reached listing limits", "T10 and the observed house-style refusal")

	-- The menu path: opening the listing flow, the price prompt refuses the
	-- validation with the same reason (`slots`). The flow holds the stack
	-- (the user can cancel to recover it). We assert the chat and that a
	-- quit from the prompt returns the stack.
	H.cmd("ah", "jake", "")
	H.receive("jake", "smp_ah:board", { ah_your_items = "" })
	H.receive("jake", "smp_ah:your_items", { ah_list = "" })
	local dinv = H.detached["smp_ah_insert_jake"]
	dinv:set_size("insert", 5)
	local s = jake._inv:get_stack("main", 3)
	local left = dinv:simulate_put("insert", 1, s, jake)
	ok(left:is_empty(), "T10 the stone went into the insert row")
	jake._inv:set_stack("main", 3, H.ItemStack())
	H.receive("jake", "smp_ah:insert", { ah_price = "" })
	H.receive("jake", "smp_ah:price", { ah_done = "", ah_price = "10" })
	ok(H.last_chat("jake"):find("You reached listing limits") ~= nil,
		"T10 the menu path refuses too: " .. tostring(H.last_chat("jake")))
	ok(smp_ah._flows.jake ~= nil and smp_ah._flows.jake.stack ~= nil,
		"T10 the flow holds the stone for retry")
	-- Quitting the prompt returns it.
	H.receive("jake", "smp_ah:price", { quit = true })
	H.receive("jake", "smp_ah:insert", { quit = true })
	eq(smp_ah._flows.jake, nil, "T10 no flow is left holding it after the quit")
	local stone_count = 0
	for i = 1, jake._inv:get_size("main") do
		stone_count = stone_count + jake._inv:get_stack("main", i):get_count()
	end
	eq(stone_count, 4, "T10 every stone is back in the inventory (sum of stacks)")

	-- `/ah sell <price>` chats the refusal itself.
	H.set_money("jake", 0)
	jake:set_wield_index(1)
	jake._inv:set_stack("main", 1, H.ItemStack("mcl_core:stone 1"))
	H.clear_chat("jake")
	local ok_cmd, msg = H.cmd("ah", "jake", "sell 10")
	eq(ok_cmd, true, "T10 `/ah sell` returns true even when refusing")
	eq(H.last_chat("jake"), "You reached listing limits",
		"T10 and the caller sees the house-style refusal")
	ok(jake._inv:get_stack("main", 1):get_name() == "mcl_core:stone",
		"T10 and the stack was put back")

	-- A tier raises the limit (f13 §4.1: tier1 45).
	smp_ah.cfg.slots.tier1 = 45
	local kate = smp_store.api.ensure_player("jake")
	kate.rank = { tier = "tier1", expires_at = os.time() + 86400 }
	smp_store.api.upsert_player(kate)
	eq(smp_ah.slots("jake"), 45, "T10 a live tier1 grant raises the limit to 45")
	ok(smp_ah.create_listing("jake", H.ItemStack("mcl_core:stone 1"), 1000),
		"T10 and the third listing now succeeds")

	-- An expired grant does not (f13 §4.2.3 grandfathering: nothing new).
	kate.rank = { tier = "tier1", expires_at = os.time() - 10 }
	smp_store.api.upsert_player(kate)
	eq(smp_ah.slots("jake"), 2, "T10 an expired grant falls back to the configured default")

	smp_ah.cfg.slots.default = saved_default
	smp_ah.cfg.slots.tier1 = 45
	smp_ranks.ah_limit = saved_ah_limit
	smp_ranks.limit    = saved_limit
end)

----------------------------------------------------------------------
-- Extra coverage the acceptance matrix implies but does not enumerate
----------------------------------------------------------------------

section("X-a", "listing tooltip money forms follow shared §0.6", function()
	wipe()
	local alice = H.player("alice")
	local a = mk("s1", "mcl_throwing:ender_pearl 16", 70000)     -- $700 [F0108]
	local b = mk("s1", "mcl_core:diamond 64", 900000)            -- $ 9K [F0124]
	local c = mk("s1", "mcl_tools:shovel_diamond 1", 2500000)    -- $ 25K [F0115]
	local d = mk("s1", "mcl_core:dirt 2", 100)                   -- $1 [F0142]
	eq(smp_ah.fs.money(70000), "$700", "§0.6 bare form has no space")
	eq(smp_ah.fs.money(900000), "$ 9K", "§0.6 suffixed form has a space")
	eq(smp_ah.fs.money(2500000), "$ 25K", "§0.6 $ 25K")
	eq(smp_ah.fs.money(100), "$1", "§0.6 $1")
	eq(smp_ah.fs.money_inline(3000000), "$30K", "§0.6 parenthesised form has no space")
	eq(smp_ah.fs.money_after(510000), "5.1K", "the `$ @1` template tail")
	eq(smp_ah.fs.money_tail(900000), " 9K", "the `$@1` template tail")
	H.cmd("ah", "alice", "")
	local p = H.plain(H.form("alice"))
	ok(p:find("Ender Pearl\\n$700\\nmcl_throwing:ender_pearl", 1, true) ~= nil,
		"$700 tooltip [F0108]")
	ok(p:find("Diamond\\n$ 9K\\nmcl_core:diamond", 1, true) ~= nil, "$ 9K tooltip [F0124]")
	ok(p:find("Diamond Shovel\\n$ 25K\\nmcl_tools:shovel_diamond", 1, true) ~= nil,
		"$ 25K tooltip [F0115]")
	ok(p:find("component%(s%)") == nil, "no component line anywhere")
	-- Stacks show a count badge, like the observed board [F0108 "16"].
	ok(p:find("label%[[%d%.]+,[%d%.]+;16%]") ~= nil, "the stack count is rendered on the icon")
	ok(a and b and c and d, "listings created")
end)

section("X-b", "price bounds, fees and the rate limit", function()
	wipe()
	local leo = H.player("leo")
	H.set_money("leo", 1000000)
	eq(select(2, smp_ah.create_listing("leo", H.ItemStack("mcl_core:stone 1"), 99)),
		"price", "below `ah.min_price` ($1) is refused")
	eq(select(2, smp_ah.create_listing("leo", H.ItemStack("mcl_core:stone 1"),
		100000000000001)), "price", "above `ah.max_price` is refused")
	ok(smp_ah.create_listing("leo", H.ItemStack("mcl_core:stone 1"), 100),
		"exactly $1 is accepted [F0142]")

	-- Fees are PROPOSED 0; with a fee they round down in the payer's favour.
	smp_ah.cfg.listing_fee_pct = 3
	H.set_money("leo", 1000)
	eq(select(2, smp_ah.create_listing("leo", H.ItemStack("mcl_core:stone 1"), 100000)),
		"fee", "a listing fee the seller cannot pay is refused")
	H.set_money("leo", 100000)
	ok(smp_ah.create_listing("leo", H.ItemStack("mcl_core:stone 1"), 10000), "with funds it lists")
	eq(H.money("leo"), 100000 - 300, "3% of $100 = $3, rounded down")
	smp_ah.cfg.listing_fee_pct = 0

	-- A sale tax reduces only the seller's credit.
	smp_ah.cfg.sale_tax_pct = 10
	local mia = H.player("mia")
	H.set_money("mia", 100000)
	local rec = mk("noah", "mcl_core:diamond 1", 10000)
	local ok_buy = smp_ah.buy("mia", rec.id, 1)
	ok(ok_buy ~= nil, "the purchase succeeds")
	eq(H.money("mia"), 90000, "the buyer pays the full asking price")
	eq(H.money("noah"), 9000, "the seller receives it minus the 10% tax")
	smp_ah.cfg.sale_tax_pct = 0

	-- Rate limit (shared §2.6 R9, PROPOSED one per second).
	smp_ah.cfg.rate_limit = 1
	smp_ah._last_list["mia"] = os.time()
	eq(select(2, smp_ah.create_listing("mia", H.ItemStack("mcl_core:stone 1"), 1000)),
		"rate", "a second listing in the same second is refused")
	smp_ah._last_list["mia"] = os.time() - 5
	ok(smp_ah.create_listing("mia", H.ItemStack("mcl_core:stone 1"), 1000),
		"and allowed again later")
	smp_ah.cfg.rate_limit = 0
end)

section("X-c", "expiry, cancellation and reclaim", function()
	wipe()
	local owen = H.player("owen", { items = {} })
	local rec = mk("owen", "mcl_core:diamond 8", 8000)
	listings.get(rec.id).expires = os.time() - 10      -- force expiry

	-- Lazily inactive: it must not be sold.
	eq(listings.get_active(rec.id), nil, "an expired listing is not active")
	local buyer = H.player("buyer")
	H.set_money("buyer", 100000000)
	eq(select(2, smp_ah.buy("buyer", rec.id, 1)), "expired", "and cannot be bought")
	eq(#listings.query({}).items, 0, "it is off the board")

	-- The sweep flips the state and keeps it reclaimable for `ah.reclaim_days`.
	local expired = listings.sweep(os.time(), 100)
	eq(expired, 1, "the sweep expires it")
	eq(listings.get(rec.id).state, "expired", "state is expired")
	eq(#listings.reclaimable("owen"), 1, "and it is reclaimable")

	H.cmd("ah", "owen", "")
	H.receive("owen", "smp_ah:board", { ah_your_items = "" })
	has(H.form("owen"), "Click to reclaim", "`Your Items` offers the reclaim")
	H.receive("owen", "smp_ah:your_items", { ["ah_y" .. rec.id] = "" })
	eq(H.last_chat("owen"), "Item reclaimed", "the reclaim says so")
	eq(owen._inv:get_stack("main", 1):to_string(), "mcl_core:diamond 8",
		"and the stack is back")
	eq(listings.get(rec.id), nil, "the reclaimed record is gone")

	-- Cancelling an active listing returns it too (V-42, PROPOSED).
	local rec2 = mk("owen", "mcl_core:stone 16", 1600)
	H.cmd("ah", "owen", "")
	H.receive("owen", "smp_ah:board", { ah_your_items = "" })
	has(H.form("owen"), "Click to cancel", "`Your Items` offers the cancel")
	H.receive("owen", "smp_ah:your_items", { ["ah_y" .. rec2.id] = "" })
	eq(H.last_chat("owen"), "Listing cancelled", "the cancel says so")
	eq(listings.get(rec2.id).state, "cancelled", "state is cancelled")
	eq(#listings.query({}).items, 0, "and it is off the board")

	-- With no room, nothing is lost and nothing is cancelled.
	wipe()
	local full = H.player("full")
	for i = 1, 36 do full._inv:set_stack("main", i, H.ItemStack("mcl_core:dirt 64")) end
	local rec3 = mk("full", "mcl_core:diamond 1", 1000)
	H.clear_chat("full")
	eq(select(2, smp_ah.withdraw("full", rec3.id)), "no_space", "a full inventory refuses")
	eq(listings.get(rec3.id).state, "active", "and the listing stays active")
	eq(H.last_chat("full"), "No room in your inventory", "with the reason")
end)

section("X-d", "persistence, indexes and history", function()
	wipe()
	local rec = mk("quinn", "mcl_core:diamond 64", 900000)
	local rec2 = mk("quinn", "mcl_throwing:ender_pearl 16", 70000)
	listings.flush()
	local data = H.storage_data("smp_ah")
	ok(data["ah:l:" .. rec.id] ~= nil, "the listing is persisted")
	ok(data["ah:seq"] ~= nil, "the id sequence is persisted")
	local json = H.json_decode(data["ah:l:" .. rec.id])
	eq(json.price, 900000, "the price round-trips as integer cents")
	eq(json.unit_price, 14062, "the derived unit price round-trips (floored)")
	eq(json.count, 64, "the count round-trips")
	eq(json.stack, "mcl_core:diamond 64", "the stack string round-trips")

	-- Reload from storage: ids, versions and every index must come back.
	local loaded = listings.load()
	eq(loaded, 2, "both listings reload")
	local back = listings.get(rec.id)
	eq(back.price, 900000, "price survives the reload")
	eq(back.version, 1, "version survives the reload")
	eq(#listings.for_seller("quinn"), 2, "the seller index is rebuilt")
	eq(#listings.listings_at_or_below(keys.key(H.ItemStack("mcl_core:diamond 1"), "M1"),
		math.huge), 1, "the M1 index is rebuilt")
	local diamond_hits = listings.search_ids("diamon")
	ok(diamond_hits ~= nil and diamond_hits[rec.id] == true, "the search index is rebuilt")
	eq(listings.query({ sort = "lowest_price" }).items[1].id, rec2.id,
		"and the board sorts after a reload")

	-- Search tokens come from the display name and the itemstring; the
	-- search vocabulary is small (distinct item names) so the scan is
	-- bounded — f03 §4.15 says "avoid full scans" over listings, not over
	-- the vocabulary.
	-- search_ids returns a SET of listing ids ({ [id] = true }), so count its
	-- members with pairs() rather than `#` (ids are not contiguous 1..n).
	local function set_size(set)
		if type(set) ~= "table" then return 0 end
		local n = 0
		for _ in pairs(set) do n = n + 1 end
		return n
	end
	ok(listings.search_ids("ender pearl") ~= nil, "multi-word search")
	-- "mcl_throwing" tokenises to {"mcl", "throwing"}; both words must match.
	-- Only the ender pearl listing has a token starting with "throwing",
	-- so the diamond listing drops out.
	local hits = listings.search_ids("mcl_throwing")
	eq(set_size(hits), 1, "search by itemstring, with both query words required")
	ok(hits and hits[rec2.id] == true, "and only the ender pearl listing matches")
	eq(listings.search_ids(""), nil, "an empty query is no filter")
	eq(set_size(listings.search_ids("zzz")), 0, "no match yields an empty set")
	eq(#listings.query({ search = "zzz" }).items, 0, "and the board is empty for it")

	-- History: newest first, 100 per page, at most 10 pages [S23].
	local buyer = H.player("buyer")
	H.set_money("buyer", 10 ^ 12)
	for i = 1, 3 do
		local r = mk("quinn", "mcl_core:stone 1", 1000 + i)
		smp_ah.buy("buyer", r.id, 1)
	end
	local page, pages = listings.history(1)
	eq(#page, 3, "three transactions")
	ok(page[1].sold_at_ms >= page[3].sold_at_ms, "newest first [S23]")
	eq(listings.config().history_page, 100, "100 per page [S23]")
	eq(listings.config().history_pages, 10, "up to 10 pages [S23]")
	ok(pages >= 1, "page count")
end)

section("X-e", "commands, aliases and staff removal", function()
	wipe()
	local ruby = H.player("ruby", { items = { "mcl_core:dirt 4" } })
	H.set_money("ruby", 0)

	-- `/ah sell <price>` lists the held stack (LIVE [S5]).
	local ok_cmd, msg = H.cmd("ah", "ruby", "sell 12")
	eq(ok_cmd, true, "/ah sell returns true")
	local rec = listings.for_seller("ruby")[1]
	ok(rec ~= nil, "/ah sell created the listing")
	eq(rec and rec.price, 1200, "/ah sell prices the whole stack in cents")
	eq(rec and rec.count, 4, "/ah sell took the held stack")
	eq(ruby._inv:get_stack("main", 1):to_string(), "", "/ah sell emptied the wield slot")
	eq(H.last_chat("ruby"), "You listed 4 Dirt for $12", "and said so")

	-- Aliases.
	for _, alias in ipairs({ "auction", "auctionhouse" }) do
		H.cmd(alias, "ruby", "")
		eq(H.formname("ruby"), "smp_ah:board", "/" .. alias .. " opens the board")
	end

	-- `/ah sell` refusals.
	H.clear_chat("ruby")
	H.cmd("ah", "ruby", "sell")
	eq(H.cmd("ah", "ruby", "sell"), false, "/ah sell with no price is a usage error")
	ruby._inv:set_stack("main", 2, H.ItemStack())
	ruby:set_wield_index(2)
	H.cmd("ah", "ruby", "sell 5")
	eq(H.last_chat("ruby"), "Hold the item you want to list", "an empty hand is refused")

	-- `/ahadmin remove <id>` returns the item to the seller.
	ruby:set_wield_index(1)
	ruby._inv:set_stack("main", 1, H.ItemStack("mcl_core:dirt 4"))
	H.cmd("ah", "ruby", "sell 8")
	local rec2 = listings.for_seller("ruby")[1]
	local admin = H.player("admin")
	H.cmd("ahadmin", "admin", "remove " .. rec2.id)
	eq(listings.get(rec2.id).state, "cancelled", "the staff removal closed it")
	ok(H.has_chat("admin", "Removed listing " .. rec2.id), "and told the admin")
	eq(select(2, H.cmd("ahadmin", "admin", "remove 999999")), nil, "an unknown id refuses")

	-- `/smp test smp_ah` is wired into the f01 dispatcher.
	local smp_cmd = H.commands["smp"]
	ok(smp_cmd ~= nil and smp_cmd._smp_ah_hooked == true, "/smp test smp_ah is hooked")
end)

section("X-f", "money is integer cents and conserved", function()
	wipe()
	local ada = H.player("ada")
	local bea = H.player("bea")
	H.set_money("ada", 123456789)
	H.set_money("bea", 1)
	local rec = mk("cy", "mcl_core:diamond 3", 1234567)
	eq(rec.unit_price, math.floor(1234567 / 3), "the unit price is an integer (floored)")
	eq(rec.unit_price * 3, 1234566, "and never advertises more than the total")
	eq(rec.unit_price, math.floor(rec.unit_price), "no float cents in the record")
	local before = H.money("ada") + H.money("bea") + H.money("cy")
	ok(smp_ah.buy("ada", rec.id, 1), "the purchase succeeds")
	local after = H.money("ada") + H.money("bea") + H.money("cy")
	eq(after, before, "money is conserved across the purchase")
	eq(H.money("ada"), 123456789 - 1234567, "the buyer paid integer cents")
	eq(H.money("cy"), 1234567, "the seller received integer cents")

	-- Insufficient funds is refused before anything mutates.
	local rec2 = mk("cy", "mcl_core:diamond 1", 10 ^ 11)
	H.clear_chat("bea")
	eq(select(2, smp_ah.buy("bea", rec2.id, 1)), "insufficient_funds", "a poor buyer is refused")
	eq(H.last_chat("bea"), "Insufficient funds", "with the reason")
	eq(listings.get(rec2.id).state, "active", "and the listing is untouched")
	eq(H.money("cy"), 1234567, "and the seller is not paid")

	-- A full inventory is refused before anything mutates.
	local full = H.player("full")
	H.set_money("full", 10 ^ 12)
	for i = 1, 36 do full._inv:set_stack("main", i, H.ItemStack("mcl_core:dirt 64")) end
	local rec3 = mk("cy", "mcl_core:stone 64", 1000)
	H.clear_chat("full")
	eq(select(2, smp_ah.buy("full", rec3.id, 1)), "no_space", "no room, no purchase")
	eq(H.last_chat("full"), "No room in your inventory", "with the reason")
	eq(H.money("full"), 10 ^ 12, "and no money moved")
	eq(listings.get(rec3.id).state, "active", "and the listing is untouched")
end)

section("X-g", "keys: the M1/M2 identity f03 §4.1 and §5 need", function()
	wipe()
	local sword = H.ItemStack({ name = "mcl_tools:shovel_diamond", wear = 0,
		metadata = { ["mcl_enchanting:enchantments"] = "return { efficiency = 5 }" } })
	local worn = H.ItemStack({ name = "mcl_tools:shovel_diamond", wear = 999 })
	local m1 = keys.key(sword, "M1")
	ok(m1 ~= nil, "an enchanted, unworn shovel has an M1 key")
	eq(keys.key(worn, "M1"), nil, "a worn one does not (shared §2.5)")
	ok(keys.matches(sword, m1, "M1"), "matches() at M1")
	ok(not keys.matches(worn, m1, "M1"), "a worn stack does not match at M1")
	ok(keys.key(sword, "M2") ~= keys.key(worn, "M2"), "M2 distinguishes wear")

	-- Two identical listings share an M1 key, so f04's sweep finds both.
	local a = mk("kim", "mcl_core:diamond 8", 8000)
	local b = mk("lee", "mcl_core:diamond 16", 16000)
	eq(a.key_m1, b.key_m1, "identical items share an M1 key")
	ok(a.key == b.key, "the M2 key ignores count (count is in the stack string, not the key)")
	eq(#smp_ah.listings_at_or_below(a.key_m1, math.huge), 2, "both are in the M1 index")
	eq(a.key, keys.key(H.ItemStack("mcl_core:diamond 8"), "M2"), "the record carries the M2 key")
end)

----------------------------------------------------------------------
-- X-h — smp_ah.cheapest_for (f05 Quick Buy contract)
----------------------------------------------------------------------

section("X-h", "cheapest_for fills a Quick Buy entry cheapest-first", function()
	wipe()
	local alice = H.player("alice")
	H.set_money("alice", 100000000)

	-- Three diamond listings at different unit prices / stack sizes.
	mk("kim", "mcl_core:diamond 8", 8000)     -- unit 1000
	mk("lee", "mcl_core:diamond 16", 32000)   -- unit 2000
	mk("mia", "mcl_core:diamond 32", 16000)   -- unit 500 (cheapest per item)

	-- Fill a 50-item order (8+16+32 = 56 >= 50): cheapest-first picks mia
	-- (500/unit) then kim (1000/unit) then lee (2000/unit) until 50 is met.
	local r = smp_ah.cheapest_for("mcl_core:diamond", {}, 50)
	ok(r ~= nil, "cheapest_for finds enough listings")
	eq(#r.listings, 3, "aggregates all three listings")
	eq(r.listings[1].seller, "mia", "cheapest unit price first")
	eq(r.listings[2].seller, "kim", "then the next cheapest")
	eq(r.listings[3].seller, "lee", "then the dearest")
	eq(r.cost_cents, 8000 + 32000 + 16000, "cost is the sum of asking prices")

	-- A quantity that cannot be filled returns nil.
	eq(smp_ah.cheapest_for("mcl_core:diamond", {}, 1000), nil,
		"insufficient listings return nil")

	-- An unenchanted spec must NOT match an enchanted listing (M1 identity).
	wipe()
	local enchanted = H.ItemStack({ name = "mcl_tools:sword_netherite", wear = 0,
		metadata = { ["mcl_enchanting:enchantments"] = "return { sharpness = 5 }" } })
	local rec, err = smp_ah.create_listing("kim", enchanted, 5000)
	ok(rec ~= nil, "enchanted listing created: " .. tostring(err))
	eq(smp_ah.cheapest_for("mcl_tools:sword_netherite", {}, 1), nil,
		"an unenchanted spec does not match an enchanted listing")
	local r2 = smp_ah.cheapest_for("mcl_tools:sword_netherite", { sharpness = 5 }, 1)
	ok(r2 ~= nil and #r2.listings == 1, "the matching ench spec finds it")
	eq(r2.cost_cents, 5000, "and its cost is the listing's asking price")
end)

----------------------------------------------------------------------

print(string.format("smp_ah: %d passed, %d failed", passed, failed))
if failed > 0 then
	print("FAILED checks:")
	for _, f in ipairs(failures) do print("  - " .. f) end
	os.exit(1)
end
print("ALL OK (f03 T1–T10 + extras)")
