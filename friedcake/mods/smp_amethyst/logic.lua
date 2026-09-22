-- FriedcakeSMP — smp_amethyst/logic.lua
--
-- Pure geometry and graph logic for the multi-block tools. No engine
-- calls: everything takes plain positions (tables with x/y/z numbers)
-- and a voxel/group accessor function, so it can be unit-tested under
-- plain LuaJIT (see friedcake/dev-tests/test_amethyst.lua).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local M = {}

local function same(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

local function add(a, b)
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

-- The 3x3 plane of positions centred on `under` and perpendicular to
-- the dug face. The face normal is (under - above); the plane is spanned
-- by the two axes other than the normal's axis. Returns 9 positions
-- (the centre plus its 8 in-plane neighbours).
--
-- f06 §4.3: the Shard Pickaxe "mines nine blocks at once" in "the plane
-- perpendicular to the dug face".
function M.plane_positions(under, above)
	local n = {
		x = under.x - above.x,
		y = under.y - above.y,
		z = under.z - above.z,
	}
	-- The normal must be a unit axis. Identify it and pick the other two.
	local axes = { "x", "y", "z" }
	local normal_axis
	local plane_axes = {}
	for _, ax in ipairs(axes) do
		if n[ax] ~= 0 then
			normal_axis = ax
		end
	end
	if not normal_axis then
		-- Degenerate (above == under): fall back to the XY plane.
		return {
			add(under, {x=-1,y=-1,z=0}), add(under, {x=0,y=-1,z=0}), add(under, {x=1,y=-1,z=0}),
			add(under, {x=-1,y=0,z=0}),  under,                              add(under, {x=1,y=0,z=0}),
			add(under, {x=-1,y=1,z=0}),  add(under, {x=0,y=1,z=0}),          add(under, {x=1,y=1,z=0}),
		}
	end
	for _, ax in ipairs(axes) do
		if ax ~= normal_axis then plane_axes[#plane_axes + 1] = ax end
	end
	local a, b = plane_axes[1], plane_axes[2]
	local out = {}
	for da = -1, 1 do
		for db = -1, 1 do
			local off = { x = 0, y = 0, z = 0 }
			off[a] = da
			off[b] = db
			out[#out + 1] = add(under, off)
		end
	end
	return out
end

-- Breadth-first search from `start` through positions whose
-- `group_at(pos)` returns a table containing any of `groups` (a list of
-- group names), stopping after at most `limit` visited positions.
-- `group_at` returns the groups table for a position (or nil/{} for air).
--
-- Returns the list of visited positions (start first), which is
-- truncated to `limit`. f06 §4.3: the Shard Axe "fells a tree with
-- connected logs and leaves ... limited to amethyst.felling_limit".
function M.bfs_connected(start, group_at, groups, limit)
	local want = {}
	for _, g in ipairs(groups) do want[g] = true end

	local function ok(pos)
		local groups_tbl = group_at(pos)
		if not groups_tbl then return false end
		for g in pairs(want) do
			if groups_tbl[g] then return true end
		end
		return false
	end

	local visited = { [start.x .. "," .. start.y .. "," .. start.z] = true }
	local queue = { start }
	local out = { start }
	local NEIGH = {
		{x=1,y=0,z=0},{x=-1,y=0,z=0},
		{x=0,y=1,z=0},{x=0,y=-1,z=0},
		{x=0,y=0,z=1},{x=0,y=0,z=-1},
	}
	local head = 1
	while head <= #queue and #out < limit do
		local p = queue[head]
		head = head + 1
		for _, d in ipairs(NEIGH) do
			local q = add(p, d)
			local key = q.x .. "," .. q.y .. "," .. q.z
			if not visited[key] then
				visited[key] = true
				if ok(q) then
					queue[#queue + 1] = q
					out[#out + 1] = q
					if #out >= limit then return out end
				end
			end
		end
	end
	return out
end

-- True if two positions are the same cell.
function M.same_pos(a, b)
	return same(a, b)
end

return M
