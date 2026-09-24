-- FriedcakeSMP dev smoke test: smp_combat (+ smp_bounty claim chain)
--
-- Covers the parts of spec/features/f10-combat.md §9 that are testable
-- without a live server:
--   T1  melee tags both parties; a second hit refreshes the timer
--   T2  an arrow tags shooter and victim via the `_shooter` field
--   T3  every blocked command is refused with a message naming it;
--       /sell, /msg, /ah and /bounty still work; untagged players pass
--   T4  disconnecting while tagged drops main, craft, armor and offhand
--       at the logout position and clears the lists
--   T5  the combat-log kill is credited in statistics and pays an
--       outstanding bounty from escrow
--   T6  the combat-logged player respawns at world spawn on next join;
--       the flag then clears
--   T7  /kill (suicide reason) while tagged credits the last attacker
--       and pays the bounty
--   T11 tag state does not survive a restart (in-memory only)
--   T12 untagging on the death of either party, including a third
--       party whose opponent died
--   C1  combat.disable_elytra — elytra flight refused while tagged
-- plus: explosion ring attribution (TNT, punched crystal, 10 s window),
-- the spawn safe zone (X10: no PvP tag inside it) and the action-bar
-- countdown.
--
-- Run: luajit friedcake/dev-tests/test_combat.lua
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
assert(DEV, "run this test as friedcake/dev-tests/test_combat.lua from the repo root (or inside it)")

local H = dofile(DEV .. "harness_f10.lua")

