-- FriedcakeSMP — smp_tp homes subsystem (f09)
--
-- Homes are NOT their own mod: they are a subsystem of smp_tp, the same
-- mod that owns the f08 teleport framework. This file implements
-- spec/features/f09-homes.md end to end:
--
--   * Data layer over the smp_store player-record `homes` field (§5).
--   * Slot limits through smp_ranks.home_limit (f13 §4.2.4), stubbed
--     here with the f09 §4.1 table until f13 lands (TODO(f13)).
--   * Commands: /homes (primary, OBSERVED [F0055]) with /home alias,
--     /sethome [name], /delhome <id>.
--   * The observed menu tree (§3): the `Homes` tab row [F0061] ->
--     per-home submenu [F0063–F0075] -> `Choose Icon` [F0066] /
--     `Rename` [F0071] / delete confirmation (PROPOSED).
--   * Teleport through the f08 warm-up, re-validating the home id on
--     receipt of every client field (§8): client fields are untrusted
--     and the home may have been deleted while the menu was open (T8).
--
-- The v0.1 flat grid with sneak-click delete is WRONG (§1); this file
-- must not be read as reviving it.
--
-- Loading: this file is dofile'd from smp_tp/init.lua after
-- commands.lua. See §11 "Proposed shared changes" in
-- spec/features/f09-homes.md — the integrator wires the dofile line
-- (init.lua belongs to f08 and is not edited by the f09 agent).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_tp.S
local cfg = smp_tp.cfg

----------------------------------------------------------------------
-- §7 configuration (declared here: config.lua belongs to f08)
--
-- | Key                             | Default | Status              |
-- | homes.slots                     | §4.1    | LIVE [S17]          |
-- | homes.name_max                  | 32      | PROPOSED            |
-- | homes.tabs_before_more          | 3       | OBSERVED [F0061]    |
-- | homes.default_icon              | bed     | PROPOSED            |
-- | homes.delete_confirm            | true    | PROPOSED            |
----------------------------------------------------------------------

local function setting(key, default)
	if core.settings and core.settings.get then
		local v = core.settings:get("smp_tp." .. key)
		if v ~= nil and v ~= "" then return v end
	end
	return default
end

cfg.homes = cfg.homes or {}
if cfg.homes.slots == nil then
	cfg.homes.slots = {
		default = 2,      -- LEGACY [S25]; current default undocumented
		tier1   = 9,      -- LIVE [S17] (Donut+)
		tier2   = 27,     -- LIVE [S17] (Donut++)
		tier3   = 90,     -- LIVE [S17] (Donut+++, Media)
		media   = 90,     -- as tier3 since 16 June 2026 [S17]
	}
end
cfg.homes.name_max         = tonumber(setting("homes.name_max", 32)) or 32              -- PROPOSED
cfg.homes.tabs_before_more = tonumber(setting("homes.tabs_before_more", 3)) or 3        -- OBSERVED [F0061]
cfg.homes.default_icon     = setting("homes.default_icon", "mcl_beds:bed_red_bottom")   -- PROPOSED (bed, §4.6)
cfg.homes.delete_confirm   = setting("homes.delete_confirm", "true") ~= "false"         -- PROPOSED (§4.5)

smp_tp.homes = {}
local H = smp_tp.homes

H.FORMNAME = "smp_tp:homes"

local TRIANGLE = "\226\154\160"   -- U+26A0 warning triangle (§4.2)
local ICON_COLS = 8
local ICON_ROWS = 4
local ICON_PAGE = ICON_COLS * ICON_ROWS

----------------------------------------------------------------------
-- Small helpers (no string patterns — this engine's pattern matcher is
-- unreliable, see f08 §10; use plain find/sub/tonumber everywhere)
----------------------------------------------------------------------

local function trim(s)
	s = s or ""
	local a, b = 1, #s
	while a <= b do
		local c = s:byte(a)
		if c ~= 32 and c ~= 9 then break end
		a = a + 1
	end
	while b >= a do
		local c = s:byte(b)
		if c ~= 32 and c ~= 9 then break end
		b = b - 1
	end
	return s:sub(a, b)
