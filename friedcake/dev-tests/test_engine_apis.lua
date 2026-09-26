-- FriedcakeSMP dev-tests: engine-API regression guard (P0 brief, item B4-3).
--
-- Background — SPEC-CONFORMANCE-REPORT.md §2, findings B1–B3: the modpack
-- once called engine functions that DO NOT EXIST in Luanti, at load time,
-- in seven mods:
--
--     core.register_on_globalstep(...)  real name: core.register_globalstep
--     core.modpath("x.lua")             real call:  core.get_modpath("modname")
--                                       (returns a directory — the path join
--                                        has to change too)
--
-- A real server aborted during mod loading, so every feature in the pack
-- was unreachable in production. All 11 dev-test suites stayed green
-- anyway, because the harnesses defined fakes for BOTH nonexistent
-- names: the tests encoded the bugs instead of catching them.
--
-- Guarding only those two literal names would have left the next one
-- uncaught (the brief's own audit missed core.register_on_pickup in
-- smp_amethyst), so this guard checks the whole CLASS:
--
--   1. static scan for the two literal names — in mods and in the
--      harnesses (this file is the one allowed exception, because a
--      guard has to name what it forbids);
--   2. every core.* name referenced under friedcake/mods/ must appear in
--      the recorded engine API surface, engine_api_surface.txt — a miss
--      is reported as file:line. This subsumes (1) for the mods and
--      catches any future wrong name, not just today's two;
--   3. loads the real harness and asserts the CORRECT names —
--      core.register_globalstep and core.get_modpath — exist in its
--      `core` stub table, and that the fakes do not.
--
-- Known blind spot: full-line Lua comments are not scanned (they are
-- skipped), so prose may name a missing API without tripping the guard.
-- Trailing comments on a code line ARE scanned.
--
-- Run: luajit friedcake/dev-tests/test_engine_apis.lua
-- Exits non-zero on any failure (tools/agent-flow.sh test).

-- Locate the repository root from the script path so the harness also
-- works from a git worktree checkout (same approach as test_ranks.lua).
local function find_root()
	local script = (arg and arg[0]) or ""
	local prefix = script:match("^(.-)friedcake/dev%-tests/[^/]*$")
	if prefix and prefix ~= "" then
		return (prefix:gsub("/+$", ""))
	end
	local probe = io.open("friedcake/mods/modpack.conf", "r")
	if probe then
		probe:close()
		return "."
	end
	error("cannot locate the repo root: run from the repo root or pass an absolute script path")
end

local ROOT = find_root()
local MODPACK = ROOT .. "/friedcake"
local SELF = "test_engine_apis.lua"

local passed, failed = 0, 0
local function ok(cond, msg)
	if cond then
		passed = passed + 1
		print("PASS: " .. msg)
	else
		failed = failed + 1
		print("FAIL: " .. msg)
	end
end

----------------------------------------------------------------------
-- Static scan helpers
----------------------------------------------------------------------

