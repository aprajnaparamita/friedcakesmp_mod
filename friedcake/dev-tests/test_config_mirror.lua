-- dev-tests/test_config_mirror.lua — D7 three-set guard
--
-- Re-derives the three configuration sets and enforces that
-- spec/shared/06-config-reference.md (MIRROR) and every feature file's
-- §7 table (DECLARED) agree with what the pack actually reads (READ):
--
--   READ      every core.settings access in friedcake/mods/** production
--             files (literal calls + helper-wrapped calls + the explicit
--             PREFIX_PATTERNS expansions for prefix-composed reads).
--             In-mod test files (basename starting `test`) are skipped:
--             they stub the engine, they are not the config contract.
--   DECLARED  the union of all `## 7. Configuration` first-cell keys
--             across spec/features/*.md (multi-key cells and `x.*`
--             prefix rows expanded). f16-legacy.md is skipped: DESCOPED
--             permanently (D8, 2026-09-24) — its §7 table documents a
--             feature that will never exist, which is why the four
--             `legacy.*` mirror rows are struck.
--   MIRROR    every first-cell key of shared/06's table.
--
-- Checks (fixes/prompts/p2-config-mirror.md R6):
--   1. every pack-prefixed READ key is in MIRROR
--   2. every MIRROR row is READ or DECLARED_ONLY or DECLARED
--   3. every DECLARED key is in MIRROR
--   4. stale DECLARED_ONLY entries (brief landed / key now read) fail
--   5. prefix-composed reads only expand through PREFIX_PATTERNS below
--   6. foreign prefixes (mcl_, server., mg_, beds_, tt, …) are skipped
--      unless some §7 declares them
--   7. duplicate MIRROR rows fail
--
-- Run: luajit friedcake/dev-tests/test_config_mirror.lua
-- Prints a summary + the DECLARED_ONLY drain list and exits 0 on success.

local ROOT = ((arg and arg[0]) or ""):match("^(.*)friedcake/dev-tests/[^/]+$") or "./"
local MIRROR_PATH = ROOT .. "spec/shared/06-config-reference.md"
local FEATURES_DIR = ROOT .. "spec/features/"
local MODS_DIR = ROOT .. "friedcake/mods/"

----------------------------------------------------------------------
-- Tables under review (a rename shows up here, never silently)
----------------------------------------------------------------------

-- Declared-only keys: advertised in a feature §7 but not yet read by
-- code, pending a specific brief. When that brief lands its read, check
-- 4 fails this entry as stale until it is removed here (and the drain
-- list shrinks).
local DECLARED_ONLY = {
	-- f03 brief A6 owns the history storage seam: today's reads are
	-- `ah.history_page` / `ah.history_pages` (smp_ah/init.lua:51-52).
	["ah.history"] = "f03",
	-- f04 brief O3: code reads the underscore alias only
	-- (smp_orders/init.lua:42-45); dotted `orders.slots.*` is the
	-- documented primary spelling (shared/06 R4).
	["orders.slots.*"] = "f04",
	-- f07 brief F07-8/9: code reads the compound `spawners.C` list
	-- (smp_spawners/init.lua:93); the per-type keys are not read yet.
	["spawners.C.skeleton"] = "f07",
}

-- Brief ids whose DECLARED_ONLY duty is discharged (P1/P3-era items
-- only, per the prompt). P1 struck `settings.categories` from MIRROR and
-- §7 entirely; P3 struck the four `legacy.*` rows — neither left an
-- entry behind, so this list starts empty.
local drained = {}

-- Prefix-composed reads: site (must literally appear in file) → how to
-- expand. Editing one of these concats in code without updating this
-- table fails check 5 explicitly.
local PREFIX_PATTERNS = {
	{
		-- smp_tp's `setting()` helper composes "smp_tp." .. key
		-- (smp_tp/config.lua:11, smp_tp/homes.lua:46). Only helper
		-- calls in these files get the prefix; the direct
		-- `core.settings:get("world.spawn_protect_radius")` does not.
		kind = "file_prefix",
		helper = "setting",
		prefix = "smp_tp.",
		files = { ["smp_tp/config.lua"] = true, ["smp_tp/homes.lua"] = true },
		site = '"smp_tp." .. key',
	},
	{
		-- smp_store SETTING_KEYS loop (init.lua:29).
		kind = "expand",
		file = "smp_store/init.lua",
		site = '"store." .. k',
		expand = {
			"store.backend", "store.flush_interval",
			"store.max_balance", "store.ledger_page_size",
		},
	},
	{
		-- smp_ah reload tier loop (init.lua:85).
		kind = "expand",
		file = "smp_ah/init.lua",
		site = '"ah.slots." .. tier',
		expand = {
			"ah.slots.default", "ah.slots.tier1",
			"ah.slots.tier2", "ah.slots.tier3",
		},
	},
	{
		-- smp_ranks slot-table helper (tiers.lua:77-79) reads the
		-- flattened underscore keys for all three perk tables.
		kind = "expand",
		file = "smp_ranks/tiers.lua",
		site = 'prefix .. ".slots_default"',
		expand = {
			"homes.slots_default", "homes.slots_tier1",
			"homes.slots_tier2", "homes.slots_tier3",
			"ah.slots_default", "ah.slots_tier1",
			"ah.slots_tier2", "ah.slots_tier3",
			"orders.slots_default", "orders.slots_tier1",
			"orders.slots_tier2", "orders.slots_tier3",
		},
	},
	{
		-- smp_ranks cooldown loop (tiers.lua:111); default/tier1 are
		-- literal get_num calls and are caught by the helper scan.
		kind = "expand",
		file = "smp_ranks/tiers.lua",
		site = '"rtp.cooldown_" .. id',
		expand = { "rtp.cooldown_tier2", "rtp.cooldown_tier3", "rtp.cooldown_media" },
	},
	{
		-- smp_social/info.lua info screens: keys live in `def.key`
		-- fields, not call arguments.
		kind = "expand",
		file = "smp_social/info.lua",
		site = 'key = "info.',
		expand = {
			"info.help", "info.rules", "info.discord", "info.media",
			"info.link", "info.store", "info.website", "info.ranks",
			"info.medal",
		},
	},
}

-- Helper functions whose FIRST string argument is a settings key.
local HELPERS = {
	"setting", "num_setting", "list_setting", "setting_number",
	"setting_bool", "num", "str", "bool",
	"get_str", "get_num", "get_bool", "cfg_number", "cfg_bool",
	"cfg_string", "get_info",
}

-- Direct engine reads: core.settings:get / get_bool / get_np / get_string.
local DIRECT = "settings%s*:%s*get[%w_]*%s*%(%s*\"([^\"]+)\""

local FOREIGN_PREFIXES = { "mcl_", "server.", "mg_", "beds_", "tt" }

-- Descoped features excluded from DECLARED (see header).
local DESCOPED = { ["f16-legacy.md"] = "D8 (2026-09-24): never to be built" }

----------------------------------------------------------------------
-- Small utilities
----------------------------------------------------------------------

local violations = {}

local function fail(msg)
	violations[#violations + 1] = msg
end

local function read_file(path)
	local fh = io.open(path, "r")
	if not fh then return nil end
	local data = fh:read("*a")
	fh:close()
	return data
end

local function list_files(dir, suffix)
	local out = {}
	local p = io.popen('find "' .. dir .. '" -maxdepth 2 -name "*' .. suffix .. '" 2>/dev/null')
	if not p then return out end
	for line in p:lines() do out[#out + 1] = line end
	p:close()
	table.sort(out)
	return out
end

local function basename(path)
	return path:match("([^/]+)$") or path
end

local function is_foreign(key)
	for _, p in ipairs(FOREIGN_PREFIXES) do
		if key:sub(1, #p) == p then return true end
	end
	return false
end

-- First cell of a markdown table row → backticked key tokens.
local function first_cell_keys(line)
	local cell = line:match("^|%s*([^|]*)%s*|")
	if not cell then return nil end
	local keys = {}
	for tok in cell:gmatch("`([^`]+)`") do
		keys[#keys + 1] = tok
	end
	return keys
end

----------------------------------------------------------------------
-- READ: derive from code
----------------------------------------------------------------------

local read = {} -- key -> { sites... }
local read_add = function(key, site)
	if not key or key == "" then return end
	if not key:find(".", 1, true) then return end -- config keys are dotted
	if key:sub(-1) == "." then return end -- concat prefix fragment ("smp_tp.", "store.", …)
	local e = read[key]
	if not e then e = { sites = {} }; read[key] = e end
	for _, s in ipairs(e.sites) do
		if s == site then return end
	end
	e.sites[#e.sites + 1] = site
end

local scan_files = {}
for _, path in ipairs(list_files(MODS_DIR, ".lua")) do
	local base = basename(path)
	if base:sub(1, 4) ~= "test" then -- production files only
		scan_files[#scan_files + 1] = path
	end
end

for _, path in ipairs(scan_files) do
	local rel = path:sub(#MODS_DIR + 1) -- e.g. smp_tp/config.lua
	local src = read_file(path)
	if src then
		local n = 0
		for line in (src .. "\n"):gmatch("(.-)\n") do
			n = n + 1
			local site = rel .. ":" .. n
			-- direct core.settings:get*( "key" )
			for key in (" " .. line):gmatch(DIRECT) do
				read_add(key, site)
			end
			-- helper-wrapped reads: helper("key", …)
			for _, h in ipairs(HELPERS) do
				local pat = "[^%w_]" .. h .. "%s*%(%s*\"([^\"]+)\""
				for key in (" " .. line):gmatch(pat) do
					-- smp_tp's setting() helper composes the prefix.
					local prefixed = false
					for _, entry in ipairs(PREFIX_PATTERNS) do
						if entry.kind == "file_prefix"
						   and entry.helper == h and entry.files[rel] then
							key = entry.prefix .. key
							prefixed = true
						end
					end
					read_add(key, site .. (prefixed and (" (" .. h .. " → prefix)") or ""))
				end
			end
			-- info screen def.key fields
			for key in line:gmatch("key%s*=%s*\"(info%.[%w_]+)\"") do
				read_add(key, site)
			end
		end
	end
end

-- Explicit prefix-pattern expansions (check 5): each site must exist.
for _, entry in ipairs(PREFIX_PATTERNS) do
	local files = {}
	if entry.kind == "expand" then files[entry.file] = true end
	if entry.kind == "file_prefix" then files = entry.files end
	local found = false
	for rel in pairs(files) do
		local src = read_file(MODS_DIR .. rel)
		if src and src:find(entry.site, 1, true) then found = true end
	end
	if not found then
		fail("PREFIX_PATTERNS site not found in code: " .. entry.site
			.. " — update the expansion table")
	else
		for _, key in ipairs(entry.expand or {}) do
			read_add(key, (entry.file or "smp_tp/*") .. " (PREFIX_PATTERNS: "
				.. entry.site .. ")")
		end
	end
end

----------------------------------------------------------------------
-- DECLARED: union of feature §7 first cells
----------------------------------------------------------------------

local declared = {}
local declared_src = {}
local skipped_features = {}
local function declared_add(key, origin)
	if declared[key] then
		declared_src[key] = declared_src[key] .. ", " .. origin
	else
		declared[key] = true
		declared_src[key] = origin
	end
end

for _, path in ipairs(list_files(FEATURES_DIR, ".md")) do
	local base = basename(path)
	if DESCOPED[base] then
		skipped_features[base] = DESCOPED[base]
	else
		local src = read_file(path)
		local in_s7 = false
		local n = 0
		for line in (src .. "\n"):gmatch("(.-)\n") do
			n = n + 1
			if line:match("^## 7%. Configuration") then
				in_s7 = true
			elseif in_s7 and line:match("^## ") then
				in_s7 = false
			elseif in_s7 then
				local keys = first_cell_keys(line)
				if keys then
					for _, k in ipairs(keys) do
						declared_add(k, base .. ":" .. n)
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- MIRROR: shared/06 first cells
----------------------------------------------------------------------

local mirror_order = {} -- tokens in row order (duplicates check)
local mirror = {}
local mirror_src = {}
do
	local src = read_file(MIRROR_PATH)
	if not src then
		print("FAIL: cannot read " .. MIRROR_PATH)
		os.exit(1)
	end
	local n = 0
	for line in (src .. "\n"):gmatch("(.-)\n") do
		n = n + 1
		local keys = first_cell_keys(line)
		if keys then
			for _, k in ipairs(keys) do
				mirror_order[#mirror_order + 1] = k
				if not mirror[k] then
					mirror[k] = { row = n }
					mirror_src[k] = tostring(n)
				else
					mirror_src[k] = mirror_src[k] .. "," .. n
				end
			end
		end
	end
end

local function is_prefix_row(key)
	return key:sub(-2) == ".*"
end

-- key is present in a set, allowing `x` ⇄ `x.*` base/prefix coverage.
local function set_covers(set, key, prefix_list)
	if set[key] then return true end
	if is_prefix_row(key) then
		local base = key:sub(1, -3)
		if set[base] then return true end
	else
		if set[key .. ".*"] then return true end
	end
	for _, p in ipairs(prefix_list) do
		if key:sub(1, #p) == p then return true end
	end
	return false
end

local function prefixes_of(set)
	local out = {}
	for k in pairs(set) do
		if is_prefix_row(k) then out[#out + 1] = k:sub(1, -2) end -- "x.*" → "x."
	end
	return out
end

local mirror_prefixes = prefixes_of(mirror)
local declared_prefixes = prefixes_of(declared)

local function read_covers(key)
	if read[key] then return true end
	if is_prefix_row(key) then
		local p = key:sub(1, -2) -- "x.*" → "x."
		for k in pairs(read) do
			if k:sub(1, #p) == p then return true end
		end
	end
	return false
end

----------------------------------------------------------------------
-- Checks
----------------------------------------------------------------------

local pack_read, foreign_read = 0, 0

-- 1 + 6: every pack-prefixed READ key is in MIRROR (foreign skipped
-- unless some §7 declares it).
for key, info in pairs(read) do
	local declared_here = declared[key] == true
	if is_foreign(key) then
		foreign_read = foreign_read + 1
		if declared_here and not set_covers(mirror, key, mirror_prefixes) then
			fail(key .. " read at " .. info.sites[1]
				.. " but absent from shared/06 (foreign key, declared in §7)")
		end
	else
		pack_read = pack_read + 1
		if not set_covers(mirror, key, mirror_prefixes) then
			fail(key .. " read at " .. info.sites[1] .. " but absent from shared/06")
		end
	end
end

-- 2: every MIRROR row is READ or DECLARED_ONLY or DECLARED.
for key in pairs(mirror) do
	if not read_covers(key)
	   and not DECLARED_ONLY[key]
	   and not set_covers(declared, key, declared_prefixes) then
		fail(key .. " advertised but unread (mirror row " .. mirror_src[key] .. ")")
	end
end

-- 3: every DECLARED key is in MIRROR.
for key in pairs(declared) do
	if not set_covers(mirror, key, mirror_prefixes) then
		fail(key .. " in " .. (declared_src[key] or "?") .. " §7 but absent from shared/06")
	end
end

-- 4: stale DECLARED_ONLY entries.
local drain = {}
for key, brief in pairs(DECLARED_ONLY) do
	if read_covers(key) then
		fail("DECLARED_ONLY stale: " .. key .. " is now read — remove the entry")
	end
	for _, d in ipairs(drained) do
		if d == brief then
			fail("DECLARED_ONLY stale: brief " .. brief .. " already drained — remove " .. key)
		end
	end
	drain[#drain + 1] = { key = key, brief = brief }
end
table.sort(drain, function(a, b) return a.key < b.key end)

-- 7: duplicate MIRROR rows.
local seen = {}
for _, k in ipairs(mirror_order) do
	seen[k] = (seen[k] or 0) + 1
end
for k, c in pairs(seen) do
	if c > 1 then
		fail("duplicate MIRROR row: " .. k .. " (" .. c .. "×)")
	end
end

----------------------------------------------------------------------
-- Summary
----------------------------------------------------------------------

local rows = 0
do
	local fh = io.open(MIRROR_PATH, "r")
	for line in fh:lines() do
		if line:match("^|") and not line:match("^|%s*%-") then rows = rows + 1 end
	end
	fh:close()
end

local declared_count = 0
for _ in pairs(declared) do declared_count = declared_count + 1 end
local read_count = 0
for _ in pairs(read) do read_count = read_count + 1 end
local mirror_count = 0
for _ in pairs(mirror) do mirror_count = mirror_count + 1 end

print("config mirror guard (D7) — READ vs DECLARED vs MIRROR")
print(string.format("  READ     : %d keys (pack %d, foreign %d) from %d production files",
	read_count, pack_read, foreign_read, #scan_files))
print(string.format("  DECLARED : %d keys from feature §7 tables", declared_count))
for base, why in pairs(skipped_features) do
	print("             (skipped " .. base .. ": " .. why .. ")")
end
print(string.format("  MIRROR   : %d keys in %d table rows", mirror_count, rows - 1))
print("  DECLARED_ONLY drain list (" .. #drain .. "):")
for _, d in ipairs(drain) do
	print(string.format("    %-28s brief %s", d.key, d.brief))
end

if #violations > 0 then
	print("")
	print("VIOLATIONS (" .. #violations .. "):")
	for _, v in ipairs(violations) do print("  FAIL " .. v) end
	os.exit(1)
end

print("")
print("ALL OK — zero unexplained rows in both directions")
os.exit(0)
