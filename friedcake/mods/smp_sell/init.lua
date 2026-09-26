-- FriedcakeSMP — smp_sell
--
-- Implements spec/features/f02-sell.md: `/sell`, the observed `Sell`
-- container, base prices, `/worth`, `/sellhistory` and sell routing into
-- open orders.
--
-- Commands
--   /sell                 open the `Sell` container          [F0092-F0096]
--   /sell hand            sell the held stack                CLONE [C1]
--   /sell all             sell the whole inventory           CLONE [C1]
--   /sellhistory [page]   past sales                         LIVE [S3]
--   /worth [item]         show a base price                  CLONE [C1]
--
-- Module map (each file is dofile'd/loadfile'd below; none of them registers
-- anything global except through the `smp_sell` table):
--   items.lua     canonical keys M0/M1/M2, plainness, shulker codec
--   prices.lua    reloadable base-price table (integer cents)
--   receipt.lua   the sale receipt and its chat rendering
--   orders.lua    routing adapter to smp_orders (optional, P3)
--   history.lua   per-player sell history
--   sell.lua      the sale engine: plan -> validate -> pay
--   menu.lua      the detached-inventory container menu
--
-- Money is integer cents everywhere (AGENTS.md rule 6) and every
-- player-facing string goes through `core.get_translator` (rule 7).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local MODNAME = core.get_current_modname() or "smp_sell"
local S = core.get_translator(MODNAME)
local modpath = core.get_modpath(MODNAME)

smp_sell = {
	_VERSION = "0.1.0",
	_SPEC = "spec/features/f02-sell.md",
}

----------------------------------------------------------------------
-- Configuration (f02 §7, mirrored in shared/06-config-reference.md)
----------------------------------------------------------------------

-- Forward declarations: reload_cfg() closes over these, and the modules are
-- assigned below in dependency order.
local items, prices, history, receipt, orders, engine, menu, arbitrage

local function get_str(key, default)
	local v = core.settings and core.settings:get(key)
	if v == nil or v == "" then return default end
	return v
end

local function get_num(key, default)
	local v = tonumber(get_str(key, nil))
	if v == nil or v ~= v then return default end
	return v
end

-- `sell.meta_exempt` (f02 §7, default "amethyst items"). Syntax: a
-- comma-separated list where an entry ending in `*` is an item prefix and
-- any other entry is a metadata key. The default exempts the amethyst expiry
-- timer that f06 stores as `smp:expires_at` [S9], so a timed shard tool is
-- still sellable at M0.
local function parse_meta_exempt(raw)
	local keys, item_prefixes = {}, {}
	for entry in (raw or ""):gmatch("([^,]+)") do
		entry = entry:match("^%s*(.-)%s*$") or ""
		if entry ~= "" then
			local prefix = entry:match("^(.-)%*$")
			if prefix then
				item_prefixes[prefix] = true
			else
				keys[entry] = true
			end
		end
	end
	return keys, item_prefixes
end

local cfg = {}

local function reload_cfg()
	cfg.mode               = get_str("sell.mode", "button")          -- OBSERVED [F0094]
	if cfg.mode ~= "button" and cfg.mode ~= "close" then
		core.log("warning", "[smp_sell] unknown sell.mode=" .. tostring(cfg.mode)
			.. " — using button")
		cfg.mode = "button"
	end
	cfg.multiplier         = get_num("sell.multiplier", 1.0)
	if cfg.multiplier < 0 then cfg.multiplier = 1.0 end
	cfg.history_size       = math.floor(get_num("sell.history_size", 100))
	cfg.history_page_size  = math.floor(get_num("sell.history_page_size", 5))
	cfg.receipt_max_lines  = math.floor(get_num("sell.receipt_max_lines", 8))
	cfg.base_prices_path   = get_str("sell.base_prices", "")
	-- PROPOSED (f02 §10 V-98/V-99): server price for unlisted items, and the
	-- per-enchantment-level bonus, both integer cents.
	-- V-98: default_price = 0 disables the default (feature off) until an
	-- operator opts in. The $1 default was an unlimited money faucet (moss,
	-- bone-meal flora, craft-multiplier recipes). SEE f02 §10 for the mirror
	-- change to spec/shared/06-config-reference.md.
	cfg.default_price      = math.max(0, math.floor(get_num("sell.default_price", 0)))
	cfg.enchant_bonus      = math.max(0, math.floor(get_num("sell.enchant_bonus", 50000)))
	cfg.sell_enchanted     = get_str("sell.enchanted", "true") ~= "false"
	cfg.max_balance        = get_num("economy.max_balance",
	                             get_num("store.max_balance", 1e15))
	cfg.meta_exempt_raw    = get_str("sell.meta_exempt", "smp:expires_at,mcl_amethyst:*")
	cfg.meta_exempt_keys, cfg.meta_exempt_items = parse_meta_exempt(cfg.meta_exempt_raw)

	if prices then
		prices.set_default_price(cfg.default_price)
		prices.reload(cfg.base_prices_path)
	end
