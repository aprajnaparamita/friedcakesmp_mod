-- FriedcakeSMP — smp_world
-- f15 World Rules and Server Configuration: the four hooks of the config
-- package — spawn protection, soft world border, account-per-IP flag and
-- staff-name filter. The rules themselves are documented in
-- friedcake/WORLD_RULES.md; the specification is
-- spec/features/f15-world-rules.md.
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_world = {}

----------------------------------------------------------------------
-- Configuration
--
-- All keys are read LIVE from minetest.conf (defaults from spec §7, all
-- PROPOSED). The pins for engine settings live in
-- friedcake/minetest.conf.example.
----------------------------------------------------------------------

local DEFAULT_SPAWN_RADIUS = 128 -- spec §7 world.spawn_protect_radius
local DEFAULT_BORDER_MARGIN = 16 -- spec §7 world.border_margin
local DEFAULT_MAX_ACCOUNTS = 5   -- rule LIVE [S18]; enforcement PROPOSED
local DEFAULT_NAME_FILTER =
	"^admin$,^admin[%d_%-],^administrator$," ..
	"^staff$,^staff[%d_%-],^mod$,^mod[%d_%-]," ..
	"^moderator$,^moderator[%d_%-],^operator$," ..
	"^owner$,^server$,^server[%d_%-]" -- PROPOSED (f15 §7)

local function cfg_number(key, default)
	local v = tonumber(core.settings:get(key))
	return v or default
end

local function cfg_bool(key, default)
	local v = core.settings:get(key)
	if v == nil then
		return default
	end
	v = string.lower(v)
	return not (v == "false" or v == "0" or v == "no" or v == "off")
end

local function cfg_string(key, default)
	local v = core.settings:get(key)
	if v == nil then
		return default
	end
	return v
end

----------------------------------------------------------------------
-- 1. Spawn protection (spec §4.2.1, §6, acceptance T1, X10)
----------------------------------------------------------------------

-- The configured square half-width, for f08's /rtp ring clipping.
function smp_world.spawn_radius()
	return cfg_number("world.spawn_protect_radius", DEFAULT_SPAWN_RADIUS)
end

-- O(1) spawn protection test: a square of half-width
-- world.spawn_protect_radius around the origin, Overworld only. No node
-- scanning — pure arithmetic plus one dimension lookup (spec §6).
function smp_world.is_spawn_protected(pos)
	local r = smp_world.spawn_radius()
	if r <= 0 then
		return false -- radius 0 disables spawn protection
	end
	if math.abs(pos.x) > r or math.abs(pos.z) > r then
		return false
	end
	return mcl_worlds.pos_to_dimension(pos) == "overworld"
end

-- Compose into the existing core.is_protected chain (spec §6, §8): the
-- engine default returns false, Mineclonia's mcl_levelgen wraps that for
-- ungenerated chunks, and we wrap whatever is current. WRAPPING — never
-- replacing — keeps every earlier layer reachable regardless of mod load
-- order, so every mod that consults core.is_protected (f07 spawner
-- digging, f06 amethyst tools, f10 PvP policy, f08 /rtp landing) honours
-- spawn protection automatically (T1, X10).
local old_is_protected = core.is_protected

function core.is_protected(pos, name)
	if pos and smp_world.is_spawn_protected(pos) then
		-- The engine's protection_bypass privilege is documented as
		-- "Can bypass node protection in the world"; honouring it here
		-- keeps staff able to build and clear at spawn.
		local bypass = name and
			core.check_player_privs(name, "protection_bypass")
		if not bypass then
			return true
		end
	end
	return old_is_protected(pos, name)
end

-- The verbatim f15 refusal string (spec §6 / §3, PROPOSED house style).
-- Registered unconditionally per spec §6: Mineclonia's only other
-- protection source today is mcl_levelgen's ungenerated-chunk guard,
-- where "This area is protected." is equally accurate.
function smp_world.on_protection_violation(pos, name)
	core.chat_send_player(name, S("This area is protected."))
end

core.register_on_protection_violation(smp_world.on_protection_violation)

----------------------------------------------------------------------
-- 2. Soft world border (spec §4.2.2, §6, acceptance T3)
----------------------------------------------------------------------

