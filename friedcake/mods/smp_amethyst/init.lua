-- FriedcakeSMP — smp_amethyst
--
-- Timed shard items (f06 §4.3). Each is bought with shards, sellable and
-- auctionable but NOT orderable (the blacklist in blacklist.lua is
-- imported by f04), and carries a self-destruct timer starting at one
-- day [S9] (expiry.lua).
--
-- Items:
--   smp_amethyst:pickaxe      Shard Pickaxe ("drill") — 3x3 plane dig
--   smp_amethyst:axe          Shard Axe — fells connected logs+leaves
--   smp_amethyst:shovel       Shard Shovel — 3x3 plane dig, dirt only
--   smp_amethyst:haste_potion Shard Potion of Haste — Haste II, 24 h
--   smp_amethyst:bucket       Amethyst Bucket (LEGACY) — drains 27 water
--   smp_amethyst:sell_axe     Amethyst Sell Axe (LIVE) — sells containers
--
-- Multi-block digs use a per-player re-entrancy guard
-- (smp_amethyst._digging[player_name]); without it a node's dig
-- callbacks re-enter the tool and it recurses into itself.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())
local modpath = core.get_modpath("smp_amethyst")

smp_amethyst = {}

----------------------------------------------------------------------
-- Configuration (spec f06 §7)
----------------------------------------------------------------------

local cfg = {
	-- LIVE [S9]: self-destruct timer starts at one day.
	lifetime = tonumber(core.settings:get("amethyst.lifetime")) or 86400,
	-- PROPOSED: cap on nodes the felling axe removes per use.
	felling_limit = tonumber(core.settings:get("amethyst.felling_limit")) or 512,
	-- PROPOSED: how often online inventories are swept for expiry.
	sweep_interval = tonumber(core.settings:get("amethyst.sweep_interval")) or 300,
	-- LIVE [S9]: Haste II for 24 h.
	haste_level = tonumber(core.settings:get("amethyst.haste_level")) or 2,
	haste_duration = tonumber(core.settings:get("amethyst.haste_duration")) or 86400,
	-- PROPOSED: node names the multi-block digs never touch.
	dig_blacklist_nodes = {
		["mcl_core:barrier"] = true,
		["mcl_core:realm_barrier"] = true,
		["mcl_mobspawners:spawner"] = true,
	},
}
smp_amethyst.cfg = cfg

local expiry = dofile(modpath .. "/expiry.lua")
local logic = dofile(modpath .. "/logic.lua")
smp_amethyst.expiry = expiry
smp_amethyst.logic = logic
-- The orders blacklist f04 imports (f06 §4.3 [S9]).
smp_amethyst.blacklist = dofile(modpath .. "/blacklist.lua")

----------------------------------------------------------------------
-- Re-entrancy guard for multi-block digs
----------------------------------------------------------------------

smp_amethyst._digging = {}   -- player_name -> true while a dig is running

local function in_dig(name) return smp_amethyst._digging[name] == true end
local function begin_dig(name) smp_amethyst._digging[name] = true end
local function end_dig(name) smp_amethyst._digging[name] = nil end

