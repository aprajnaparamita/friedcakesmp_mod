-- FriedcakeSMP — smp_amethyst/bucket.lua
--
-- Amethyst Bucket (LEGACY [S9]). Drained 27 water blocks at once:
-- removes every water node in the 3x3x3 cube around the pointed
-- position, protection-checked per node.
--
-- Spec: f06 §4.3 (LEGACY row).

local S = core.get_translator(core.get_current_modname())
local am = smp_amethyst

local CUBE = {
	{x=-1,y=-1,z=-1},{x=0,y=-1,z=-1},{x=1,y=-1,z=-1},
	{x=-1,y=0,z=-1},{x=0,y=0,z=-1},{x=1,y=0,z=-1},
	{x=-1,y=1,z=-1},{x=0,y=1,z=-1},{x=1,y=1,z=-1},
	{x=-1,y=-1,z=0},{x=0,y=-1,z=0},{x=1,y=-1,z=0},
	{x=-1,y=0,z=0},{x=0,y=0,z=0},{x=1,y=0,z=0},
	{x=-1,y=1,z=0},{x=0,y=1,z=0},{x=1,y=1,z=0},
	{x=-1,y=-1,z=1},{x=0,y=-1,z=1},{x=1,y=-1,z=1},
	{x=-1,y=0,z=1},{x=0,y=0,z=1},{x=1,y=0,z=1},
	{x=-1,y=1,z=1},{x=0,y=1,z=1},{x=1,y=1,z=1},
}

local function is_water(node)
	if not node then return false end
	local def = core.registered_nodes[node.name]
	local groups = def and def.groups or {}
	return (groups.water or 0) > 0 or (groups.liquid_water or 0) > 0
end

core.register_item("smp_amethyst:bucket", {
	description = S("Amethyst Bucket"),
	inventory_image = "mcl_amethyst_shard.png",
	wield_image = "mcl_amethyst_shard.png",
	stack_max = 1,
	on_use_primary = function(itemstack, player, pointed_thing)
		local name = player:get_player_name()

		if am.in_dig(name) then return itemstack end
		if am.is_tagged(name) then
			core.chat_send_player(name,
				S("You cannot use this while in combat"))
			return itemstack
		end
		if am.remove_expired(itemstack, player) then
			return ItemStack("")
		end
		if not pointed_thing or pointed_thing.type ~= "node" then
			return itemstack
		end
		local under = pointed_thing.under

		local drained = 0
		for _, off in ipairs(CUBE) do
			local pos = {
				x = under.x + off.x,
				y = under.y + off.y,
				z = under.z + off.z,
			}
			local node = core.get_node_or_nil(pos)
			if is_water(node) and not core.is_protected(pos, name) then
				core.set_node(pos, "air")
				drained = drained + 1
			end
		end

		if drained > 0 then
			core.chat_send_player(name, S("Drained @1 water blocks.", drained))
		end
		am.refresh_description(itemstack)
		player:set_wielded_item(itemstack)
		return itemstack
	end,
})