-- The clamp coordinate: mapgen_limit - world.border_margin. Read through
-- core.get_mapgen_setting because mapgen_limit is stored PER WORLD
-- (map_meta.txt wins over minetest.conf) and the API reports the ACTIVE
-- value — the exact call spec §6 prescribes. Returns false when the world
-- is unlimited (mapgen_limit 0 / unset) or the margin consumes the limit,
-- which disables the soft border.
function smp_world.border_limit()
	local limit = tonumber(core.get_mapgen_setting("mapgen_limit"))
	if not limit or limit <= 0 then
		return false
	end
	local margin = cfg_number("world.border_margin", DEFAULT_BORDER_MARGIN)
	local clamp = limit - margin
	if clamp <= 0 then
		return false
	end
	return clamp
end

-- Move one player back inside the border and tell them (verbatim f15
-- string, spec §6). O(1) per player; never a per-node scan.
function smp_world.enforce_border(player)
	if not cfg_bool("world.soft_border", true) then
		return
	end
	local limit = smp_world.border_limit()
	if not limit then
		return
	end
	local p = player:get_pos()
	if math.abs(p.x) <= limit and math.abs(p.z) <= limit then
		return
	end
	-- Clamp X and Z into [-limit, limit]; Y is untouched (mapgen_limit is
	-- a horizontal bound).
	player:set_pos({
		x = math.max(-limit, math.min(limit, p.x)),
		y = p.y,
		z = math.max(-limit, math.min(limit, p.z)),
	})
	core.chat_send_player(player:get_player_name(),
		S("You have reached the world border."))
end

-- One sweep: every online player at most once per second, so the border
-- costs O(online players) per second in one globalstep (spec §4.4
-- budget). The accumulator keeps only the sub-second remainder — after a
-- lag spike this sweeps ONCE instead of bursting one sweep per accumulated
-- second.
local border_acc = 0

function smp_world.border_step(dtime)
	if not cfg_bool("world.soft_border", true) then
		border_acc = 0
		return
	end
	border_acc = border_acc + dtime
	if border_acc < 1 then
		return
	end
	border_acc = border_acc - math.floor(border_acc)
	for _, player in ipairs(core.get_connected_players()) do
		smp_world.enforce_border(player)
	end
end

core.register_globalstep(function(dtime)
	smp_world.border_step(dtime)
end)

----------------------------------------------------------------------
-- 3. Accounts per IP — flag, never block (spec §4.1, acceptance T5)
----------------------------------------------------------------------

-- Distinct-account index keyed by sha1(IP), kept in THIS MOD's own
-- storage. Spec §5 says the counter is "derived ... from the player
-- database" and "no table is owned", but no store maps accounts to IPs
-- (smp_store's player records have no IP field, core.get_player_ip is
-- online-only, offline player meta is unreachable) — the deviation and
-- its storage contract are written up in f15 §10 (V-88 proposed) and the
-- Proposed shared changes block.
--
-- Privacy: IPs are never stored in the clear — only sha1(ip) buckets.
local ip_index -- [sha1(ip)] = { [player_name] = true }, loaded lazily
-- Captured at load time: core.get_mod_storage() resolves the calling mod's
-- name via core.get_current_modname(), which is only valid while the mod's
-- file is being loaded — not inside callbacks.
local storage = core.get_mod_storage()

local function get_storage()
	return storage
end

local function load_index()
	if ip_index then
		return ip_index
	end
	local raw = get_storage():get_string("accounts_per_ip")
	if raw ~= "" then
		ip_index = core.parse_json(raw) or {}
	else
		ip_index = {}
	end
	return ip_index
end

local function save_index()
	get_storage():set_string("accounts_per_ip", core.write_json(ip_index))
end

local function ip_key(ip)
	if core.sha1 then
		return core.sha1(ip)
	end
	return ip -- engine fallback; sha1 has shipped since 5.0
end

-- Distinct accounts known for an address (0 if none). Read-only: creates
-- no buckets. For tests and moderation introspection.
function smp_world.accounts_on_ip(ip)
	local bucket = load_index()[ip_key(ip)]
	if not bucket then
		return 0
	end
	local n = 0
	for _ in pairs(bucket) do
		n = n + 1
	end
	return n
end

-- Staff flag channel: log unconditionally (logs are not player-facing, so
-- no translator) and tell online staff. Also counts flags for tests and
-- future introspection (O(online players), but only on the rare flag).
smp_world.staff_flag_count = 0

