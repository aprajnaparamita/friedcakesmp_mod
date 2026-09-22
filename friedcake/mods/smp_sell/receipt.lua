-- FriedcakeSMP — smp_sell/receipt.lua
--
-- The sale receipt: what was sold, how much went to the server, how much was
-- routed to open orders, and how that is reported to the player.
--
-- Entry schema is f02 §5 verbatim; the two per-line money fields
-- (server_cents, order_cents) are additive so history lines can be rendered
-- without re-deriving unit prices (PROPOSED, f02 §10 V-90).
--
-- Strings. No sell result string appears in any frame (f02 §3.3, V-55), so
-- these are invented in the observed house style (shared §0.5.4) on the
-- shape of the delivery result `You delivered 1 Totem of Undying and
-- received $30K` [F0227]. Money uses `smp_core.fmt_money(cents, "body")`,
-- i.e. the suffixed-with-a-space form that shared §0.6 makes a MUST. Note
-- that [F0227] itself reads `$30K` with no space, contradicting §0.6; the
-- contradiction is recorded in f02 §10 (V-91) rather than resolved here.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local deps = ...   -- loadfile'd with { items = <items module>, S = <translator> }

local items = deps.items
local S = deps.S

local R = {}

-- Reasons a stack cannot be sold, in player words.
local REASON_TEXT = {
	enchanted = "enchanted",
	worn      = "worn",
	named     = "renamed",
	metadata  = "modified",
	container = "not empty",
	no_price  = nil,          -- the server simply does not buy it
	empty     = nil,
}

local function money(cents)
	return smp_core.fmt_money(cents or 0, "body")
end

----------------------------------------------------------------------
-- Receipt object
----------------------------------------------------------------------

function R.new(source)
	local self = {
		source       = source or "container",
		time         = os.time(),
		lines        = {},      -- array, in the order items were added
		by_key       = {},      -- item key -> line
		server_total = 0,       -- integer cents
		order_total  = 0,       -- integer cents
		returned     = {},      -- { { name = <display>, reason = <key> } }
	}

	function self:line(key)
		local l = self.by_key[key]
		if not l then
			l = {
				item = key, qty = 0, server = 0, order = 0, order_ids = {},
				server_cents = 0, order_cents = 0,
			}
			self.by_key[key] = l
			self.lines[#self.lines + 1] = l
		end
		return l
	end

	-- qty units sold to the server at `unit` cents each.
	function self:add_server(key, qty, unit)
		qty = math.floor(tonumber(qty) or 0)
		unit = math.floor(tonumber(unit) or 0)
		if qty <= 0 then return end
		local l = self:line(key)
		l.qty = l.qty + qty
		l.server = l.server + qty
		l.server_cents = l.server_cents + qty * unit
		self.server_total = self.server_total + qty * unit
	end

	-- qty units routed into order `order_id` at `unit_price` cents each.
	function self:add_order(key, qty, unit_price, order_id)
		qty = math.floor(tonumber(qty) or 0)
		unit_price = math.floor(tonumber(unit_price) or 0)
		if qty <= 0 then return end
		local l = self:line(key)
		l.qty = l.qty + qty
		l.order = l.order + qty
		l.order_cents = l.order_cents + qty * unit_price
		self.order_total = self.order_total + qty * unit_price
		if order_id then
			local seen = false
			for _, id in ipairs(l.order_ids) do
				if id == order_id then seen = true break end
			end
			if not seen then l.order_ids[#l.order_ids + 1] = order_id end
		end
	end

	-- Rewrite a line with what was actually paid. `E.pay` calls this after
	-- the money moved, so an order that refused its routed units (they fall
	-- back to the server price) leaves the receipt, the chat message and the
	-- stored history all agreeing. Totals are adjusted by the delta, which
	-- makes the call idempotent.
	function self:set_line(key, server_qty, server_cents, order_qty, order_cents, order_ids)
		local l = self:line(key)
		server_qty = math.floor(tonumber(server_qty) or 0)
		server_cents = math.floor(tonumber(server_cents) or 0)
		order_qty = math.floor(tonumber(order_qty) or 0)
		order_cents = math.floor(tonumber(order_cents) or 0)
		self.server_total = self.server_total - l.server_cents + server_cents
		self.order_total = self.order_total - l.order_cents + order_cents
		l.server, l.server_cents = server_qty, server_cents
		l.order, l.order_cents = order_qty, order_cents
		l.qty = server_qty + order_qty
		if order_ids then l.order_ids = order_ids end
	end

	-- An item that went back to the player instead of being sold.
	function self:add_returned(stack, reason)
		self.returned[#self.returned + 1] = {
			name = items.display_name(stack),
			key = items.stack_name(stack),
			reason = reason or "no_price",
		}
	end

	function self:sold_count()
		local n = 0
		for _, l in ipairs(self.lines) do n = n + l.qty end
		return n
	end

	function self:total()
		return self.server_total + self.order_total
	end

	function self:is_empty()
		return #self.lines == 0
	end

	-- History entry, exactly the f02 §5 shape (plus the two money fields).
	function self:to_entry()
		local lines = {}
		for _, l in ipairs(self.lines) do
			lines[#lines + 1] = {
				item = l.item, qty = l.qty, server = l.server, order = l.order,
				order_ids = l.order_ids,
				server_cents = l.server_cents, order_cents = l.order_cents,
			}
		end
		return {
			time = self.time,
			source = self.source,
			lines = lines,
			server_total = self.server_total,
			order_total = self.order_total,
		}
	end

	-- Chat feedback. Bounded: at most `max_lines` messages, then a summary.
	function self:messages(max_lines)
		max_lines = math.max(1, math.floor(tonumber(max_lines) or 8))
		local out = {}

		for _, l in ipairs(self.lines) do
			if #out >= max_lines then break end
			local name = items.display_name(l.item)
			if l.server > 0 then
				out[#out + 1] = S("You sold @1 @2 and received @3",
					l.server, name, money(l.server_cents))
			end
			if l.order > 0 and #out < max_lines then
				out[#out + 1] = S("You sold @1 @2 to an open order and received @3",
					l.order, name, money(l.order_cents))
			end
		end

		if #self.returned > 0 and #out < max_lines + 2 then
			-- Group by (name, reason) so a full inventory of junk is one line.
			local grouped, order = {}, {}
			for _, r in ipairs(self.returned) do
				local k = r.key .. "\1" .. r.reason
				if not grouped[k] then
					grouped[k] = { name = r.name, reason = r.reason, n = 0 }
					order[#order + 1] = k
				end
				grouped[k].n = grouped[k].n + 1
			end
			local shown = 0
			for _, k in ipairs(order) do
				if shown >= 3 then break end
				local g = grouped[k]
				local text = REASON_TEXT[g.reason]
				if text then
					out[#out + 1] = S("@1 could not be sold (@2) and was returned",
						g.name, S(text))
				else
					out[#out + 1] = S("@1 could not be sold and was returned", g.name)
				end
				shown = shown + 1
			end
			if #order > shown then
				out[#out + 1] = S("and @1 more", #order - shown)
			end
		end

		if #out == 0 then
			out[#out + 1] = S("No items to sell")
		end
		return out
	end

	return self
end

return R