end

----------------------------------------------------------------------
-- Sell cooldown (SE-5: ~1/s rate limit for /sell and container confirm)
----------------------------------------------------------------------

local sell_cooldown = {}
local SELL_COOLDOWN_SECONDS = 1

local function now_seconds()
	if type(core.get_gametime) == "function" then return core.get_gametime() end
	return os.time()
end

local function sell_cooldown_active(name)
	local until_t = sell_cooldown[name]
	return until_t ~= nil and now_seconds() < until_t
end

function smp_sell._reset_sell_cooldown(name)
	sell_cooldown[name] = nil
end

local function set_sell_cooldown(name)
	sell_cooldown[name] = now_seconds() + SELL_COOLDOWN_SECONDS
end

----------------------------------------------------------------------
-- Module loading
----------------------------------------------------------------------

local function load_module(file, ...)
	local path = modpath .. "/" .. file
	local chunk, err = loadfile(path)
	if not chunk then
		error("[smp_sell] cannot load " .. file .. ": " .. tostring(err))
	end
	local ok, result = pcall(chunk, ...)
	if not ok then
		error("[smp_sell] error in " .. file .. ": " .. tostring(result))
	end
	if type(result) ~= "table" then
		error("[smp_sell] " .. file .. " did not return a table")
	end
	return result
end

items   = load_module("items.lua")
prices  = load_module("prices.lua", items)
history = load_module("history.lua", cfg)
receipt = load_module("receipt.lua", { items = items, S = S })
orders  = load_module("orders.lua")
engine  = load_module("sell.lua", {
	items = items, prices = prices, history = history, receipt = receipt,
	orders = orders, cfg = cfg, S = S,
})
menu    = load_module("menu.lua", {
	items = items, prices = prices, history = history, receipt = receipt,
	orders = orders, engine = engine, cfg = cfg, S = S,
	sell_cooldown_active = sell_cooldown_active,
	set_sell_cooldown = set_sell_cooldown,
})
arbitrage = load_module("arbitrage.lua")

reload_cfg()

smp_sell.cfg     = cfg
smp_sell.items   = items
smp_sell.prices  = prices
smp_sell.history = history
smp_sell.receipt = receipt
smp_sell.orders  = orders
smp_sell.engine  = engine
smp_sell.menu    = menu
smp_sell.arbitrage = arbitrage

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function smp_sell.reload()
	reload_cfg()
	return prices.status()
end

-- Base price in integer cents, or nil.
function smp_sell.base_price(item)
	if type(item) ~= "string" then
		item = item and item.get_name and item:get_name() or nil
	end
	return prices.base_price(items.resolve_name(item or ""))
end

-- What `/sell` pays per unit right now: base price x sell.multiplier.
function smp_sell.unit_value(item)
	if type(item) ~= "string" then
		item = item and item.get_name and item:get_name() or nil
	end
	return prices.unit_value(items.resolve_name(item or ""), cfg.multiplier)
end

