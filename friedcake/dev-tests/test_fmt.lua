-- Standalone smoke test for smp_core's formatter/parser.
local M = {}
local function pick_suffix(cents)
	if cents >= 100000000000000 then return "T", cents / 100000000000000 end
	if cents >= 100000000000     then return "B", cents / 100000000000     end
	if cents >= 100000000        then return "M", cents / 100000000        end
	if cents >= 100000           then return "K", cents / 100000           end
	return nil, cents / 100
end
function M.fmt_money(cents, style)
	if cents ~= cents or cents == math.huge or cents == -math.huge then
		return style == "inline" and "$0" or "$ 0"
	end
	cents = math.floor(cents + 0.5)
	if cents < 0 then cents = 0 end
	local suffix, scaled = pick_suffix(cents)
	local space = (style == "body") and " " or ""
	if suffix then
		local rendered = string.format("%.1f%s", scaled, suffix)
		rendered = rendered:gsub("%.0([KMmBbTt])", "%1")
		return "$" .. space .. rendered
	end
	if cents % 100 == 0 then
		return string.format("$%s%d", space, math.floor(cents / 100))
	end
	return string.format("$%s%.2f", space, cents / 100)
end

function M.fmt_qty(n)
	if n ~= n or n == math.huge or n == -math.huge or n < 0 then return "0" end
	n = math.floor(n)
	local function pretty(scaled, suffix)
		local r = string.format("%.1f%s", scaled, suffix)
		r = r:gsub("%.0([kmbt])", "%1")
		return r
	end
	if n >= 1000000000 then return pretty(n / 1000000000, "b") end
	if n >= 1000000    then return pretty(n / 1000000,    "m") end
	if n >= 1000       then return pretty(n / 1000,       "k") end
	return tostring(n)
end

function M.parse_amount(text)
	if type(text) ~= "string" then return nil, "not a string" end
	text = text:match("^%s*(.-)%s*$") or ""
	if text == "" then return nil, "empty" end
	local body = text
	local suffix_mult = 1
	local last = text:sub(-1)
	if last:match("[kKmMbBtT]") then
		body = text:sub(1, -2)
		local lc = last:lower()
		if     lc == "k" then suffix_mult = 1000
		elseif lc == "m" then suffix_mult = 1000000
		elseif lc == "b" then suffix_mult = 1000000 * 1000
		elseif lc == "t" then suffix_mult = 1000000 * 1000000
		end
	end
	local n = tonumber(body)
	if n == nil        then return nil, "not a number" end
	if n ~= n          then return nil, "NaN"          end
	if n == math.huge  then return nil, "too large"    end
	if n < 0           then return nil, "negative"     end
	local cents = math.floor(n * 100 * suffix_mult + 0.5)
	if cents > 1e15 then return nil, "too large" end
	return cents, nil
end

local function eq(a, b, msg)
	if a ~= b then
		error(string.format("FAIL %s: expected %q got %q", msg, tostring(b), tostring(a)), 2)
	end
end

-- T1
eq(M.fmt_money(70000, "body"),    "$ 700",     "$700 body")
eq(M.fmt_money(70000, "inline"),  "$700",      "$700 inline")
eq(M.fmt_money(510000, "body"),   "$ 5.1K",    "$ 5.1K body")
eq(M.fmt_money(3000000, "body"),  "$ 30K",     "$ 30K body")
eq(M.fmt_money(900000, "body"),   "$ 9K",      "$ 9K body")
eq(M.fmt_money(2500000, "body"),  "$ 25K",     "$ 25K body")
eq(M.fmt_money(18200000, "body"), "$ 182K",    "$ 182K body")
eq(M.fmt_money(400000000, "body"), "$ 4M",     "$ 4M body")
eq(M.fmt_money(100, "inline"),    "$1",        "$1 inline")
eq(M.fmt_money(3000000, "inline"),"$30K",      "$30K inline")

-- T2
eq(M.fmt_qty(753000),  "753k",  "753k")
eq(M.fmt_qty(1300000), "1.3m",  "1.3m")
eq(M.fmt_qty(167000),  "167k",  "167k")
eq(M.fmt_qty(200000),  "200k",  "200k")

-- T3
local c
c = M.parse_amount("250k");  eq(c, 25000000, "250k -> 25,000,000 cents ($250,000)")
c = M.parse_amount("1.5M");  eq(c, 150000000, "1.5M -> 150,000,000 cents")
c = M.parse_amount("10");    eq(c, 1000, "10 -> 1000 cents ($10)")
c = M.parse_amount("10.50"); eq(c, 1050, "10.50 -> 1050 cents")
assert(M.parse_amount("-1")    == nil, "reject -1")
assert(M.parse_amount("nan")   == nil, "reject nan")
assert(M.parse_amount("inf")   == nil, "reject inf")
assert(M.parse_amount("1e400") == nil, "reject 1e400")
assert(M.parse_amount("")      == nil, "reject empty")
assert(M.parse_amount("abc")   == nil, "reject abc")

print("ALL OK")
