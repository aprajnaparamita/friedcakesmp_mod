-- FriedcakeSMP — smp_core
-- Shared formatter, parser and menu-session helpers.
-- Implements spec/shared/00-conventions.md §0.5–0.7 and 04-ui-kit.md §4.9.
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_core = {}

----------------------------------------------------------------------
-- Money and quantity formatting
--
-- These three functions are the ONLY sanctioned way to render or read
-- an amount in FriedcakeSMP. Any other implementation will drift from
-- the observed spacing rules in spec/shared/00-conventions.md §0.6.
--
-- Conventions reproduced here:
--   * Bare amounts and inline/parenthesised amounts: no space ($700, $1, $30K)
--   * Chat lines and tooltip bodies: space       ($ 5.1K, $ 9K)
--   * Suffixes are upper-case for money (K, M, B, T)
--   * Suffixes are lower-case for quantities (k, m, b)
--
-- Storage is integer cents (00-conventions.md §0.7). The maximum balance
-- is 10^13 dollars = 10^15 cents, well within Lua number precision.
----------------------------------------------------------------------

-- Two-decimal rounding that never goes negative on tiny inputs.
-- Math.floor(x*100 + 0.5) is what we want; expressed explicitly because
-- float drift matters around 0.01 dollar amounts.
local function round_cents(n)
	-- n is integer cents already.
	return math.floor(n + 0.5)
end

-- Compact suffix for money: K (10^3), M (10^6), B (10^9), T (10^12).
-- We pick the largest suffix that still leaves a non-zero whole part.
-- (We do NOT use the next suffix if the value rounds to it — that would
-- render $999.99 as $1K. The observed form is "$ 1K" only when the value
-- reaches $1,000.)
local function pick_suffix(cents)
	-- cents -> dollars. Thresholds are in cents.
	if cents >= 100000000000000 then return "T", cents / 100000000000000 end  -- $10^12
	if cents >= 100000000000     then return "B", cents / 100000000000     end  -- $10^9
	if cents >= 100000000        then return "M", cents / 100000000        end  -- $10^6
	if cents >= 100000           then return "K", cents / 100000           end  -- $10^3
	return nil, cents / 100
end

-- Format a quantity of cents as observed: either "$X" (no space) or
-- "$ X" (with space). style is "inline" or "body".
function smp_core.fmt_money(cents, style)
	assert(type(cents) == "number", "fmt_money: cents must be a number")
	if cents ~= cents or cents == math.huge or cents == -math.huge then
		return style == "inline" and "$0" or "$ 0"
	end
	cents = math.floor(cents + 0.5)
	if cents < 0 then cents = 0 end -- money is non-negative; defensive only
	local suffix, scaled = pick_suffix(cents)
	local space = (style == "body") and " " or ""
	if suffix then
		-- One decimal, then strip trailing ".0" so 30.0K renders as 30K.
		local rendered = string.format("%.1f%s", scaled, suffix)
		rendered = rendered:gsub("%.0([KMmBbTt])", "%1")
		return "$" .. space .. rendered
	end
	-- No suffix: dollars with cents, no space (inline) or space (body).
	-- Reproduces $700 and $ 5 (the observed "no suffix, with space" form).
	if cents % 100 == 0 then
		return string.format("$%s%d", space, math.floor(cents / 100))
	end
	return string.format("$%s%.2f", space, cents / 100)
end

-- Format a plain integer quantity using lower-case suffixes. Used for
-- "Delivered: 167k/200k" style counts. (00-conventions.md §0.6.)
function smp_core.fmt_qty(n)
	assert(type(n) == "number", "fmt_qty: n must be a number")
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