local function list_lua(dir)
	local files = {}
	local p = io.popen(string.format(
		'find "%s" -type f -name "*.lua" 2>/dev/null', dir))
	if p then
		for line in p:lines() do files[#files + 1] = line end
		p:close()
	end
	table.sort(files)
	return files
end

local function read_lines(f)
	local fh = io.open(f, "r")
	if not fh then return nil end
	local out = {}
	for line in fh:lines() do out[#out + 1] = line end
	fh:close()
	return out
end

-- The two names the engine does not have. These literals appear here —
-- and nowhere else under friedcake/ — because a guard must name its
-- forbidden symbols; that single exception is allowed by acceptance
-- criterion 2 of fixes/00-P0-blockers.md.
local FORBIDDEN = {
	{ what = "register_on_globalstep (engine has core.register_globalstep)",
	  pat = "register_on_globalstep" },
	{ what = "core.modpath (engine has core.get_modpath)",
	  pat = "core%.modpath" },
}

-- Returns "path:line: <what>" for every hit.
local function scan(files, rules)
	local hits = {}
	for _, f in ipairs(files) do
		local lines = read_lines(f)
		if lines then
			for n, line in ipairs(lines) do
				for _, rule in ipairs(rules) do
					if line:find(rule.pat) then
						hits[#hits + 1] =
							string.format("%s:%d: %s", f, n, rule.what)
					end
				end
			end
		end
	end
	return hits
end

-- Every `core.<name>` a file references, with line numbers, filtered to
-- names missing from `accepted`.
--
-- The leading-character guard keeps prose out of the results: it rejects
-- "f01-economy-core.md" (hyphen before `core`), "smp_core.md" and
-- "mcl_core.something" (underscore), none of which are API references.
local function scan_unresolved(files, accepted)
	local hits = {}
	for _, f in ipairs(files) do
		local lines = read_lines(f)
		if lines then
			for n, line in ipairs(lines) do
				-- skip full-line comments (see the blind spot above)
				if not line:match("^%s*%-%-") then
					local padded = " " .. line
					local i = 1
					while true do
						local s, e, name =
							padded:find("[^%w_%-]core%.([%a_][%w_]*)", i)
						if not s then break end
						if not accepted[name] then
							hits[#hits + 1] = string.format(
								"%s:%d: core.%s is not in engine_api_surface.txt",
								f, n, name)
						end
						i = e + 1
					end
				end
			end
		end
	end
	return hits
end

local function report(hits, limit)
	if #hits == 0 then return "" end
	limit = limit or 20
	local shown = {}
	for i = 1, math.min(limit, #hits) do shown[#shown + 1] = hits[i] end
	local more = #hits - #shown
	return "\n  " .. table.concat(shown, "\n  ")
		.. (more > 0 and string.format("\n  ... and %d more", more) or "")
end

----------------------------------------------------------------------
-- Recorded engine API surface (see the header of that file for how it
-- is generated from the local engine clone).
----------------------------------------------------------------------

local accepted, surface_n = {}, 0
do
	local lines = read_lines(MODPACK .. "/dev-tests/engine_api_surface.txt")
	if lines then
		for _, line in ipairs(lines) do
			local body = line:gsub("#.*", ""):gsub("^%s+", ""):gsub("%s+$", "")
			local name = body:match("^([^%s]+)")
			if name and not accepted[name] then
				accepted[name] = true
				surface_n = surface_n + 1
			end
		end
	end
end

----------------------------------------------------------------------
-- Enumeration + sanity (without these every check below could pass
-- vacuously on an empty file list)
----------------------------------------------------------------------

local mod_files = list_lua(MODPACK .. "/mods")
-- Exclude in-mod test files (they test the guard, not use the bad API)
local filtered_mod_files = {}
for _, f in ipairs(mod_files) do
	if not f:match("/test%.lua$") then
		filtered_mod_files[#filtered_mod_files + 1] = f
	end
end
mod_files = filtered_mod_files
local dev_files = list_lua(MODPACK .. "/dev-tests")

ok(#mod_files >= 20,
	string.format("scanner sanity: enumerated %d lua files under mods/", #mod_files))
ok(#dev_files >= 15,
	string.format("scanner sanity: enumerated %d lua files under dev-tests/", #dev_files))
ok(surface_n >= 500,
	string.format("scanner sanity: loaded %d accepted names from engine_api_surface.txt",
		surface_n))

local known = scan(mod_files,
	{ { what = "known-present", pat = "register_globalstep" } })
ok(#known >= 1,
	string.format("scanner sanity: reader finds a pattern known to occur (%d hits)",
		#known))

----------------------------------------------------------------------
-- 1. Neither the mods nor the harnesses may use the two literal names
--    the engine does not have.
----------------------------------------------------------------------

local mod_hits = scan(mod_files, FORBIDDEN)
ok(#mod_hits == 0,
	"mods/: no reference to a nonexistent engine API" .. report(mod_hits))

local others = {}
for _, f in ipairs(dev_files) do
	if f:match("[^/]+$") ~= SELF then others[#others + 1] = f end
end
ok(#others < #dev_files, "scanner sanity: this guard excludes itself from its own scan")

local dev_hits = scan(others, FORBIDDEN)
ok(#dev_hits == 0,
	"dev-tests/: harnesses stub only engine-real names" .. report(dev_hits))

----------------------------------------------------------------------
-- 2. The class-level check: every core.* name the mods reference must
--    be one the engine actually provides.
----------------------------------------------------------------------

local unresolved = scan_unresolved(mod_files, accepted)
ok(#unresolved == 0,
	string.format("mods/: all core.* references resolve against the %d-name engine surface",
		surface_n) .. report(unresolved))

----------------------------------------------------------------------
-- 3. The harness's `core` stub must define the REAL names, so a
--    harness can never again mask a wrong-name regression.
----------------------------------------------------------------------

local H = dofile(MODPACK .. "/dev-tests/harness_f10.lua")
ok(type(H) == "table", "harness_f10.lua loads and returns its handle")

local stub = rawget(_G, "core")
ok(type(stub) == "table", "harness exposes a core stub table")

if type(stub) == "table" then
	ok(type(stub.register_globalstep) == "function",
		"core stub defines register_globalstep (engine-real name)")
	ok(type(stub.get_modpath) == "function",
		"core stub defines get_modpath (engine-real name)")

	ok(rawget(stub, "register_on_globalstep") == nil,
		"core stub does not fake register_on_globalstep")
	ok(rawget(stub, "modpath") == nil,
		"core stub does not fake core.modpath")
	ok(rawget(stub, "register_on_pickup") == nil,
		"core stub does not fake register_on_pickup (client-free name)")
	ok(rawget(stub, "get_player_names") == nil,
		"core stub does not fake get_player_names (client-only name)")
end

----------------------------------------------------------------------
print(string.format("engine-API guard: passed=%d failed=%d", passed, failed))
if failed > 0 then
	print("TEST_ENGINE_APIS FAILED")
	os.exit(1)
end
print("ALL OK")
os.exit(0)
