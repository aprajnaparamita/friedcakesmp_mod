-- FriedcakeSMP — smp_ah
--
-- The auction house. Implements spec/features/f03-auction.md.
--
-- Commands:
--   /ah [search]              open the board, optionally pre-filtered  [F0105–F0107]
--   /auction, /auctionhouse   aliases
--   /ah sell <price>          list the held stack (shortcut; LIVE [S5])
--   /ahadmin remove <id>      staff removal with the item returned (§5.5)
--   /smp test smp_ah          acceptance tests (T1–T10)
--
-- Menus (shared/04-ui-kit.md §4.1):
--   container  `Auction (Page N)`, `Auction > Your Items`, `Insert Item`,
--              `Confirm Listing`, `Auction > Confirm Purchase`
--   prompt     `Search Auction`, `Edit Sign Message`
--
-- Everything economic follows shared §2.3: validate every precondition, then
-- mutate in a fixed order with no yields in between. Money is integer cents
-- (shared §0.7). Every player-facing string goes through `S` (AGENTS.md 7).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())
local F = core.formspec_escape

smp_ah = smp_ah or {}
smp_ah.S = S
smp_ah.VERSION = 1

----------------------------------------------------------------------
-- Configuration (f03 §7; keys mirrored in shared/06-config-reference.md)
----------------------------------------------------------------------

local function num_setting(key, default)
	local raw = core.settings and core.settings:get(key)
	local v = tonumber(raw)
	if v == nil then return default end
	return v
end

local cfg = {
	-- f03 §7. Money settings are integer cents, like `economy.*` (shared §0.7).
	page_size        = math.floor(num_setting("ah.page_size", 45)),
	listing_duration = math.floor(num_setting("ah.listing_duration", 172800)),
	listing_fee_pct  = num_setting("ah.listing_fee_pct", 0),
	sale_tax_pct     = num_setting("ah.sale_tax_pct", 0),
	min_price        = math.floor(num_setting("ah.min_price", 100)),          -- $1
	max_price        = math.floor(num_setting("ah.max_price", 100000000000000)), -- $10^12
	reclaim_days     = math.floor(num_setting("ah.reclaim_days", 30)),
	insert_slots     = math.floor(num_setting("ah.insert_slots", 5)),
	rate_limit       = num_setting("ah.rate_limit", 1),
	history_page     = math.floor(num_setting("ah.history_page", 100)),
	history_pages    = math.floor(num_setting("ah.history_pages", 10)),
	flush_interval   = num_setting("store.flush_interval", 10),
	sweep_interval   = num_setting("ah.sweep_interval", 60),
	sweep_budget     = math.floor(num_setting("ah.sweep_budget", 200)),
	slots = {
		default = math.floor(num_setting("ah.slots.default", 9)),
		tier1   = math.floor(num_setting("ah.slots.tier1", 45)),
		tier2   = math.floor(num_setting("ah.slots.tier2", 90)),
		tier3   = math.floor(num_setting("ah.slots.tier3", 90)),
	},
	-- OBSERVED order of the `Filter` cycle [F0118–F0123].
	sorts = { "lowest_price", "highest_price", "recently_listed" },
}
smp_ah.cfg = cfg

local function reload_cfg()
	local fresh = {
		page_size = "ah.page_size", listing_duration = "ah.listing_duration",
		listing_fee_pct = "ah.listing_fee_pct", sale_tax_pct = "ah.sale_tax_pct",
		min_price = "ah.min_price", max_price = "ah.max_price",
		reclaim_days = "ah.reclaim_days", insert_slots = "ah.insert_slots",
		rate_limit = "ah.rate_limit", history_page = "ah.history_page",
		history_pages = "ah.history_pages", flush_interval = "store.flush_interval",
		sweep_interval = "ah.sweep_interval", sweep_budget = "ah.sweep_budget",
	}
	for k, setting in pairs(fresh) do
		local raw = core.settings and core.settings:get(setting)
		local v = tonumber(raw)
		if v ~= nil then cfg[k] = v end
	end
	for _, tier in ipairs({ "default", "tier1", "tier2", "tier3" }) do
		local v = tonumber(core.settings and core.settings:get("ah.slots." .. tier))
		if v then cfg.slots[tier] = math.floor(v) end
	end
	smp_ah.listings.configure({
		page_size = cfg.page_size, history_page = cfg.history_page,
		history_pages = cfg.history_pages, listing_duration = cfg.listing_duration,
		reclaim_days = cfg.reclaim_days,
	})
end

----------------------------------------------------------------------
-- Submodules
--
-- keys.lua     canonical M0/M1/M2 item keys (shared §2.5)
-- listings.lua in-memory store + seller/M1/M2/search indexes (f03 §4.15)
-- formspec.lua every menu, with the observed strings verbatim (f03 §3)
----------------------------------------------------------------------

local modpath = core.get_modpath(core.get_current_modname())
for _, file in ipairs({ "keys.lua", "listings.lua", "formspec.lua" }) do
	local chunk, err = loadfile(modpath .. "/" .. file)
	if not chunk then
		error("[smp_ah] cannot load " .. file .. ": " .. tostring(err))
	end
	local ok, res = pcall(chunk)
	if not ok then
		error("[smp_ah] " .. file .. " failed: " .. tostring(res))
	end
end

local keys     = smp_ah.keys
local listings = smp_ah.listings
local fs       = smp_ah.fs

listings.configure({
	page_size = cfg.page_size, history_page = cfg.history_page,
	history_pages = cfg.history_pages, listing_duration = cfg.listing_duration,
	reclaim_days = cfg.reclaim_days,
})

-- Money helpers (shared §0.6): `fs.money` is the §0.6 form; `money_inline` is
-- the parenthesised/inline form; the two "tail" forms feed the translated
-- templates that carry a literal `$`.
local money        = fs.money
local money_inline = fs.money_inline
local money_tail   = fs.money_tail
local money_after  = fs.money_after
smp_ah.money        = money
smp_ah.money_inline = money_inline

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function chat(pname, msg)
	if pname and msg then core.chat_send_player(pname, msg) end
end

local function trim(s)
	return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

local function player_of(pname)
	return core.get_player_by_name(pname)
end

local function inventory_of(pname)
	local p = player_of(pname)
	return p and p:get_inventory() or nil
end

local function money_of(pname)
	local rec = smp_store.api.get_player(pname)
	return (rec and math.floor(tonumber(rec.money) or 0)) or 0
end

local function log(level, msg)
	core.log(level, "[smp_ah] " .. msg)
end

