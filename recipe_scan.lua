-- Throwaway audit: extract every core.register_craft recipe from the local
-- Mineclonia source and check it against smp_sell's price table.
-- NOT committed: it depends on ~/dev/mineclonia-git.
-- Run: luajit recipe_scan.lua

local MINE = (os.getenv("MINE") or (os.getenv("HOME") .. "/dev/mineclonia-git")) .. "/mods"
local PRICES = arg[1] or "friedcake/mods/smp_sell/prices_default.lua"
local TOL = tonumber(arg[2] or 9)

local price = assert(loadfile(PRICES))()

----------------------------------------------------------------------
-- Gather files
----------------------------------------------------------------------
local files = {}
do
	local p = io.popen('find "' .. MINE .. '" -name "*.lua" -type f 2>/dev/null')
	if p then
		for line in p:lines() do files[#files + 1] = line end
		p:close()
	end
end
io.stderr:write(#files .. " lua files\n")

local texts = {}
for _, f in ipairs(files) do
	local h = io.open(f, "r")
	if h then texts[f] = h:read("*a"); h:close() end
end

----------------------------------------------------------------------
-- Aliases (literal register_alias("a","b") plus the mcl_walls pattern)
----------------------------------------------------------------------
local alias = {}
for src, text in pairs(texts) do
	for a, b in text:gmatch('register_alias%s*%(%s*"([^"]+)"%s*,%s*"([^"]+)"%s*%)') do
		alias[a] = b
	end
end
-- mcl_walls registers nodename -> nodename.."_short_pillar" for every wall
for _, text in pairs(texts) do
	for name in text:gmatch('register_wall_def%s*%(%s*"([^"]+)"') do
		alias[name] = name .. "_short_pillar"
	end
end

local function resolve(n, depth)
	depth = depth or 0
	while type(alias[n]) == "string" and alias[n] ~= n and depth < 32 do
		n = alias[n]; depth = depth + 1
	end
	return n
end

----------------------------------------------------------------------
-- Values: mirror prices.lua rebuild() (key + resolved key both carry value)
----------------------------------------------------------------------
local value = {}
for k, v in pairs(price) do
	if type(k) == "string" then
		local cents
		if type(v) == "number" then cents = math.floor(v + 0.5)
		elseif v == false or v == nil then cents = nil
		else cents = nil end
		if cents and cents > 0 then
			value[k] = cents
			local r = resolve(k)
			if value[r] == nil then value[r] = cents end
		else
			value[k] = false            -- explicitly unsellable
			local r = resolve(k)
			if value[r] == nil then value[r] = false end
		end
	end
end
local function val(name)
	local v = value[resolve(name)]
	if v == false then return 0 end
	return v or 0
end
local function priced(name)
	local v = value[resolve(name)]
	return v ~= nil and v ~= false
end

----------------------------------------------------------------------
-- Balanced-paren block extraction (handles quotes, long strings, comments)
----------------------------------------------------------------------
local function extract_block(s, start_i)
	-- start_i points at '('
	local i = start_i + 1
	local depth = 1
	local n = #s
	while i <= n do
		local c = s:sub(i, i)
		if c == '"' then
			i = i + 1
			while i <= n do
				local d = s:sub(i, i)
				if d == "\\" then i = i + 2
				elseif d == '"' then i = i + 1; break
				else i = i + 1 end
			end
		elseif s:sub(i, i + 1) == "[[" then
			local _, e = s:find("]]", i + 2, true)
			i = e and (e + 1) or (n + 1)
		elseif s:sub(i, i + 1) == "--" then
			if s:sub(i + 2, i + 3) == "[[" then
				local _, e = s:find("]]", i + 4, true)
				i = e and (e + 1) or (n + 1)
			else
				local e = s:find("\n", i, true)
				i = e or (n + 1)
			end
		elseif c == "(" then depth = depth + 1; i = i + 1
		elseif c == ")" then
			depth = depth - 1; i = i + 1
			if depth == 0 then return s:sub(start_i + 1, i - 2) end
		else i = i + 1 end
	end
	return nil
end

----------------------------------------------------------------------
-- Recipe extraction
----------------------------------------------------------------------
local recipes = {}        -- { out = {name, count}, ins = { {name, count} }, src, kind }
local failures = {}
local skipped_group = {}

local function item_split(cell)
	if type(cell) ~= "string" then return nil end
	local name, cnt = cell:match("^(%S+)%s*(%d*)$")
	if not name or name == "" then return nil end
	return name, tonumber(cnt) or 1
end

local function add(out_str, input_cells, kind, src)
	local oname, ocount = item_split(out_str)
	if not oname then return end
	local ins = {}
	for _, cell in ipairs(input_cells) do
		if type(cell) == "string" then
			if cell:match("^group:") then
				if priced(oname) then skipped_group[#skipped_group + 1] =
					src .. " -> " .. oname .. " from " .. cell end
			else
				local nm, ct = item_split(cell)
				if nm then ins[#ins + 1] = { nm, ct } end
			end
		end
	end
	recipes[#recipes + 1] = { out = { oname, ocount }, ins = ins, src = src, kind = kind }
end

local craft_pat = "register_craft%s*"
local counts = { normal = 0, shapeless = 0, cooking = 0, other = 0, failed = 0 }
for src, text in pairs(texts) do
	local idx = 1
	while true do
		local s = text:find(craft_pat, idx)
		if not s then break end
		local paren = text:find("%(", s)
		idx = s + 1
		-- ensure the ( is the call's own (allow `register_craft {` table call)
		local between = text:sub(s + #"register_craft", (paren or 0) - 1)
		local block
		if paren and between:match("^%s*$") then
			block = extract_block(text, paren)
		else
			-- table-call form: register_craft{...}
			local brace = text:find("%{", s)
			if brace and text:sub(s + #"register_craft", brace - 1):match("^%s*$") then
				-- reuse paren extractor by faking: find matching brace manually
				local i, depth = brace + 1, 1
				local ok = true
				while i <= #text and ok do
					local c = text:sub(i, i)
					if c == '"' then
						i = i + 1
						while i <= #text do
							local d = text:sub(i, i)
							if d == "\\" then i = i + 2
							elseif d == '"' then i = i + 1; break
							else i = i + 1 end
						end
					elseif c == "{" then depth = depth + 1; i = i + 1
					elseif c == "}" then depth = depth - 1; i = i + 1
						if depth == 0 then block = text:sub(brace + 1, i - 2); break end
					else i = i + 1 end
				end
			end
		end
		if block then
			local f, err = load("return " .. block)
			if not f then
				counts.failed = counts.failed + 1
				failures[#failures + 1] = src .. ": " .. tostring(err)
			else
				local ok, def = pcall(f)
				if not ok or type(def) ~= "table" then
					counts.failed = counts.failed + 1
					failures[#failures + 1] = src .. ": run: " .. tostring(def)
				elseif type(def.output) == "string" then
					local kind = def.type or "normal"
					if kind == "shapeless" then
						counts.shapeless = counts.shapeless + 1
						add(def.output, def.recipe or {}, kind, src)
					elseif kind == "cooking" then
						counts.cooking = counts.cooking + 1
						add(def.output, { def.recipe }, kind, src)
					elseif kind == "normal" or def.recipe then
						counts.normal = counts.normal + 1
						local cells = {}
						for _, row in ipairs(def.recipe or {}) do
							if type(row) == "table" then
								for _, cell in ipairs(row) do cells[#cells + 1] = cell end
							end
						end
						add(def.output, cells, kind, src)
					else
						counts.other = counts.other + 1
					end
				else
					counts.other = counts.other + 1    -- fuel, toolrepair, ...
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Stonecutter: register_wall_def("name", { _mcl_stonecutter_recipes = {...} })
----------------------------------------------------------------------
local sc_inputs_by_wall = {}
for src, text in pairs(texts) do
	for name, rest in text:gmatch('register_wall_def%s*%(%s*"([^"]+)"%s*,%s*%b{}') do
		sc_inputs_by_wall[name] = sc_inputs_by_wall[name] or {}
		local body = text:match('register_wall_def%s*%(%s*"' .. name:gsub(":", "%%:") .. '"%s*,%s*(%b{})')
		if body then
			local list = body:match("_mcl_stonecutter_recipes%s*=%s*(%b{})")
			if list then
				for item in list:gmatch('"([^"]+)"') do
					local set = sc_inputs_by_wall[name]
					if not set[item] then set[item] = true; set[#set + 1] = item end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Check
----------------------------------------------------------------------
local violations = {}
local total = #recipes
local function check_one(kind, oname, ocount, ins, src)
	local ov = val(oname) * ocount
	local sum = 0
	local parts = {}
	for _, it in ipairs(ins) do
		local v = val(it[1])
		sum = sum + v * it[2]
		parts[#parts + 1] = string.format("%dx%s=%d", it[2], it[1], v * it[2])
	end
	if ov > sum + TOL then
		violations[#violations + 1] = string.format(
			"[%s] %dx %s = %d  >  inputs %d  (+%d)  %s :: %s",
			kind, ocount, oname, ov, sum, ov - sum, table.concat(parts, " + "),
			(src or "?"):gsub(MINE .. "/", ""))
	end
end

for _, r in ipairs(recipes) do
	check_one(r.kind, r.out[1], r.out[2], r.ins, r.src)
end
for name, set in pairs(sc_inputs_by_wall) do
	for i = 1, #set do
		local input = set[i]
		-- output variants: only the alias-resolved pillar carries the price
		check_one("stonecutter", name, 1, { { input, 1 } }, "mcl_walls stonecutter: " .. name)
	end
end

table.sort(violations)
print(string.format("files=%d recipes=%d normal=%d shapeless=%d cooking=%d other=%d failed=%d",
	#files, total, counts.normal, counts.shapeless, counts.cooking, counts.other, counts.failed))
print(string.format("walls with stonecutter recipes: %d", (function()
	local n = 0 for _ in pairs(sc_inputs_by_wall) do n = n + 1 end return n end)()))
print(string.format("VIOLATIONS (%d) tol=%d:", #violations, TOL))
for _, v in ipairs(violations) do print("  " .. v) end
if #skipped_group > 0 then
	print("group inputs feeding priced outputs (value treated as 0):")
	for _, g in ipairs(skipped_group) do print("  " .. g) end
end
if #failures > 0 then
	print("UNEVALUABLE recipe blocks: " .. #failures)
	for i = 1, math.min(#failures, 40) do print("  " .. failures[i]) end
end
