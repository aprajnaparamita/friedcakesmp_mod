-- FriedcakeSMP dev smoke test: smp_bounty (escrow, anti-abuse, refund)
--
-- Covers the parts of spec/features/f10-combat.md §9 that are testable
-- without a live server:
--   T8  /bounty add debits and escrows; two contributions stack into
--       one total; ledger codes are bounty_escrow; min/self/funds/unknown
--       refusals
--   T9  no payout when killer and target share an IP, inside the safe
--       zone, or within the 3,600 s claim window — and the window is
--       keyed per VICTIM, not per pair (S07/CB-2.4)
--   CB-2.1 a last-attacker fallback credit pays no bounty: only a
--       direct kill or a combat log pays (S07/CB-2.1)
--   CB-2.2 no payout to a friend (mutual smp_social follow) or to a
--       killer below the playtime threshold (fresh alts, S07/CB-2.2)
--   T10 /bountyadmin clear refunds every contributor in full and
--       removes the bounty
-- plus: view/list command output, the claim broadcast, and escrow
-- conservation (X3): balances + escrow totals never change.
--
-- Run: luajit friedcake/dev-tests/test_bounty.lua
-- Exits non-zero on any failure.

local function readable(p)
	local f = io.open(p, "r")
	if f then f:close() return true end
	return false
end

local DEV
for _, c in ipairs({
	"friedcake/dev-tests/",
	"dev-tests/",
	"../dev-tests/",
}) do
	if readable(c .. "harness_f10.lua") then DEV = c break end
end
assert(DEV, "run this test as friedcake/dev-tests/test_bounty.lua from the repo root (or inside it)")

local H = dofile(DEV .. "harness_f10.lua")

-- MS-3 (strict engine stub, S07): Luanti's bindings take
-- `const std::string &name`, so a call with a non-string RAISES through
-- luaL_checkstring instead of quietly returning nil. Defined here in the
-- test file on purpose — S09 owns the pack-wide shared-harness variant.
local function strict(fn, api)
	return function(name, ...)
		if type(name) ~= "string" then
			error(string.format(
				"bad argument #1 to '%s' (string expected, got %s)",
				api, type(name)), 2)
		end
		return fn(name, ...)
	end
end
core.get_player_by_name = strict(core.get_player_by_name, "get_player_by_name")
core.get_player_ip = strict(core.get_player_ip, "get_player_ip")
core.player_exists = strict(core.player_exists, "player_exists")
core.chat_send_player = strict(core.chat_send_player, "chat_send_player")
core.show_formspec = strict(core.show_formspec, "show_formspec")
core.close_formspec = strict(core.close_formspec, "close_formspec")
core.check_player_privs = strict(core.check_player_privs, "check_player_privs")

H.load_stack()
H.mods_loaded() -- the engine fires on_mods_loaded after every main chunk

local OUT = { x = 600, y = 10, z = 600 }
local SPAWN = { x = 0, y = 8, z = 0 }

-- `playtime` is the CB-2.2 anti-alt threshold input (smp_store
-- rec.playtime). Everyone is an established account by default; pass 0
-- for a fresh one. get_player returns a copy, so the field goes through
-- update_player_field (which needs an existing record).
local function join_player(name, ip, seed, playtime)
	local p = H.player(name, OUT, ip)
	H.join(p)
	smp_store.api.ensure_player(name)
	if playtime == nil then playtime = 999999 end
	if playtime > 0 then
		smp_store.api.update_player_field(name, "playtime", playtime)
	end
	if seed and seed > 0 then
		smp_store.api.set_money(name, seed, "admin", "f10 test seed")
	end
	return p
end

join_player("carol", "1.1.1.1", 10000000)
join_player("dave",  "2.2.2.2", 10000000)
join_player("erin",  "3.3.3.3", 1000000)
join_player("mark",  "4.4.4.4", 0)
join_player("eve",   "5.5.5.5", 0)
join_player("bob",   "6.6.6.6", 0)
join_player("farma", "9.9.9.9", 0)
join_player("alt",   "9.9.9.9", 0) -- same IP as farma
join_player("pauper", "10.10.10.10", 0)

