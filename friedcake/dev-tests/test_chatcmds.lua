-- FriedcakeSMP dev-tests: pack-wide chat-command lint (MS-2, S06/SP-1).
--
-- Background — fixes/security/S06-spawners.md: smp_spawners registered
-- `/spawner` with `privilege = "smp_admin"`. The engine only ever reads
-- `privs` (luanti builtin/common/chatcommands.lua:44-51 —
-- `def.privs = def.privs or {}`), so the typo asked for NOTHING and
-- every player could mint spawners with `/spawner give`. One dead key,
-- no error, no warning: exactly the class of bug a lint exists for.
--
-- WHAT THIS SCANS
--   Every `*.lua` under friedcake/mods/, for registration sites of
--       core.register_chatcommand(...)
--       core.override_chatcommand(...)
--       smp_social.register_cmd(...)      (the pack's own wrapper)
--   and for each site whose `def` is a literal table it extracts the
--   depth-1 keys of that table.
--
-- HOW (mechanism, so the result is auditable and not a grep trick)
--   1. mask(): a single pass that blanks comments, short strings and
--      long-bracket strings/comments to spaces while PRESERVING every
--      newline, so structure is parseable and line numbers stay exact.
--      Prose such as `-- the old privilege = "smp_admin"` therefore
--      cannot trip the lint.
--   2. sites are found on the masked text (structure only), the
--      matching `)` is found by bracket depth, and the def table is the
--      first top-level `{` inside the argument list.
--   3. keys are read with a small table-constructor scanner that tracks
--      "expect key" vs "expect value" at depth 0, so `func = function()
--      local x = 1 end` does not report `x` as a key.
--   4. the command NAME is read from the ORIGINAL text (the masked one
--      has blanked the string literal).
--
-- RULES (a violation is a failure; the suite exits non-zero)
--   R1  `privilege` key            — SP-1: the engine ignores it, so
--                                     this def demands no privilege at
--                                     all. Reported separately because
--                                     it is the bug that prompted MS-2.
--   R2  any key outside {params, description, privs, func,
--       mod_origin}                — the engine reads exactly those five
--                                     (chatcommands.lua:44-51 +
--                                     chat.lua:73). Any other key is
--                                     dead: a typo like `privs_` or
--                                     `paramz` silently does nothing,
--                                     which is the same failure mode as
--                                     R1. New def keys are added by
--                                     changing KNOWN_KEYS here (and
--                                     saying why in the comment).
--   R3  admin-sounding command with no `privs` key — see
--       ADMIN_WORDS + EXEMPT below. The name is only a heuristic: it
--       cannot know what a command does, so it errs towards flagging
--       and every legitimate exception is listed in EXEMPT with the
--       file:line of the guard that replaces the privilege.
--
-- NON-FATAL NOTES (printed, limits of the method — they are NOT
-- failures, because resolving them needs a compiler, not a lint)
--   N1  def passed as a variable      — `core.register_chatcommand(n,
--                                       def)` inside smp_social's
--                                       wrapper and its mods-loaded re-
--                                       assertion. The CALLERS pass
--                                       literal tables and are scanned
--                                       instead.
--   N2  command name passed as a variable — R3 cannot be applied to
--       that site (`smp_ah`'s alias loop, `smp_social/info.lua`'s link
--       loop). Its def keys ARE still checked (R1/R2).
--   N3  `privs = {}` — declares an empty privilege set. That is a real
--       engine value (equivalent to "everyone"), so it satisfies R3,
--       but it deserves a human look for an admin-sounding name.
--   N4  non-identifier (quoted) def key — not extracted; would show up
--       as a missing known key only if the rest of the table were
--       empty. None exist in the pack today.
--
-- KNOWN BLIND SPOTS (documented, not silently ignored)
--   * Aliases, wrappers and defs built at runtime are not resolved
--     (N1/N2).
--   * R3 reads the NAME only, so `/spawner give …` — whose own name is
--     innocent — is caught by R1, not R3. R3 is the belt; R1/R2 are the
--     braces.
--   * Behaviour (what func actually does) is out of scope: this is a
--     static lint with no engine, no privilege graph and no yielding
--     analysis.
--
-- PROOF THAT IT CATCHES THE BUG (see the fixture section below)
--   * fixture: a `privilege = "smp_admin"` def is flagged by R1;
--   * fixture: a `paramz = ""` def is flagged by R2;
--   * fixture: an unguarded `banplayer` def is flagged by R3;
--   * regression: the pre-fix source, fetched with
--     `git show 85e4a5d:friedcake/mods/smp_spawners/init.lua`, is
--     flagged by R1 (skipped with a notice if that object is not in
--     the local object database);
--   * negative control: today's smp_spawners/init.lua scans clean.
--
-- Run: luajit friedcake/dev-tests/test_chatcmds.lua
-- Exits non-zero on any failure (tools/agent-flow.sh test).

local function find_root()
	local script = (arg and arg[0]) or ""
	local prefix = script:match("^(.-)friedcake/dev%-tests/[^/]*$")
	if prefix and prefix ~= "" then
		return (prefix:gsub("/+$", ""))
	end
	-- The modpack manifest is friedcake/mods/modpack.conf; probing the
	-- non-existent friedcake/modpack.conf made relative runs fall back
	-- to a hardcoded checkout (i.e. lint somebody else's tree).
	local probe = io.open("friedcake/mods/modpack.conf", "r")
	if probe then
		probe:close()
		return "."
	end
	return "/Volumes/Dara/dev/coconut"
end

local ROOT = find_root()
local MODS = ROOT .. "/friedcake/mods"
local SELF = "test_chatcmds.lua"

local passed, failed = 0, 0
local function ok(cond, msg)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. tostring(msg))
	end
end
local function eq(a, b, msg)
	if a == b then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("FAIL: %s — expected %s got %s",
			tostring(msg), tostring(b), tostring(a)))
	end