--- Refusal strings. A refusal states the reason (shared §4.8 rule 3); every
--- one of these is PROPOSED in the house style of shared §0.5.4 except
--- `already_bought`, which is OBSERVED verbatim [F0037, F0055].
local REFUSALS = {
	already_bought = function() return S("This item was already bought") end,
	expired        = function() return S("This listing has expired") end,
	unknown        = function() return S("That listing does not exist") end,
	not_yours      = function() return S("That listing is not yours") end,
	slots          = function() return S("You reached listing limits") end,
	rate           = function() return S("Wait a moment before listing another item") end,
	price          = function()
		return S("Price must be between @1 and @2", money(cfg.min_price), money(cfg.max_price))
	end,
	invalid_price  = function(reason) return S("Invalid price: @1", tostring(reason or "?")) end,
	insufficient_funds = function() return S("Insufficient funds") end,
	fee            = function() return S("Insufficient funds") end,
	no_space       = function() return S("No room in your inventory") end,
	empty          = function() return S("Hold the item you want to list") end,
	insert_first   = function() return S("Insert an item first") end,
	offline        = function() return S("That did not work") end,
	corrupt        = function() return S("That listing does not exist") end,
}

local function refuse(pname, code, ...)
	local make = REFUSALS[code]
	chat(pname, make and make(...) or S("That did not work"))
	return nil, code
end

----------------------------------------------------------------------
-- Ledger
----------------------------------------------------------------------

local function ledger(entry)
	entry.time = entry.time or os.time()
	entry.currency = entry.currency or "money"
	entry.counterparty = entry.counterparty or ""
	entry.item_key = entry.item_key or ""
	entry.qty = entry.qty or 0
	entry.ref = entry.ref or ""
	entry.flags = entry.flags or {}
	entry.amount = math.floor(tonumber(entry.amount) or 0)
	smp_store.api.append_ledger(entry)
end

--- A percentage fee, rounded DOWN in the payer's favour (shared §0.7).
local function pct_of(cents, pct)
	pct = tonumber(pct) or 0
	if pct <= 0 then return 0 end
	return math.floor((math.floor(cents) * pct) / 100)
end

----------------------------------------------------------------------
-- Item return queue (shared §2.6 R6)
--
-- Items held by an unfinished listing flow must never be destroyed. When the
-- player cannot be given the stack back (offline, inventory full) it is
-- queued here and persisted, then delivered on the next join.
----------------------------------------------------------------------

smp_ah._returns = {}   -- [pname] = { itemstring, ... }

local function returns_key(pname) return "ah:r:" .. pname end