local function money_supply()
	local sum = 0
	for name in pairs(H.players) do sum = sum + H.money(name) end
	for _, b in pairs(smp_bounty.db.bounties) do sum = sum + (b.total or 0) end
	return sum
end
local baseline = money_supply()
H.eq(baseline, 21000000, "baseline supply = 21000000 cents of seeds")

local function has_ledger(name, ltype, amount)
	local entries = smp_store.api.ledger_for(name, 1, 100)
	for _, e in ipairs(entries or {}) do
		if e.type == ltype and e.amount == amount then return true end
	end
	return false
end

local bounty = H.commands.bounty
local bountyadmin = H.commands.bountyadmin
H.yes(bounty and bountyadmin, "commands registered")

----------------------------------------------------------------------
-- T8: /bounty add debits and escrows; contributions stack
----------------------------------------------------------------------

local carol0 = H.money("carol")
local ok, msg = bounty.func("carol", "add dave 5k")
H.yes(ok, "T8 add via command succeeds")
H.eq(msg, "You added $ 5K to dave's bounty. New total: $ 5K.",
	"T8 add confirmation message")
H.eq(H.money("carol"), carol0 - 500000, "T8 contributor debited immediately")

local erin0 = H.money("erin")
ok, msg = bounty.func("erin", "add dave 3000")
H.yes(ok, "T8 second contribution succeeds")
H.eq(H.money("erin"), erin0 - 300000, "T8 second contributor debited")

local b = smp_bounty.get("dave")
H.yes(b, "T8 bounty exists")
H.eq(b.total, 800000, "T8 two contributions stack into one total")
H.eq(b.contributors.carol, 500000, "T8 carol's contribution recorded")
H.eq(b.contributors.erin, 300000, "T8 erin's contribution recorded")

H.yes(has_ledger("carol", "bounty_escrow", -500000),
	"T8 ledger code bounty_escrow (carol)")
H.yes(has_ledger("erin", "bounty_escrow", -300000),
	"T8 ledger code bounty_escrow (erin)")

-- Refusals: min, self, unknown target, insufficient funds.
local before = H.money("carol")
ok, msg = bounty.func("carol", "add mark 5")
H.no(ok, "T8 below minimum refused")
H.eq(msg, "The minimum bounty is $ 1K.", "T8 minimum message")
H.eq(H.money("carol"), before, "T8 refused add debits nothing")
H.no(smp_bounty.get("mark"), "T8 no bounty created on refusal")

ok, msg = bounty.func("carol", "add carol 2000")
H.no(ok, "T8 self-bounty refused")
H.eq(msg, "You cannot place a bounty on yourself.", "T8 self message")

ok, msg = bounty.func("carol", "add ghost 2000")
H.no(ok, "T8 unknown target refused")
H.eq(msg, "Player ghost does not exist", "T8 unknown-target message")

ok, msg = bounty.func("pauper", "add mark 1000")
H.no(ok, "T8 insufficient funds refused")
H.eq(msg, "Insufficient funds.", "T8 funds message")
H.no(smp_bounty.get("mark"), "T8 still no bounty on mark")

----------------------------------------------------------------------
-- T9: anti-abuse — same IP, victim claim window, safe zone
----------------------------------------------------------------------

-- Same IP: farma's bounty cannot be claimed by alt.
ok = bounty.func("carol", "add farma 2000")
H.yes(ok, "T9 bounty on farma placed")
local alt0 = H.money("alt")
H.yes(smp_bounty.is_abuse("alt", "farma", OUT), "T9 is_abuse: same IP")
H.no(smp_bounty.try_claim("alt", "farma", OUT), "T9 same IP payout refused")
H.yes(smp_bounty.get("farma"), "T9 bounty survives the IP refusal")
H.eq(H.money("alt"), alt0, "T9 no money paid on same IP")

