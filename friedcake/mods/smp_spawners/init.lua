-- FriedcakeSMP — smp_spawners
-- Virtual spawners: a node with metadata and a node timer. Zero
-- entities, zero ABMs (goal G1). Implements spec/features/f07-spawners.md.
--
-- Commands:
--   /spawner give <player> <type> [count]   issue spawner items (admin)
--     requires the smp_admin privilege (S06/SP-1); every issue leaves
--     an audit line in the `action` log (see the command below).
--
-- Submodules (loaded below in dependency order):
--   types.lua       spawner type table (data only; PROPOSED markers)
--   accrue.lua      production curve and lazy accrual
--   item.lua        smp_spawners:spawner_item (item meta carries type)
--   node.lua        smp_spawners:spawner node + metadata schema
--   interaction.lua place, stacking, Silk Touch break, menu open
--   formspecs.lua   container menu over the virtual storage
--   routing.lua     sell-all bridge into f02
--   performance.lua node timer lifecycle and no-op callbacks
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local MODNAME = core.get_current_modname() or "smp_spawners"
smp_spawners = { S = core.get_translator(MODNAME) }
local S = smp_spawners.S

----------------------------------------------------------------------
-- Configuration (f07 §7)
--
-- build_cfg() is a pure function of a settings object, so the whole
-- §7 table can be re-built from any store (the engine's core.settings,
-- or an injected fake in the dev-tests). Settings readers take the
-- store as their first argument for the same reason.
----------------------------------------------------------------------

local function num(settings, key, default)
	local v = tonumber(settings:get(key))
	if v == nil then return default end
	return v
end

local function str(settings, key, default)
	local v = settings:get(key)
	if v == nil or v == "" then return default end
	return v
end

-- `get_bool(key, default)` returns the default only when the key is
-- unset, so a default-true key CAN be turned off. The old
-- `get_bool(key) or default` never let `false` through
-- (`false or default == default`) — see f07 §10, F07-2.
--
-- Engine semantics (luanti src/script/lua_api/l_settings.cpp:119-139 +
-- src/settings.cpp:485): a stored value wins over the default and is
-- read with `is_yes` semantics, so `false` really is `false`.
local function bool(settings, key, default)
	return settings:get_bool(key, default)
end

-- f07 §4.7 acquisition sources and their §7 defaults.
local ACQ_SOURCES = { "shard_shop", "crates", "natural", "admin" }
local ACQ_DEFAULTS = { shard_shop = false, crates = false,
                       natural = false, admin = true }

-- Token grammar for the `spawners.acquisition = {...}` table value
-- (PROPOSED: the spec fixes the key shape, not its spelling).
local YES_TOKENS = { ["true"] = true, ["yes"] = true, ["1"] = true,
                     ["on"] = true }
local NO_TOKENS  = { ["false"] = true, ["no"] = true, ["0"] = true,
                     ["off"] = true }

local function parse_bool(v)
	if type(v) == "boolean" then return v end
	if type(v) ~= "string" then return nil end
	local s = v:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if YES_TOKENS[s] then return true end
	if NO_TOKENS[s] then return false end
	return nil
end