function smp_world.flag_staff(message)
	smp_world.staff_flag_count = smp_world.staff_flag_count + 1
	core.log("warning", "[smp_world] " .. message)
	for _, p in ipairs(core.get_connected_players()) do
		local name = p:get_player_name()
		if core.check_player_privs(name, { smp_admin = true })
				or core.check_player_privs(name, { smp_moderator = true }) then
			core.chat_send_player(name, message)
		end
	end
end

----------------------------------------------------------------------
-- 4. Staff-impersonation name filter (spec §4.1, f15 §7)
----------------------------------------------------------------------

-- Returns the first configured pattern the lower-cased name matches, or
-- nil. world.staff_name_filter is a comma-separated Lua pattern list;
-- unset = the PROPOSED built-in default, "" = filter disabled.
function smp_world.staff_name_filter_matched(name)
	local raw = cfg_string("world.staff_name_filter", DEFAULT_NAME_FILTER)
	if raw == "" then
		return nil
	end
	local lower = string.lower(name)
	for pattern in string.gmatch(raw, "[^,]+") do
		pattern = pattern:match("^%s*(.-)%s*$") or pattern
		if pattern ~= "" and string.find(lower, pattern) then
			return pattern
		end
	end
	return nil
end

-- Join-time action (world.staff_name_action, PROPOSED f15 §7):
--   flag (default) — notify staff and log; the player is untouched
--   kick           — flag, then disconnect with a refusal
--   off            — do nothing
-- Returns the matched pattern, or nil when the name passes. Nothing here
-- can affect accounts: the rule's enforcement is moderation-first, exactly
-- like the account-per-IP flag above.
function smp_world.apply_name_filter(name)
	local action = cfg_string("world.staff_name_action", "flag")
	if action ~= "kick" then
		action = (action == "off") and "off" or "flag"
	end
	if action == "off" then
		return nil
	end
	local matched = smp_world.staff_name_filter_matched(name)
	if not matched then
		return nil
	end
	smp_world.flag_staff(S(
		"Staff impersonation suspected: @1 matched '@2'", name, matched))
	if action == "kick" then
		core.kick_player(name, S("This name is reserved for staff"))
	end
	return matched
end

----------------------------------------------------------------------
-- 5. Join dispatch
----------------------------------------------------------------------

-- Runs on every join: name filter first, then the account-per-IP count.
-- Callback returns are ignored by the engine — by construction this hook
-- CANNOT block a join (acceptance T5: flag only, never ban).
function smp_world.on_joinplayer(player)
	local name = player:get_player_name()

	smp_world.apply_name_filter(name)

	local ip = core.get_player_ip(name)
	if not ip then
		return
	end
	local index = load_index()
	local key = ip_key(ip)
	local bucket = index[key]
	if not bucket then
		bucket = {}
		index[key] = bucket
	end
	if bucket[name] then
		return -- already counted; rejoins do not re-flag
	end
	bucket[name] = true
	save_index()

	local n = 0
	for _ in pairs(bucket) do
		n = n + 1
	end
	local max = cfg_number("world.max_accounts_per_ip", DEFAULT_MAX_ACCOUNTS)
	if n > max then
		smp_world.flag_staff(S(
			"Alt-account flag: @1 accounts from one IP (joiner: @2)",
			tostring(n), name))
	end
end

core.register_on_joinplayer(smp_world.on_joinplayer)

----------------------------------------------------------------------
-- 6. Zero-ABM invariant (spec §4.4, acceptance T7)
--
-- The performance budget forbids ABMs anywhere in the smp_ mod set.
-- Every registered ABM carries mod_origin (engine builtin/game/register.lua),
-- so after all mods load we check the whole set and complain loudly if any
-- smp_* mod slipped one in. The static-source counterpart of this check
-- lives in dev-tests/test_world.lua.
----------------------------------------------------------------------

core.register_on_mods_loaded(function()
	local abms = core.registered_abms or {}
	for _, abm in ipairs(abms) do
		local origin = tostring(abm.mod_origin or "")
		if origin:sub(1, 4) == "smp_" then
			core.log("error", "[smp_world] ABM registered by " .. origin ..
				" - violates the f15 T7 zero-ABM invariant (spec 4.4)")
		end
	end
end)