local function load_returns()
	local storage = listings.storage()
	if not storage or type(storage.get_keys) ~= "function" then return end
	for _, key in ipairs(storage:get_keys() or {}) do
		local pname = key:match("^ah:r:(.+)$")
		if pname then
			local list = core.parse_json and core.parse_json(storage:get_string(key))
			if type(list) == "table" then
				smp_ah._returns[pname] = smp_ah._returns[pname] or {}
				for _, itemstring in ipairs(list) do
					if type(itemstring) == "string" and itemstring ~= "" then
						smp_ah._returns[pname][#smp_ah._returns[pname] + 1] = itemstring
					end
				end
			end
		end
	end
end

local function save_returns()
	local storage = listings.storage()
	if not storage then return end
	for pname, list in pairs(smp_ah._returns) do
		local key = returns_key(pname)
		if #list == 0 then
			if type(storage.remove) == "function" then storage:remove(key)
			else storage:set_string(key, "") end
		elseif core.write_json then
			storage:set_string(key, core.write_json(list))
		end
	end
end

local function queue_return(pname, stack)
	if not stack or stack:is_empty() then return end
	smp_ah._returns[pname] = smp_ah._returns[pname] or {}
	local list = smp_ah._returns[pname]
	list[#list + 1] = stack:to_string()
	log("action", "queued return for " .. pname .. ": " .. stack:to_string())
end

--- Give a stack back to its owner. Returns true when it went straight into
--- the inventory, false when it had to be queued (or dropped).
local function return_stack(pname, stack)
	if not stack or stack:is_empty() then return true end
	local inv = inventory_of(pname)
	if inv then
		local left = inv:add_item("main", stack)
		if left:is_empty() then return true end
		queue_return(pname, left)
		return false
	end
	queue_return(pname, stack)
	return false
end

local function deliver_returns(pname)
	local list = smp_ah._returns[pname]
	if not list or #list == 0 then return 0 end
	smp_ah._returns[pname] = {}
	local n = 0
	for _, itemstring in ipairs(list) do
		local stack = ItemStack(itemstring)
		if not stack:is_empty() then
			return_stack(pname, stack)
			n = n + 1
		end
	end
	if n > 0 then
		chat(pname, S("@1 item(s) were returned to you", n))
		log("action", "delivered " .. n .. " queued return(s) to " .. pname)
	end
	save_returns()
	return n
end

----------------------------------------------------------------------
-- Menu state
--
-- View state lives in the shared session table (shared §2.4) under one
-- formname; the formspec actually shown is tracked in `v.formname` so a stale
-- `quit` from a superseded form can never mutate the current one
-- (shared §2.6 R4).
--
-- The listing flow is deliberately NOT a session: `smp_economy` calls
-- `smp_core.close_all_sessions()` from its own `on_leaveplayer` handler,
-- which runs before ours, and a pending stack must survive that
-- (shared §2.6 R6, X1 duplication drill).
----------------------------------------------------------------------

local SESSION = "smp_ah:view"

local FORM = {
	board           = "smp_ah:board",
	your_items      = "smp_ah:your_items",
	insert          = "smp_ah:insert",
	price           = "smp_ah:price",
	confirm_listing = "smp_ah:confirm_listing",
	search          = "smp_ah:search",
	confirm_buy     = "smp_ah:confirm_buy",
}
smp_ah.FORM = FORM

smp_ah._flows = {}      -- [pname] = { stage = "insert"|"price"|"confirm", stack =, price = }
smp_ah._last_list = {}  -- [pname] = os.time() of the last listing (shared §2.6 R9)

local function view(pname)
	return smp_core.open_session(pname, SESSION, {
		view = "board", page = 1, page_y = 1,
		sort = cfg.sorts[1], query = "", draft = "",
		formname = nil, buy = nil,
	})
end

local function show(pname, formname, form)
	local v = view(pname)
	v.formname = formname
	core.show_formspec(pname, formname, form)
end

local function insert_inv_name(pname) return "smp_ah_insert_" .. pname end

local function flow(pname) return smp_ah._flows[pname] end

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------

local function query_board(v)
	return listings.query({
		sort = v.sort, page = v.page, page_size = cfg.page_size, search = v.query,
	})
end

local function query_yours(v, pname)
	return listings.query({
		seller = pname, states = { active = true, expired = true },
		sort = v.sort, page = v.page_y, page_size = cfg.page_size,
	})
end

--- Re-render the current view. Exposed so tests and other mods can refresh.
function smp_ah.render(pname)
	local v = view(pname)
	if v.view == "your_items" then
		local q = query_yours(v, pname)
		v.page_y = q.page
		return show(pname, FORM.your_items, fs.your_items(q))
	elseif v.view == "search" then
		return show(pname, FORM.search, fs.search(v.draft or ""))
	elseif v.view == "insert" then
		return show(pname, FORM.insert,
			fs.insert(insert_inv_name(pname), cfg.insert_slots))
	elseif v.view == "price" then
		return show(pname, FORM.price, fs.price(v.price_draft or ""))
	elseif v.view == "confirm_listing" then
		local f = flow(pname)
		if not f or not f.stack or f.stack:is_empty() then
			v.view = "board"
			return smp_ah.render(pname)
		end
		local rec = { name = f.stack:get_name(), count = f.stack:get_count(),
			display = keys.display(f.stack) }
		return show(pname, FORM.confirm_listing, fs.confirm_listing(rec, f.price or 0))
	elseif v.view == "confirm_buy" then
		local rec = v.buy and listings.get(v.buy.id)
		if not rec then
			v.view = "board"
			return smp_ah.render(pname)
		end
		return show(pname, FORM.confirm_buy, fs.confirm_purchase(rec))
	end
	-- Default: the board.
	local q = query_board(v)
	v.page = q.page
	return show(pname, FORM.board, fs.board(q))
end

function smp_ah.open_board(pname, opts)
	opts = opts or {}
	local v = view(pname)
	v.view = "board"
	v.page = 1
	if opts.query ~= nil then
		v.query = trim(opts.query)
		v.draft = v.query
	end
	if opts.sort then
		for _, s in ipairs(cfg.sorts) do
			if s == opts.sort then v.sort = s end
		end
	end
	return smp_ah.render(pname)
end

function smp_ah.open_your_items(pname)
	local v = view(pname)
	v.view = "your_items"
	v.page_y = 1
	return smp_ah.render(pname)
end

function smp_ah.close(pname)
	smp_core.close_session(pname, SESSION)
	for _, formname in pairs(FORM) do
		core.close_formspec(pname, formname)
	end
end

----------------------------------------------------------------------
-- Sort cycle (f03 §4.3, OBSERVED [F0118–F0123])
----------------------------------------------------------------------

--- Advance to the next sort. Returns the new sort id.
function smp_ah.cycle_sort(pname)
	local v = view(pname)
	local order = cfg.sorts
	local idx = 1
	for i, id in ipairs(order) do
		if id == v.sort then idx = i end
	end
	v.sort = order[(idx % #order) + 1]
	v.page, v.page_y = 1, 1
	return v.sort
end

function smp_ah.sort_index(pname)
	local v = view(pname)
	for i, id in ipairs(cfg.sorts) do
		if id == v.sort then return i end
	end
	return 1
end

----------------------------------------------------------------------
-- Listing flow: Your Items -> List -> Insert Item -> price -> confirm
-- (f03 §4.5, all OBSERVED except the confirm control itself)
----------------------------------------------------------------------

--- Owner-only detached inventory for `Insert Item` (shared §2.6 R5).
local function make_insert_callbacks(pname)
	local function owner(player)
		return player and player:get_player_name() == pname
	end
	local function occupied(inv)
		local list = inv:get_list("insert") or {}
		for _, stack in ipairs(list) do
			if not stack:is_empty() then return true end
		end
		return false
	end
	return {
		allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
			if not owner(player) then return 0 end
			if from_list ~= "insert" or to_list ~= "insert" then return 0 end
			return count
		end,
		-- One stack at a time: the flow prices a single stack (f03 §4.6).
		allow_put = function(inv, listname, index, stack, player)
			if not owner(player) then return 0 end
			if listname ~= "insert" then return 0 end
			if stack:is_empty() then return 0 end
			if occupied(inv) then return 0 end
			return stack:get_count()
		end,
		allow_take = function(inv, listname, index, stack, player)
			if not owner(player) then return 0 end
			if listname ~= "insert" then return 0 end
			return stack:get_count()
		end,
	}
end

--- Create (or recreate) the detached inventory for a player's insert flow.
function smp_ah.ensure_insert_inventory(pname)
	local name = insert_inv_name(pname)
	local inv = core.create_detached_inventory(name, make_insert_callbacks(pname), pname)
	if inv then inv:set_size("insert", math.max(1, cfg.insert_slots)) end
	return inv
end

--- The stack currently offered for listing: the detached inventory while the
--- player is dragging it around, the flow record once they have moved on.
function smp_ah.inserted_stack(pname)
	local f = flow(pname)
	if f and f.stack and not f.stack:is_empty() then return f.stack end
	local inv = core.get_detached_inventory and
		core.get_detached_inventory(insert_inv_name(pname))
	if not inv then return nil end
	for _, stack in ipairs(inv:get_list("insert") or {}) do
		if not stack:is_empty() then return stack end
	end
	return nil
end

function smp_ah.open_insert(pname)
	-- Any unfinished flow is aborted first: its stack goes home, never into
	-- the new one (X1).
	smp_ah.abort_flow(pname)
	smp_ah._flows[pname] = { stage = "insert" }
	smp_ah.ensure_insert_inventory(pname)
	view(pname).view = "insert"
	return show(pname, FORM.insert, fs.insert(insert_inv_name(pname), cfg.insert_slots))
end

--- Move the inserted stack into the flow (exactly once) and open the price
--- prompt. Returns the stack, or nil + reason.
function smp_ah.take_inserted(pname)
	local inv = core.get_detached_inventory and
		core.get_detached_inventory(insert_inv_name(pname))
	if not inv then return nil, "empty" end
	local stack
	for _, s in ipairs(inv:get_list("insert") or {}) do
		if not s:is_empty() then stack = s break end
	end
	if not stack then return nil, "empty" end
	inv:set_list("insert", {})
	if not inv:get_list("insert") or #inv:get_list("insert") ~= 0 then
		-- Defensive: the list must be empty now, or the stack could be copied.
		inv:set_size("insert", math.max(1, cfg.insert_slots))
		inv:set_list("insert", {})
	end
	local f = smp_ah._flows[pname] or { stage = "insert" }
	smp_ah._flows[pname] = f
	f.stack = stack
	f.stage = "price"
	f.price = nil
	return stack, nil
end

function smp_ah.open_price(pname)
	local stack, err = smp_ah.take_inserted(pname)
	if not stack then return refuse(pname, err or "insert_first") end
	view(pname).view = "price"
	view(pname).price_draft = ""
	return show(pname, FORM.price, fs.price(""))
end

--- Put the flow's stack back into the insert row (used when the player backs
--- out of the price prompt).
function smp_ah.restore_inserted(pname)
	local f = flow(pname)
	if not f or not f.stack or f.stack:is_empty() then return false end
	local inv = core.get_detached_inventory and
		core.get_detached_inventory(insert_inv_name(pname))
	if not inv then return false end
	inv:set_list("insert", {})
	local left = inv:add_item("insert", f.stack)
	if left:is_empty() then
		f.stack = nil
		f.stage = "insert"
		return true
	end
	-- The row would not take it back: return it to the player instead.
	return_stack(pname, left)
	f.stack = nil
	f.stage = "insert"
	return true
end

--- End the flow, giving the held stack back to its owner (shared §2.6 R6).
function smp_ah.abort_flow(pname)
	local f = smp_ah._flows[pname]
	smp_ah._flows[pname] = nil
	local inv = core.get_detached_inventory and
		core.get_detached_inventory(insert_inv_name(pname))
	if inv then
		for _, stack in ipairs(inv:get_list("insert") or {}) do
			if not stack:is_empty() then return_stack(pname, stack) end
		end
		inv:set_list("insert", {})
	end
	if core.remove_detached_inventory then
		core.remove_detached_inventory(insert_inv_name(pname))
	end
	if f and f.stack and not f.stack:is_empty() then
		return_stack(pname, f.stack)
	end
end

----------------------------------------------------------------------
-- Slot limits (f03 §4.8, f13 §4.2.4)
----------------------------------------------------------------------

--- `smp_ranks` owns the tier table and MUST be consulted through its perk API
-- (f13 §4.2.4). It is still a stub, so fall back to the configured table and
-- the rank recorded in the player record. TODO(f13).
function smp_ah.slots(pname)
	if smp_ranks then
		if type(smp_ranks.ah_limit) == "function" then
			local n = smp_ranks.ah_limit(pname)
			if type(n) == "number" and n > 0 then return math.floor(n) end
		end
		if type(smp_ranks.limit) == "function" then
			local n = smp_ranks.limit(pname, "ah")
			if type(n) == "number" and n > 0 then return math.floor(n) end
		end
	end
	local rec = smp_store.api.get_player(pname)
	local tier = rec and rec.rank and rec.rank.tier
	if tier and rec.rank.expires_at and
	   (tonumber(rec.rank.expires_at) or 0) <= os.time() then
		tier = nil     -- expired grants do not raise limits (f13 §4.2.3)
	end
	return cfg.slots[tier] or cfg.slots.default
end

----------------------------------------------------------------------
-- Order routing (f03 §4.11, §6.1)
--
-- TODO(f04): `smp_orders` is another agent's feature
-- (spec/features/f04-orders.md). f03 §6.1 routes a new listing into a
-- compatible (M1) open order whenever that order pays more per item than the
-- listing asks. The contract f03 depends on:
--
--   smp_orders.best_open_order(m1_key) -> order | nil
--       order.unit_price  integer cents per item
--       order.id          for logging
--   smp_orders.fill_from_stack(order, player_name, stack) -> result
--       consumes the stack and pays the seller the order's unit price.
--
-- f04 in turn calls smp_ah.listings_at_or_below(key, unit_price) (f04 §6.1)
-- and smp_ah.consume_listing(id, buyer, price) when it absorbs a listing.
-- Until f04 lands, best_open_order returns nil and every listing goes to the
-- board.
----------------------------------------------------------------------

smp_orders = smp_orders or {}
if type(smp_orders.best_open_order) ~= "function" then
	smp_orders.best_open_order = function(_key)
		return nil      -- TODO(f04)
	end
	smp_ah._orders_stub = true
end

local function best_open_order(m1_key)
	if not m1_key or m1_key == "" then return nil end
	if type(smp_orders) ~= "table" or type(smp_orders.best_open_order) ~= "function" then
		return nil
	end
	local ok, order = pcall(smp_orders.best_open_order, m1_key)
	if not ok or type(order) ~= "table" then return nil end
	if (tonumber(order.unit_price) or 0) <= 0 then return nil end
	return order
end

--- f04 contract: mark a listing consumed by an order. The money comes from
--- the order's escrow and is `smp_orders`' business; this only closes the
--- listing and records the transaction.
function smp_ah.consume_listing(id, buyer, price, reason)
	local rec = listings.get(id)
	if not rec then return nil end
	price = math.floor(tonumber(price) or rec.price)
	listings.set_state(id, reason or "routed")
	listings.insert_transaction({
		listing = id, stack = rec.stack, price = price, qty = rec.count,
		seller = rec.seller, buyer = buyer or "", key = rec.key,
		sold_at_ms = listings.now_ms(), reason = reason or "routed",
	})
	ledger({ type = "ah_sale", actor = rec.seller, counterparty = buyer or "",
		amount = price, item_key = rec.key, qty = rec.count,
		ref = "ah:" .. tostring(id) })
	return rec
end

--- f04/f05 contract: active listings for an M1 key at or below a unit price,
--- cheapest first.
function smp_ah.listings_at_or_below(m1_key, unit_price, now)
	return listings.listings_at_or_below(m1_key, unit_price, now)
end

--- f05 contract (Quick Buy): the cheapest active listings that together fill
--- `qty` items matching `key` + `ench`.
--
-- `key` is the registered itemstring; `ench` is a `{enchant_id = level}`
-- spec table (f05 §5). Returns `{listings = {...}, cost_cents = N}` or nil.
-- The returned `listings` carry `{id, version, count, price, unit_price, ...}`
-- so `smp_quickbuy` can buy each through `smp_ah.buy(id, version)`.
function smp_ah.cheapest_for(key, ench, qty, now)
	if type(key) ~= "string" or key == "" then return nil end
	local ench_string = keys.ench_string_from_spec(ench)
	return listings.cheapest_for(key, ench_string, qty, now)
end

----------------------------------------------------------------------
-- Listing creation (f03 §6.1)
----------------------------------------------------------------------

--- Pure validation: no mutation, no yields. Callers that must remove a stack
-- first (`/ah sell`) use this so nothing is taken unless the listing will be
-- created (shared §2.3).
-- @return true | nil, reason_code
function smp_ah.validate_listing(pname, stack, total_price)
	if not pname or pname == "" then return nil, "offline" end
	if not stack or stack:is_empty() then return nil, "empty" end
	if not keys.key(stack, "M2") then return nil, "empty" end
	total_price = math.floor(tonumber(total_price) or -1)
	if total_price < cfg.min_price or total_price > cfg.max_price then
		return nil, "price"
	end
	if listings.count_active(pname) >= smp_ah.slots(pname) then
		return nil, "slots"
	end
	local last = smp_ah._last_list[pname]
	if cfg.rate_limit > 0 and last and (os.time() - last) < cfg.rate_limit then
		return nil, "rate"
	end
	local fee = pct_of(total_price, cfg.listing_fee_pct)
	if fee > 0 and money_of(pname) < fee then return nil, "fee" end
	return true
end

--- Create a listing.
--
-- The caller owns `stack` and must have already removed it from wherever it
-- was; on refusal the caller must return it. Returns:
--   record, nil        listing created (id in record.id)
--   true,  "routed"    sold into a better-paying open order (f03 §4.11)
--   nil,   reason      refused; the stack is untouched
function smp_ah.create_listing(pname, stack, total_price)
	local ok, err = smp_ah.validate_listing(pname, stack, total_price)
	if not ok then return nil, err end
	total_price = math.floor(total_price)

	local count = stack:get_count()
	local m1 = keys.key(stack, "M1")
	local m2 = keys.key(stack, "M2")
	local unit = math.floor(total_price / count)

	-- Route into a better-paying open order first [S2][S6] (f03 §6.1).
	local order = best_open_order(m1)
	if order and (math.floor(tonumber(order.unit_price) or 0) > unit) and
	   type(smp_orders.fill_from_stack) == "function" then
		local routed, res = pcall(smp_orders.fill_from_stack, order, pname, stack)
		if routed then
			smp_ah._last_list[pname] = os.time()
			log("action", string.format("listing routed to order %s: %s x%d from %s",
				tostring(order.id), stack:get_name(), count, pname))
			return res or true, "routed"
		end
		log("error", "smp_orders.fill_from_stack failed: " .. tostring(res))
	end

	local now = os.time()
	local rec, ierr = listings.insert({
		seller  = pname,
		stack   = stack:to_string(),
		key     = m2,
		key_m1  = m1 or "",
		name    = stack:get_name(),
		count   = count,
		display = keys.display(stack),
		price   = total_price,
		state   = "active",
		created = now,
		expires = now + cfg.listing_duration,
	})
	if not rec then return nil, ierr or "corrupt" end

	local fee = pct_of(total_price, cfg.listing_fee_pct)
	if fee > 0 then
		-- Writes its own `ah_list` ledger entry (shared §2.6 R3).
		smp_store.api.take_money(pname, fee, "ah_list", "ah:" .. rec.id)
	else
		-- f03 §6.1: a zero-amount `ah_list` entry so the audit trail shows the
		-- listing event even when fees are disabled.
		ledger({ type = "ah_list", actor = pname, amount = 0, item_key = m2,
			qty = count, ref = "ah:" .. rec.id })
	end
	smp_ah._last_list[pname] = now
	log("action", string.format("listing %d: %s x%d for %d cents by %s",
		rec.id, rec.name, count, total_price, pname))
	return rec, nil
end

--- Commit the flow's stack as a listing (the `Confirm Listing` step).
function smp_ah.commit_listing(pname)
	local f = flow(pname)
	if not f or not f.stack or f.stack:is_empty() then
		return refuse(pname, "empty")
	end
	if not f.price or f.price <= 0 then
		return refuse(pname, "price")
	end
	local stack = f.stack
	local rec, err = smp_ah.create_listing(pname, stack, f.price)
	if not rec then
		-- Refused: the stack was never consumed, so abort_flow gives it back
		-- to the player and nothing is left holding it.
		smp_ah.abort_flow(pname)
		smp_ah.close(pname)
		return refuse(pname, err or "unknown")
	end
	smp_ah._flows[pname] = nil
	if core.remove_detached_inventory then
		core.remove_detached_inventory(insert_inv_name(pname))
	end
	smp_ah.close(pname)
	if err == "routed" then
		-- f04 paid the seller from the order's escrow and told them itself.
		return true, "routed"
	end
	-- PROPOSED result line, in the observed house style (shared §4.8 rule 2).
	chat(pname, S("You listed @1 @2 for @3", rec.count,
		(rec.display and rec.display.name) or rec.name, money(rec.price)))
	return rec, nil
end

----------------------------------------------------------------------
-- Purchase (f03 §6.2)
----------------------------------------------------------------------

--- Buy a listing, re-validating identity and version.
--
-- `seen_version` is the version the buyer's screen was built from; it comes
-- from the server-side session, never from a client field (shared §2.6 R4).
-- A listing that changed underneath the buyer produces exactly
-- `This item was already bought` [F0037] — OBSERVED, and proof that the
-- reference server re-validates too.
--
-- @return record | nil, reason
function smp_ah.buy(pname, id, seen_version)
	local rec = listings.get(id)
	if not rec then return refuse(pname, "unknown") end
	if rec.state ~= "active" or
	   (seen_version ~= nil and math.floor(tonumber(seen_version) or -1) ~= rec.version) then
		return refuse(pname, "already_bought")
	end
	if not listings.is_active(rec) then return refuse(pname, "expired") end

	local player = player_of(pname)
	if not player then return refuse(pname, "offline") end
	local inv = player:get_inventory()
	if not inv then return refuse(pname, "offline") end
	if money_of(pname) < rec.price then return refuse(pname, "insufficient_funds") end

	local stack = ItemStack(rec.stack)
	if stack:is_empty() then
		log("error", "listing " .. tostring(id) .. " holds an empty stack: " .. tostring(rec.stack))
		return refuse(pname, "corrupt")
	end
	if not inv:room_for_item("main", stack) then return refuse(pname, "no_space") end

	-- No yields from here (shared §2.3): remove the source value, add the
	-- destination value, write the ledger entries, mark the records dirty.
	local taken = smp_store.api.take_money(pname, rec.price, "ah_buy", "ah:" .. rec.id)
	if not taken then return refuse(pname, "insufficient_funds") end

	listings.set_state(rec.id, "sold")

	local tax = pct_of(rec.price, cfg.sale_tax_pct)
	local net = rec.price - tax
	smp_store.api.add_money(rec.seller, net, "ah_sale", "ah:" .. rec.id)

	local left = inv:add_item("main", stack)
	if not left:is_empty() then
		-- room_for_item said yes, so this should be unreachable; never destroy
		-- what was paid for (X1).
		log("error", "purchase " .. tostring(rec.id) .. " left " .. left:to_string())
		return_stack(pname, left)
	end

	listings.insert_transaction({
		listing = rec.id, stack = rec.stack, price = rec.price, qty = rec.count,
		seller = rec.seller, buyer = pname, key = rec.key,
		sold_at_ms = listings.now_ms(), reason = "sold",
	})

	-- OBSERVED result line [F0055]: `You bought 1 Ender Chest for $ 5.1K`.
	chat(pname, S("You bought @1 @2 for $ @3", rec.count,
		(rec.display and rec.display.name) or rec.name, money_after(rec.price)))

	local seller = player_of(rec.seller)
	if seller and rec.seller ~= pname then
		-- PROPOSED sale notification (f03 §3.8: never observed), phrased like
		-- the observed delivery line [F0227].
		chat(rec.seller, S("You sold @1 @2 and received $@3", rec.count,
			(rec.display and rec.display.name) or rec.name, money_tail(net)))
	end

	log("action", string.format("purchase %d: %s x%d for %d cents, %s -> %s",
		rec.id, rec.name, rec.count, rec.price, rec.seller, pname))
	return rec, nil
end

----------------------------------------------------------------------
-- Cancel and reclaim (f03 §4.9; V-42 — never observed)
----------------------------------------------------------------------

--- Cancel an active listing, or reclaim an expired one. PROPOSED: the
-- reference server's mechanism was never recorded (V-42).
function smp_ah.withdraw(pname, id)
	local rec = listings.get(id)
	if not rec then return refuse(pname, "unknown") end
	if rec.seller ~= pname then return refuse(pname, "not_yours") end
	if rec.state ~= "active" and rec.state ~= "expired" then
		return refuse(pname, "already_bought")
	end
	local stack = ItemStack(rec.stack)
	if stack:is_empty() then return refuse(pname, "corrupt") end
	local inv = inventory_of(pname)
	if not inv then return refuse(pname, "offline") end
	if not inv:room_for_item("main", stack) then return refuse(pname, "no_space") end

	-- No yields from here.
	local was_active = (rec.state == "active")
	if was_active then
		listings.set_state(id, "cancelled")
	else
		listings.purge(id)
	end
	local left = inv:add_item("main", stack)
	if not left:is_empty() then return_stack(pname, left) end
	ledger({ type = "ah_list", actor = pname, amount = 0, item_key = rec.key,
		qty = rec.count, ref = "ah:" .. tostring(id),
		flags = { withdraw = was_active and "cancelled" or "reclaimed" } })
	chat(pname, was_active and S("Listing cancelled") or S("Item reclaimed"))
	log("action", string.format("%s %d returned to %s",
		was_active and "listing" or "expired listing", id, pname))
	return rec, nil
end

--- Staff removal with the item returned to the seller (shared §5.5).
function smp_ah.admin_remove(actor, id)
	local rec = listings.get(id)
	if not rec then return refuse(actor, "unknown") end
	local stack = ItemStack(rec.stack)
	if rec.state == "active" or rec.state == "expired" then
		if not stack:is_empty() then
			listings.set_state(rec.id, "cancelled")
			return_stack(rec.seller, stack)
		end
	else
		listings.purge(rec.id)
	end
	ledger({ type = "admin", actor = rec.seller, counterparty = actor, amount = 0,
		item_key = rec.key, qty = rec.count, ref = "ah:" .. tostring(id),
		flags = { ahadmin = true } })
	log("action", "ahadmin remove " .. tostring(id) .. " by " .. tostring(actor))
	chat(actor, S("Removed listing @1", tostring(id)))
	return rec, nil
end

----------------------------------------------------------------------
-- Field handling (shared §2.6 R4: check the formname, use the server-side
-- session, re-validate every action; client fields are untrusted)
----------------------------------------------------------------------

local function listing_id_from(field)
	-- `ah_l<id>` (board) and `ah_y<id>` (your items). The id is looked up
	-- server-side; a forged id resolves to nothing or to a real listing the
	-- player then has to confirm — it can never mutate on its own (T9).
	return tonumber(field:match("^ah_[ly](%d+)$"))
end

local function board_fields(pname, v, fields)
	if fields.ah_filter then
		smp_ah.cycle_sort(pname)
		return smp_ah.render(pname)
	elseif fields.ah_prev then
		v.page = math.max(1, (v.page or 1) - 1)
		return smp_ah.render(pname)
	elseif fields.ah_next then
		v.page = (v.page or 1) + 1
		return smp_ah.render(pname)
	elseif fields.ah_search then
		v.view = "search"
		v.draft = v.query or ""
		return smp_ah.render(pname)
	elseif fields.ah_your_items then
		return smp_ah.open_your_items(pname)
	end
	for name in pairs(fields) do
		local id = listing_id_from(name)
		if id then
			local rec = listings.get_active(id)
			if not rec then return refuse(pname, "already_bought") end
			-- The version the confirm screen is built from is stored
			-- server-side; the client never supplies it.
			v.view = "confirm_buy"
			v.buy = { id = rec.id, version = rec.version }
			return smp_ah.render(pname)
		end
	end
end

local function your_items_fields(pname, v, fields)
	if fields.ah_board then
		v.view = "board"
		v.page = 1
		return smp_ah.render(pname)
	elseif fields.ah_list then
		return smp_ah.open_insert(pname)
	elseif fields.ahy_prev then
		v.page_y = math.max(1, (v.page_y or 1) - 1)
		return smp_ah.render(pname)
	elseif fields.ahy_next then
		v.page_y = (v.page_y or 1) + 1
		return smp_ah.render(pname)
	end
	for name in pairs(fields) do
		local id = listing_id_from(name)
		if id then
			smp_ah.withdraw(pname, id)
			return smp_ah.render(pname)
		end
	end
end

local function search_fields(pname, v, fields)
	local submit = fields.ah_go or
		(fields.key_enter and fields.key_enter_field == "ah_query")
	if submit then
		v.query = trim(fields.ah_query or "")
		v.page = 1
		v.view = "board"
		return smp_ah.render(pname)
	elseif fields.ah_cancel then
		-- `Cancel` leaves the active filter untouched [F0114].
		v.view = "board"
		return smp_ah.render(pname)
	elseif fields.quit then
		v.view = "board"
		return smp_ah.render(pname)
	end
end

local function insert_fields(pname, v, fields)
	-- The only control on `Insert Item` is the sign that opens the price
	-- prompt (f03 §4.5: place the stack, then `Edit Sign Message`).
	if fields.ah_price then
		return smp_ah.open_price(pname)
	end
end

local function price_fields(pname, v, fields)
	local submit = fields.ah_done or
		(fields.key_enter and fields.key_enter_field == "ah_price")
	if not submit then return end
	local f = flow(pname)
	if not f or not f.stack or f.stack:is_empty() then
		return refuse(pname, "empty")
	end
	local text = trim(fields.ah_price or "")
	local cents, perr = smp_core.parse_amount(text)
	if not cents then
		-- Stay on the prompt so the player can correct it; the stack is safe
		-- in the flow.
		v.price_draft = text
		chat(pname, REFUSALS.invalid_price(perr))
		return smp_ah.render(pname)
	end
	local ok, err = smp_ah.validate_listing(pname, f.stack, cents)
	if not ok then
		v.price_draft = text
		chat(pname, (REFUSALS[err] or REFUSALS.unknown)())
		return smp_ah.render(pname)
	end
	f.price = cents
	f.stage = "confirm"
	v.view = "confirm_listing"
	return smp_ah.render(pname)
end

local function confirm_listing_fields(pname, v, fields)
	if fields.ah_confirm then
		return smp_ah.commit_listing(pname)
	elseif fields.ah_cancel or fields.quit then
		-- Backing out of `Confirm Listing` ends the flow and returns the item.
		smp_ah.abort_flow(pname)
		smp_ah.close(pname)
		return
	end
end

local function confirm_buy_fields(pname, v, fields)
	if fields.ah_buy then
		local buy = v.buy
		v.buy = nil
		v.view = "board"
		if not buy then return refuse(pname, "unknown") end
		local rec, err = smp_ah.buy(pname, buy.id, buy.version)
		-- The board is re-rendered either way: the listing is gone on success
		-- and stale on a lost race.
		smp_ah.render(pname)
		return rec, err
	elseif fields.ah_cancel or fields.quit then
		v.buy = nil
		v.view = "board"
		return smp_ah.render(pname)
	end
end

--- The one entry point for every smp_ah formspec.
function smp_ah.handle_fields(pname, formname, fields)
	fields = fields or {}
	local v = smp_core.get_session(pname, SESSION)
	if not v or v.formname ~= formname then
		-- A form we did not last show: ignore it entirely (R4). Cleanup for a
		-- flow that is still open happens in abort_flow / on_leaveplayer.
		return
	end

	if fields.quit then
		if v.view == "price" then
			-- Back out of the sign-editor substitution to `Insert Item`,
			-- keeping the stack in the insert row (f03 §3.6).
			smp_ah.restore_inserted(pname)
			v.view = "insert"
			return smp_ah.render(pname)
		elseif v.view == "insert" or v.view == "confirm_listing" then
			smp_ah.abort_flow(pname)
			smp_core.close_session(pname, SESSION)
			return
		elseif v.view == "search" or v.view == "confirm_buy" then
			v.view = "board"
			v.buy = nil
			return smp_ah.render(pname)
		end
		smp_core.close_session(pname, SESSION)
		return
	end

	if v.view == "board" and formname == FORM.board then
		return board_fields(pname, v, fields)
	elseif v.view == "your_items" and formname == FORM.your_items then
		return your_items_fields(pname, v, fields)
	elseif v.view == "search" and formname == FORM.search then
		return search_fields(pname, v, fields)
	elseif v.view == "insert" and formname == FORM.insert then
		return insert_fields(pname, v, fields)
	elseif v.view == "price" and formname == FORM.price then
		return price_fields(pname, v, fields)
	elseif v.view == "confirm_listing" and formname == FORM.confirm_listing then
		return confirm_listing_fields(pname, v, fields)
	elseif v.view == "confirm_buy" and formname == FORM.confirm_buy then
		return confirm_buy_fields(pname, v, fields)
	end
	-- Unknown view/formname pair: close the session, mutate nothing.
	smp_core.close_session(pname, SESSION)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if type(formname) ~= "string" or formname:sub(1, 7) ~= "smp_ah:" then return end
	if not player or type(player.get_player_name) ~= "function" then return end
	smp_ah.handle_fields(player:get_player_name(), formname, fields or {})
end)

----------------------------------------------------------------------
-- Commands (f03 §2, shared §5.1)
----------------------------------------------------------------------

--- `/ah sell <price>` — list the held stack (LIVE [S5]). The observed listing
-- path is the menu (f03 §2); this is the shortcut.
local function ah_sell(pname, text)
	local cents, perr = smp_core.parse_amount(trim(text))
	if not cents then
		return false, S("Usage: /ah sell <price>")
	end
	local player = player_of(pname)
	if not player then return false end
	local inv = player:get_inventory()
	local index = player:get_wield_index()
	local stack = inv and inv:get_stack("main", index)
	if not stack or stack:is_empty() then
		chat(pname, REFUSALS.empty())
		return true
	end
	-- Validate before anything is removed (shared §2.3).
	local ok, err = smp_ah.validate_listing(pname, stack, cents)
	if not ok then
		chat(pname, (REFUSALS[err] or REFUSALS.unknown)())
		return true
	end
	local count = stack:get_count()
	local display = keys.display(stack)
	-- No yields from here: remove the held stack, then create the listing.
	inv:set_stack("main", index, ItemStack(""))
	local rec, cerr = smp_ah.create_listing(pname, stack, cents)
	if not rec then
		return_stack(pname, stack)
		chat(pname, (REFUSALS[cerr] or REFUSALS.unknown)())
		return true
	end
	if cerr == "routed" then return true end
	chat(pname, S("You listed @1 @2 for @3", count,
		(display and display.name) or stack:get_name(), money(cents)))
	return true
end

local function ah_func(pname, param)
	param = trim(param)
	local sub, rest = param:match("^(%S+)%s*(.*)$")
	if sub and sub:lower() == "sell" then
		return ah_sell(pname, rest)
	end
	if not player_of(pname) then return false end
	smp_ah.open_board(pname, { query = param })
	return true
end

core.register_chatcommand("ah", {
	params = S("[search]"),
	description = S("Open the auction house, optionally pre-filtered."),
	func = ah_func,
})

for _, alias in ipairs({ "auction", "auctionhouse" }) do
	core.register_chatcommand(alias, {
		params = S("[search]"),
		description = S("Alias for /ah."),
		func = function(pname, param) return ah_func(pname, param) end,
	})
end

-- `/ahadmin remove <id>` (shared §5.5).
core.register_chatcommand("ahadmin", {
	params = S("remove <id>"),
	description = S("Auction house administration: remove a listing and return the item."),
	privs = { smp_admin = true },
	func = function(pname, param)
		local sub, rest = trim(param):match("^(%S+)%s*(.*)$")
		if (sub or ""):lower() ~= "remove" then
			return false, S("Usage: /ahadmin remove <id>")
		end
		local id = math.floor(tonumber(rest) or 0)
		if id <= 0 then return false, S("Usage: /ahadmin remove <id>") end
		local rec = smp_ah.admin_remove(pname, id)
		if not rec then return false end
		return true
	end,
})

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

-- Storage. Listings live in smp_ah's own mod storage as JSON documents
-- (shared §2.2). smp_store exposes no generic table API yet; see the
-- "Proposed shared changes" block in spec/features/f03-auction.md.
listings.attach_storage(core.get_mod_storage())
local loaded = listings.load()
load_returns()
log("action", "loaded " .. tostring(loaded) .. " listing(s) from storage")

local flush_t, sweep_t = 0, 0

core.register_on_globalstep(function(dtime)
	dtime = tonumber(dtime) or 0
	flush_t = flush_t + dtime
	if flush_t >= cfg.flush_interval then
		flush_t = 0
		if listings.dirty_count() > 0 then listings.flush() end
		save_returns()
	end
	sweep_t = sweep_t + dtime
	if sweep_t >= cfg.sweep_interval then
		sweep_t = 0
		-- Amortised: at most `sweep_budget` listings per sweep (shared §2.7).
		local expired, purged = listings.sweep(os.time(), cfg.sweep_budget)
		if expired > 0 or purged > 0 then
			log("action", string.format("sweep: %d expired, %d purged", expired, purged))
		end
	end
end)

core.register_on_shutdown(function()
	listings.flush()
	save_returns()
end)

core.register_on_joinplayer(function(player)
	if not player or type(player.get_player_name) ~= "function" then return end
	deliver_returns(player:get_player_name())
end)

-- shared §2.6 R6: items in temporary containers go back to the inventory
-- before the player is saved.
core.register_on_leaveplayer(function(player)
	local pname = type(player) == "string" and player or
		(player and type(player.get_player_name) == "function" and player:get_player_name())
	if not pname then return end
	smp_ah.abort_flow(pname)
	smp_core.close_all_sessions(pname)
	smp_ah._last_list[pname] = nil
	save_returns()
end)

core.register_on_mods_loaded(function()
	-- Every mod has registered its items by now, so the control-item mapping
	-- of shared §4.3 can be resolved for real (and cached as final).
	fs.registry_ready(true)
	fs.reset_items()
	local resolved = {}
	for kind in pairs(fs.CONTROLS) do
		resolved[#resolved + 1] = kind .. "=" .. (fs.item(kind) or "<button>")
	end
	table.sort(resolved)
	log("action", "control items: " .. table.concat(resolved, " "))
	reload_cfg()
	-- Hook /smp test smp_ah into the dispatcher that smp_economy registers.
	-- smp_economy is f01's file and cannot be edited from here (AGENTS.md
	-- rule 4); the wrapper falls through to the original handler.
	local cmd = core.registered_chatcommands and core.registered_chatcommands["smp"]
	if cmd and type(cmd.func) == "function" and not cmd._smp_ah_hooked then
		local orig = cmd.func
		cmd._smp_ah_hooked = true
		cmd._smp_ah_orig = orig
		cmd.func = function(pname, param)
			local target = (param or ""):match("^%s*test%s+(%S+)")
			if target == "smp_ah" or target == "ah" or target == "f03" then
				return smp_ah.run_tests(pname)
			end
			return orig(pname, param)
		end
		log("action", "hooked /smp test smp_ah into the /smp dispatcher")
	end
end)

-- `/smp reload` re-reads the ah.* settings (f01 §2).
local economy_reload = core.registered_chatcommands and core.registered_chatcommands["smp"]
if economy_reload and type(economy_reload.func) == "function" then
	local orig = economy_reload.func
	economy_reload.func = function(pname, param)
		local r = orig(pname, param)
		if (param or ""):match("^%s*reload") then reload_cfg() end
		-- `cmd` may already be wrapped by the on_mods_loaded hook; that hook
		-- reads the *current* func, so re-wrapping here would double-call.
		return r
	end
end

----------------------------------------------------------------------
-- In-game acceptance tests: /smp test smp_ah
----------------------------------------------------------------------

function smp_ah.run_tests(pname)
	local chunk, err = loadfile(modpath .. "/test.lua")
	if not chunk then
		return false, S("Could not load smp_ah/test.lua: @1", tostring(err))
	end
	local ok, results = pcall(chunk)
	if not ok or type(results) ~= "table" then
		return false, S("Tests crashed: @1", tostring(results))
	end
	local lines = {
		S("--- smp_ah tests ---"),
		S("Passed: @1", results.passed or 0),
		S("Failed: @1", results.failed or 0),
	}
	if (results.failed or 0) > 0 then
		for _, l in ipairs(results.lines or {}) do lines[#lines + 1] = l end
	end
	chat(pname, table.concat(lines, "\n"))
	log("action", "smp_ah tests run by " .. tostring(pname) .. " — passed=" ..
		tostring(results.passed) .. " failed=" .. tostring(results.failed))
	return (results.failed or 0) == 0
end

----------------------------------------------------------------------
-- Public API summary (for f04, f05, f14)
--
--   smp_ah.open_board(pname, {query=, sort=})
--   smp_ah.create_listing(pname, stack, total_price)   f03 §6.1
--   smp_ah.buy(pname, id, seen_version)                f03 §6.2
--   smp_ah.listings_at_or_below(m1_key, unit_price)    f04 §6.1
--   smp_ah.consume_listing(id, buyer, price)           f04 §6.1 absorb_listing
--   smp_ah.listings.cheapest(m1_key)                   f05 Quick Buy
--   smp_ah.listings.history(page)                      f14 / API export [S23]
----------------------------------------------------------------------

log("action", "loaded: /ah /auction /auctionhouse /ah sell /ahadmin — " ..
	"page_size=" .. cfg.page_size .. " slots.default=" .. cfg.slots.default ..
	" min_price=" .. cfg.min_price .. "c")
