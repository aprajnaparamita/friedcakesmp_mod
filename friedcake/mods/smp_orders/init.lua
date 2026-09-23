-- FriedcakeSMP — smp_orders
-- Buy orders with escrow: the Orders board, the four-step creation
-- wizard, the delivery flow, routing with the auction house (f03) and
-- /sell (f02). Implements spec/features/f04-orders.md.
--
-- Commands:
--   /orders                  open the orders board            [F0155]
--   /order [search]          search orders (LIVE [S6]) or open the board
--   /orderadmin remove <id>  remove an order, with refund (shared §5.5)
--
-- Submodules (loaded below in dependency order):
--   orders.lua    data layer: CRUD, id/buyer/key indexes, persistence
--   escrow.lua    deposit / payout / refund with ledger entries (R3)
--   au_bridge.lua smp_ah bridge — TODO(f03) stubs
--   display.lua   plural/singular names, enchantment lines, tooltips
--   formspec.lua  every menu, verbatim strings
--   routing.lua   creation + auction sweep + routing-in API (f02/f03)
--   delivery.lua  Deliver Items / Confirm Delivery over a detached inv
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_orders = {}

local MODNAME = core.get_current_modname() or "smp_orders"
smp_orders.S = core.get_translator(MODNAME)
local S = smp_orders.S

----------------------------------------------------------------------
-- Configuration (f04 §7)
----------------------------------------------------------------------

local function num(key, default)
	local v = tonumber(core.settings:get(key))
	if v == nil then return default end
	return v
end