-- CB-2.2: a fresh account (playtime below MIN_KILLER_PLAYTIME) cannot
-- collect either, with no IP or friendship edge involved. farma's
-- bounty is left for the view test below.
join_player("newbie", "11.11.11.11", 0, 0)
H.eq(smp_bounty.abuse.check("newbie", "farma", OUT), "playtime",
	"CB-2.2 sub-threshold playtime refused")
local newbie0 = H.money("newbie")
H.no(smp_bounty.try_claim("newbie", "farma", OUT),
	"CB-2.2 fresh-alt payout refused")
H.eq(H.money("newbie"), newbie0, "CB-2.2 no money paid to the alt")
H.yes(smp_bounty.get("farma"), "CB-2.2 the bounty survives for a real killer")

-- CB-2.4: the 3,600 s window is keyed by VICTIM — one payout per victim
-- per window, whoever the killer is. A second, unrelated killer is
-- refused inside the window and allowed after it.
ok = bounty.func("carol", "add eve 5000")
H.yes(ok, "T9 bounty on eve placed")
local mark0 = H.money("mark")
H.wipe(H.all_chat)
H.yes(smp_bounty.try_claim("mark", "eve", OUT), "T9 first claim succeeds")
H.eq(H.money("mark"), mark0 + 500000, "T9 claimant paid from escrow")
H.eq(H.last(H.all_chat),
	"mark claimed the $ 5K bounty on eve.", "T9 claim broadcast")
H.yes(has_ledger("mark", "bounty_payout", 500000),
	"T9 ledger code bounty_payout")

ok = bounty.func("carol", "add eve 5000")
H.yes(ok, "T9 bounty on eve re-placed")
local dave0 = H.money("dave")
H.no(smp_bounty.try_claim("dave", "eve", OUT),
	"CB-2.4 victim window refuses a second killer inside 3600 s")
H.eq(H.money("dave"), dave0, "CB-2.4 refused payout moves no money")
H.yes(smp_bounty.get("eve"), "CB-2.4 the bounty survives the refusal")

H.advance(3600)
H.yes(smp_bounty.try_claim("dave", "eve", OUT),
	"CB-2.4 victim window expires after 3600 s")
H.eq(H.money("dave"), dave0 + 500000, "CB-2.4 paid once the window has passed")

-- Safe zone: no payout inside the spawn radius (X10).
ok = bounty.func("carol", "add bob 7000")
H.yes(ok, "T9 bounty on bob placed")
H.yes(smp_bounty.is_abuse("mark", "bob", SPAWN), "T9 is_abuse: safe zone")
H.no(smp_bounty.try_claim("mark", "bob", SPAWN),
	"T9 no payout inside the safe zone")
H.yes(smp_bounty.get("bob"), "T9 bounty survives the zone refusal")
H.yes(smp_bounty.try_claim("mark", "bob", OUT),
	"T9 the same pair claims outside the zone")
H.no(smp_bounty.get("bob"), "T9 bounty paid and removed")

----------------------------------------------------------------------
-- CB-2.1 + CB-2.2 (friends): attribution source and collusion
----------------------------------------------------------------------

-- CB-2.1 at the rule level: the last-attacker fallback (a reason-less
-- death: fall, lava, void, set_hp(0) / /kill) never pays, whatever the
-- killer's standing; a direct kill passes every rule here.
H.eq(smp_bounty.abuse.check("dave", "eve", nil, "fallback"), "source",
	"CB-2.1 fallback attribution refused")
H.eq(smp_bounty.abuse.check("mark", "alice", OUT, "death"), nil,
	"CB-2.1 a direct kill passes")

-- CB-2.2 (friend): a mutual follow is collusion — the friend's payout
-- is refused, a stranger's is not. smp_social is not part of this
-- stack, so the graph is faked for this section and removed after it.
local friendships = { { "dave", "erin" } }
_G.smp_social = {
	is_friend = function(a, b)
		for _, e in ipairs(friendships) do
			if (e[1] == a and e[2] == b) or (e[1] == b and e[2] == a) then
				return true
			end
		end
		return false
	end,
}
ok = bounty.func("carol", "add erin 2000")
H.yes(ok, "CB-2.2 bounty on erin placed")
H.eq(smp_bounty.abuse.check("dave", "erin", OUT), "friend",
	"CB-2.2 friend collusion refused")