end

local function fesc(s)
	return core.formspec_escape(tostring(s))
end

local function chat(name, msg)
	core.chat_send_player(name, msg)
end

local function find_by_id(homes, id)
	for _, hm in ipairs(homes) do
		if hm.id == id then return hm end
	end
	return nil
end

-- Smallest free positive integer id (§6 next_free_index).
local function next_free_id(homes)
	local used = {}
	for _, hm in ipairs(homes) do used[hm.id] = true end
	local id = 1
	while used[id] do id = id + 1 end
	return id
end

local function floor_pos(pos)
	return {
		x = math.floor(pos.x + 0.5),
		y = math.floor(pos.y + 0.5),
		z = math.floor(pos.z + 0.5),
	}
end

----------------------------------------------------------------------
-- Data layer (§5): the `homes` field of the smp_store player record
----------------------------------------------------------------------

function H.list(name)
	local rec = smp_store.api.ensure_player(name)
	if type(rec.homes) ~= "table" then rec.homes = {} end
	return rec.homes
end

local function save(name, homes)
	-- One synchronous write; no yields between validate and mutate
	-- anywhere in this file (shared §2.3).
	smp_store.api.update_player_field(name, "homes", homes)
end

function H.get(name, id)
	return find_by_id(H.list(name), id)
end

-- Resolve a /homes or /delhome argument: a numeric id first, then a
-- display name (case-insensitive). Names may collide (PROPOSED, §10);
-- the first match wins.
function H.resolve(name, key)
	local homes = H.list(name)
	local idn = tonumber(key)
	if idn then
		local h = find_by_id(homes, idn)
		if h then return h end
	end
	local lower = trim(key):lower()
	for _, hm in ipairs(homes) do
		if type(hm.name) == "string" and hm.name:lower() == lower then
			return hm
		end
	end
	return nil
end

-- Slot limit.
-- TODO(f13): smp_ranks.home_limit is the perk API (f13 §4.2.4) and takes
-- the player NAME. Until it lands, read the f09 §4.1 slot table here:
-- default 2, tier1 9, tier2 27, tier3 90.
function H.home_limit(name)
	if smp_ranks and smp_ranks.home_limit then
		return smp_ranks.home_limit(name)
	end
	local slots = cfg.homes.slots
	local tier = "default"
	if smp_tp.bridge and smp_tp.bridge.tier then
		tier = smp_tp.bridge.tier(name)
	end
	return slots[tier] or slots.default
end

----------------------------------------------------------------------
-- Mutations
--
-- Each returns (true, ...) or (false, reason) and sends its own chat
-- line where one is observed. Every function validates first and then
-- mutates with no yield in between, so two rapid /sethome calls cannot
-- exceed the limit (T1).
----------------------------------------------------------------------

