# S05 — Quick Buy, shard shop, shards, amethyst sell axe

**Target mods:** `smp_quickbuy`, `smp_shardshop`, `smp_shards`, `smp_amethyst`
**Branch:** `agent/sec-s05-shops` · **Audited at:** `85e4a5d`

## Mission

Fix a player-triggerable **server shutdown** in Quick Buy. Stop the sell axe
from destroying items. Repair the shard shop's field handler. Close the
AFK-shards → money pipe.

## Constraints (AGENTS.md)

Edit only the four target mods. `smp_ah` changes are **S03**'s: coordinate
through that brief. Spec and default changes → `§10` of `f05` and `f06`.

## Findings

| ID | Sev | Status | Where | One line |
|---|---|---|---|---|
| QB-1 | **Critical** | CONFIRMED | `smp_quickbuy/bridges.lua:63`, `buy.lua:79` | Passes an ObjectRef as a player name, so `luaL_checkstring` throws and **any player can shut the server down** |
| AX-1 | High | CONFIRMED | `smp_amethyst/sell_axe.lua:42` | `accepted ~= false` is true for `nil`: a refused order routing **deletes the stack** |
| AX-2 | Medium | CONFIRMED | `smp_amethyst/sell_axe.lua:99` | Loop is `0..size-1`: slot 0 is invalid and the last slot is never processed |
| SH-1 | Medium | CONFIRMED | `smp_shardshop/init.lua:145`, `:178` | The handler treats the ObjectRef as a name: the menu can never buy, and sessions are never closed |
| SH-2 | Medium | CONFIRMED | `smp_shards/init.lua:3-48`, `smp_shardshop/catalogue.lua`, `smp_sell` prices | AFK playtime → shards → shop gear → `/sell` for about $100K per item |
| SH-3 | Low | CONFIRMED | `smp_core/init.lua:163-173` (ESCALATE) | `open_session` returns an existing session and ignores `initial`, so stale `offer_id` / `entry_index` values survive |

---

### QB-1 — Quick Buy crashes the server (CRITICAL, DoS)

**Where.** `smp_quickbuy/buy.lua:79` calls
`smp_quickbuy.au.buy(player, l.id, l.version)` with the **ObjectRef**.
`bridges.lua:63` forwards it unchanged to `smp_ah.buy(pname, …)`, which
expects a **string**. The first thing `smp_ah.buy` does with it that
reaches C++ is `core.get_player_by_name(pname)` (`smp_ah/init.lua:211`),
or `core.chat_send_player(pname, …)` on its refusal paths
(`smp_ah/init.lua:203`). Both run `luaL_checkstring`
(`~/dev/luanti/src/script/lua_api/l_env.cpp:648`,
`l_server.cpp:92`), which raises. The error escapes
`on_player_receive_fields` and becomes a fatal mod error, so the server
shuts down.

**Repro (vanilla client).** List 1 dirt on `/ah` from an alt. On the main
account, `/shop` → add an entry for dirt, qty 1 → click the entry. The
server stops.

**Impact.** Any player can stop the server at will, repeatedly. Quick Buy
has also never worked in-engine. The dev-tests pass only because the
bridges are stubbed.

**Fix.**
1. `bridges.lua`: `return smp_ah.buy(player:get_player_name(), id, version)`.
   Accept either type:
   `local pname = type(player) == "string" and player or player:get_player_name()`.
2. Defence in depth (coordinate with S03): at the top of `smp_ah.buy`, add
   `if type(pname) ~= "string" then return nil, "offline" end`.
3. Put `pcall` around the per-listing buy in `buy.lua`, so one bad listing
   cannot abort the loop halfway.

**Tests.** Add a dev-test harness stub where `core.get_player_by_name` and
`core.chat_send_player` **error on a non-string argument**, matching the
engine. Then a Quick Buy purchase through the real `smp_ah` (not the stub)
succeeds, charges `cost_cents`, and delivers the item. Add this "strict
engine stub" to the shared harness so every suite gets it.

---

### AX-1 — Sell axe deletes stacks when order routing refuses

**Where.** `sell_axe.lua:40-42`:

```lua
local ok, accepted = pcall(smp_orders.fill_from_stack, order, player, stack)
return ok and accepted ~= false
```