-- Exposed to the item modules (dofile'd below) so each tool's
-- on_use_primary enters the same per-player guard.
smp_amethyst.in_dig = in_dig
smp_amethyst.begin_dig = begin_dig
smp_amethyst.end_dig = end_dig

----------------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------------

-- Combat tag (f10, smp_combat). Not implemented yet; guarded so this
-- mod loads before f10 lands. f06 §4.3: tools are "refused while tagged".
function smp_amethyst.is_tagged(player_name)
	if smp_combat and type(smp_combat.is_tagged) == "function" then
		return smp_combat.is_tagged(player_name) and true or false
	end
	return false
end

-- Set the self-destruct timer on a freshly bought item.
function smp_amethyst.set_expiry(stack, now)
	return expiry.set_expiry(stack, (now or os.time()) + cfg.lifetime)
end

function smp_amethyst.is_expired(stack, now)
	return expiry.is_expired(stack, now)
end

-- Refresh the "Expires in ..." description line (f06 §4.3).
function smp_amethyst.refresh_description(stack, now)
	return expiry.refresh_description(stack, S, now)
end

-- Remove an expired item from the player's hand with a message.
-- Returns true if the item was removed.
function smp_amethyst.remove_expired(stack, player)
	if not expiry.is_expired(stack) then return false end
	local def = core.registered_items[stack:get_name()]
	local name = def and def.description or stack:get_name()
	core.chat_send_player(player:get_player_name(), S("@1 has expired.", name))
	stack:set_count(0)
	return true
end

-- A node is a dig blacklist hit when it is bedrock, not diggable, a
-- named blacklist node, or a container (carries an inventory). PROPOSED.
function smp_amethyst.dig_blacklisted(pos)
	local node = core.get_node_or_nil(pos)
	if not node or node.name == "air" then return false end
	local def = core.registered_nodes[node.name] or {}
	local groups = def.groups or {}
	if groups.bedrock or groups.not_diggable then return true end
	if cfg.dig_blacklist_nodes[node.name] then return true end
	local meta = core.get_meta(pos)
	if type(meta.get_inventory) == "function" and meta:get_inventory() then
		return true
	end
	return false
end

-- Dig one node without touching the wielded tool: no wear, no
-- on_use_primary re-entry. Drops are still generated and given to the
-- player. Used for the neighbour blocks of a multi-block dig so wear is
-- applied exactly once per use (on the primary block, via core.node_dig).
function smp_amethyst.dig_node_once(pos, player, toolname)
	local node = core.get_node_or_nil(pos)
	if not node or node.name == "air" then return false end
	local def = core.registered_nodes[node.name]
	if not def or not def.diggable then return false end
	if def.can_dig and not def.can_dig(pos, player) then return false end
	if core.is_protected(pos, player and player:get_player_name()) then
		return false
	end
	local drops = core.get_node_drops(node, toolname)
	core.handle_node_drops(pos, drops, player)
	core.remove_node(pos)
	return true
end

-- Sweep the main and offhand lists of one player's inventory, removing
-- expired amethyst items. Returns the number removed.
function smp_amethyst.sweep_player(player)
	local inv = player:get_inventory()
	if not inv then return 0 end
	local name = player:get_player_name()
	local removed = 0
	local function notify(stack)
		local def = core.registered_items[stack:get_name()]
		local n = def and def.description or stack:get_name()
		core.chat_send_player(name, S("@1 has expired.", n))
	end
	removed = removed + expiry.sweep_list(inv, "main", notify)
	removed = removed + expiry.sweep_list(inv, "offhand", notify)
	return removed
end

----------------------------------------------------------------------
-- Lifecycle: sweep + haste re-apply
----------------------------------------------------------------------

local sweep_tick = 0

-- Haste re-application on join (haste.lua registers into this list).
local join_hooks = {}
function smp_amethyst.register_join_hook(fn) join_hooks[#join_hooks + 1] = fn end

core.register_on_joinplayer(function(player)
	smp_amethyst.sweep_player(player)
	-- Refresh descriptions of any amethyst items carried on join.
	local inv = player:get_inventory()
	if inv then
		for _, list in ipairs({ "main", "offhand" }) do
			local size = inv:get_size(list)
			for i = 0, size - 1 do
				local st = inv:get_stack(list, i)
				if not st:is_empty() and expiry.is_amethyst(st:get_name()) then
					smp_amethyst.refresh_description(st)
					inv:set_stack(list, i, st)
				end
			end
		end
	end
	for _, fn in ipairs(join_hooks) do fn(player) end
end)

core.register_globalstep(function(dtime)
	sweep_tick = sweep_tick + dtime
	if sweep_tick >= cfg.sweep_interval then
		sweep_tick = 0
		for _, player in ipairs(core.get_connected_players()) do
			smp_amethyst.sweep_player(player)
		end
	end
end)

-- An expired item picked up from the ground/container is removed lazily
-- (f06 §4.3: "items in containers are removed lazily when ... picked up").
core.register_on_pickup(function(itemstack, player)
	if not player or not player:is_player() then return itemstack end
	if expiry.is_amethyst(itemstack:get_name()) and expiry.is_expired(itemstack) then
		smp_amethyst.remove_expired(itemstack, player)
	end
	return itemstack
end)

----------------------------------------------------------------------
-- Register the items (each module defines its own on_use_primary/on_use)
----------------------------------------------------------------------

dofile(modpath .. "/pickaxe.lua")
dofile(modpath .. "/axe.lua")
dofile(modpath .. "/shovel.lua")
dofile(modpath .. "/haste.lua")
dofile(modpath .. "/sell_axe.lua")
dofile(modpath .. "/bucket.lua")

core.log("action", "[smp_amethyst] loaded: 6 shard items, lifetime="
	.. cfg.lifetime .. "s, felling_limit=" .. cfg.felling_limit)