-- §6 on_new_home. arg = explicit name or nil/"" for `Home <n>`.
function H.do_sethome(name, pos, arg)
	if type(pos) ~= "table" then return false, "nopos" end
	local homes = H.list(name)
	local limit = H.home_limit(name)
	if #homes >= limit then
		-- Exact observed string (plural "limits") [F0055].
		chat(name, S("You reached home limits"))
		return false, "limit"
	end
	local id = next_free_id(homes)
	local newname = trim(arg)
	if newname == "" then
		-- /sethome without a name auto-names `Home <n>` (§4.2, OBSERVED).
		newname = S("Home @1", id)
	end
	if #newname > cfg.homes.name_max then
		-- PROPOSED message (§10).
		chat(name, S("Home name is too long"))
		return false, "long"
	end
	local home = {
		id      = id,
		name    = newname,
		icon    = cfg.homes.default_icon,
		pos     = floor_pos(pos),
		created = os.time(),
	}
	-- validate done; mutate + persist as one synchronous block.
	homes[#homes + 1] = home
	save(name, homes)
	-- Exact observed string [F0055].
	chat(name, S("Home set"))
	return true, home
end

function H.do_delete(name, id)
	local homes = H.list(name)
	local h = find_by_id(homes, id)
	if not h then
		-- Exact observed string [F0055].
		chat(name, S("Home does not exist"))
		return false
	end
	for i, hm in ipairs(homes) do
		if hm.id == id then
			table.remove(homes, i)
			save(name, homes)
			-- Exact observed string [F0055].
			chat(name, S("Home deleted"))
			return true
		end
	end
	chat(name, S("Home does not exist"))
	return false
end

function H.do_rename(name, id, newname)
	local homes = H.list(name)
	local h = find_by_id(homes, id)
	if not h then
		chat(name, S("Home does not exist"))
		return false, "missing"
	end
	newname = trim(newname)
	if newname == "" then
		-- PROPOSED message (§10).
		chat(name, S("Home name cannot be empty"))
		return false, "empty"
	end
	if #newname > cfg.homes.name_max then
		-- PROPOSED message (§10).
		chat(name, S("Home name is too long"))
		return false, "long"
	end
	-- validate done; mutate + persist.
	h.name = newname
	save(name, homes)
	-- Exact observed string, @1 = new name (F0089, reconstructed).
	chat(name, S("You renamed your home to @1", newname))
	return true
end

function H.set_icon(name, id, icon)
	local homes = H.list(name)
	local h = find_by_id(homes, id)
	if not h then return false end
	h.icon = icon
	save(name, homes)
	return true
end

----------------------------------------------------------------------
-- Teleport (§4.4): through the f08 warm-up, re-validated here.
----------------------------------------------------------------------

function H.teleport(name, id)
	local h = H.get(name, id)
	if not h or type(h.pos) ~= "table" then
		chat(name, S("Home does not exist"))
		return false
	end
	local player = core.get_player_by_name(name)
	if not player then return false end
	if smp_tp.teleport_with_warmup then
		smp_tp.teleport_with_warmup(player, { x = h.pos.x, y = h.pos.y, z = h.pos.z }, "home")
	end
	-- TODO(f08): without the warm-up framework the teleport is skipped
	-- rather than performed instantly — a home must not bypass the
	-- warm-up (f08 §4.1). f08 has landed on agent/f08-teleport, so the
	-- guard above is expected to be taken.
	return true
end

----------------------------------------------------------------------
-- Menu session (§3). One formname for the whole tree; server-side
-- session state selects the screen (shared §2.4, §4.9).
--
--   row     -> the `Homes` tab row        [F0061]
--   sub     -> the per-home submenu       [F0063–F0075]
--   icon    -> `Choose Icon`              [F0066]
--   rename  -> `Rename`                   [F0071]
--   confirm -> delete confirmation        (PROPOSED, §4.5)
----------------------------------------------------------------------

function H.set_screen(name, state)
	local s = smp_core.get_session(name, H.FORMNAME)
	if not s then
		s = smp_core.open_session(name, H.FORMNAME, {})
	end
	-- Clear previous screen state, keep the session bookkeeping.
	local dead = {}
	for k in pairs(s) do
		if k:sub(1, 1) ~= "_" then dead[#dead + 1] = k end
	end
	for _, k in ipairs(dead) do s[k] = nil end
	for k, v in pairs(state) do s[k] = v end
	return s
end

local function show_fs(name, fs)
	smp_core.show_formspec(name, H.FORMNAME, fs)
end

-- Item list for `Choose Icon`: every registered item, sorted by
-- display description (§3.3; V-35 is open on curated-vs-full, the spec
-- currently says full). Colors are stripped for display and sorting;
-- the first line of the description is what shows.
local function strip_desc(def, itemstring)
	local desc = def.description
	if type(desc) ~= "string" or desc == "" then desc = itemstring end
	if core.strip_colors then desc = core.strip_colors(desc) end
	local nl = desc:find("\n", 1, true)
	if nl then desc = desc:sub(1, nl - 1) end
	return desc
end

local function icon_list(query)
	local q = trim(query):lower()
	local out = {}
	for itemstring, def in pairs(core.registered_items) do
		if type(def) == "table" then
			local desc = strip_desc(def, itemstring)
			if q == "" or desc:lower():find(q, 1, true) then
				out[#out + 1] = { s = itemstring, d = desc:lower(), t = desc }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.d ~= b.d then return a.d < b.d end
		return a.s < b.s
	end)
	return out
end

----------------------------------------------------------------------
-- Builders. Each returns a formspec string; rendering does not mutate
-- the session, so tests can build screens for a synthetic state.
----------------------------------------------------------------------

-- §3.1 the `Homes` tab row: prompt menu, top of the screen, one
-- item_image_button per home (tooltip `<name>` / `Click to manage`),
-- `New Home` following the last home, `Show More` at the far right
-- when #homes > homes.tabs_before_more.
function H.build_row(name, s)
	local homes = H.list(name)
	local limit = H.home_limit(name)
	local wrap = #homes > cfg.homes.tabs_before_more
	local show_all = s and s.show_all and wrap
	local shown = show_all and #homes or math.min(#homes, cfg.homes.tabs_before_more)

	local cols = 7
	local row, col = 0, 0
	local function slot()
		if col >= cols then
			row = row + 1
			col = 0
		end
		local x = 0.3 + col * 1.7
		local y = 0.9 + row * 1.7
		col = col + 1
		return x, y
	end

	local els = {}
	for i = 1, shown do
		local hm = homes[i]
		local x, y = slot()
		els[#els + 1] = string.format(
			"item_image_button[%.2f,%.2f;1.6,1.4;%s;home_%s;%s]",
			x, y, fesc(hm.icon or cfg.homes.default_icon),
			tostring(hm.id), fesc(hm.name))
		els[#els + 1] = string.format("tooltip[home_%s;%s\n%s]",
			tostring(hm.id), fesc(hm.name), fesc(S("Click to manage")))
	end
	-- §6: New Home only while below the limit.
	if #homes < limit then
		local x, y = slot()
		els[#els + 1] = string.format("button[%.2f,%.2f;1.9,1.4;new_home;%s]",
			x, y, fesc(S("New Home")))
	end
	-- Show More sits at the far right, separated from the home tabs.
	if wrap and not show_all then
		els[#els + 1] = string.format("button[11.0,0.9;1.7,1.4;show_more;%s]",
			fesc(S("Show More")))
	end

	local size_h = 2.5 + row * 1.7
	local head = {
		"formspec_version[6]",
		string.format("size[13.00,%.2f]", size_h),
		"bgcolor[#000000C0]",
		string.format("label[5.60,0.40;%s %s]", fesc(S("Homes")), TRIANGLE),
	}
	return table.concat(head) .. table.concat(els)
end

-- §3.2 per-home submenu: 2x2 grid (Teleport / Change Icon, Rename /
-- Delete) with a centred Back beneath; Delete red [F0068].
function H.build_sub(h)
	return table.concat({
		"formspec_version[6]",
		"size[6.00,4.40]",
		"bgcolor[#000000C0]",
		string.format("label[1.40,0.40;%s %s]", fesc(h.name), TRIANGLE),
		"style[delete;textcolor=red]",
		string.format("button[0.50,1.00;2.50,0.90;teleport;%s]", fesc(S("Teleport"))),
		string.format("button[3.00,1.00;2.50,0.90;icon;%s]", fesc(S("Change Icon"))),
		string.format("button[0.50,2.10;2.50,0.90;rename;%s]", fesc(S("Rename"))),
		string.format("button[3.00,2.10;2.50,0.90;delete;%s]", fesc(S("Delete"))),
		string.format("button[1.75,3.30;2.50,0.80;back;%s]", fesc(S("Back"))),
	})
end

-- §3.3 `Choose Icon`: tall prompt, Search field, Search/Default/Back
-- row, then the paged item grid. Page > 1 appends `(Page N)` to the
-- title (house grammar, shared §4.2; the observed screen was page 1
-- with the plain title — PROPOSED extension, §10).
function H.build_icon(s, h)
	local page = math.max(1, math.floor(tonumber(s.page) or 1))
	local query = s.query or ""
	local list = icon_list(query)
	local pages = math.max(1, math.ceil(#list / ICON_PAGE))
	if page > pages then page = pages end
	local first = (page - 1) * ICON_PAGE

	local els = {}
	for i = 1, ICON_PAGE do
		local it = list[first + i]
		if not it then break end
		local x = 0.40 + ((i - 1) % ICON_COLS) * 1.25
		local y = 3.00 + math.floor((i - 1) / ICON_COLS) * 1.15
		els[#els + 1] = string.format(
			"item_image_button[%.2f,%.2f;1.10,1.10;%s;icon_item_%d;%s]",
			x, y, fesc(it.s), i, fesc(it.t))
	end
	if pages > 1 then
		els[#els + 1] = string.format("button[0.40,7.70;1.60,0.70;page_prev;%s]",
			fesc(S("Prev")))
		els[#els + 1] = string.format("button[8.60,7.70;1.60,0.70;page_next;%s]",
			fesc(S("Next")))
	end

	local title = page > 1 and S("Choose Icon (Page @1)", page) or S("Choose Icon")
	local head = {
		"formspec_version[6]",
		"size[10.60,8.60]",
		"bgcolor[#000000C0]",
		string.format("label[3.80,0.40;%s %s]", fesc(title), TRIANGLE),
		string.format("label[0.40,0.70;%s]", fesc(S("Search"))),
		string.format("field[0.40,1.00;6.50,0.80;icon_query;;%s]", fesc(query)),
		"field_close_on_enter[icon_query;false]",
		string.format("button[0.40,1.95;1.90,0.70;icon_search;%s]", fesc(S("Search"))),
		string.format("button[2.50,1.95;1.90,0.70;icon_default;%s]", fesc(S("Default"))),
		string.format("button[4.60,1.95;1.90,0.70;icon_back;%s]", fesc(S("Back"))),
	}
	return table.concat(head) .. table.concat(els)
end

-- §3.4 `Rename`: field pre-filled with the CURRENT name, Save and
-- Cancel stacked and centred.
function H.build_rename(s, h)
	local prefill = h.name
	if s.prefill ~= nil then prefill = s.prefill end
	return table.concat({
		"formspec_version[6]",
		"size[5.00,4.00]",
		"bgcolor[#000000C0]",
		string.format("label[1.90,0.40;%s %s]", fesc(S("Rename")), TRIANGLE),
		string.format("label[0.50,0.85;%s]", fesc(S("New Name"))),
		string.format("field[0.50,1.15;4.00,0.80;rename_query;;%s]", fesc(prefill)),
		"field_close_on_enter[rename_query;false]",
		string.format("button[1.25,2.20;2.50,0.80;save;%s]", fesc(S("Save"))),
		string.format("button[1.25,3.15;2.50,0.80;cancel;%s]", fesc(S("Cancel"))),
	})
end

-- §4.5 delete confirmation (PROPOSED — not observed; the red Delete
-- hover [F0068] suggests the interface treats deletion as destructive).
function H.build_confirm(h)
	return table.concat({
		"formspec_version[6]",
		"size[5.00,3.00]",
		"bgcolor[#000000C0]",
		string.format("label[1.00,0.40;%s %s]", fesc(S("Delete @1?", h.name)), TRIANGLE),
		"style[confirm_cancel;bgcolor=red]",
		"style[confirm_delete;textcolor=red]",
		string.format("button[0.40,1.90;2.00,0.80;confirm_cancel;%s]", fesc(S("Cancel"))),
		string.format("button[2.60,1.90;2.00,0.80;confirm_delete;%s]", fesc(S("Delete"))),
	})
end

----------------------------------------------------------------------
-- Navigation + render
----------------------------------------------------------------------

function H.render(name)
	local s = smp_core.get_session(name, H.FORMNAME)
	if not s then return end
	if s.screen == "row" then
		show_fs(name, H.build_row(name, s))
		return
	end
	-- Every other screen acts on a home id: re-validate on render too —
	-- the home may have been deleted while the menu was open (T8).
	local h = H.get(name, s.id)
	if not h then
		chat(name, S("Home does not exist"))
		H.show_homes(name)
		return
	end
	if s.screen == "sub" then
		show_fs(name, H.build_sub(h))
	elseif s.screen == "icon" then
		show_fs(name, H.build_icon(s, h))
	elseif s.screen == "rename" then
		show_fs(name, H.build_rename(s, h))
	elseif s.screen == "confirm" then
		show_fs(name, H.build_confirm(h))
	else
		-- Corrupt session state: fail closed.
		smp_core.close_session(name, H.FORMNAME)
		core.close_formspec(name, H.FORMNAME)
	end
end

function H.show_homes(name)
	H.set_screen(name, { screen = "row" })
	H.render(name)
end

function H.show_sub(name, id)
	if not H.get(name, id) then
		chat(name, S("Home does not exist"))
		H.show_homes(name)
		return
	end
	H.set_screen(name, { screen = "sub", id = id })
	H.render(name)
end

local function open_sub_or_gone(name, id)
	if H.get(name, id) then
		H.set_screen(name, { screen = "sub", id = id })
		H.render(name)
	else
		chat(name, S("Home does not exist"))
		H.show_homes(name)
	end
end

----------------------------------------------------------------------
-- Field handling. Client fields are untrusted (R4): the pressed key
-- only selects WHICH server-side state to act on; ids and queries are
-- always re-validated against the store.
----------------------------------------------------------------------

local function pressed(f, key)
	local v = f[key]
	return v ~= nil and v ~= false
end

-- Dynamic button key (`home_<id>`, `icon_item_<n>`) without patterns.
local function dynamic_num(f, prefix)
	for k in pairs(f) do
		if k:sub(1, #prefix) == prefix then
			local n = tonumber(k:sub(#prefix + 1))
			if n then return n end
		end
	end
	return nil
end

function H.handle_fields(player, fields)
	local name = player:get_player_name()
	return smp_core.handle_fields(name, H.FORMNAME, fields, function(s, f)
		if f.quit then return "close" end
		local screen = s.screen

		if screen == "row" then
			local id = dynamic_num(f, "home_")
			if id then
				open_sub_or_gone(name, id)
				return nil
			end
			if pressed(f, "show_more") then
				-- V-32 is open; PROPOSED: Show More re-renders the row
				-- with every home tab (no second page mechanism).
				s.show_all = true
				H.render(name)
				return nil
			end
			if pressed(f, "new_home") then
				-- The New Home tab is equivalent to /sethome (§3.1).
				H.do_sethome(name, player:get_pos(), nil)
				H.show_homes(name)
				return nil
			end
			return nil
		end

		-- All other screens target a home id that may have gone stale.
		local h = H.get(name, s.id)
		if not h then
			-- T8: fails safely — no teleport, no crash, back to the row.
			chat(name, S("Home does not exist"))
			H.show_homes(name)
			return nil
		end

		if screen == "sub" then
			if pressed(f, "back") then
				H.show_homes(name)
				return nil
			end
			if pressed(f, "teleport") then
				H.teleport(name, h.id)
				return "close"
			end
			if pressed(f, "icon") then
				H.set_screen(name, { screen = "icon", id = h.id, page = 1, query = "" })
				H.render(name)
				return nil
			end
			if pressed(f, "rename") then
				H.set_screen(name, { screen = "rename", id = h.id })
				H.render(name)
				return nil
			end
			if pressed(f, "delete") then
				if cfg.homes.delete_confirm then
					H.set_screen(name, { screen = "confirm", id = h.id })
					H.render(name)
				else
					H.do_delete(name, h.id)
					H.show_homes(name)
				end
				return nil
			end
			return nil
		end

		if screen == "icon" then
			if pressed(f, "icon_back") then
				H.set_screen(name, { screen = "sub", id = h.id })
				H.render(name)
				return nil
			end
			-- Keep whatever the player typed in the session; the field
			-- value rides along with every button press.
			if type(f.icon_query) == "string" then s.query = f.icon_query end
			if pressed(f, "icon_default") then
				H.set_icon(name, h.id, cfg.homes.default_icon)
				H.set_screen(name, { screen = "sub", id = h.id })
				H.render(name)
				return nil
			end
			if pressed(f, "icon_search") then
				s.page = 1
				H.render(name)
				return nil
			end
			if pressed(f, "page_prev") then
				s.page = math.max(1, (tonumber(s.page) or 1) - 1)
				H.render(name)
				return nil
			end
			if pressed(f, "page_next") then
				s.page = (tonumber(s.page) or 1) + 1
				H.render(name)
				return nil
			end
			local n = dynamic_num(f, "icon_item_")
			if n then
				local list = icon_list(s.query or "")
				local page = math.max(1, math.floor(tonumber(s.page) or 1))
				local it = list[(page - 1) * ICON_PAGE + n]
				-- A forged or stale index selects nothing: icon unchanged.
				if it then H.set_icon(name, h.id, it.s) end
				H.set_screen(name, { screen = "sub", id = h.id })
				H.render(name)
				return nil
			end
			return nil
		end

		if screen == "rename" then
			if pressed(f, "cancel") or pressed(f, "back") then
				H.set_screen(name, { screen = "sub", id = h.id })
				H.render(name)
				return nil
			end
			if pressed(f, "save") then
				local typed = f.rename_query
				if type(typed) ~= "string" then typed = h.name end
				local okr = H.do_rename(name, h.id, typed)
				if okr then
					H.set_screen(name, { screen = "sub", id = h.id })
				else
					-- Validation failed (message already sent): show the
					-- Rename screen again with what was typed (T3 loop).
					H.set_screen(name, { screen = "rename", id = h.id, prefill = typed })
				end
				H.render(name)
				return nil
			end
			return nil
		end

		if screen == "confirm" then
			if pressed(f, "confirm_cancel") or pressed(f, "back") then
				H.set_screen(name, { screen = "sub", id = h.id })
				H.render(name)
				return nil
			end
			if pressed(f, "confirm_delete") then
				H.do_delete(name, h.id)
				H.show_homes(name)
				return nil
			end
			return nil
		end

		-- Unknown screen: fail closed.
		return "close"
	end)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= H.FORMNAME then return end
	return H.handle_fields(player, fields)
end)

----------------------------------------------------------------------
-- Commands (§2). `/homes` is the observed primary; `/home` the alias.
----------------------------------------------------------------------

-- NOTE on return values: core's chat-command runner sends the SECOND
-- return value as a chat line, and a bare `false` triggers its
-- "Invalid command usage." + help output. Every observed string is
-- therefore delivered exactly once by chat_send_player inside the
-- helpers, and the command funcs below always return plain `true`
-- (handled) — never a message tuple — so chat output stays verbatim
-- (T1/T2/T4/T5).

core.register_chatcommand("homes", {
	params = S("[id]"),
	description = S("Open the Homes menu, or teleport to a home."),
	func = function(name, param)
		local key = trim(param)
		if key == "" then
			H.show_homes(name)
			return true
		end
		local h = H.resolve(name, key)
		if not h then
			-- Exact observed string [F0055] (T5).
			chat(name, S("Home does not exist"))
			return true
		end
		H.teleport(name, h.id)
		return true
	end,
})

core.register_chatcommand("home", {
	params = S("[id]"),
	description = S("Open the Homes menu, or teleport to a home."),
	func = function(name, param)
		local cmd = core.registered_chatcommands["homes"]
		if cmd and cmd.func then return cmd.func(name, param) end
		return false
	end,
})

core.register_chatcommand("sethome", {
	params = S("[name]"),
	description = S("Save the current position as a home."),
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return false end
		-- Chat happens inside do_sethome (T1/T2 verbatim strings).
		H.do_sethome(name, player:get_pos(), trim(param))
		return true
	end,
})

core.register_chatcommand("delhome", {
	params = S("<id>"),
	description = S("Delete a home."),
	func = function(name, param)
		local key = trim(param)
		if key == "" then
			-- PROPOSED usage line (§10); mirrors f08's Usage style.
			chat(name, S("Usage: /delhome <id>"))
			return true
		end
		local h = H.resolve(name, key)
		if not h then
			chat(name, S("Home does not exist"))
			return true
		end
		H.do_delete(name, h.id)
		return true
	end,
})

core.log("action", "[smp_tp] homes subsystem loaded (f09)")

return H
