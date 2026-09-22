-- FriedcakeSMP — smp_stats (spec: features/f14-stats.md)
--
-- Collects every counter in the project into rec.stats (f14 §4.1, §5),
-- drives the observed scoreboard sidebar (§3.1, §4.3), rebuilds the ten
-- official leaderboard snapshots (§4.2) and issues personal API keys
-- (§4.4).
--
-- Public surface (claim-f14; f05/f10 contracts):
--   smp_stats.add(player_or_name, key, value)  -> new value | nil, err
--   smp_stats.get(player_or_name, key)         -> number
--   smp_stats.add_playtime(player_or_name, seconds)
--   smp_stats.boards[category]                 -> top-N snapshot (§5)
--   smp_stats.rebuild()                        -> rebuild every board
--
-- Both economy write paths land in the same table: f02 assigns
-- rec.stats.money_made_from_sell directly, f05/f10 call add(), which
-- writes rec.stats[key].
--
-- Layout (claim-f14, 9-step order): counters -> combat -> mobs ->
-- playtime -> scoreboard -> boards -> formspec -> api -> commands.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local MODNAME = core.get_current_modname() or "smp_stats"

smp_stats = {}
smp_stats.modname = MODNAME
smp_stats.S = core.get_translator(MODNAME)
local S = smp_stats.S

----------------------------------------------------------------------
-- Configuration (f14 §7). `api.mode` defaults to `snapshot` per
-- claim-f14 (spec §7's table says `off`; recorded in §10 F14-D5).
----------------------------------------------------------------------

local function setting_number(key, default)
	local raw = tonumber(core.settings:get(key))
	if raw and raw > 0 then return raw end
	return default
end

local api_mode = core.settings:get("api.mode")
if type(api_mode) ~= "string" or api_mode == "" then
	api_mode = "snapshot"
elseif api_mode ~= "off" and api_mode ~= "snapshot" and api_mode ~= "push" then
	core.log("warning", "[smp_stats] unknown api.mode=" .. tostring(api_mode)
		.. " — falling back to snapshot")
	api_mode = "snapshot"
end

smp_stats.cfg = {
	-- §7 (all PROPOSED except scoreboard.enabled, OBSERVED [F0287]).
	refresh           = setting_number("leaderboards.refresh", 300),
	size              = setting_number("leaderboards.size", 100),
	scoreboard_enabled = core.settings:get_bool("scoreboard.enabled", true),
	scoreboard_title   = core.settings:get("scoreboard.title"),
	persist           = setting_number("stats.persist_interval", 60),
	api_mode          = api_mode,
}

-- Sidebar title (§4.3.3): `scoreboard.title`, then `server.name`
-- (shared §0.5 rule 3; observed `Voire` unexplained, V-76), then the
-- shared config default.
function smp_stats.scoreboard_title()
	local t = smp_stats.cfg.scoreboard_title
	if type(t) == "string" and t ~= "" then return t end
	local raw = core.settings:get("server.name")
	if type(raw) == "string" and raw:match("%S") then return raw end
	return "Donut SMP" -- shared/06-config-reference.md server.name
end

----------------------------------------------------------------------
-- Submodules (same load pattern as smp_settings / smp_orders).
----------------------------------------------------------------------

local MP = core.get_modpath(MODNAME) or "."
local files = {
	"counters.lua",
	"combat.lua",
	"mobs.lua",
	"playtime.lua",
	"scoreboard.lua",
	"boards.lua",
	"formspec.lua",
	"api.lua",
}
for _, file in ipairs(files) do
	local chunk, err = loadfile(MP .. "/" .. file)
	if not chunk then
		error("[smp_stats] cannot load " .. file .. ": " .. tostring(err))
	end
	local ok, lerr = pcall(chunk)
	if not ok then
		error("[smp_stats] error in " .. file .. ": " .. tostring(lerr))
	end
end

local fs = smp_stats.fs

----------------------------------------------------------------------
-- /stats [player]  (f14 §2, §4.1.1 — menu, PROPOSED layout V-23)

core.register_chatcommand("stats", {
	params = S("[player]"),
	description = S("Show statistics for a player."),
	func = function(player_name, param)
		param = param and param:match("^%s*(.-)%s*$") or ""
		local target = param ~= "" and param or player_name
		return fs.show_stats(player_name, target)
	end,
})

----------------------------------------------------------------------
-- /leaderboard [category]  (aliases /lb, /leaderboards — f14 §2)

core.register_chatcommand("leaderboard", {
	params = S("[category]"),
	description = S("Show the leaderboards."),
	func = function(player_name, param)
		param = (param or ""):lower():match("^%s*(.-)%s*$")
		if param == "" then
			return fs.show_picker(player_name)
		end
		if not smp_stats.category_by_key(param) then
			return false, S("Unknown leaderboard category: @1", param)
		end
		return fs.show_board(player_name, param, 1)
	end,
})

core.register_chatcommand("lb", {
	params = S("[category]"),
	description = S("Alias for /leaderboard."),
	func = function(player_name, param)
		return core.registered_chatcommands.leaderboard.func(player_name, param)
	end,
})

core.register_chatcommand("leaderboards", {
	params = S("[category]"),
	description = S("Alias for /leaderboard."),
	func = function(player_name, param)
		return core.registered_chatcommands.leaderboard.func(player_name, param)
	end,
})

----------------------------------------------------------------------
-- /baltop — the command is owned by f01 (smp_economy); f14 owns the
-- data source (§4.2.2): keep f01's exact chat output, read it from
-- the money snapshot instead of a live full-table sort (PROPOSED,
-- §10 F14-D7). Falls back to f01's implementation until the first
-- rebuild has published a board.

local function money_chat(cents)
	return smp_core.fmt_money(cents, "body")
end

local baltop_cmd = core.registered_chatcommands and
	core.registered_chatcommands.baltop
if baltop_cmd and type(core.override_chatcommand) == "function" then
	local orig_baltop = baltop_cmd.func
	core.override_chatcommand("baltop", {
		func = function(player_name, param)
			local page = tonumber(param and param:match("^%s*(%d+)") or "1") or 1
			if page < 1 then page = 1 end
			local board = smp_stats.boards and smp_stats.boards.money
			if not board or #board == 0 then
				return orig_baltop(player_name, param)
			end
			-- f01's exact format: header + 10 rows (smp_economy §4).
			local size = 10
			local total = #board
			local total_pages = math.max(1, math.ceil(total / size))
			local start = (page - 1) * size + 1
			local stop = math.min(page * size, total)
			local out = { S("--- Money Top (page @1/@2) ---", page, total_pages) }
			for i = start, stop do
				out[#out + 1] = S("@1. @2 — @3", i, board[i].name,
					money_chat(board[i].value))
			end
			core.chat_send_player(player_name, table.concat(out, "\n"))
			return true
		end,
	})
end

----------------------------------------------------------------------
-- /api lives in api.lua (f14 §4.4).

core.log("action", "[smp_stats] loaded: /stats /leaderboard /baltop(snapshot)"
	.. " — api.mode=" .. smp_stats.cfg.api_mode
	.. ", refresh=" .. smp_stats.cfg.refresh .. "s"
	.. ", size=" .. smp_stats.cfg.size)