-- Parse a user-supplied amount into cents. Accepts:
--   "250k", "1.5M", "10", "10.50", "10.99", case-insensitive suffixes
-- Rejects (returns nil, error_message):
--   ""               empty
--   "-1", "-10"      negative
--   "nan", "NaN"     not a number
--   "inf", "Inf"     infinite
--   "1e400"          overflows Lua number
--   "abc"            not numeric
--
-- Returns (cents, nil) on success, or (nil, reason) on failure.
function smp_core.parse_amount(text)
	if type(text) ~= "string" then return nil, "not a string" end
	text = text:match("^%s*(.-)%s*$") or ""
	if text == "" then return nil, "empty" end

	-- Pull a trailing suffix letter, lower-cased.
	local body = text
	local suffix_mult = 1
	local last = text:sub(-1)
	if last:match("[kKmMbBtT]") then
		body = text:sub(1, -2)
		local lc = last:lower()
		if     lc == "k" then suffix_mult = 1000
		elseif lc == "m" then suffix_mult = 1000000
		elseif lc == "b" then suffix_mult = 1000000 * 1000 -- 10^9
		elseif lc == "t" then suffix_mult = 1000000 * 1000000 -- 10^12
		end
	end

	-- Reject anything that isn't a plain decimal now (we have already
	-- stripped the suffix). tonumber catches "1e400" as inf and "abc" as nil.
	local n = tonumber(body)
	if n == nil        then return nil, "not a number" end
	if n ~= n          then return nil, "NaN"          end
	if n == math.huge  then return nil, "too large"    end
	if n < 0           then return nil, "negative"     end

	local cents = math.floor(n * 100 * suffix_mult + 0.5)
	-- 10^13 dollars = 10^15 cents. Lua number exact to 2^53.
	if cents > 1e15 then return nil, "too large" end
	return cents, nil
end

----------------------------------------------------------------------
-- Menu session table
--
-- Every formspec menu in FriedcakeSMP keeps state in a per-player table
-- keyed by formname. Client fields are untrusted and every action is
-- re-validated. spec/shared/02-architecture.md §2.4.
--
-- Usage from a feature mod:
--
--   local session = smp_core.open_session(player_name, "smp_economy:bal", {
--       page = 1,
--   })
--   if session then
--       smp_core.show_formspec(player_name, "smp_economy:bal",
--           formspec_for_bal(session),
--           "bal")
--   end
--
--   -- In core.register_on_player_receive_fields:
--   smp_core.handle_fields(player_name, formname, fields, function(s, f)
--       if f.quit then return "close" end
--       -- mutate s, return new formspec string or nil
--   end)
----------------------------------------------------------------------

smp_core._sessions = {}  -- [player_name][formname] = state

function smp_core.open_session(player_name, formname, initial)
	if not player_name or not formname then return nil end
	smp_core._sessions[player_name] = smp_core._sessions[player_name] or {}
	local s = smp_core._sessions[player_name][formname]
	if s then return s end
	s = initial or {}
	s._formname = formname
	s._opened = core.get_gametime()
	smp_core._sessions[player_name][formname] = s
	return s
end

function smp_core.get_session(player_name, formname)
	return smp_core._sessions[player_name] and
	       smp_core._sessions[player_name][formname]
end

function smp_core.close_session(player_name, formname)
	if not smp_core._sessions[player_name] then return end
	smp_core._sessions[player_name][formname] = nil
end

function smp_core.close_all_sessions(player_name)
	smp_core._sessions[player_name] = nil
end

-- Dispatcher. Pass the result of a handler ("close", "stay", or nil) to
-- the engine. Handler signature: function(session, fields) -> "close"|nil.
function smp_core.handle_fields(player_name, formname, fields, handler)
	local session = smp_core.get_session(player_name, formname)
	if not session then return "close" end
	local result = handler(session, fields)
	if result == "close" then
		smp_core.close_session(player_name, formname)
		core.close_formspec(player_name, formname)
	end
	return result
end

-- Convenience wrapper around core.show_formspec that sets the standard
-- Friedcake formspec preamble (spec/shared/04-ui-kit.md §4.9).
function smp_core.show_formspec(player_name, formname, formspec, _)
	core.show_formspec(player_name, formname, formspec)
end

----------------------------------------------------------------------
-- Sanity helpers
----------------------------------------------------------------------

-- Render a number exactly the way fmt_money would, but only for tests.
smp_core._internal_round_cents = round_cents
smp_core._internal_pick_suffix = pick_suffix

----------------------------------------------------------------------
-- Self-check: prints a one-line summary at load time so a misconfigured
-- engine (no core.get_translator, no math.floor, ...) fails loudly.
----------------------------------------------------------------------

local function self_check()
	-- We do NOT test against the live spec strings here; that lives in
	-- /smp test smp_core. This is just "do the helpers exist".
	assert(type(smp_core.fmt_money)  == "function")
	assert(type(smp_core.fmt_qty)    == "function")
	assert(type(smp_core.parse_amount) == "function")
	assert(type(smp_core.open_session)  == "function")
end

local ok, err = pcall(self_check)
if not ok then
	core.log("error", "[smp_core] self-check failed at load: " .. tostring(err))
	error(err)
end

core.log("action", "[smp_core] loaded: fmt_money/fmt_qty/parse_amount + sessions ready")