-- The entry point f02 §6 documents, and the cross-mod contract other
-- features call (f07 spawner "Sell all", f06 amethyst sell axe):
--
--   smp_sell.sell(player, stacks) -> true when the stacks were paid for
--
-- Accepts a single ItemStack or an array of them. The CALLER owns the
-- physical item movement: it passes the stacks over, and removes them from
-- their container only when this returns `true`. So `true` means "every
-- stack was consumed and paid for" — a partial sale (for example a shulker
-- box with ineligible contents) returns `false` and leaves the caller's
-- stacks exactly as they were. This keeps the amethyst sell axe's promise
-- ("a stack is never removed unless a route accepted it") lossless.
function smp_sell.sell(player, stacks)
	local name = type(player) == "string" and player or player:get_player_name()
	if type(stacks) ~= "table" or getmetatable(stacks) ~= nil then
		stacks = { stacks }              -- a single ItemStack
	end

	-- Pre-check: refuse a partial sale BEFORE any money or item moves.
	local plan = engine.plan(name, stacks, "api")
	if #plan.groups == 0 then
		return false, plan.receipt:messages(cfg.receipt_max_lines)
	end
	if #plan.returns > 0 then
		-- Something could not be sold (an ineligible stack, or a shulker box
		-- whose contents would only partly sell). The caller still owns the
		-- stacks, so report and leave them alone.
		return false, plan.receipt:messages(cfg.receipt_max_lines)
	end

	local ok, messages = engine.transact(name, stacks, "api", {
		consume = function() end,        -- the caller already removed them
		give_back = function(list)
			-- Only reachable on an internal failure: never lose the items.
			local p = core.get_player_by_name(name)
			if p then menu.give_back(p, list) end
		end,
	})
	return ok, messages
end

-- Combat: `/sell` works while combat-tagged (f02 §4.6 [S3], f10 T3). Nothing
-- in this mod consults combat state, and f10 MUST NOT add `sell`,
-- `sellhistory` or `worth` to `combat.blocked_commands`.
smp_sell.ALLOWED_IN_COMBAT = { sell = true, sellhistory = true, worth = true }

----------------------------------------------------------------------
-- /sell
----------------------------------------------------------------------