`fill_from_stack` returns `nil, reason` when it refuses:
`smp_orders/routing.lua:231` (changed), `:234` (own order), `:237` (no
match), and `:246` (`"full"`, when the stack exceeds the order's
remaining quantity). `nil ~= false` is **true**, so the axe reports the
stack as routed and `inv:set_stack("main", i, "")` deletes it. No
payment is made.

**Griefing repro.** An attacker opens an order for **1** diamond at a high
unit price. Every sell-axe user who then processes a chest holding a stack
of diamonds loses the whole stack.

**Fix.**
```lua
return ok and type(accepted) == "table" and (accepted.accepted or 0) > 0
```
On refusal, fall through to `route_to_sell`.

### AX-2 — Off-by-one

`for i = 0, size - 1` should be `for i = 1, size`. Inventory lists are
1-based. Index 0 reads an empty stack, and the last slot is never sold.

**Tests.**
- Order remaining 1, chest holding 64 diamonds: the axe sells the 64 to
  the server (or skips them), and the chest never loses them unpaid.
- A 27-slot chest with an item only in slot 27: it is processed.

**Note.** The axe checks only `core.is_protected`. Outside spawn there is
no protection unless the operator installs a claims mod. The axe then
turns any chest a player can reach into **cash for that player**. Record
this in f06 §10 as a design risk. A candidate rule: require
`core.get_meta(pos):get_string("owner")` to match, where the container
has an owner, or refuse locked or other players' containers.

---

### SH-1 — Shard shop handler uses the ObjectRef as a name

`smp_shardshop/init.lua:145` names the first callback parameter
`player_name`, but `register_on_player_receive_fields` passes an
**ObjectRef**. `smp_core.handle_fields(ObjectRef, …)` finds no session
(sessions are keyed by name) and returns `"close"`, so no purchase can ever
complete from the menu. `:178` (`on_leaveplayer`) has the same mistake,
so sessions are never cleared. This is not exploitable today, but it hides
the SH-3 hazard below.

**Fix.** Use `local name = player:get_player_name()` in both places.
**Test:** a harness purchase through the real field handler debits shards
and delivers the item.

### SH-3 — Stale session state (ESCALATE, `smp_core`)

`smp_core.open_session` (`smp_core/init.lua:163-173`) returns any existing
session **unchanged** and ignores `initial`. Once SH-1 is fixed, the
following can happen:

1. Open the confirm dialog for offer A.
2. Close it with Esc. `quit` only returns `"stay"`, so the session stays.
3. Click offer B.
4. The session still holds `offer_id = A`, and **Buy** purchases A.

**Fix, locally:** `smp_core.close_session(name, FORM_CONFIRM)` before
`open_session`, and handle `f.quit` → `"close"`.
**Fix, integrator:** propose that `open_session` accept a `reset` flag, or
merge `initial` into the existing table.

---

### SH-2 — AFK shards turn into money (economy)

- Shards: 1 per 600 s of **online** time, with no AFK check
  (`smp_shards/init.lua:3`, and the comment at `:41` says so).
- The shard shop sells, for example, a *Netherite Axe* (600 shards)
  enchanted `efficiency 5, unbreaking 3, mending 1`.
- `/sell` pays `mcl_tools:axe_netherite` = $100,000
  (`smp_sell/prices_default.lua`), plus the V-99 enchant bonus of
  9 levels × $500 = **$104,500**.

That is about $174 per shard, or about $1,000 per AFK hour per account,
with no limit on alt accounts. The hoe, bow, crossbow and armour offers
have no price entry, so they get the $1 default plus an enchant bonus of
about $4,500 each.

**Fix options** (a spec decision; record in f06 §10 / f02 §10):
1. Stamp shop-issued stacks with `smp:shardshop=1` meta, and have
   `smp_sell` refuse (or pay 0 for) stacks carrying it. The `smp_sell`
   side belongs to the S02 brief.
2. Add AFK detection before awarding shards: no award unless the player
   has moved or interacted within the interval.
3. At minimum, drop the enchant bonus for shop-issued gear.

## Definition of done

- QB-1, AX-1, AX-2 and SH-1 fixed, with tests.
- The strict engine stub is in the dev-test harness.
- SH-2 and SH-3 recorded as open questions or escalations.
