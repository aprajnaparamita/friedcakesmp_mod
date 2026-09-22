-- Smoke test for smp_store mod_storage backend.
-- We don't round-trip JSON — that's the engine's job. We verify the
-- backend writes the expected keys and that ledger ids are monotonic.

local store = {}
local writes = {}

core = {
	get_mod_storage = function() return {
		get_string = function(_, k) return store[k] or "" end,
		set_string = function(_, k, v) store[k] = v; writes[#writes+1] = k end,
		get_keys   = function(_)
			local out = {}
			for k in pairs(store) do out[#out+1] = k end
			return out
		end,
	} end,
	write_json = function(v)
		-- encode just enough to be string-like; we don't read back
		return "JSON(" .. type(v) .. ")"
	end,
	parse_json = function(s)
		-- we never round-trip in this test
		return nil
	end,
	get_translator = function() return function(s, ...) return s end end,
	log = function() end,
	request_insecure_environment = function() return nil end,
	settings = { get = function() return "" end },
	get_worldpath = function() return "/tmp" end,
	get_modpath = function(m) return "/tmp/" .. m end,
	DIR_DELIM = "/",
}

local backend = dofile("/Volumes/Dara/dev/coconut/friedcake/mods/smp_store/backends/mod_storage.lua")
backend.migrate()

-- Test 1: upsert_player writes a player key.
backend.upsert_player({
	name = "alice", first_join = 1000, money = 0, shards = 0, playtime = 0,
	rank = {}, homes = {}, stats = {}, social = {}, quickbuy = {}, keys = {},
})
assert(store["player:alice"], "player:alice key written")
print("PASS: upsert_player writes player:<name>")

-- Test 2: all_player_names enumerates offline players.
local names = backend.all_player_names()
local has_alice = false
for _, n in ipairs(names) do if n == "alice" then has_alice = true end end
assert(has_alice, "alice appears in all_player_names")
print("PASS: all_player_names enumerates offline players")

-- Test 3: ledger append assigns monotonic ids.
local id1 = backend.append_ledger({ type = "ah_sale", actor = "alice",
	amount = 64000000, currency = "money", qty = 64, ref = "ah:1", flags = {} })
local id2 = backend.append_ledger({ type = "ah_buy", actor = "alice",
	amount = -64000000, currency = "money", qty = 64, ref = "ah:1", flags = {} })
assert(id1 == 1 and id2 == 2, "ids start at 1 and increase")
assert(store["ledger:0000000001"], "ledger 1 stored")
assert(store["ledger:0000000002"], "ledger 2 stored")
assert(store["ledger:nextid"] == "3", "nextid advanced")
print("PASS: ledger append is monotonic")

-- Test 4: ledger_for returns sensible page count even when entries are
-- unparseable JSON (the engine would normally parse; we just check shape).
local _, pages = backend.ledger_for("alice", 1, 10)
assert(pages >= 1, "ledger_for returns total_pages >= 1")
print("PASS: ledger_for returns valid total_pages")

-- Test 5: flush / close are no-ops.
backend.flush(); backend.close()
print("PASS: flush+close")

print("ALL OK (mod_storage backend)")