-- Sell the stack the player is holding.
local function sell_hand(player)
	local name = player:get_player_name()
	local inv = player:get_inventory()
	local wield_index = player:get_wield_index() or 1
	local stack = inv:get_stack("main", wield_index)
	if not stack or stack:is_empty() then
		return false, { S("You are not holding anything") }
	end
	local snapshot = ItemStack(stack)

	return engine.transact(name, { snapshot }, "hand", {
		consume = function()
			inv:set_stack("main", wield_index, ItemStack(""))
		end,
		give_back = function(list)
			-- Put the held item back into the hand slot when it is free, so
			-- `/sell hand` on an ineligible item leaves it where it was.
			local current = inv:get_stack("main", wield_index)
			for i, s in ipairs(list) do
				if current and current:is_empty() and s then
					inv:set_stack("main", wield_index, s)
					current = inv:get_stack("main", wield_index)
					list[i] = ItemStack("")
				end
			end
			local rest = {}
			for _, s in ipairs(list) do
				if s and not s:is_empty() then rest[#rest + 1] = s end
			end
			if #rest > 0 then menu.give_back(player, rest) end
		end,
	})
end

-- Sell every sellable item in the player's main inventory.
local function sell_all(player)
	local name = player:get_player_name()
	local inv = player:get_inventory()
	local size = inv:get_size("main")
	local snapshot, snap_slot = {}, {}
	for i = 1, size do
		local s = inv:get_stack("main", i)
		if s and not s:is_empty() then
			snapshot[#snapshot + 1] = ItemStack(s)
			snap_slot[#snapshot] = i          -- snapshot index -> inventory slot
		end
	end
	if #snapshot == 0 then
		return false, { S("No items to sell") }
	end

	return engine.transact(name, snapshot, "all", {
		consume = function()
			local empty = {}
			for i = 1, size do empty[i] = ItemStack("") end
			inv:set_list("main", empty)
		end,
		give_back = function(list, plan)
			-- Put every returned stack back in the slot it came from, so
			-- `/sell all` does not reshuffle the inventory. Anything without
			-- a known slot (a box whose contents changed size, or items from
			-- a partially failed sale) is packed by the engine; a full
			-- inventory drops the remainder at the player's feet.
			local slots = {}
			for i = 1, size do slots[i] = ItemStack("") end
			local rest = {}
			local used = {}
			for idx, s in ipairs(list or {}) do
				if s and not s:is_empty() then
					local snap_idx = plan and plan.return_slots and plan.return_slots[idx]
					local home = snap_idx and snap_slot[snap_idx]
					if home and not used[home] then
						slots[home] = s
						used[home] = true
					else
						rest[#rest + 1] = s
					end
				end
			end
			inv:set_list("main", slots)
			for _, s in ipairs(rest) do
				local left = s
				local ok, res = pcall(inv.add_item, inv, "main", s)
				if ok then left = res or ItemStack("") end
				if left and not left:is_empty() then
					menu.give_back(player, { left })
				end
			end
		end,
	})
end

core.register_chatcommand("sell", {
	params = S("[hand|all]"),
	description = S("Open the Sell menu, or sell the held stack or the whole inventory."),
	func = function(player_name, param)
		local player = core.get_player_by_name(player_name)
		if not player then return false end

		-- SE-5: rate-limit /sell to ~1/s (reuses /pay cooldown pattern)
		if sell_cooldown_active(player_name) then
			return false, S("Please wait before selling again")
		end

		param = (param or ""):match("^%s*(.-)%s*$") or ""
		local sub = param:match("^(%S+)")

		if sub == nil then
			-- `/sell` opens the observed container [F0092-F0096].
			-- Cooldown is set on actual sale (confirm/hand/all), not on menu open,
			-- because in close mode the sale happens on quit.
			menu.open(player)
			return true
		elseif sub == "hand" or sub == "all" then
			local ok, messages
			if sub == "hand" then
				ok, messages = sell_hand(player)
			else
				ok, messages = sell_all(player)
			end
			if not ok then
				-- A refusal is reported as the command result, like /pay.
				return false, (messages and messages[1]) or S("No items to sell")
			end
			set_sell_cooldown(player_name)
			for _, line in ipairs(messages or {}) do
				core.chat_send_player(player_name, line)
			end
			return true
		end
		return false, S("Usage: /sell [hand|all]")
	end,
})

----------------------------------------------------------------------
-- /worth
----------------------------------------------------------------------

-- Resolve a player-typed item reference to an itemstring.
local function resolve_item_arg(arg)
	if arg == nil or arg == "" then return nil, "empty" end
	if arg == "hand" or arg == "held" then return nil, "hand" end

	local resolved = items.resolve_name(arg)
	if core.registered_items and core.registered_items[resolved] then
		return resolved, nil
	end

	-- Match the tail of an itemstring ("diamond" -> "mcl_core:diamond").
	local matches = {}
	for key in pairs(prices.all()) do
		local tail = key:match(":(.+)$")
		if tail == arg or key == arg then matches[#matches + 1] = key end
	end
	if #matches == 1 then return matches[1], nil end
	if #matches > 1 then
		table.sort(matches)
		return nil, "ambiguous", matches
	end
	return nil, "unknown"
end

core.register_chatcommand("worth", {
	params = S("[item]"),
	description = S("Show the server price of the held item, or of a named item."),
	func = function(player_name, param)
		local player = core.get_player_by_name(player_name)
		if not player then return false end

		param = (param or ""):match("^%s*(.-)%s*$") or ""
		local arg = param:match("^(%S+)")
		local stack

		if arg == nil then
			stack = player:get_wielded_item()
			if not stack or stack:is_empty() then
				return false, S("You are not holding anything")
			end
		else
			local key, err, matches = resolve_item_arg(arg)
			if err == "hand" then
				stack = player:get_wielded_item()
			elseif err == "ambiguous" then
				return false, S("More than one item matches @1 (for example @2)",
					arg, matches[1])
			elseif err then
				return false, S("Unknown item @1", arg)
			else
				stack = ItemStack(key)
			end
			if not stack or stack:is_empty() then
				return false, S("Unknown item @1", arg)
			end
		end

		local key = items.stack_name(stack)
		local name = items.display_name(stack)
		local ok, reason, ench = items.sellable(stack, {
			meta_exempt = cfg.meta_exempt_keys,
			item_exempt = cfg.meta_exempt_items,
			sell_enchanted = cfg.sell_enchanted,
		})
		local base = ok and prices.base_price(key) or 0
		local bonus = ok and prices.enchant_bonus(ench, cfg.enchant_bonus, base) or 0
		local unit = prices.unit_value(key, cfg.multiplier, bonus)
		if not unit then
			return true, S("@1 has no server price", name)
		end

		local out = { S("@1: @2 each", name, smp_core.fmt_money(unit, "body")) }
		local base, is_default = prices.base_price(key)
		if bonus > 0 then
			out[#out + 1] = S("Base price @1 + enchantment bonus @2",
				smp_core.fmt_money(base, "body"), smp_core.fmt_money(bonus, "body"))
		end
		if is_default then
			out[#out + 1] = S("(default price for items without a listed price)")
		end
		if cfg.multiplier ~= 1 then
			out[#out + 1] = S("Base price: @1 each (multiplier @2x)",
				smp_core.fmt_money(base, "body"), tostring(cfg.multiplier))
		end
		-- Say so when the held stack could not actually be sold as it is.
		if not ok and reason and reason ~= "no_price" then
			local words = {
				worn = "worn", named = "renamed",
				metadata = "modified", container = "not empty", empty = "empty",
			}
			out[#out + 1] = S("This stack cannot be sold as it is (@1)",
				words[reason] and S(words[reason]) or reason)
		end
		return true, table.concat(out, "\n")
	end,
})

----------------------------------------------------------------------
-- /sellhistory
----------------------------------------------------------------------

core.register_chatcommand("sellhistory", {
	params = S("[page]"),
	description = S("Show your past sales to the server."),
	func = function(player_name, param)
		local page = tonumber((param or ""):match("(%d+)")) or 1
		local entries, total_pages, total =
			history.page(player_name, page, cfg.history_page_size)

		if total == 0 then
			return true, S("No sales yet")
		end

		local out = { S("--- Sell history (page @1/@2) ---", page, total_pages) }
		for _, e in ipairs(entries) do
			local qty, label = 0, nil
			for _, l in ipairs(e.lines or {}) do
				qty = qty + (l.qty or 0)
				if label == nil then label = items.display_name(l.item) end
			end
			local what
			if #(e.lines or {}) == 1 then
				what = S("@1 @2", qty, label or "?")
			else
				what = S("@1 items in @2 lines", qty, #(e.lines or {}))
			end
			local total_cents = (e.server_total or 0) + (e.order_total or 0)
			local line = S("#@1 @2 @3 received @4",
				e.id,
				os.date("%Y-%m-%d %H:%M", e.time or 0),
				what,
				smp_core.fmt_money(total_cents, "body"))
			if (e.order_total or 0) > 0 then
				line = line .. S(" (@1 server, @2 orders)",
					smp_core.fmt_money(e.server_total, "body"),
					smp_core.fmt_money(e.order_total, "body"))
			end
			out[#out + 1] = line
		end
		return true, table.concat(out, "\n")
	end,
})

----------------------------------------------------------------------
-- /smp reload and /smp test smp_sell
--
-- smp_economy owns `/smp`. It is not edited here (AGENTS.md rule 4); the
-- command is wrapped with the engine's own override mechanism so that
-- `/smp reload` also re-reads the base prices (f02 §4.9 "Base prices live in
-- a reloadable configuration file") and `/smp test smp_sell` runs this mod's
-- tests. Everything else is delegated unchanged.
----------------------------------------------------------------------

local function run_tests(player_name)
	local path = modpath .. "/test.lua"
	local chunk, err = loadfile(path)
	if not chunk then
		return false, S("Could not load smp_sell/test.lua: @1", tostring(err))
	end
	local ok, results = pcall(chunk)
	if not ok then
		return false, S("Tests crashed: @1", tostring(results))
	end
	if type(results) ~= "table" then
		return false, S("Tests returned no results")
	end
	local lines = {
		S("--- smp_sell tests ---"),
		S("Passed: @1", results.passed or 0),
		S("Failed: @1", results.failed or 0),
	}
	if (results.failed or 0) > 0 then
		for _, l in ipairs(results.lines or {}) do lines[#lines + 1] = l end
	end
	core.chat_send_player(player_name, table.concat(lines, "\n"))
	core.log("action", string.format(
		"[smp_sell] tests run by %s — passed=%s failed=%s",
		player_name, tostring(results.passed), tostring(results.failed)))
	return (results.failed or 0) == 0
end
smp_sell.run_tests = run_tests

local smp_cmd = core.registered_chatcommands and core.registered_chatcommands["smp"]
if smp_cmd and core.override_chatcommand then
	local original = smp_cmd.func
	core.override_chatcommand("smp", {
		func = function(player_name, param)
			local op = (param or ""):match("^%s*(%S+)") or ""
			local target = (param or ""):match("^%s*test%s+(%S+)") or ""
			if op == "reload" then
				local status = smp_sell.reload()
				local ok, msg = true, nil
				if type(original) == "function" then ok, msg = original(player_name, param) end
				core.chat_send_player(player_name, S("Sell prices reloaded: @1 item(s)",
					status.prices or 0))
				if status.override_error then
					core.chat_send_player(player_name,
						S("Price override file failed to load: @1", status.override_error))
				end
				return ok, msg
			elseif op == "test" and (target == "smp_sell" or target == "sell" or target == "f02") then
				return run_tests(player_name)
			end
			if type(original) == "function" then
				return original(player_name, param)
			end
			return false, S("Usage: /smp reload|test|backend")
		end,
	})
	core.log("action", "[smp_sell] /smp wrapped for reload and test smp_sell")
else
	core.log("action", "[smp_sell] /smp not present; reload via /sellreload")
	core.register_chatcommand("sellreload", {
		params = "",
		description = S("Reload the sell base prices (admin)."),
		privs = { smp_admin = true },
		func = function(player_name, _)
			local status = smp_sell.reload()
			return true, S("Sell prices reloaded: @1 item(s)", status.prices or 0)
		end,
	})
end

----------------------------------------------------------------------
-- Menu events
----------------------------------------------------------------------

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= menu.FORMNAME then return end
	local name = player:get_player_name()
	if not smp_core.get_session(name, formname) then
		-- R4: no server-side session means this formspec is stale or forged.
		return
	end
	if fields.confirm ~= nil then
		menu.confirm(player)
		return
	end
	if fields.quit then
		menu.close(player, "quit")     -- T6: nothing is sold without confirm
	end
end)

core.register_on_leaveplayer(function(player, timeout)
	-- R6 / T7: return the container BEFORE the player is saved. This runs
	-- whether or not the session survived another mod's leave handler.
	local name = player:get_player_name()
	local returned = menu.return_contents(player, name)
	if core.remove_detached_inventory then
		pcall(core.remove_detached_inventory, menu.inv_name(name))
	end
	if returned > 0 then
		core.log("action", "[smp_sell] " .. name .. " left with " .. returned
			.. " stack(s) in the sell container; returned to the inventory")
	end
end)

core.register_on_dieplayer(function(player, reason)
	-- Death drops are handled by mcl_death_drop for the four registered
	-- lists; the sell container is not one of them, so its contents are put
	-- on the ground with the rest rather than staying in a volatile
	-- detached inventory.
	local name = player:get_player_name()
	if not menu.is_open(name) then return end
	local inv = menu.get_inv(name)
	local stacks = {}
	if inv then
		for i = 1, inv:get_size("main") do
			local s = inv:get_stack("main", i)
			if s and not s:is_empty() then stacks[#stacks + 1] = ItemStack(s) end
		end
	end
	smp_core.close_session(name, menu.FORMNAME)
	if core.close_formspec then pcall(core.close_formspec, name, menu.FORMNAME) end
	if #stacks > 0 then
		local pos = player:get_pos()
		for _, s in ipairs(stacks) do
			if not pcall(core.item_drop, s, player, pos) and core.add_item then
				pcall(core.add_item, pos, s)
			end
		end
		core.log("action", "[smp_sell] " .. name .. " died with " .. #stacks
			.. " stack(s) in the sell container; dropped at the death position")
	end
	menu.unpersist(name)
	local inv2 = menu.get_inv(name)
	if inv2 then
		local empty = {}
		for i = 1, inv2:get_size("main") do empty[i] = ItemStack("") end
		pcall(inv2.set_list, inv2, "main", empty)
	end
	if core.remove_detached_inventory then
		pcall(core.remove_detached_inventory, menu.inv_name(name))
	end
end)

core.register_on_joinplayer(function(player)
	-- Crash net 3: a mirrored container from a server that died is handed
	-- back on the next join.
	local name = player:get_player_name()
	pcall(menu.recover, player, name)
end)

core.register_on_shutdown(function()
	-- R6/R12: nobody should lose items to a clean shutdown either.
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if menu.is_open(name) then
			menu.return_contents(player, name)
		end
	end
end)

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------

core.register_on_mods_loaded(function()
	-- Aliases are only complete once every mod has loaded, so the price
	-- table is normalised again here (mcl_walls:cobble is an alias, and
	-- players hold the resolved name).
	prices.reload(cfg.base_prices_path)
end)

local status = prices.status()
core.log("action", string.format(
	"[smp_sell] loaded: /sell /sellhistory /worth — mode=%s multiplier=%s history=%d prices=%d",
	cfg.mode, tostring(cfg.multiplier), cfg.history_size, status.prices or 0))
