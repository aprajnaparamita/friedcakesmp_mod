-- FriedcakeSMP — smp_amethyst/haste.lua
--
-- Shard Potion of Haste. Haste II for 24 h [S9]:
--   mcl_potions.give_effect_by_level("haste", player, 2, 86400)
--
-- Mineclonia's effects live in per-object memory and do NOT survive
-- logout, so the expiry is mirrored in player meta `smp:haste_until`
-- (absolute Unix time) and re-applied on join with the remaining time.
--
-- Spec: f06 §4.3.

local S = core.get_translator(core.get_current_modname())
local am = smp_amethyst

local META_KEY = "smp:haste_until"

local function get_haste_until(player)
	local raw = player:get_meta():get_string(META_KEY)
	local n = raw ~= "" and tonumber(raw) or nil
	if not n or n ~= n or n <= 0 then return nil end
	return math.floor(n)
end

local function set_haste_until(player, t)
	player:get_meta():set_string(META_KEY, tostring(math.floor(t)))
end

local function apply_haste(player, level, duration)
	if mcl_potions and type(mcl_potions.give_effect_by_level) == "function" then
		mcl_potions.give_effect_by_level("haste", player, level, duration)
	end
end

-- Re-apply on join if the stored window is still open and the in-memory
-- effect is gone.
am.register_join_hook(function(player)
	local until_t = get_haste_until(player)
	if not until_t then return end
	local now = os.time()
	if until_t <= now then
		set_haste_until(player, 0)
		return
	end
	local has = mcl_potions and type(mcl_potions.has_effect) == "function"
		and mcl_potions.has_effect(player, "haste")
	if not has then
		apply_haste(player, am.cfg.haste_level, until_t - now)
	end
end)

core.register_item("smp_amethyst:haste_potion", {
	description = S("Shard Potion of Haste"),
	inventory_image = "mcl_potions_haste.png",
	stack_max = 16,
	on_use = function(itemstack, player, pointed_thing)
		if am.remove_expired(itemstack, player) then
			return ItemStack("")
		end
		local now = os.time()
		-- Validate first (shared §2.3): the item is present (checked by
		-- the engine and by remove_expired above); then mutate: effect,
		-- meta, stack count — no yields between.
		apply_haste(player, am.cfg.haste_level, am.cfg.haste_duration)
		set_haste_until(player, now + am.cfg.haste_duration)
		itemstack:set_count(itemstack:get_count() - 1)
		player:set_wielded_item(itemstack)
		core.chat_send_player(player:get_player_name(),
			S("You are hastened for @1.",
				am.expiry.duration_str(am.cfg.haste_duration)))
		return itemstack
	end,
})