local cfg = {
	-- LIVE [S17]: tier1 45, tier2 90; default and tier3 PROPOSED
	slots = {
		default = num("orders.slots_default", 9),
		tier1   = num("orders.slots_tier1", 45),
		tier2   = num("orders.slots_tier2", 90),
		tier3   = num("orders.slots_tier3", 90),
	},
	duration = num("orders.duration", 604800),          -- PROPOSED 7 days
	sorts = { "most_per_item", "most_paid", "recently_listed" }, -- OBSERVED [F0180]
	default_amount = num("orders.default_amount", 1),   -- OBSERVED [F0199]
	allow_self_delivery = core.settings:get_bool("orders.allow_self_delivery") or false,
	page_size = num("orders.page_size", 45),            -- PROPOSED (mirrors ah)
	min_price = num("orders.min_price", 100),           -- PROPOSED $1 ("Minimum: $ 1" [F0202])
	flush_interval = num("orders.flush_interval", 10),  -- shared §2.2
	expire_check_interval = num("orders.expire_check_interval", 60),
	create_interval = 1,                                -- R9 (PROPOSED)
	blacklist = { "mcl_amethyst:" },                    -- LIVE [S9]
}
do
	local raw = core.settings:get("orders.blacklist")
	if raw and raw ~= "" then
		cfg.blacklist = {}
		for p in raw:gmatch("[^,]+") do
			p = p:match("^%s*(.-)%s*$")
			if p ~= "" then cfg.blacklist[#cfg.blacklist + 1] = p end
		end
	end
end
smp_orders.cfg = cfg

----------------------------------------------------------------------
-- Small helpers used across submodules
----------------------------------------------------------------------

-- Accept a PlayerRef or a name.
function smp_orders.player_name(player)
	if type(player) == "string" and player ~= "" then return player end
	if type(player) == "table" and player.get_player_name then
		local ok, name = pcall(player.get_player_name, player)
		if ok and name and name ~= "" then return name end
	end
	return nil
end

-- Integer quantity parser accepting the §0.6 suffixes ("250k", "1.5m").
-- Returns an integer >= 1, or nil + reason.
function smp_orders.parse_qty(text)
	if type(text) ~= "string" then return nil, "not a string" end
	text = text:match("^%s*(.-)%s*$") or ""
	if text == "" then return nil, "empty" end
	local mult = 1
	local last = text:sub(-1)
	if last:match("[kKmMbBtT]") then
		local lc = last:lower()
		if     lc == "k" then mult = 1e3
		elseif lc == "m" then mult = 1e6
		elseif lc == "b" then mult = 1e9
		elseif lc == "t" then mult = 1e12 end
		text = text:sub(1, -2)
	end
	local n = tonumber(text)
	if not n then return nil, "not a number" end
	if n ~= n or n == math.huge then return nil, "not a number" end
	if n < 0 then return nil, "negative" end
	n = math.floor(n * mult + 0.5)
	if n < 1 then return nil, "too small" end
	if n > 1e12 then return nil, "too large" end
	return n
end

----------------------------------------------------------------------
-- Submodules
----------------------------------------------------------------------

local modpath = core.get_modpath(MODNAME)
for _, file in ipairs({
	"orders.lua",
	"escrow.lua",
	"au_bridge.lua",
	"display.lua",
	"formspec.lua",
	"routing.lua",
	"delivery.lua",
}) do
	local chunk, err = loadfile(modpath .. "/" .. file)
	if not chunk then
		error("[smp_orders] cannot load " .. file .. ": " .. tostring(err))
	end
	local ok, lerr = pcall(chunk)
	if not ok then
		error("[smp_orders] error in " .. file .. ": " .. tostring(lerr))
	end
end

local fs = smp_orders.fs
local display = smp_orders.display
local delivery = smp_orders.delivery

----------------------------------------------------------------------
-- Item catalogue for Choose Item
----------------------------------------------------------------------

smp_orders._catalog = nil

function smp_orders.item_catalog_all()
	if smp_orders._catalog then return smp_orders._catalog end
	local list = {}
	for name, def in pairs(core.registered_items or {}) do
		if type(def) == "table"
		   and def.description and def.description ~= ""
		   and not (def.groups and def.groups.not_in_creative_inventory == 1)
		   and not smp_orders.blacklisted(name) then
			list[#list + 1] = name
		end
	end
	table.sort(list, function(a, b)
		local da = smp_items.display_name(a):lower()
		local db = smp_items.display_name(b):lower()
		if da ~= db then return da < db end
		return a < b
	end)
	smp_orders._catalog = list
	return list
end

function smp_orders.search_items(text)
	local all = smp_orders.item_catalog_all()
	text = (text or ""):match("^%s*(.-)%s*$") or ""
	if text == "" then return all end
	local needle = text:lower()
	local out = {}
	for _, name in ipairs(all) do
		if name:lower():find(needle, 1, true)
		   or smp_items.display_name(name):lower():find(needle, 1, true) then
			out[#out + 1] = name
		end
	end
	return out
end

----------------------------------------------------------------------
-- Menu presentation
----------------------------------------------------------------------

smp_orders._sort_pref = {}   -- per-player board sort preference (PROPOSED)

function smp_orders.show_board(pname, page, sort)
	sort = sort or smp_orders._sort_pref[pname] or cfg.sorts[1]
	local orders = smp_orders.open_orders(sort)
	local total_pages = math.max(1, math.ceil(#orders / cfg.page_size))
	page = math.min(math.max(1, page or 1), total_pages)
	local session = smp_core.open_session(pname, fs.FORMNAME.board, {})
	session.page = page
	session.sort = sort
	session.total_pages = total_pages
	local first = (page - 1) * cfg.page_size
	local page_orders = {}
	for i = first + 1, math.min(#orders, first + cfg.page_size) do
		page_orders[#page_orders + 1] = orders[i]
	end
	smp_core.show_formspec(pname, fs.FORMNAME.board,
		fs.board(page_orders, session))
end

function smp_orders.show_your(pname, page)
	local orders = smp_orders.orders_for(pname)
	local limit = smp_orders.slot_limit(pname)
	page = math.max(1, page or 1)
	local session = smp_core.open_session(pname, fs.FORMNAME.your, {})
	session.page = page
	smp_core.show_formspec(pname, fs.FORMNAME.your,
		fs.your(orders, session, limit))
end

function smp_orders.show_manage(pname, order_id)
	local o = smp_orders.get_order(order_id)
	if not o or o.buyer ~= pname then
		core.chat_send_player(pname, S("This order has changed"))
		return
	end
	smp_core.close_session(pname, fs.FORMNAME.manage)
	smp_core.open_session(pname, fs.FORMNAME.manage, { order_id = o.id })
	smp_core.show_formspec(pname, fs.FORMNAME.manage, fs.manage(o))
end

----------------------------------------------------------------------
-- Wizard (server-side session — shared §2.4, f04 §8; T5)
----------------------------------------------------------------------

function smp_orders.wizard_start(pname)
	smp_core.close_session(pname, fs.FORMNAME.wizard)
	local session = smp_core.open_session(pname, fs.FORMNAME.wizard, {
		step = 1,           -- 1 Choose Item, 2 How many?, 3 Price, 4 Review
		jump = nil,         -- set when a Change … button sent us here
		item = nil,         -- { name = itemstring, key = M1 key }
		amount = nil,
		price = nil,
		search = "",
		searched = false,
		results = smp_orders.item_catalog_all(),
		page = 1,
	})
	smp_orders.wizard_show(pname, session)
end

function smp_orders.wizard_show(pname, session)
	local spec
	if session.step == 1 then
		spec = fs.choose_item(session)
	elseif session.step == 2 then
		spec = fs.how_many(session)
	elseif session.step == 3 then
		spec = fs.price_per_item(session)
	else
		spec = fs.review(session)
	end
	smp_core.show_formspec(pname, fs.FORMNAME.wizard, spec)
end

local function wizard_fields(pname, fields)
	local session = smp_core.get_session(pname, fs.FORMNAME.wizard)
	if not session then return end

	if fields.quit then
		smp_core.close_session(pname, fs.FORMNAME.wizard)
		return
	end
	-- Cancel / Cancel! abandon the whole wizard (PROPOSED reading).
	if fields.wiz_cancel or fields.wiz_cancel_bang then
		smp_core.close_session(pname, fs.FORMNAME.wizard)
		smp_orders.show_your(pname)
		return
	end
	-- Keep the typed text even when another control was clicked.
	if type(fields.search) == "string" and session.step == 1 then
		session.search = fields.search
	end

	if session.step == 1 then
		if fields.prev_page or fields.next_page then
			local total = math.max(1,
				math.ceil(#(session.results or {}) / fs.CATALOG_PAGE))
			session.page = session.page + (fields.next_page and 1 or -1)
			session.page = math.min(math.max(1, session.page), total)
			smp_orders.wizard_show(pname, session)
			return
		end
		if fields.do_search or (fields.key_enter and fields.search ~= nil) then
			session.results = smp_orders.search_items(session.search or "")
			session.searched = true
			session.page = 1
			smp_orders.wizard_show(pname, session)
			return
		end
		for k in pairs(fields) do
			local i = tonumber(k:match("^item_(%d+)$"))
			if i then
				local first = ((session.page or 1) - 1) * fs.CATALOG_PAGE
				local name = (session.results or {})[first + i]
				if name then
					session.item = {
						name = name,
						key = smp_items.key(ItemStack(name), "M1"),
					}
					-- A Change Item jump returns to Review alone (T5);
					-- the normal flow advances to How many?
					if session.jump == 1 then
						session.jump = nil
						session.step = 4
					else
						session.step = 2
					end
					smp_orders.wizard_show(pname, session)
					return
				end
			end
		end
		return
	end

	if session.step == 2 then
		if fields.wiz_next or fields.key_enter then
			local qty, err = smp_orders.parse_qty(fields.amount or "")
			if not qty then
				core.chat_send_player(pname, S("Invalid amount: @1", err or "?"))
				smp_orders.wizard_show(pname, session)
				return
			end
			session.amount = qty
			if session.jump == 2 then
				session.jump = nil
				session.step = 4
			else
				session.step = 3
			end
			smp_orders.wizard_show(pname, session)
		end
		return
	end

	if session.step == 3 then
		if fields.wiz_review or fields.key_enter then
			local cents, err = smp_core.parse_amount(fields.price or "")
			if not cents then
				core.chat_send_player(pname, S("Invalid amount: @1", err or "?"))
				smp_orders.wizard_show(pname, session)
				return
			end
			if cents < cfg.min_price then
				core.chat_send_player(pname,
					S("Price below minimum (@1)", display.money(cfg.min_price)))
				smp_orders.wizard_show(pname, session)
				return
			end
			session.price = cents
			session.jump = nil
			session.step = 4
			smp_orders.wizard_show(pname, session)
		end
		return
	end

	-- Step 4: Review Order
	if fields.change_item then
		session.jump = 1
		session.step = 1
		session.search = ""
		session.searched = false
		session.results = smp_orders.item_catalog_all()
		session.page = 1
		smp_orders.wizard_show(pname, session)
		return
	end
	if fields.change_amount then
		session.jump = 2
		session.step = 2
		smp_orders.wizard_show(pname, session)
		return
	end
	if fields.change_price then
		session.jump = 3
		session.step = 3
		smp_orders.wizard_show(pname, session)
		return
	end
	if fields.create_order then
		if not session.item or not session.item.key then
			core.chat_send_player(pname, S("This item cannot be ordered"))
			return
		end
		local id, err = smp_orders.create(pname, session.item.key,
			session.amount, session.price)
		if not id then
			core.chat_send_player(pname, err or S("This order has changed"))
			return -- stay on Review Order
		end
		smp_core.close_session(pname, fs.FORMNAME.wizard)
		core.chat_send_player(pname, S("Order created"))
		smp_orders.show_board(pname, 1)   -- observed: back to the board [F0209]
	end
end

----------------------------------------------------------------------
-- Board / Your Orders / Manage field handlers
----------------------------------------------------------------------

local function cycle_sort(sort)
	for i, s in ipairs(cfg.sorts) do
		if s == sort then
			return cfg.sorts[(i % #cfg.sorts) + 1]
		end
	end
	return cfg.sorts[1]
end
smp_orders.cycle_sort = cycle_sort

local function board_fields(pname, fields)
	local session = smp_core.get_session(pname, fs.FORMNAME.board)
	if not session then return end
	if fields.quit then
		smp_core.close_session(pname, fs.FORMNAME.board)
		return
	end
	if fields.ctl_filter then
		session.sort = cycle_sort(session.sort)
		smp_orders._sort_pref[pname] = session.sort
		smp_orders.show_board(pname, 1, session.sort)
		return
	end
	if fields.ctl_your then
		smp_core.close_session(pname, fs.FORMNAME.board)
		smp_orders.show_your(pname)
		return
	end
	if fields.ctl_orders then
		smp_orders.show_board(pname, session.page, session.sort)
		return
	end
	if fields.ctl_shard then
		smp_orders.open_shard_shop(pname)
		return
	end
	if fields.prev_page then
		smp_orders.show_board(pname, session.page - 1, session.sort)
		return
	end
	if fields.next_page then
		smp_orders.show_board(pname, session.page + 1, session.sort)
		return
	end
	for k in pairs(fields) do
		local id = tonumber(k:match("^order_(%d+)$"))
		if id then
			local o = smp_orders.get_order(id)
			if not o or o.state ~= "open" then
				core.chat_send_player(pname, S("This order has changed"))
				smp_orders.show_board(pname, session.page, session.sort)
				return
			end
			smp_core.close_session(pname, fs.FORMNAME.board)
			if o.buyer == pname then
				-- Own order on the board: manage, not deliver (self-delivery
				-- is refused — V-45/T11).
				smp_orders.show_manage(pname, id)
			else
				delivery.open(pname, id)
			end
			return
		end
	end
end

local function your_fields(pname, fields)
	local session = smp_core.get_session(pname, fs.FORMNAME.your)
	if not session then return end
	if fields.quit then
		smp_core.close_session(pname, fs.FORMNAME.your)
		return
	end
	if fields.ctl_back then
		smp_core.close_session(pname, fs.FORMNAME.your)
		smp_orders.show_board(pname, 1)
		return
	end
	if fields.new_order then
		smp_core.close_session(pname, fs.FORMNAME.your)
		smp_orders.wizard_start(pname)
		return
	end
	if fields.prev_page then
		smp_orders.show_your(pname, session.page - 1)
		return
	end
	if fields.next_page then
		smp_orders.show_your(pname, session.page + 1)
		return
	end
	for k in pairs(fields) do
		local id = tonumber(k:match("^order_(%d+)$"))
		if id then
			smp_core.close_session(pname, fs.FORMNAME.your)
			smp_orders.show_manage(pname, id)
			return
		end
	end
end

local function manage_fields(pname, fields)
	local session = smp_core.get_session(pname, fs.FORMNAME.manage)
	if not session then return end
	if fields.quit then
		smp_core.close_session(pname, fs.FORMNAME.manage)
		return
	end
	local o = smp_orders.get_order(session.order_id)
	if fields.back then
		smp_core.close_session(pname, fs.FORMNAME.manage)
		smp_orders.show_your(pname)
		return
	end
	if not o or o.buyer ~= pname then
		core.chat_send_player(pname, S("This order has changed"))
		smp_core.close_session(pname, fs.FORMNAME.manage)
		return
	end
	if fields.collect_items then
		local player = core.get_player_by_name(pname)
		local taken, err = smp_orders.collect(o, player or pname)
		if taken then
			core.chat_send_player(pname, S("You collected @1 @2",
				display.qty(taken), display.order_name(o)))
			smp_orders.show_manage(pname, o.id)
		else
			core.chat_send_player(pname, err or S("No items to collect"))
		end
		return
	end
	if fields.cancel_order then
		if o.state ~= "open" then
			core.chat_send_player(pname, S("This order has changed"))
			smp_core.close_session(pname, fs.FORMNAME.manage)
			smp_orders.show_your(pname)
			return
		end
		local refunded, err = smp_orders.cancel(o, pname)
		if refunded then
			core.chat_send_player(pname, S("Order cancelled, @1 refunded",
				display.money(refunded)))
			smp_core.close_session(pname, fs.FORMNAME.manage)
			smp_orders.show_your(pname)
		else
			core.chat_send_player(pname, err or S("This order has changed"))
		end
	end
end

local function deliver_fields(player, fields)
	local pname = player:get_player_name()
	local session = smp_core.get_session(pname, fs.FORMNAME.deliver)
	if not session then return end
	if fields.quit then
		-- Menu closed without confirm: return every item (R6, X1).
		delivery.close(pname, true, player)
		return
	end
	if fields.to_confirm then
		session.mode = "confirm"
		delivery.show(pname, session, player)
		return
	end
	if fields.confirm_delivery then
		if session.mode ~= "confirm" then
			-- Forged field (R4): ignore unless we are on the confirm screen.
			return
		end
		delivery.confirm(player, session)
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if type(formname) ~= "string" then return end
	if formname:sub(1, 11) ~= "smp_orders:" then return end
	local pname = player:get_player_name()
	if formname == fs.FORMNAME.board then
		board_fields(pname, fields)
	elseif formname == fs.FORMNAME.your then
		your_fields(pname, fields)
	elseif formname == fs.FORMNAME.manage then
		manage_fields(pname, fields)
	elseif formname == fs.FORMNAME.wizard then
		wizard_fields(pname, fields)
	elseif formname == fs.FORMNAME.deliver then
		deliver_fields(player, fields)
	end
end)

----------------------------------------------------------------------
-- Shard shop entry point (f06 §3: reachable from the orders board)
----------------------------------------------------------------------

function smp_orders.open_shard_shop(pname)
	if smp_shardshop and type(smp_shardshop.open) == "function" then
		local player = core.get_player_by_name and core.get_player_by_name(pname)
		local ok, err = pcall(smp_shardshop.open, player or pname)
		if ok then return true end
		core.log("error", "[smp_orders] smp_shardshop.open failed: " .. tostring(err))
	end
	-- TODO(f06): shard shop not shipped yet.
	core.chat_send_player(pname, S("The Shard Shop is not available yet"))
	return false
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------

core.register_chatcommand("orders", {
	params = "",
	description = S("Open the orders board."),
	func = function(pname, _)
		smp_orders.show_board(pname, 1)
		return true
	end,
})

core.register_chatcommand("order", {
	params = S("[search]"),
	description = S("Search orders, or open the orders board."),
	func = function(pname, param)
		param = (param or ""):match("^%s*(.-)%s*$") or ""
		if param == "" then
			smp_orders.show_board(pname, 1)
			return true
		end
		-- LIVE [S6]: search. Renders a chat list (PROPOSED format — the
		-- reference search screen was not recorded).
		local needle = param:lower()
		local hits = {}
		for _, o in ipairs(smp_orders.open_orders(
				smp_orders._sort_pref[pname] or cfg.sorts[1])) do
			if display.item_name(o):lower():find(needle, 1, true)
			   or display.order_name(o):lower():find(needle, 1, true)
			   or o.template:lower():find(needle, 1, true) then
				hits[#hits + 1] = o
			end
		end
		if #hits == 0 then
			return true, S("No orders found")
		end
		local lines = {}
		for i = 1, math.min(10, #hits) do
			local o = hits[i]
			lines[#lines + 1] = S("@1 @2 — @3 each — @4/@5 Delivered",
				"#" .. o.id, display.order_name(o), display.money(o.unit_price),
				display.qty(o.delivered), display.qty(o.qty))
		end
		if #hits > 10 then
			lines[#lines + 1] = S("… and @1 more", #hits - 10)
		end
		return true, table.concat(lines, "\n")
	end,
})

core.register_chatcommand("orderadmin", {
	params = S("remove <id>"),
	description = S("Remove an order, with refund (shared §5.5)."),
	privs = { smp_admin = true },
	func = function(pname, param)
		local sub, arg = (param or ""):match("^%s*(%S+)%s*(%S*)%s*$")
		if sub ~= "remove" then
			return false, S("Usage: /orderadmin remove <id>")
		end
		local id = tonumber(arg)
		local o = id and smp_orders.get_order(id)
		if not o then
			return false, S("No such order")
		end
		if o.state ~= "open" then
			return true, S("Order @1 is @2", id, o.state)
		end
		local refunded = smp_orders.cancel(o, pname, true)
		core.log("action", string.format(
			"[smp_orders] /orderadmin remove %d by %s (refunded %d)",
			id, pname, refunded or 0))
		return true, S("Order @1 removed, @2 refunded", id,
			display.money(refunded or 0))
	end,
})

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

-- R6 / T13: leaving with the delivery grid open returns every item.
core.register_on_leaveplayer(function(player, _)
	local pname = smp_orders.player_name(player)
	if not pname then return end
	delivery.close(pname, true, player)
	smp_core.close_session(pname, fs.FORMNAME.board)
	smp_core.close_session(pname, fs.FORMNAME.your)
	smp_core.close_session(pname, fs.FORMNAME.manage)
	smp_core.close_session(pname, fs.FORMNAME.wizard)
	smp_orders._last_create[pname] = nil
end)

-- Flush dirty orders periodically and sweep expiries (shared §2.2/§2.7:
-- no ABMs, bounded per-step work).
local flush_timer = 0
local expire_timer = 0
core.register_globalstep(function(dtime)
	flush_timer = flush_timer + dtime
	if flush_timer >= cfg.flush_interval then
		flush_timer = 0
		smp_orders.save_dirty()
	end
	expire_timer = expire_timer + dtime
	if expire_timer >= cfg.expire_check_interval then
		expire_timer = 0
		smp_orders.expire_due(os.time())
	end
end)

core.register_on_shutdown(function()
	smp_orders.save_dirty()
end)

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------

smp_orders.load_all()

core.log("action", "[smp_orders] loaded: /orders /order /orderadmin — "
	.. "escrow, wizard, delivery ready")