-- The §7 configuration table. `settings` defaults to the engine store.
function smp_spawners.build_cfg(settings)
	settings = settings or core.settings

	local stack_mode = str(settings, "spawners.stack_mode", "all")
	if stack_mode ~= "all" and stack_mode ~= "one" then
		-- Keep the raw value (operators can see what they wrote) but
		-- degrade to the default behaviour and say so (f07 §10, F07-10).
		core.log("warning", "[smp_spawners] unknown spawners.stack_mode "
			.. string.format("%q", tostring(stack_mode))
			.. "; falling back to \"all\"")
	end

	-- f07 §4.7 / §7 `spawners.acquisition`: one table key is the
	-- documented shape (spec §7, F07-9); the flat
	-- `spawners.acquisition.<src>` keys remain as a per-source
	-- fallback for existing configs.
	local acq = {}
	for _, src in ipairs(ACQ_SOURCES) do acq[src] = ACQ_DEFAULTS[src] end
	local from_table = {}
	local raw_acq = settings:get("spawners.acquisition")
	if type(raw_acq) == "string" and raw_acq:find("%S") then
		local body = raw_acq:gsub("[%[%]{}]", "")
		for k, v in body:gmatch("([%w_]+)%s*=%s*([%w_]+)") do
			if acq[k] ~= nil then
				local b = parse_bool(v)
				if b ~= nil then
					acq[k] = b
					from_table[k] = true
				else
					core.log("warning",
						"[smp_spawners] spawners.acquisition."
						.. k .. ": cannot read " .. string.format("%q", v))
				end
			end
		end
	end
	for _, src in ipairs(ACQ_SOURCES) do
		if not from_table[src] then
			local v = settings:get_bool("spawners.acquisition." .. src,
				acq[src])
			if v ~= nil then acq[src] = v end
		end
	end

	return {
		-- PROPOSED: single-spawner rate, roughly a vanilla spawner.
		r = num(settings, "spawners.r", 6),
		-- timer interval; the clamp for active_only is 2 x this (f07 §4.5)
		timer_interval = num(settings, "spawners.timer_interval", 60),
		-- active_only | always | capped (default active_only)
		accrual_mode = str(settings, "spawners.accrual_mode", "active_only"),
		-- PROPOSED, used only by accrual_mode = "capped"
		offline_cap_hours = num(settings, "spawners.offline_cap_hours", 24),
		-- LIVE [S24]: "all" = the whole held stack merges; "one" = one
		-- spawner per click (f07 §10, F07-10).
		stack_mode = stack_mode,
		-- f07 §4.4
		storage = {
			per_spawner = num(settings, "spawners.storage.per_spawner", 2880), -- PROPOSED
			hard_cap = num(settings, "spawners.storage.hard_cap", 2147483647), -- PROPOSED
		},
		xp = {
			per_spawner_cap = num(settings, "spawners.xp.per_spawner_cap", 2000), -- PROPOSED
		},
		-- CLONE [C3]
		require_silk_touch = bool(settings, "spawners.require_silk_touch", true),
		sneak_break_max = num(settings, "spawners.sneak_break_max", 64),
		-- PROPOSED
		open_requires_access = bool(settings, "spawners.open_requires_access", false),
		blast_immune = bool(settings, "spawners.blast_immune", true),
		convert_natural = bool(settings, "spawners.convert_natural", false),
		-- f07 §4.6.8: optional hopper extraction, off by default
		hopper_extraction = bool(settings, "spawners.hopper_extraction", false),
		-- f07 §4.2 "conditional" creeper (f07 §10)
		enable_creeper = bool(settings, "spawners.enable_creeper", true),
		-- f07 §4.7: no new supply; admin issue only [S10]
		acquisition = acq,
		-- C per type: skeleton is LIVE [S24]; the rest PROPOSED.
		-- (types.lua carries the defaults; apply_C_overrides writes the
		-- configured ones as plain keys — see below.)
		C = setmetatable({}, {
			__index = function(_, type_id)
				local def = smp_spawners.types and
					smp_spawners.types.def[type_id]
				return def and def.C or nil
			end,
		}),
	}
end

-- f07 §7 `spawners.C.skeleton` (documented shape, F07-8) and the
-- older compound `spawners.C = "skeleton=1505.35,zombie=250"` spelling.
-- The dotted keys are the documented ones, so they win when both are
-- present. Values must be positive numbers; anything else is ignored
-- and the per-type default from types.lua stands.
function smp_spawners.apply_C_overrides(settings, cfg)
	settings = settings or core.settings
	cfg = cfg or smp_spawners.cfg

	local raw = settings:get("spawners.C")
	if type(raw) == "string" and raw:find("%S") then
		for k, v in raw:gmatch("([^,%s]+)=([^,%s]+)") do
			local id = k:match("^[%w_]+$")
			local val = tonumber(v)
			if id and val and val > 0 then
				cfg.C[id] = val
			end
		end
	end

	local defs = (smp_spawners.types and smp_spawners.types.def) or {}
	for id in pairs(defs) do
		local val = tonumber(settings:get("spawners.C." .. id))
		if val and val > 0 then
			cfg.C[id] = val
		end
	end
