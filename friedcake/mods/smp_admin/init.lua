-- FriedcakeSMP — smp_admin
-- Registers the smp_admin / smp_moderator privileges every other smp_*
-- mod relies on, plus the two moderation primitives the spec demands but
-- no feature brief may own (integrator rulings D9 + D10, 2026-09-24).
--
-- Public surface:
--   smp_admin.flag(kind, detail)   -> id   persisted staff-review ring
--                                           buffer (f01 §4.2.5)
--   smp_admin.flags()              -> array, oldest-first copy
--   smp_admin.mute(name, seconds)  -> true (nil or 0 = permanent)
--   smp_admin.unmute(name)         -> true if an entry existed
--   smp_admin.is_muted(name)       -> boolean [, remaining_seconds];
--                                     storage-backed so offline names and
--                                     restarts survive, lazy expiry on read
--                                     (f11 §4.1.3)
--
-- Commands (mirror: spec/shared/05-command-reference.md §5.5):
--   /mute <player> [seconds]   omitted duration = permanent
--   /unmute <player>
--   Both require smp_moderator OR smp_admin — Luanti has no privilege
--   hierarchy, so the pair is checked explicitly (the server console,
--   caller "", is allowed by the engine before func runs; the explicit
--   check below mirrors that).
--
-- Everything here is synchronous: no yields anywhere (shared §2.3
-- discipline binds the call sites this sits in later, e.g. f01's
-- transfer path). Money is never touched: `detail` arrives preformatted.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())
local storage = core.get_mod_storage()

smp_admin = {}

-- Privileges granted by /grant <name> smp_admin  /grant ... smp_moderator
-- The descriptions are written for staff, not for the player.

core.register_privilege("smp_admin", {
	description = S("Full FriedcakeSMP administration: edit money, reload config, run tests."),
	give_to_singleplayer = false,
})

core.register_privilege("smp_moderator", {
	description = S("FriedcakeSMP moderation: read the ledger, see hidden info."),
	give_to_singleplayer = false,
})

-- Privileges added by later features will register themselves in their own
-- mod; smp_admin does not own them.

----------------------------------------------------------------------
-- Staff check — Luanti has no privilege hierarchy, so both privileges
-- are named explicitly wherever one grants access.
----------------------------------------------------------------------

local function is_staff(name)
	if name == nil or name == "" then return true end -- server console
	local privs = core.get_player_privs(name)
	return type(privs) == "table"
		and (privs.smp_admin == true or privs.smp_moderator == true)
end

----------------------------------------------------------------------
-- D9 — transfer flags: a persisted ring buffer of staff-review entries
-- (f01 §4.2.5: "flagged for staff review. Flagged, not blocked").
----------------------------------------------------------------------

local FLAG_CAP = 500
local FLAG_KEY = "flags"
local FLAG_NEXT_KEY = "flag_nextid"

local function load_flags()
	local raw = storage:get_string(FLAG_KEY)
	if raw == "" then return {} end
	local ok, list = pcall(core.parse_json, raw)
	if not ok or type(list) ~= "table" then return {} end
	return list
end