-- C1 (§4.2.5): a stand-in for Mineclonia's playerphysics/elytra.lua
-- entity def. The harness registers no engine entities, and smp_combat's
-- hook installs against the prototype table in core.registered_entities
-- — the same table the engine uses as a luaentity's metatable, which is
-- why mutating it reaches live entities.
local attach_log, detach_log = {}, {}
local elytra_obj = {}
local elytra_ent = {
	name = "mcl_armor:elytra_entity",
	detach = function(self, player)
		detach_log[#detach_log + 1] = player:get_player_name()
		self.driver = nil
		player._attach = nil
	end,
}
elytra_obj.get_luaentity = function() return elytra_ent end
local elytra_def = {
	name = "mcl_armor:elytra_entity",
	object = elytra_obj,
	attach = function(self, player)
		attach_log[#attach_log + 1] = player:get_player_name()
		self.driver = player
		player._attach = self.object
	end,
}
core.registered_entities = { ["mcl_armor:elytra_entity"] = elytra_def }

H.load_stack()

local punch = H.callbacks.punch[1]
local hpchange = H.callbacks.hpchange[1]
local on_die = H.callbacks.die[1]
local on_leave = H.callbacks.leave[1]
local on_join = H.callbacks.join[1]
local place = H.callbacks.place[1]
local punchnode = H.callbacks.punchnode[1]
H.yes(punch and hpchange and on_die and on_leave and on_join,
	"all smp_combat callbacks registered")

----------------------------------------------------------------------
-- Players
----------------------------------------------------------------------

local alice   = H.player("alice",   { x = 500, y = 10, z = 500 }, "1.1.1.1")
local bob     = H.player("bob",     { x = 502, y = 10, z = 500 }, "2.2.2.2")
local carol   = H.player("carol",   { x = 510, y = 10, z = 510 }, "3.3.3.3")
local dave    = H.player("dave",    { x = 520, y = 10, z = 520 }, "4.4.4.4")
local eve     = H.player("eve",     { x = 530, y = 10, z = 530 }, "5.5.5.5")
local mallory = H.player("mallory", { x = 800, y = 10, z = 800 }, "6.6.6.6")
local vera    = H.player("vera",    { x = 805, y = 10, z = 805 }, "7.7.7.7")
local in_spawn = H.player("in_spawn", { x = 0, y = 8, z = 0 }, "8.8.8.8")
for _, p in ipairs({ alice, bob, carol, dave, eve, mallory, vera, in_spawn }) do
	H.join(p)
end

smp_store.api.set_money("carol", 10000000, "admin", "f10 test seed")

----------------------------------------------------------------------
-- T1: melee tags both parties; refresh on the second hit
----------------------------------------------------------------------

punch(alice, bob)
H.yes(smp_combat.is_tagged("alice"), "T1 melee tags the victim")
H.yes(smp_combat.is_tagged("bob"), "T1 melee tags the attacker")
H.yes(smp_combat.is_tagged(alice), "T1 is_tagged accepts an ObjectRef (f05 bridge)")
H.eq(smp_combat.last_attacker("alice"), "bob", "T1 last_attacker recorded")
H.eq(smp_combat.tags.alice.expires, H.now() + 20,
	"T1 tag lasts combat.tag_seconds (20)")
H.advance(10)
punch(alice, bob)
H.eq(smp_combat.tags.alice.expires, H.now() + 20,
	"T1 second hit refreshes the timer")
H.eq(smp_combat.seconds_left("alice"), 20, "T1 seconds_left after refresh")

----------------------------------------------------------------------
-- Action-bar countdown (§4.2.3)
----------------------------------------------------------------------

H.step(1)
H.eq(H.last(H.titles.alice), "In combat: 20s", "countdown on the action bar")
H.advance(5)
H.step(1)
H.eq(H.last(H.titles.alice), "In combat: 15s", "countdown ticks down")
smp_combat.untag("alice")
H.yes((H.title_removes.alice or 0) >= 1, "untag clears the action bar")
H.no(smp_combat.is_tagged("alice"), "untag removes the tag")

----------------------------------------------------------------------
-- T2: arrow attribution through `_shooter`
----------------------------------------------------------------------

smp_combat.untag("bob")
local arrow = H.entity({ _shooter = bob, _pos = { x = 501, y = 10, z = 500 } })
H.eq(smp_combat.resolve_attacker(arrow), "bob", "T2 _shooter attribution")
H.eq(smp_combat.resolve_attacker(nil), nil, "T2 environment resolves to nil")
hpchange(alice, -4, {
	type = "set_hp", mcl_damage = true,
	_mcl_reason = { type = "arrow", source = arrow, direct = arrow },
})
H.yes(smp_combat.is_tagged("alice"), "T2 arrow tags the victim")
H.yes(smp_combat.is_tagged("bob"), "T2 arrow tags the shooter")
H.eq(smp_combat.last_attacker("alice"), "bob", "T2 attacker is the shooter")

hpchange(carol, -4, { type = "fall" })
H.no(smp_combat.is_tagged("carol"), "T2 fall damage does not tag")

----------------------------------------------------------------------
-- T3: blocked commands, /sell /msg /ah /bounty allowed
----------------------------------------------------------------------

local BLOCKED = {
	"rtp", "rtpqueue", "tpa", "tp", "tpahere", "tpaccept",
	"homes", "home", "spawn", "warp", "world", "shop",
}
H.yes(smp_combat.is_tagged("alice"), "precondition: alice tagged")
for _, cmd in ipairs(BLOCKED) do
	H.yes(H.dispatch_chatcommand("alice", cmd, ""),
		"T3 /" .. cmd .. " blocked while tagged")
	local msg = H.last(H.chat.alice)
	H.eq(msg, "You cannot use /" .. cmd .. " during combat.",
		"T3 /" .. cmd .. " refusal names the command")
end
for _, cmd in ipairs({ "sell", "msg", "ah", "bounty" }) do
	H.no(H.dispatch_chatcommand("alice", cmd, ""),
		"T3 /" .. cmd .. " allowed while tagged")
end
smp_combat.untag("alice")
H.no(H.dispatch_chatcommand("alice", "rtp", ""),
	"T3 untagged players are not blocked")
punch(alice, bob) -- retag for the combat-log scenario

----------------------------------------------------------------------
-- C1: combat.disable_elytra — elytra flight refused while tagged
----------------------------------------------------------------------

-- Enable the key for this test section
smp_combat.cfg.combat.disable_elytra = true

-- Ensure alice is untagged at start
smp_combat.untag("alice")
smp_combat.untag("bob")

-- Reset attach/detach logs
for i = #attach_log, 1, -1 do attach_log[i] = nil end
for i = #detach_log, 1, -1 do detach_log[i] = nil end

-- Untagged player: attach should succeed
local elytra_ent2 = core.registered_entities["mcl_armor:elytra_entity"]
elytra_ent2.attach(elytra_obj, alice)
H.eq(#attach_log, 1, "C1 elytra attach allowed when untagged")
H.eq(attach_log[1], "alice", "C1 attach called with correct player")

-- Now tag alice and try to attach — should be refused with message
smp_combat.tag("alice", "bob")
H.yes(smp_combat.is_tagged("alice"), "C1 alice is tagged")
for i = #attach_log, 1, -1 do attach_log[i] = nil end
elytra_ent2.attach(elytra_obj, alice)
H.eq(#attach_log, 0, "C1 elytra attach refused while tagged")
H.eq(H.last(H.chat.alice), "You cannot use elytra during combat.",
	"C1 refusal message sent to player")

-- Test force-detach on globalstep when already flying
-- Simulate alice already attached to elytra
alice._attach = elytra_obj
elytra_ent.driver = alice
for i = #detach_log, 1, -1 do detach_log[i] = nil end
smp_combat.elytra.step()
H.eq(#detach_log, 1, "C1 globalstep detaches already-flying tagged player")
H.eq(detach_log[1], "alice", "C1 detach called with correct player")
H.eq(H.last(H.chat.alice), "Your elytra flight was ended by the combat tag.",
	"C1 force-detach message sent")

-- Untag alice — attach should work again
smp_combat.untag("alice")
for i = #attach_log, 1, -1 do attach_log[i] = nil end
elytra_ent2.attach(elytra_obj, alice)
H.eq(#attach_log, 1, "C1 elytra attach allowed after untag")

-- Disable the key again — attach should work even while tagged
smp_combat.cfg.combat.disable_elytra = false
smp_combat.tag("alice", "bob")
for i = #attach_log, 1, -1 do attach_log[i] = nil end
elytra_ent2.attach(elytra_obj, alice)
H.eq(#attach_log, 1, "C1 elytra attach allowed when key is false even if tagged")

-- Cleanup for next tests
smp_combat.untag("alice")
smp_combat.untag("bob")

----------------------------------------------------------------------
-- Explosion attribution: 10 s (pos, placer) ring
----------------------------------------------------------------------

local tnt = H.entity({ _pos = { x = 800, y = 10, z = 800 } })
place({ x = 800, y = 10, z = 800 }, { name = "mcl_tnt:tnt" }, mallory)
hpchange(vera, -8, {
	type = "set_hp", mcl_damage = true,
	_mcl_reason = { type = "explosion", source = tnt, direct = tnt },
})
H.yes(smp_combat.is_tagged("vera"), "TNT explosion tags the placer")
H.eq(smp_combat.last_attacker("vera"), "mallory",
	"TNT attribution comes from the ring buffer")
smp_combat.untag("vera")
smp_combat.untag("mallory")

local ring_before = #smp_combat.attribution.ring
punchnode({ x = 810, y = 10, z = 810 }, { name = "mcl_tnt:tnt" }, mallory)
H.eq(#smp_combat.attribution.ring, ring_before + 1,
	"punching TNT records the ring")
ring_before = #smp_combat.attribution.ring
place({ x = 900, y = 10, z = 900 }, { name = "mcl_core:cobble" }, bob)
H.eq(#smp_combat.attribution.ring, ring_before,
	"ordinary node placement is not recorded")

-- Stale entries are honoured for 10 s, not longer.
place({ x = 800, y = 10, z = 800 }, { name = "mcl_tnt:tnt" }, mallory)
H.advance(11)
hpchange(vera, -8, {
	type = "set_hp", mcl_damage = true,
	_mcl_reason = { type = "explosion", source = tnt, direct = tnt },
})
H.no(smp_combat.is_tagged("vera"), "ring attribution expires after 10 s")

-- Punched end crystal: mcl_end passes source = the puncher directly.
hpchange(vera, -8, {
	type = "set_hp", mcl_damage = true,
	_mcl_reason = { type = "explosion", source = mallory, direct = tnt },
})
H.yes(smp_combat.is_tagged("vera"),
	"crlosion with a player source needs no ring")
H.eq(smp_combat.last_attacker("vera"), "mallory", "crystal puncher attributed")
smp_combat.untag("vera")
smp_combat.untag("mallory")

----------------------------------------------------------------------
-- X10: no PvP tag inside the spawn safe zone
----------------------------------------------------------------------

smp_combat.untag("bob")
punch(in_spawn, bob)
H.no(smp_combat.is_tagged("in_spawn"), "X10 no tag for the spawn-side player")
H.no(smp_combat.is_tagged("bob"), "X10 the attacker is not tagged either")

----------------------------------------------------------------------
-- T4 + T5 + T6: combat log (one scenario: logout -> drops, credit,
-- payout, flag; then rejoin -> spawn respawn + flag clear)
----------------------------------------------------------------------

punch(alice, bob) -- alice.last_attacker = bob; both tagged
alice._inv.main   = { H.stack("mcl_core:diamond"), H.stack("mcl_core:apple") }
alice._inv.craft  = { H.stack("mcl_core:wood") }
alice._inv.armor  = { H.stack("mcl_armor:helmet_diamond") }
alice._inv.offhand = { H.stack("mcl_shield:shield") }

local carol_before = H.money("carol")
local b, err = smp_bounty.escrow_deposit("carol", "alice", 500000)
H.yes(b and not err, "T5 seed a bounty on alice")
H.eq(H.money("carol"), carol_before - 500000, "T5 bounty debited into escrow")
local bob_before = H.money("bob")
H.wipe(H.added)
H.wipe(H.all_chat)

H.yes(on_leave(alice), "alice's logout is a combat log")
H.callbacks.leave[2](alice) -- smp_bounty's own leave hook (IP remember)

-- T4: every registered list dropped at the logout position
H.eq(#H.added, 5, "T4 five stacks dropped")
local seen = {}
for _, e in ipairs(H.added) do
	seen[e.name] = (seen[e.name] or 0) + 1
	H.eq(e.pos.x, 500, "T4 drop x at logout position")
	H.eq(e.pos.y, 10, "T4 drop y at logout position")
	H.eq(e.pos.z, 500, "T4 drop z at logout position")
end
H.eq(seen["mcl_core:diamond"], 1, "T4 main list dropped")
H.eq(seen["mcl_core:wood"], 1, "T4 craft list dropped")
H.eq(seen["mcl_armor:helmet_diamond"], 1, "T4 armor list dropped")
H.eq(seen["mcl_shield:shield"], 1, "T4 offhand list dropped")
H.eq(#alice._inv.main, 0, "T4 main cleared")
H.eq(#alice._inv.craft, 0, "T4 craft cleared")
H.eq(#alice._inv.armor, 0, "T4 armor cleared")
H.eq(#alice._inv.offhand, 0, "T4 offhand cleared")
H.eq(alice._meta_ints["smp:combat_logged"], 1, "T6 combat-logged flag set")
H.no(smp_combat.is_tagged("alice"), "the leaver is untagged")
H.yes(smp_combat.is_tagged("bob"), "the opponent stays tagged")

local broadcast = false
for _, m in ipairs(H.all_chat) do
	if m == "alice has logged out during combat." then broadcast = true end
end
H.yes(broadcast, "combat log is broadcast (combat.log_broadcast)")

-- T5: credit the kill to bob: statistics and bounty
local stats_kill = false
for _, s in ipairs(H.stats) do
	if s.name == "bob" and s.key == "kills" and s.val == 1 then
		stats_kill = true
	end
end
H.yes(stats_kill, "T5 kill credited in statistics (f14 stub)")
H.eq(H.money("bob"), bob_before + 500000,
	"T5 combat-log kill pays the bounty from escrow")
H.no(smp_bounty.get("alice"), "T5 bounty removed after payout")
H.eq(H.money("carol"), carol_before - 500000,
	"T5 escrow moved, never minted (X3)")

-- T6: respawn at world spawn on next join; flag clears
alice:set_pos({ x = 500, y = 10, z = 500 }) -- engine restores logout pos
on_join(alice)
H.eq(alice._meta_ints["smp:combat_logged"], 0, "T6 flag cleared on join")
H.eq(alice:get_pos().x, 0, "T6 respawn x is world spawn")
H.eq(alice:get_pos().y, 100, "T6 respawn y is world spawn")
H.eq(alice:get_pos().z, 0, "T6 respawn z is world spawn")

----------------------------------------------------------------------
-- T7: /kill (no attacker in the reason) while tagged credits the
-- last attacker and pays the bounty
----------------------------------------------------------------------

local xavier = H.player("xavier", { x = 840, y = 10, z = 840 }, "9.9.9.9")
H.join(xavier)

punch(dave, eve) -- dave.last_attacker = eve; both tagged
local seed7, err7 = smp_bounty.escrow_deposit("carol", "dave", 250000)
H.yes(seed7 and not err7, "T7 seed a bounty on dave")
local eve_before = H.money("eve")
on_die(dave, { type = "set_hp", mcl_damage = true,
	_mcl_reason = { type = "generic" } })
H.eq(H.money("eve"), eve_before + 250000,
	"T7 /kill credit pays the bounty to the last attacker")
H.no(smp_combat.is_tagged("dave"), "T7 victim untagged on death")
H.no(smp_combat.is_tagged("eve"), "T7 opponent untagged on death")

----------------------------------------------------------------------
-- T12: untag on the death of either party
----------------------------------------------------------------------

-- Death of the player also clears the opponent.
punch(alice, bob)
on_die(alice, { type = "punch", object = bob })
H.no(smp_combat.is_tagged("alice"), "T12 dead player untagged")
H.no(smp_combat.is_tagged("bob"), "T12 killer untagged")

-- Death of the opponent clears a third party who was fighting them.
punch(vera, mallory)       -- vera <-> mallory
punch(xavier, vera)        -- xavier's opponent is vera
on_die(vera, { type = "punch", object = mallory })
H.no(smp_combat.is_tagged("vera"), "T12 victim untagged")
H.no(smp_combat.is_tagged("mallory"), "T12 killer untagged")
H.no(smp_combat.is_tagged("xavier"),
	"T12 third party whose opponent died is untagged")
local mallory_kill = false
for _, s in ipairs(H.stats) do
	if s.name == "mallory" and s.key == "kills" then mallory_kill = true end
end
H.yes(mallory_kill, "T12 killer from the death reason is credited")

----------------------------------------------------------------------
-- Escrow conservation across everything above (X3, lite)
----------------------------------------------------------------------

local supply = 0
for name in pairs(H.players) do supply = supply + H.money(name) end
for _, bb in pairs(smp_bounty.db.bounties) do supply = supply + bb.total end
H.eq(supply, 10000000,
	"money supply unchanged: balances + escrow (carol was seeded 10000000)")

----------------------------------------------------------------------
-- T11: tags are in-memory only — a restart wipes them
----------------------------------------------------------------------

punch(bob, alice)
H.yes(smp_combat.is_tagged("bob"), "T11 tag present before the restart")
for _, k in ipairs(H.storage_keys()) do
	local lk = k:lower()
	H.no(lk:find("combat", 1, true) or lk:find("tag", 1, true),
		"T11 no combat state written to storage (key: " .. k .. ")")
end
_G.smp_combat = nil
H.load("smp_combat") -- a restarted process: fresh Lua state
H.no(smp_combat.is_tagged("bob"), "T11 tags do not survive a restart")
H.no(smp_combat.is_tagged("alice"), "T11 no tags survive a restart")

H.done("test_combat (T1-T7, T11, T12, X10)")