end

smp_spawners.cfg = smp_spawners.build_cfg(core.settings)

----------------------------------------------------------------------
-- Submodules
----------------------------------------------------------------------

local modpath = core.get_modpath(MODNAME)
for _, file in ipairs({
	"types.lua",
	"accrue.lua",
	"item.lua",
	"node.lua",
	"performance.lua",
	"interaction.lua",
	"formspecs.lua",
	"routing.lua",
}) do
	local chunk, err = loadfile(modpath .. "/" .. file)
	if not chunk then
		error("[smp_spawners] cannot load " .. file .. ": " .. tostring(err))
	end
	local ok, lerr = pcall(chunk)
	if not ok then
		error("[smp_spawners] error in " .. file .. ": " .. tostring(lerr))
	end
end

-- types.lua is loaded now, so the per-type C overrides can resolve the
-- documented `spawners.C.<type>` names (F07-8).
smp_spawners.apply_C_overrides(core.settings, smp_spawners.cfg)

smp_spawners.formspecs.register_handler()
smp_spawners.formspecs.register_leave()

----------------------------------------------------------------------
-- Commands (f07 §2)
----------------------------------------------------------------------

local function usage(sender)
	core.chat_send_player(sender, S("/spawner give <player> <type> [count]"))
end

-- The smp_admin privilege is registered by smp_admin (load order in
-- modpack.conf puts it before us).
--
-- S06/SP-1 (CRITICAL): the field the engine reads is `privs = {…}`
-- (builtin/common/chatcommands.lua:44-51 — `def.privs = def.privs or {}`,
-- so anything else requires NO privilege). The old `privilege = "smp_admin"`
-- was silently ignored and any player could mint spawners. The pack-wide
-- lint dev-tests/test_chatcmds.lua fails on that key.
core.register_chatcommand("spawner", {
	privs = { smp_admin = true },
	func = function(sender, params)
		local parts = {}
		for w in params:gmatch("%S+") do parts[#parts + 1] = w end

		if #parts == 0 then usage(sender) return end
		if parts[1] ~= "give" then usage(sender) return end

		local target, type_id = parts[2], parts[3]
		if not target or not type_id then usage(sender) return end
		if not smp_spawners.cfg.acquisition.admin then
			core.chat_send_player(sender,
				S("Administrative spawner issue is disabled"))
			return
		end
		if not smp_spawners.types.get(type_id) then
			core.chat_send_player(sender, S("Unknown spawner type"))
			return
		end
		local count = 1
		if parts[4] then
			local n = math.floor(tonumber(parts[4]) or 0)
			if n < 1 or n > 64 then
				core.chat_send_player(sender,
					S("Count must be between 1 and 64"))
				return
			end
			count = n
		end
		local player = core.get_player_by_name(target)
		if not player then
			core.chat_send_player(sender, S("Player not found: @1", target))
			return
		end
		local stack = smp_spawners.make_item(type_id, count)
		local inv = player:get_inventory()

		-- S06/SP-1: audit every issue. Before the fix there was no
		-- trail at all, so an exploited world could not be reviewed.
		core.log("action", "[smp_spawners] /spawner give " .. count ..
			"x" .. type_id .. " to " .. target .. " by " .. sender)

		-- S06/SP-2: InvRef:add_item returns the leftover stack, which
		-- is always a truthy ItemStack — the test is `not left:is_empty()`.
		-- Whatever did not fit is dropped at the target's feet, never
		-- destroyed (luanti l_inventory.cpp:275-291).
		local left = inv:add_item("main", stack)
		if left and not left:is_empty() then
			core.add_item(vector.offset(player:get_pos(), 0, 0.5, 0),
				left)
		end
		core.chat_send_player(sender,
			S("Gave @1 @2 @3 Spawner", target, count,
				smp_spawners.types.get(type_id).display))
		return true
	end,
})

core.log("action",
	"[smp_spawners] loaded: virtual spawners, node timer " ..
	smp_spawners.cfg.timer_interval .. "s, accrual " ..
	smp_spawners.cfg.accrual_mode)