end

----------------------------------------------------------------------
-- 1. Masking: comments and strings -> spaces, newlines preserved
----------------------------------------------------------------------

-- If `s` at index j starts a long bracket `[=*[`, return the `=`
-- string ("" for `[[`); otherwise nil.
local function long_level(s, j)
	if s:sub(j, j) ~= "[" then return nil end
	local k, eq = j + 1, 0
	while s:sub(k, k) == "=" do
		eq = eq + 1
		k = k + 1
	end
	if s:sub(k, k) == "[" then return string.rep("=", eq) end
	return nil
end

local function blank(s, from, to)
	-- Preserve newlines so line numbers survive masking.
	local out = {}
	for i = from, to do
		local c = s:sub(i, i)
		out[#out + 1] = (c == "\n") and "\n" or " "
	end
	return table.concat(out)
end

local function mask(src)
	local out, i, n = {}, 1, #src
	while i <= n do
		local c = src:sub(i, i)
		if src:sub(i, i + 1) == "--" then
			local lvl = long_level(src, i + 2)
			if lvl then
				local close = "]" .. lvl .. "]"
				local _, e = src:find(close, i + 2 + #lvl + 2, true)
				local stop = e or n
				out[#out + 1] = blank(src, i, stop)
				i = stop + 1
			else
				local stop = (src:find("\n", i, true) or (n + 1)) - 1
				out[#out + 1] = blank(src, i, stop)
				i = stop + 1
			end
		elseif c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local ch = src:sub(j, j)
				if ch == "\\" then
					j = j + 2
				elseif ch == c then
					j = j + 1
					break
				elseif ch == "\n" then
					-- unterminated string: stop at the line end
					break
				else
					j = j + 1
				end
			end
			local stop = math.min(j, n + 1)
			out[#out + 1] = blank(src, i, stop - 1)
			i = stop
		else
			local lvl = long_level(src, i)
			if lvl then
				local close = "]" .. lvl .. "]"
				local _, e = src:find(close, i + #lvl + 2, true)
				local stop = e or n
				out[#out + 1] = blank(src, i, stop)
				i = stop + 1
			else
				out[#out + 1] = c
				i = i + 1
			end
		end
	end
	return table.concat(out)
end

----------------------------------------------------------------------
-- 2. Registration sites
----------------------------------------------------------------------

local CALL_PATTERNS = {
	"core%.register_chatcommand%s*%(",
	"core%.override_chatcommand%s*%(",
	"smp_social%.register_cmd%s*%(",
}

-- Matching closer for the bracket opened at `open` (a `(` index).
local function match_bracket(s, open)
	local open_ch = s:sub(open, open)
	local close_ch = ({ ["("] = ")", ["{"] = "}", ["["] = "]" })[open_ch]
	local depth, i, n = 0, open, #s
	while i <= n do
		local c = s:sub(i, i)
		if c == open_ch then
			depth = depth + 1
		elseif c == close_ch then
			depth = depth - 1
			if depth == 0 then return i end
		end
		i = i + 1
	end
	return nil
end

-- Depth-1 keys of a table constructor body (masked text).
--
-- Two things make this more than a split on commas:
--   * `mode` alternates on a depth-0 `,`/`;`, so only "expect key"
--     positions are read as keys;
--   * `fn` counts open blocks that end with `end` (`function`, `if`,
--     `for`, `while`, `do`, `repeat`). While `fn > 0` we are inside a
--     VALUE (the `func = function() … end` body), so its
--     `local x = 1`, its `return false, NO_PRIV` commas and its
--     `parts[1]` indexing are never mistaken for def keys. Strings and
--     comments are already masked, so keywords in prose cannot count.
--
-- Returns keys (set), order (list) and values (key -> raw value text,
-- needed to tell `privs = {}` from `privs = { smp_admin = true }`).
local BLOCK_OPEN = { ["function"] = true, ["if"] = true, ["for"] = true,
	["while"] = true, ["repeat"] = true }

local function table_keys(body)
	local keys, order, values = {}, {}, {}
	local mode, depth, fn = "key", 0, 0
	local pending_do = false   -- `for`/`while` already counted their `do`
	local cur, vstart
	local i, n = 1, #body
	while i <= n do
		local c = body:sub(i, i)
		if c == "(" or c == "{" or c == "[" then
			if c == "[" and depth == 1 and mode == "key" and fn == 0 then
				order[#order + 1] = "?[quoted]"
			end
			depth = depth + 1
			i = i + 1
		elseif c == ")" or c == "}" or c == "]" then
			depth = depth - 1
			i = i + 1
		elseif depth == 0 and c:match("[%a_]") then
			local j = i
			while j <= n and body:sub(j, j):match("[%w_]") do
				j = j + 1
			end
			local id = body:sub(i, j - 1)
			i = j
			if id == "function" or BLOCK_OPEN[id] then
				fn = fn + 1
				if id == "for" or id == "while" then pending_do = true end
			elseif id == "do" then
				if pending_do then
					pending_do = false
				else
					fn = fn + 1
				end
			elseif id == "end" or id == "until" then
				if fn > 0 then fn = fn - 1 end
			elseif fn == 0 and mode == "key" then
				local k = i
				while k <= n and body:sub(k, k):match("%s") do k = k + 1 end
				if body:sub(k, k) == "=" and
					body:sub(k + 1, k + 1) ~= "=" then
					keys[id] = true
					order[#order + 1] = id
					mode = "value"
					cur, vstart = id, k + 1
					i = k + 1
				end
			end
		elseif depth == 0 and fn == 0 and mode == "value" then
			if c == "," or c == ";" then
				if cur then values[cur] = body:sub(vstart, i - 1) end
				cur = nil
				mode = "key"
			end
			i = i + 1
		else
			i = i + 1
		end
	end
	if cur then values[cur] = body:sub(vstart, n) end
	return keys, order, values
end

-- The first argument's text in the ORIGINAL source (name expression).
local function first_arg(src, masked, from, to)
	local depth, i = 0, from
	while i <= to do
		local c = masked:sub(i, i)
		if c == "(" or c == "{" or c == "[" then
			depth = depth + 1
		elseif c == ")" or c == "}" or c == "]" then
			depth = depth - 1
		elseif depth == 0 and c == "," then
			break
		end
		i = i + 1
	end
	return (src:sub(from, i - 1):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- All registration sites in one source string.
-- Returns a list of { line, kind, name, name_dynamic, keys, order,
--                      has_table }.
local function sites_of(src)
	local masked = mask(src)
	local out = {}
	local function line_of(idx)
		local n = 1
		for _ = 1, idx - 1 do
			if src:sub(_, _) == "\n" then n = n + 1 end
		end
		return n
	end
	for _, pat in ipairs(CALL_PATTERNS) do
		local search = 1
		while true do
			local s, e = masked:find(pat, search)
			if not s then break end
			local open = e            -- index of "("
			local close = match_bracket(masked, open)
			search = open + 1
			-- `function smp_social.register_cmd(name, def, aliases)` is
			-- the wrapper's DEFINITION, not a registration; the calls to
			-- it are the sites we want.
			if close and not masked:sub(1, s - 1):match("function%s*$") then
				local args_from, args_to = open + 1, close - 1
				local brace = masked:find("{", args_from, true)
				local rec = {
					line = line_of(s),
					kind = pat:gsub("%%", ""):gsub("%s*%($", ""),
					keys = nil,
					order = {},
					values = {},
					has_table = false,
				}
				-- Only a top-level `{` (not one nested in the name
				-- expression) is the def table.
				local brace_ok = false
				if brace then
					local depth, i = 0, args_from
					while i < brace do
						local c = masked:sub(i, i)
						if c == "(" or c == "{" or c == "[" then
							depth = depth + 1
						elseif c == ")" or c == "}" or c == "]" then
							depth = depth - 1
						end
						i = i + 1
					end
					brace_ok = (depth == 0)
				end
				if brace_ok then
					local bend = match_bracket(masked, brace)
					if bend and bend <= args_to then
						rec.has_table = true
						rec.keys, rec.order, rec.values =
							table_keys(masked:sub(brace + 1, bend - 1))
					end
				end
				local name_expr = first_arg(src, masked, args_from, args_to)
				rec.name_expr = name_expr
				local lit = name_expr:match('^"([^"]*)"') or
					name_expr:match("^'([^']*)'")
				rec.name = lit
				rec.name_dynamic = (lit == nil)
				out[#out + 1] = rec
			end
		end
	end
	table.sort(out, function(a, b) return a.line < b.line end)
	return out
end

local function read_file(path)
	local fh = io.open(path, "r")
	if not fh then return nil end
	local data = fh:read("*a")
	fh:close()
	return data
end

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

----------------------------------------------------------------------
-- 3. Rules
----------------------------------------------------------------------

-- The engine's own chatcommand def keys: builtin/common/chatcommands.lua
-- (params, description, privs, mod_origin) + builtin/game/chat.lua (func).
local KNOWN_KEYS = {
	params = true,
	description = true,
	privs = true,
	func = true,
	mod_origin = true,
}

-- Conservative word list for R3. It reads the COMMAND NAME only; a
-- privileged command with an innocent name (`/spawner`) is caught by R1
-- instead — see the header's blind spots. Words are substrings of the
-- lower-cased name.
--   `spawn` is deliberately NOT here: in this pack `/spawn` is the
--   player's lobby command (smp_tp/commands.lua:258), not a mob/thing
--   spawner — and `/spawner` itself is gated by R1's `privs` check.
local ADMIN_WORDS = {
	"admin", "give", "grant", "revoke", "ban", "kick", "mute", "kill",
	"reload", "reset", "purge", "wipe", "shutdown", "crash", "remove",
	"delete", "ledger", "backend", "rank",
}

-- Documented exceptions to R3: the name sounds privileged, the def
-- declares no `privs`, and the privilege lives INSIDE func instead.
-- Adding a row here is a deliberate, reviewable decision — every row
-- names the file:line of the guard that replaces the missing key.
local EXEMPT = {
	ledger = "smp_economy/init.lua:692 ledger_allowed() guards the body",
	mute = "smp_admin/init.lua:195 is_staff() before any mutation",
	unmute = "smp_admin/init.lua:212 is_staff() before any mutation",
	-- PROPOSED (S06): /kill has no inline guard either — it is exempt
	-- because it can only act on the SENDER (it opens a confirmation
	-- formspec for the caller and the field handler re-validates the
	-- session), so there is no third party to protect. Surfaced in
	-- spec/features/f07-spawners.md §10 for the integrator.
	kill = "smp_social/kill.lua:33 self-only: acts on the sender",
}

local function admin_sounding(name)
	local lower = name:lower()
	for _, w in ipairs(ADMIN_WORDS) do
		if lower:find(w, 1, true) then return w end
	end
	return nil
end

-- Returns findings = { {rule, file, line, msg} }, notes = { strings }.
local function lint_source(file, src, findings, notes)
	for _, st in ipairs(sites_of(src)) do
		local where = string.format("%s:%d", file, st.line)
		if not st.has_table then
			notes[#notes + 1] = string.format(
				"%s: N1 def passed as a variable (%s) — scanned at "
				.. "the caller", where, st.name_expr)
		else
			for _, key in ipairs(st.order) do
				if key == "?[quoted]" then
					notes[#notes + 1] = string.format(
						"%s: N4 quoted (non-identifier) def key — "
						.. "not extracted", where)
				elseif key == "privilege" then
					findings[#findings + 1] = {
						rule = "R1", file = file, line = st.line,
						msg = "`privilege` is not a key the engine "
							.. "reads (builtin/common/chatcommands."
							.. "lua:44-51) — this command demands "
							.. "NO privilege. Use "
							.. "`privs = { <name> = true }`.",
					}
				elseif not KNOWN_KEYS[key] then
					findings[#findings + 1] = {
						rule = "R2", file = file, line = st.line,
						msg = string.format(
							"unknown chatcommand def key `%s` — the "
							.. "engine reads only params/description/"
							.. "privs/func/mod_origin, so this key is "
							.. "dead", key),
					}
				end
			end

			-- R3 / N3: privilege gating for admin-sounding names.
			if st.name then
				local word = admin_sounding(st.name)
				local has_privs = st.keys and st.keys.privs
				local privs_empty = has_privs and
					((st.values.privs or ""):match(
						"^%s*{%s*}%s*$") ~= nil)
				if word and not has_privs then
					if EXEMPT[st.name] then
						notes[#notes + 1] = string.format(
							"%s: EXEMPT /%s (%s) — R3 waived: %s",
							where, st.name, word, EXEMPT[st.name])
					else
						findings[#findings + 1] = {
							rule = "R3", file = file, line = st.line,
							msg = string.format(
								"`/%s` is admin-sounding (%q) but "
								.. "declares no `privs` — add "
								.. "`privs = { … }` or an EXEMPT row "
								.. "with the guard that replaces it",
								st.name, word),
						}
					end
				elseif word and privs_empty then
					-- N3: `privs = {}` is the engine's "everyone".
					notes[#notes + 1] = string.format(
						"%s: N3 /%s declares `privs = {}` (everyone) "
						.. "— confirm that is intended for an "
						.. "admin-sounding name", where, st.name)
				end
			else
				notes[#notes + 1] = string.format(
					"%s: N2 command name is an expression (%s) — R3 "
					.. "not applied (R1/R2 still were)",
					where, st.name_expr)
			end
		end
	end
end

----------------------------------------------------------------------
-- 4. Fixtures: the lint must catch the bug class, not just pass
----------------------------------------------------------------------

local FIX_PRIVILEGE = [[
core.register_chatcommand("bad", {
	privilege = "smp_admin",
	params = "",
	description = "",
	func = function() end,
})
]]

local FIX_UNKNOWN_KEY = [[
core.register_chatcommand("typo", {
	privs = { smp_admin = true },
	paramz = "",
	func = function() end,
})
]]

local FIX_UNGUARDED = [[
core.register_chatcommand("banplayer", {
	params = "",
	description = "Ban someone",
	func = function() end,
})
]]

local FIX_EMPTY_PRIVS = [[
core.register_chatcommand("banme", {
	params = "",
	description = "",
	privs = {},
	func = function() end,
})
]]

local FIX_DYNAMIC = [[
core.register_chatcommand("thing", def)
local alias = "x"
core.register_chatcommand(alias, { params = "", func = function() end })
]]

-- Statements inside a function body must NOT read as def keys.
local FIX_FUNC_BODY = [[
core.register_chatcommand("clean", {
	privs = { smp_admin = true },
	params = "",
	description = "",
	func = function(name, param)
		local quota = 3
		local total = quota + 1
		if total > 2 then return true end
		return false
	end,
})
]]

-- A comment that contains the forbidden key must not trip the lint.
local FIX_COMMENT = [[
-- core.register_chatcommand("legacy", { privilege = "smp_admin" })
core.register_chatcommand("modern", {
	privs = { smp_admin = true },  -- was: privilege = "smp_admin"
	func = function() end,
})
]]

local function lint_text(src)
	local findings, notes = {}, {}
	lint_source("<fixture>", src, findings, notes)
	return findings, notes
end

local function rules_of(findings)
	local out = { R1 = 0, R2 = 0, R3 = 0 }
	for _, f in ipairs(findings) do out[f.rule] = (out[f.rule] or 0) + 1 end
	return out
end

print("== chatcommand lint: fixtures (would it have caught S06?) ==")

do
	local f = rules_of(lint_text(FIX_PRIVILEGE))
	eq(f.R1, 1, "fixture: `privilege =` is caught by R1")
	eq(f.R2, 0, "fixture: R1 is reported once, not double-counted")
	eq(f.R3, 0, "fixture: /bad is not admin-sounding")
end

do
	local f = rules_of(lint_text(FIX_UNKNOWN_KEY))
	eq(f.R2, 1, "fixture: an unknown def key is caught by R2")
	eq(f.R1, 0, "fixture: `privs` itself is a known key")
end

do
	local f, notes = lint_text(FIX_UNGUARDED)
	eq(rules_of(f).R3, 1, "fixture: an unguarded admin name is caught")
	local exempt_hit = false
	for _, n in ipairs(notes) do
		if n:find("EXEMPT /banplayer", 1, true) then exempt_hit = true end
	end
	ok(not exempt_hit, "fixture: an unknown name is not silently exempt")
end

do
	local f, notes = lint_text(FIX_EMPTY_PRIVS)
	eq(#f, 0, "fixture: `privs = {}` satisfies R3 (it is a real value)")
	local n3 = false
	for _, n in ipairs(notes) do
		if n:find("N3 /banme", 1, true) then n3 = true end
	end
	ok(n3, "fixture: `privs = {}` is surfaced as note N3")
end

do
	local f, notes = lint_text(FIX_DYNAMIC)
	eq(#f, 0, "fixture: dynamic defs are not failures by themselves")
	local n1, n2 = false, false
	for _, n in ipairs(notes) do
		if n:find("N1", 1, true) then n1 = true end
		if n:find("N2", 1, true) then n2 = true end
	end
	ok(n1, "fixture: a variable def is reported as note N1")
	ok(n2, "fixture: a variable name is reported as note N2")
end

do
	local f = rules_of(lint_text(FIX_FUNC_BODY))
	eq(f.R1 + f.R2 + f.R3, 0,
		"fixture: locals inside func are not read as def keys")
end

do
	local f = rules_of(lint_text(FIX_COMMENT))
	eq(f.R1 + f.R2 + f.R3, 0,
		"fixture: a commented-out `privilege =` does not trip the lint")
end

----------------------------------------------------------------------
-- 5. Regression proof: the pre-fix source, from git history
----------------------------------------------------------------------

print("== chatcommand lint: git baseline proof ==")

do
	local commit = "85e4a5d"
	local path = "friedcake/mods/smp_spawners/init.lua"
	local p = io.popen(string.format(
		'git -C "%s" show %s:%s 2>/dev/null', ROOT, commit, path))
	local old = p and p:read("*a") or nil
	if p then p:close() end
	if type(old) == "string" and #old > 0 then
		local findings = lint_text(old)
		local r1 = rules_of(findings).R1 or 0
		ok(r1 >= 1,
			string.format("baseline %s:%s is caught by R1 "
				.. "(privilege = \"smp_admin\") — %d R1 finding(s)",
				commit, path, r1))
		local here = findings[1]
		ok(here ~= nil and here.line > 0,
			"baseline finding carries a line number")
		-- And the same lint on today's file must be clean.
		local now = read_file(MODS .. "/smp_spawners/init.lua")
		ok(now ~= nil, "current smp_spawners/init.lua is readable")
		if now then
			local f2 = lint_text(now)
			eq(#f2, 0, "current smp_spawners/init.lua scans clean")
		end
	else
		print("SKIP: git object " .. commit .. ":" .. path
			.. " not available here — fixture proof above still "
			.. "applies")
		ok(true, "baseline proof skipped (object unavailable)")
	end
end

----------------------------------------------------------------------
-- 6. The live pack
----------------------------------------------------------------------

print("== chatcommand lint: friedcake/mods ==")

local findings, notes = {}, {}
local files = list_lua(MODS)
ok(#files > 0, "found lua files under friedcake/mods")
local sites = 0
for _, f in ipairs(files) do
	local src = read_file(f)
	if src then
		local rel = f:sub(#ROOT + 2)
		local before = #findings
		lint_source(rel, src, findings, notes)
		sites = sites + #sites_of(src)
		if #findings > before then
			-- keep going: report everything, then fail once
		end
	end
end

for _, n in ipairs(notes) do print("NOTE: " .. n) end
for _, f in ipairs(findings) do
	print(string.format("FAIL: %s:%d [%s] %s",
		f.file, f.line, f.rule, f.msg))
end

ok(sites > 0, string.format("scanned %d chatcommand registration sites "
	.. "across %d files", sites, #files))
eq(#findings, 0, string.format(
	"pack-wide chatcommand lint: %d finding(s), %d note(s)",
	#findings, #notes))

print(string.format("%s: %d passed, %d failed",
	SELF, passed, failed))
os.exit(failed == 0 and 0 or 1)