-- Append one entry, drop the oldest beyond the cap, log a warning and
-- notify every online staff member. One synchronous, cheap call: it sits
-- in f01's transfer path later, where shared §2.3 forbids yields.
function smp_admin.flag(kind, detail)
	kind = tostring(kind or "unknown")
	detail = tostring(detail or "")
	local list = load_flags()
	local id = tonumber(storage:get_string(FLAG_NEXT_KEY)) or 1
	list[#list + 1] = { id = id, t = os.time(), kind = kind, detail = detail }
	while #list > FLAG_CAP do
		table.remove(list, 1)
	end
	storage:set_string(FLAG_KEY, core.write_json(list))
	storage:set_string(FLAG_NEXT_KEY, tostring(id + 1))

	core.log("warning", "[smp_admin] flag " .. kind .. " " .. detail)
	local notice = S("Flag @1: @2", kind, detail)
	for _, p in ipairs(core.get_connected_players()) do
		local staff = p:get_player_name()
		if is_staff(staff) then
			core.chat_send_player(staff, notice)
		end
	end
	return id
end

-- Oldest-first copy of the buffer, for tests and future staff UI. The
-- persisted buffer — not who happened to be online — is the record of
-- truth.
smp_admin.flags = function()
	return load_flags()
end

----------------------------------------------------------------------
-- D10 — mutes: one storage key per player, so offline names work and
-- restarts survive (f11 §4.1.3 enforces; this produces).
----------------------------------------------------------------------

local function mute_key(name)
	return "mute:" .. name
end

-- seconds nil or 0 = permanent (stored as expiry 0).
function smp_admin.mute(name, seconds)
	seconds = tonumber(seconds) or 0
	local expires_at = 0
	if seconds > 0 then
		expires_at = os.time() + seconds
	end
	storage:set_string(mute_key(name), tostring(expires_at))
	return true
end

-- Clears the entry; true if one existed.
function smp_admin.unmute(name)
	local key = mute_key(name)
	if storage:get_string(key) == "" then return false end
	storage:set_string(key, "")
	return true
end

local function read_mute(name)
	local key = mute_key(name)
	local raw = storage:get_string(key)
	if raw == "" then return false end
	local expires_at = tonumber(raw)
	if not expires_at then
		storage:set_string(key, "") -- unreadable entry: drop it
		return false
	end
	if expires_at == 0 then return true end -- permanent: no remaining time
	local now = os.time()
	if expires_at <= now then
		storage:set_string(key, "") -- lazy expiry on read
		return false
	end
	return true, expires_at - now
end

-- Works for offline names (storage-backed) and never throws: the
-- smp_social chat callback pcalls this, but the answer must stay clean
-- even without that shield. remaining_seconds only for finite mutes.
function smp_admin.is_muted(name)
	if type(name) ~= "string" or name == "" then return false end
	local ok, muted, remaining = pcall(read_mute, name)
	if not ok then return false end
	return muted, remaining
end

----------------------------------------------------------------------
-- D10 — commands. Mirror rows: spec/shared/05-command-reference.md §5.5.
----------------------------------------------------------------------

local MUTE_USAGE = S("Usage: /mute <player> [seconds]")
local NO_PRIV = S("You need the smp_moderator or smp_admin privilege to do that.")

-- nil, "" and "permanent" mean permanent; otherwise a whole number of
-- seconds. Returns nil for anything unusable (non-numeric or negative),
-- so the caller can answer with the usage message and change nothing.
local function parse_seconds(raw)
	raw = raw and raw:match("^%s*(.-)%s*$") or ""
	if raw == "" or raw:lower() == "permanent" then return 0 end
	local seconds = tonumber(raw)
	if not seconds or seconds < 0 or seconds ~= math.floor(seconds) then
		return nil
	end
	return seconds
end

core.register_chatcommand("mute", {
	params = S("<player> [seconds]"),
	description = S("Mute a player for a number of seconds, or permanently."),
	func = function(caller, param)
		if not is_staff(caller) then return false, NO_PRIV end
		param = param and param:match("^%s*(.-)%s*$") or ""
		local target, duration = param:match("^(%S+)%s*(.*)$")
		if not target then return false, MUTE_USAGE end
		local seconds = parse_seconds(duration)
		if seconds == nil then
			return false, S("Invalid duration '@1'. @2", duration, MUTE_USAGE)
		end
		smp_admin.mute(target, seconds)
		if seconds > 0 then
			return true, S("Muted @1 for @2 seconds.", target, tostring(seconds))
		end
		return true, S("Muted @1 permanently.", target)
	end,
})

core.register_chatcommand("unmute", {
	params = S("<player>"),
	description = S("Clear a player's mute."),
	func = function(caller, param)
		if not is_staff(caller) then return false, NO_PRIV end
		local target = param and param:match("^%s*(%S+)%s*$")
		if not target then return false, S("Usage: /unmute <player>") end
		if not smp_admin.unmute(target) then
			return false, S("@1 is not muted.", target)
		end
		return true, S("Unmuted @1.", target)
	end,
})

core.log("action",
	"[smp_admin] loaded: privileges smp_admin, smp_moderator; flag(); mute/unmute/is_muted; /mute, /unmute")