local dave1 = H.money("dave")
H.no(smp_bounty.try_claim("dave", "erin", OUT),
	"CB-2.2 friend payout refused")
H.eq(H.money("dave"), dave1, "CB-2.2 the friend got nothing")

-- CB-2.1 end to end: the same refused killer retrying through the
-- fallback moves no money either (the refusal precedes the payout).
H.no(smp_bounty.try_claim("dave", "erin", OUT, "fallback"),
	"CB-2.1 fallback retry refused")
H.eq(H.money("dave"), dave1, "CB-2.1 fallback retry paid nothing")
H.yes(smp_bounty.get("erin"), "CB-2.2 the bounty survives both refusals")

_G.smp_social = nil -- stand down: the rest of the suite has no graph
local mark1 = H.money("mark")
H.yes(smp_bounty.try_claim("mark", "erin", OUT),
	"CB-2.2 a stranger claims the same bounty")
H.eq(H.money("mark"), mark1 + 200000, "CB-2.2 the stranger is paid")

----------------------------------------------------------------------
-- T10: /bountyadmin clear refunds every contributor in full
----------------------------------------------------------------------

local c0, e0 = H.money("carol"), H.money("erin")
ok, msg = bountyadmin.func("admin", "clear dave")
H.yes(ok, "T10 admin clear succeeds")
H.eq(H.money("carol"), c0 + 500000, "T10 carol refunded in full")
H.eq(H.money("erin"), e0 + 300000, "T10 erin refunded in full")
H.no(smp_bounty.get("dave"), "T10 bounty removed")
H.eq(msg, "Cleared dave's bounty. Refunded $ 8K.", "T10 admin message")
H.yes(has_ledger("carol", "bounty_payout", 500000),
	"T10 refund ledger code bounty_payout (carol)")
H.yes(has_ledger("erin", "bounty_payout", 300000),
	"T10 refund ledger code bounty_payout (erin)")

ok, msg = bountyadmin.func("admin", "clear dave")
H.no(ok, "T10 clearing twice is refused")
H.eq(msg, "dave has no bounty.", "T10 double-clear message")

----------------------------------------------------------------------
-- View: single target, list order, empty list
----------------------------------------------------------------------

ok, msg = bounty.func("mark", "dave")
H.yes(ok, "view of a cleared target succeeds")
H.eq(msg, "dave has no bounty.", "view: no bounty")

ok, msg = bounty.func("mark", "farma")
H.yes(ok, "view one bounty")
H.eq(msg, "farma's bounty: $ 2K", "view: single line")

ok = bounty.func("carol", "add mark 9k")
H.yes(ok, "second listed bounty placed")
H.wipe(H.chat.mark)
ok = bounty.func("mark", "")
H.yes(ok, "list renders")
H.eq(H.last(H.chat.mark),
	"--- Bounties ---\n1. mark — $ 9K\n2. farma — $ 2K",
	"list sorted by total, largest first")

ok, msg = bounty.func("pauper", "add dave 1000")
H.no(ok, "poor contributor refused") -- dave path unchanged; sanity

-- Clear the leftovers so the final supply check sees an empty escrow.
H.yes(bountyadmin.func("admin", "clear mark"), "clear mark")
H.yes(bountyadmin.func("admin", "clear farma"), "clear farma")
H.wipe(H.chat.mark)
ok = bounty.func("mark", "")
H.yes(ok, "empty list renders")
H.eq(H.last(H.chat.mark), "There are no bounties.", "empty list message")

----------------------------------------------------------------------
-- X3 (lite): balances + escrow totals unchanged across everything
----------------------------------------------------------------------

H.eq(money_supply(), baseline,
	"escrow conservation: supply equals the seed after every operation")

H.done("test_bounty (T8-T10, CB-2.1/CB-2.2/CB-2.4, views, X3)")
