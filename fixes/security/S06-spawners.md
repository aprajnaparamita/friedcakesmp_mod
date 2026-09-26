# S06 — Spawners: unprivileged `/spawner give`, item loss, open access

**Target mod:** `friedcake/mods/smp_spawners/` · **Branch:** `agent/sec-s06-spawners`
**Audit:** `fixes/security/00-PLAN.md` step 7 · **Audited at:** `85e4a5d`

## Mission

Close a **critical** privilege bug that lets any player mint spawners. Stop
the withdraw paths from destroying items. Make menu access respect
protection.

## Constraints (AGENTS.md)

- Edit only `smp_spawners`. Config default changes that appear in
  `spec/shared/06-config-reference.md` are **ESCALATE**: record them in
  `spec/features/f07-spawners.md §10` and do not edit `spec/shared/`.
- Tests: `friedcake/dev-tests/test_spawners.lua` + `smp_spawners/test.lua`.

## Findings

| ID | Sev | Status | Where | One line |
|---|---|---|---|---|
| SP-1 | **Critical** | CONFIRMED | `init.lua:244`, `init.lua:61` | `/spawner give` has no privilege check: any player can mint spawners |
| SP-2 | High | CONFIRMED | `interaction.lua:196`, `node.lua:122`, `init.lua:280` | `if not inv:add_item(...)` is never true: leftovers are destroyed |
| SP-3 | High | CONFIRMED | `interaction.lua:195`, `routing.lua:69` | `set_count(n)` for n > 65535 clears the stack: withdrawals are destroyed |
| SP-4 | Medium | CONFIRMED | `init.lua:148`, `interaction.lua:128`, `interaction.lua` `revalidate` | Menu, loot, XP and "Sell all" ignore protection by default |

---

### SP-1 — `/spawner give` is callable by every player (CRITICAL)

**Where.** `smp_spawners/init.lua:243-245`:

```lua
core.register_chatcommand("spawner", {
	privilege = "smp_admin",      -- <- not a field Luanti reads
	func = function(sender, params)
```

Luanti's chat-command table uses `privs = {…}`. The builtin
(`~/dev/luanti/builtin/common/chatcommands.lua:49`) does
`def.privs = def.privs or {}`, so this command requires **no privileges**.
The only other guard is `cfg.acquisition.admin`, which **defaults to
`true`** (`init.lua:61`).

**Repro (vanilla client).** `/spawner give <yourname> skeleton 64`, then
repeat. Each call gives 64 spawners. Stack them (sneak + right-click), wait,
then take the loot or use "Sell all".

**Impact.** Unlimited spawners mean unlimited loot, XP and, through
`/sell`, **unlimited money**. Every downstream economy (auction house,
orders, baltop) is compromised. Treat existing worlds as possibly already
exploited.

**Fix.**
1. Replace the field with `privs = { smp_admin = true },`.
2. Log every issue:
   `core.log("action", "[smp_spawners] /spawner give " .. count .. "x" .. type_id .. " to " .. target .. " by " .. sender)`.
   Today there is no audit trail at all.
3. Add a pack-wide lint to `dev-tests/`: load every mod with the
   harness, walk `core.registered_chatcommands`, and fail if any definition
   has a `privilege` key, or any key outside the documented set
   (`params, description, privs, func, mod_origin`). This mistake is easy
   to repeat.

**Tests.**
- Dev-test: `registered_chatcommands.spawner.privs.smp_admin == true`.
- Dev-test: calling the command as a player without `smp_admin` through
  the harness's builtin privilege check is refused.

**Incident response (operator).** Grep the server log for
`Gave .* Spawner` chat lines sent to non-staff. Check the spawner item
counts in player inventories (`/give`-style audit). Review the
`sell` ledger rows of the accounts involved.

---

### SP-2 — Leftover items destroyed when the inventory is full

**Where.** `InvRef:add_item` returns the **leftover ItemStack**, which is
always truthy, so `if not inv:add_item(...)` never runs its branch:

- `interaction.lua:196` (`smp_spawners.take`): the store is decremented
  first (line 193), then items that do not fit vanish.
- `node.lua:122` (breaking a spawner): spawner items that do not fit vanish.
- `init.lua:280` (`/spawner give`): the same.

The fallback itself is also wrong. `core.item_drop(pos, stack)` has the
signature `core.item_drop(itemstack, dropper, pos)`.

**Repro.** Fill your inventory, then click **Take all** on a spawner with
stored loot. The store empties and you receive nothing.

**Fix.** Use the pattern the orders mod already uses:

```lua
local left = inv:add_item("main", stack)
if not left:is_empty() then
	core.add_item(vector.offset(pos, 0, 0.5, 0), left)
end
```

A better fix for `take` is to **only decrement what was delivered**:
`state.store[item] = count - (take - left:get_count())`, and only then
`write_state`.

**Tests.** A harness inventory with 1 free slot, then Take all on 500
bones. The player gets 64, the store keeps about 436, and nothing is dropped
or lost.

---

### SP-3 — Stacks over 65535 are silently cleared

**Where.** `LuaItemStack::l_set_count`
(`~/dev/luanti/src/script/lua_api/l_item.cpp:91-96`) **clears** the stack
when `count > 65535`.

- `interaction.lua:195`: **Take all** passes `n = math.huge`, so `take`
  can be the whole store. Capacity is `2880 × stack` (`init.lua:138`), so a
  23-spawner stack exceeds the limit. The store is decremented and the
  stack is empty.
- `routing.lua:69`: **Sell all** builds one stack per item. An oversized
  lot becomes empty, `smp_sell.sell` sells the rest, and then
  `routing.lua` subtracts **every** lot from the store, including the
  unsold one.

**Fix.**
- `take`: cap `take` at `stack_max × free_slots` (use
  `ItemStack(name):get_stack_max()`), and add in chunks of at most
  `stack_max`.
- `sell_all`: split each lot into chunks of at most `stack_max` (or 65535)
  before calling `smp_sell.sell`. Subtract only what the sale reports as
  sold. `smp_sell.sell` is all-or-nothing today, so on `false` subtract
  nothing, which is already correct once the stacks are valid.

**Tests.** A store with 100000 bones: Sell all credits
`100000 × unit` and empties the store. Take all with a full inventory
removes nothing from the store.

---

### SP-4 — Protected spawners can be emptied by anyone in range

**Where.** `spawners.open_requires_access` defaults to `false`
(`init.lua:148`), so `open_menu` (`interaction.lua:127`) skips
`core.is_protected`. `smp_spawners.revalidate`, which the take, XP and
Sell all paths run, checks only distance (8 nodes). Breaking and stacking
**do** check protection (`node.lua`, `interaction.lua` `add_stack`), so the
menu is the inconsistent path.

**Impact.** On any server running a claims mod (`smp_world` only protects
spawn), another player can walk up to a claimed spawner farm and take its
loot and XP, or click **Sell all** and receive the money.

**Fix.** Check `core.is_protected(pos, name)` inside `revalidate` for every
mutating action (take, XP, sell). Viewing can remain open if the spec wants
that. Propose changing the default to `true` in f07 §10 (mirror change →
ESCALATE).

**Tests.** With `core.is_protected` stubbed to return true for a
non-owner, `take`, `collect_xp` and `sell_all` return 0 or false and the
state is unchanged.

## Definition of done

- SP-1 to SP-4 fixed, with tests.
- `luajit friedcake/dev-tests/test_spawners.lua` is green, and the chat
  command lint is added and green.
- The f07 §10 rows record the proposed default change for
  `open_requires_access`.
