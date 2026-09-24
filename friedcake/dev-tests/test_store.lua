-- Smoke test for smp_store mod_storage backend.
-- We verify the backend writes the expected keys, that ledger ids are
-- monotonic, and (D12) that history appends round-trip exactly — so JSON
-- goes through the minimal codec the dev tests share (same shape as
-- test_admin.lua / test_ranks.lua) rather than a throwaway stub.

-- Locate the repository root from the script path so the harness also
-- works from a git worktree checkout (same approach as test_ranks.lua).
local function find_root()
	local script = (arg and arg[0]) or ""
	local prefix = script:match("^(.-)friedcake/dev%-tests/[^/]*$")
	if prefix and prefix ~= "" then
		return (prefix:gsub("/+$", ""))
	end
	local probe = io.open("friedcake/modpack.conf", "r")
	if probe then
		probe:close()
		return "."
	end
	return "/Volumes/Dara/dev/coconut"
end

local ROOT = find_root()

local store = {}
local writes = {}

----------------------------------------------------------------------
-- Minimal JSON codec (same shape as test_admin.lua / test_ranks.lua):
-- the history entries must round-trip through core.write_json /
-- core.parse_json.
----------------------------------------------------------------------

local function json_encode(v)
	local t = type(v)
	if t == "nil"     then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number"  then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if v == math.floor(v) then return string.format("%.0f", v) end
		return tostring(v)
	end
	if t == "string" then
		return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
			local esc = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
				['\r'] = '\\r', ['\t'] = '\\t' }
			return esc[c] or string.format("\\u%04x", c:byte())
		end) .. '"'
	end
	if t == "table" then
		local has_str, n = false, 0
		for k in pairs(v) do
			if type(k) == "string" then has_str = true
			elseif type(k) == "number" and k > n then n = k end
		end
		if not has_str and n > 0 then
			local arr = true
			for i = 1, n do
				if v[i] == nil then arr = false break end
			end
			if arr then
				local p = {}
				for i = 1, n do p[i] = json_encode(v[i]) end
				return "[" .. table.concat(p, ",") .. "]"
			end
		end
		local p = {}
		for k, vv in pairs(v) do
			p[#p + 1] = json_encode(tostring(k)) .. ":" .. json_encode(vv)
		end
		return "{" .. table.concat(p, ",") .. "}"
	end
	return "null"
end

local json_decode
do
	local s, i = "", 1
	local function ws()
		local c = s:sub(i, i)
		while c == " " or c == "\t" or c == "\n" or c == "\r" do
			i = i + 1
			c = s:sub(i, i)
		end
	end
	local function parse_string()
		i = i + 1 -- opening quote
		local out = {}
		while true do
			local c = s:sub(i, i)
			if c == "" then error("unterminated string") end
			if c == '"' then i = i + 1 break end
			if c == "\\" then
				local nc = s:sub(i + 1, i + 1)
				i = i + 2
				if     nc == "n" then out[#out + 1] = "\n"
				elseif nc == "t" then out[#out + 1] = "\t"
				elseif nc == "r" then out[#out + 1] = "\r"
				elseif nc == "u" then
					out[#out + 1] = string.char(tonumber(s:sub(i, i + 3), 16) % 256)
					i = i + 4
				else out[#out + 1] = nc end
			else
				out[#out + 1] = c
				i = i + 1
			end
		end
		return table.concat(out)
	end
	local parse_value
	local function parse_object()
		i = i + 1 -- {
		local out = {}
		ws()
		if s:sub(i, i) == "}" then i = i + 1 return out end
		while true do
			ws()
			if s:sub(i, i) ~= '"' then error("expected key at " .. i) end
			local k = parse_string()
			ws()
			if s:sub(i, i) ~= ":" then error("expected : at " .. i) end
			i = i + 1
			out[k] = parse_value()
			ws()
			local c = s:sub(i, i)
			if c == "," then i = i + 1
			elseif c == "}" then i = i + 1 return out
			else error("expected , or } at " .. i) end
		end
	end
	local function parse_array()
		i = i + 1 -- [
		local out = {}
		ws()
		if s:sub(i, i) == "]" then i = i + 1 return out end
		while true do
			out[#out + 1] = parse_value()
			ws()
			local c = s:sub(i, i)
			if c == "," then i = i + 1
			elseif c == "]" then i = i + 1 return out
			else error("expected , or ] at " .. i) end
		end
	end
	parse_value = function()
		ws()
		local c = s:sub(i, i)
		if c == "{" then return parse_object() end
		if c == "[" then return parse_array() end
		if c == '"' then return parse_string() end
		if s:sub(i, i + 3) == "true"  then i = i + 4 return true end
		if s:sub(i, i + 4) == "false" then i = i + 5 return false end
		if s:sub(i, i + 3) == "null"  then i = i + 4 return nil end
		local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
		if not num or num == "" then error("unexpected char at " .. i) end
		i = i + #num
		return tonumber(num)
	end
	json_decode = function(str)
		if type(str) ~= "string" or str == "" then return nil end
		s, i = str, 1
		return parse_value()
	end
end

local function deep_equal(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not deep_equal(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

core = {
	get_mod_storage = function() return {
		get_string = function(_, k) return store[k] or "" end,
		set_string = function(_, k, v)
			-- Engine semantics: nil or "" removes the key (test_admin.lua).
			if v == nil or v == "" then store[k] = nil
			else store[k] = v end
			writes[#writes+1] = k
		end,
		get_keys   = function(_)
			local out = {}
			for k in pairs(store) do out[#out+1] = k end
			return out
		end,
	} end,
	write_json = json_encode,
	parse_json = json_decode,
	get_translator = function() return function(s, ...) return s end end,
	log = function() end,
	request_insecure_environment = function() return nil end,
	settings = { get = function() return "" end },
	get_worldpath = function() return "/tmp" end,
	get_modpath = function(m) return "/tmp/" .. m end,
	DIR_DELIM = "/",
}

local backend = dofile(ROOT .. "/friedcake/mods/smp_store/backends/mod_storage.lua")
backend.migrate()

-- History helper: the stored entry ids for one (kind, name) list, sorted.
local function history_ids(kind, name)
	local prefix = "history:" .. kind .. ":" .. name .. ":"
	local ids = {}
	for k in pairs(store) do
		if k:sub(1, #prefix) == prefix then
			local n = tonumber(k:sub(#prefix + 1))   -- nil for the nextid key
			if n then ids[#ids + 1] = n end
		end
	end
	table.sort(ids)
	return ids
end

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

----------------------------------------------------------------------
-- D12 history cases (smp_store.api.append_history, driver surface).
-- This file drives only the mod_storage backend — exactly how the ledger
-- cases above are covered. sqlite needs `lsqlite3` (absent on the test
-- host, see dev-tests/README.md) and postgres is the intentional stub
-- that errors on every call, so append_history is unreachable for them
-- here, same as append_ledger.
----------------------------------------------------------------------

-- Test 6: append_history returns an integer id and the entry round-trips.
local hist_entry = {
	time = 1758500300,
	source = "container",
	lines = { { item = "mcl_mobitems:bone", qty = 640, server = 400, order = 240,
	            order_ids = { 3301 }, server_cents = 400000, order_cents = 360000 } },
	server_total = 400000,          -- integer cents, stored verbatim
	order_total  = 360000,
}
local hid = backend.append_history("sell", "alice", hist_entry)
assert(hid == 1, "history ids start at 1 per (kind, name)")
assert(hid == math.floor(hid), "id is an integer, never a float")
assert(hist_entry.id == 1 and type(hist_entry.t) == "number",
	"driver stamps id and t onto the entry")
assert(hist_entry.t >= os.time() - 5 and hist_entry.t <= os.time() + 5,
	"t defaults to os.time()")
assert(store["history:sell:alice:0000000001"], "entry stored under history:<kind>:<name>:NNNNN")
assert(store["history:sell:alice:nextid"] == "2", "history nextid advanced")
local stored = core.parse_json(store["history:sell:alice:0000000001"])
assert(deep_equal(stored, hist_entry),
	"entry round-trips exactly (money as integer cents)")
print("PASS: append_history returns an integer id and round-trips")

-- Test 7: FIFO prune at an explicit cap keeps the newest entries.
for i = 1, 5 do
	local pid = backend.append_history("sell", "prune_me", { n = i, cents = i * 100 }, 3)
	assert(pid == i, "ids keep counting across prunes")
end
local pruned = history_ids("sell", "prune_me")
assert(#pruned == 3, "cap 3 keeps exactly 3 entries")
assert(pruned[1] == 3 and pruned[2] == 4 and pruned[3] == 5,
	"FIFO prune drops the oldest ids and keeps the newest")
assert(store["history:sell:prune_me:0000000001"] == nil, "entry 1 pruned away")
assert(store["history:sell:prune_me:0000000002"] == nil, "entry 2 pruned away")
assert(core.parse_json(store["history:sell:prune_me:0000000003"]).cents == 300,
	"surviving entries are the newest ones")
assert(store["history:sell:prune_me:nextid"] == "6", "pruning never rewinds nextid")
print("PASS: FIFO prune at cap keeps the newest")

-- Test 8: default cap is 100 (sell.history_size's default).
for i = 1, 105 do
	backend.append_history("sell", "big_history", { n = i })
end
local big = history_ids("sell", "big_history")
assert(#big == 100, "default cap is 100")
assert(big[1] == 6 and big[100] == 105, "the newest 100 survive, the oldest 5 are pruned")
assert(store["history:sell:big_history:0000000005"] == nil, "entry 5 pruned at default cap")
assert(store["history:sell:big_history:0000000006"] ~= nil, "entry 6 kept at default cap")
print("PASS: default cap 100, FIFO")

-- Test 9: cap below 1 keeps the newest entry (never an empty list).
backend.append_history("sell", "floor_me", { n = 1 }, 0)
backend.append_history("sell", "floor_me", { n = 2 }, 0)
local floored = history_ids("sell", "floor_me")
assert(#floored == 1 and floored[1] == 2, "cap < 1 keeps the newest entry")
print("PASS: cap below 1 floors at 1")

-- Test 10: kinds never mix for the same name.
backend.append_history("sell", "iso", { tag = "s1" })
backend.append_history("auction", "iso", { tag = "a1" })
local sell_iso = core.parse_json(store["history:sell:iso:0000000001"])
local auc_iso  = core.parse_json(store["history:auction:iso:0000000001"])
assert(sell_iso.tag == "s1" and auc_iso.tag == "a1", "sell and auction lists are separate")
assert(#history_ids("sell", "iso") == 1 and #history_ids("auction", "iso") == 1,
	"each kind keeps its own list")
print("PASS: kind-isolation (sell vs auction)")

-- Test 11: names never mix; each name has its own id sequence.
backend.append_history("sell", "iso", { tag = "s2" })
local bob_hid = backend.append_history("sell", "bob", { tag = "b1" })
assert(bob_hid == 1, "a second name starts its own id sequence at 1")
local iso_ids = history_ids("sell", "iso")
assert(#iso_ids == 2 and iso_ids[2] == 2, "entries accumulate per name only")
local bob_raw = core.parse_json(store["history:sell:bob:0000000001"])
assert(bob_raw.tag == "b1", "bob's list is untouched by iso's")
print("PASS: name-isolation")

-- Test 12: offline names work and history never touches the player blob.
local off_id = backend.append_history("sell", "offline_dave", { tag = "o" })
assert(off_id == 1, "an offline name appends without any player record")
assert(backend.get_player("offline_dave") == nil,
	"history does not create or modify the player record")
print("PASS: offline name works; player blobs untouched")

print("ALL OK (mod_storage backend)")
