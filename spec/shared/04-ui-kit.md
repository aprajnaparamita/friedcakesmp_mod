# 4. UI Kit — the observed menu grammar

**New in v0.2.** Derived from 141 video frames. This is the single place the
interface language is specified; feature files describe *their* screens and
refer here for *how* a screen is built.

The reference server's menus are Java chest-inventory GUIs. They share a small,
strict grammar. Reproducing that grammar once, correctly, gets most of the
fidelity; reproducing each menu ad hoc does not.

---

## 4.1 The two menu families

Every observed screen is one of two kinds. They look different, behave
differently, and map to different formspec constructions.

| | **Container menu** | **Prompt menu** |
|---|---|---|
| Built on | A chest inventory | A client dialog |
| Background | Opaque light grey with a slot grid | Translucent dark |
| Player inventory | **Shown**, under an `Inventory` label | Not shown |
| Controls are | Items in slots, identified by tooltip | Real buttons with text labels |
| Title | Top-left or top-centre, plain text | Top-centre, plain text |
| Examples | `Auction (Page 1)` [F0108], `Orders (Page 1)` [F0156], `Sell` [F0093], `Orders -> Deliver Items` [F0214], `Auction > Your Items` [F0131] | `Settings` [F0236], `Home 2` [F0064], `Choose Icon` [F0066], `Choose Item` [F0191], `Review Order` [F0204], `How many?` [F0199], `Rename` [F0071], `Search Auction` [F0114] |

**Rule.** A screen that moves items is a container menu. A screen that collects
a choice or a value is a prompt menu. Do not mix the two.

### Observed sizes

Container menus occupy "approximately the middle 40–60% of the screen" with a
6-row grid above a 4×9 player inventory [F0158]. Prompt menus occupy
"approximately the middle third" [F0064], except `Choose Item` and
`Choose Icon`, which are tall scrolling lists at 70–80% [F0191, F0066].

---

## 4.2 Title bar

| Pattern | Observed | Used for |
|---|---|---|
| `<Name>` | `Sell`, `Settings`, `Rename`, `Confirm Listing`, `Insert Item`, `Review Order` | A screen with one purpose |
| `<Name> (Page N)` | `Auction (Page 1)`, `Orders (Page 1)` | A paginated list |
| `<Name> (N results)` | `Choose Item (1 results)` [F0198] | A list after a search. **Reproduce the ungrammatical plural** (§0.5) |
| `<Parent> -> <Child>` | `Orders -> Your Orders`, `Orders -> Deliver Items`, `Orders -> Confirm Delivery` | A sub-screen of a container menu |
| `<Parent> > <Child>` | `Auction > Your Items` [F0131] | Same, in the auction tree |

> **Inconsistency, reproduced deliberately.** Orders uses `->` and the auction
> uses `>`. Both are single observations of a consistent pattern within their
> own feature and MUST be reproduced as observed. Do not unify them.

A yellow warning triangle sits to the right of the title on most **prompt**
menus [F0061, F0064, F0066, F0071, F0114, F0192, F0199, F0236, F0242]. Its
meaning is not established — it appears on screens with no obvious warning. See
`plan/open-questions.md` V-28.

---

## 4.3 Item-as-button (container menus)

Controls in container menus are inventory slots holding a decorative item. The
item's texture is the icon; its tooltip is the label. Observed vocabulary:

| Control | Item | Tooltip line 1 | Tooltip line 2 | Frames |
|---|---|---|---|---|
| Search | `minecraft:oak_sign` | `Search` | `Click to search` | [F0111, F0125] |
| Filter / sort | `minecraft:hopper` | `Filter` | `Click to change` | [F0118, F0180] |
| Your listings | `minecraft:chest` | `Your Items` | `Click to view` | [F0126, F0127] |
| Your orders | `minecraft:chest` | `Your Orders` | — | [F0186] |
| Orders entry point | `minecraft:book` | `Orders` | `Request and deliver items` | [F0156, F0158] |
| Shard shop entry | `minecraft:amethyst_shard` | `Shard Shop` | `Click to view` | [F0179, F0182] |
| List an item | `minecraft:gray_stained_glass_pane` | `List` | `Click to sell an item` | [F0131] |
| Confirm | `minecraft:lime_stained_glass_pane` | `Confirm` | `Click to deliver items ($30K)` | [F0222] |

### Rules

1. A control MUST be rendered with `item_image_button[]` and a `tooltip[]`
   carrying the observed lines, in order.
2. **Tooltip line 2 is an affordance hint in the form `Click to <verb>`.** When
   an action carries a cost or amount, it is appended in parentheses:
   `Click to deliver items ($30K)` [F0222].
3. Mineclonia item substitutions:

| Java item | Mineclonia itemstring |
|---|---|
| `minecraft:oak_sign` | `mcl_signs:wall_sign` |
| `minecraft:hopper` | `mcl_hoppers:hopper` |
| `minecraft:chest` | `mcl_chests:chest` |
| `minecraft:book` | `mcl_books:book` |
| `minecraft:amethyst_shard` | `mcl_amethyst:amethyst_shard` |
| `minecraft:gray_stained_glass_pane` | `mcl_core:glass_pane_gray` (verify at runtime) |
| `minecraft:lime_stained_glass_pane` | `mcl_core:glass_pane_lime` (verify at runtime) |

Glass-pane itemstrings MUST be confirmed against Mineclonia before use; the
colour-pane naming is the least certain row in this table.

---

## 4.4 Tooltips

Two shapes, both observed many times.

**Listing tooltip** — an item for sale:

```
Ender Pearl                  ← display name
$700                         ← price
minecraft:ender_pearl        ← itemstring  (translate)
15 component(s)              ← DROP (§0.5.1)
```
[F0108, F0110]

**Order tooltip** — an open buy order:

```
Netherite Helmets                                               ← plural display name
Protection IV, Respiration III, Aqua Affinity, Unbreaking III, Mending   ← enchantments, if any
$ 4M each                                                       ← unit price
251/350 Delivered                                               ← progress
Click to deliver items                                          ← affordance
minecraft:netherite_helmet                                      ← itemstring (translate)
20 component(s)                                                 ← DROP
```
[F0164, F0165]

Rules:

1. Order tooltips use the **plural** display name: `Beacons` [F0159],
   `Gold Ingots` [F0160], `Empty Maps` [F0161], `Bones` [F0171],
   `Totems of Undying` [F0212], `Netherite Helmets` [F0164]. Listing tooltips
   use the singular: `Ender Pearl` [F0108], `Diamond` [F0124],
   `Diamond Shovel` [F0115].
2. The enchantment line is present only when the item is enchanted, and reads
   as a comma-separated list of `<Enchantment> <RomanLevel>`, with level
   omitted at level 1 (`Aqua Affinity`, `Mending`) [F0164].
3. `<delivered>/<total> Delivered` uses lower-case quantity suffixes
   (§0.6).
4. Extended tooltips for gear include stat lines before the itemstring:
   `When in Main Hand:`, `5.5 Attack Damage`, `1 Attack Speed` [F0115]. These
   are vanilla client renderings; Mineclonia's own tooltip conventions apply
   instead. This is the one tooltip element not cloned verbatim.

---

## 4.5 Toggle rows (prompt menus)

Observed only in `/settings`, but the pattern is general [F0242, F0243, F0245,
F0254].

```
Public Chat: ON
Private Messages: Friends/Followed
Server Chat Messages: ON
Server Hotbar Messages: ON
Death Messages: Friends/Followed
Advancement Messages: Friends/Followed
Join/Leave Messages: Friends/Followed
Back
```

Rules:

1. A toggle is a **button** whose label is `<Setting name>: <current value>`.
   The value is part of the label, not a separate widget.
2. Clicking cycles to the next value and redraws. The hover tooltip is
   `Click to toggle` [F0245, F0242].
3. Values are **not** limited to ON/OFF. The observed third state is
   `Friends/Followed`, giving a three-way cycle
   `ON → Friends/Followed → OFF`. Ordering is inferred, not observed; see
   `plan/open-questions.md` V-29.
4. Every prompt menu below the top level ends with a `Back` button.

---

## 4.6 Value prompts

Three observed shapes for collecting a value.

**Labelled field** — `Rename` [F0071, F0074]:

```
Rename                    ← title
  New Name                ← field label
  [ Home 2            ]   ← field, pre-filled with the current value
  [ Save ]                ← stacked vertically, centred
  [ Cancel ]
```

**Search field** — `Search Auction` [F0114], `Choose Icon` [F0066],
`Choose Item` [F0192]:

```
Search Auction
  Search                  ← label above the field
  [ diamon            ]
  [ Cancel ]  [ Search ]  ← Cancel red on the left, Search green on the right
```

Colour is observed: `Cancel` in red, `Search` in green [F0114]. Reproduce it.

**Numeric prompt** — `How many?` [F0199] and `Price per item?` [F0202]:

```
How many?                 ← the title IS the question
  Amount                  ← field label
  [ 1                 ]   ← pre-filled with a sensible default
  [ Cancel ]   [ Next ]   ← Cancel bottom-left, Next bottom-right
```

The final numeric prompt in a sequence replaces `Next` with the name of the
next screen: `Price per item?` offers `Review Order` [F0203].

**Sign-edit substitution.** Listing an item for auction opens the Minecraft
sign editor: title `Edit Sign Message`, placeholder `Type price`, a single
`Done` button [F0139, F0140, F0141]. Luanti has no such screen. Substitute a
numeric prompt titled `Edit Sign Message` with the field label `Type price` and
a `Done` button — keeping the observed strings while using a normal field. See
`f03 §3` and `plan/open-questions.md` V-30.

---

## 4.7 Review and confirm

`Review Order` [F0204] is the model for every multi-step confirmation:

```
Review Order
      [item icon]
  Item: Totem of Undying
  Amount: 1
  Price: $ 10 each
  Total: $ 10

  [ Cancel! ]        [ Change Item ]
  [ Change Amount ]  [ Change Price ]
        [ Create Order ]
```

Rules:

1. A summary block of `<Field>: <Value>` lines, one per collected value, plus a
   computed `Total`.
2. **One "change" button per collected value**, letting the player jump back to
   that step alone rather than restarting. This is the most reusable pattern in
   the observed interface and SHOULD be used for every multi-step flow.
3. The commit button is named for the action (`Create Order`), never "OK".
4. `Cancel!` carries an exclamation mark. Reproduce it (§0.5).

A lighter confirmation exists for single-step actions: a `Confirm` tooltip on a
lime pane reading `Click to deliver items ($30K)` [F0222].

---

## 4.8 Feedback

| Channel | Observed | Use |
|---|---|---|
| Action bar | `Delivering...` [F0226] | Progress during a server-side operation |
| Chat | `You delivered 1 Totem of Undying and received $30K` [F0227] | Result of a completed transaction |
| Chat | `You bought 1 Ender Chest for $ 5.1K` [F0055] | Result of a purchase |
| Chat | `This item was already bought` [F0037] | Lost race on a purchase |
| Chat | `You earned 1 Shard for playing the server` [F0037] | Periodic award |
| Chat | `Home set`, `Home deleted`, `Home does not exist`, `You reached home limits` [F0055] | Result and error for homes |
| Chat | `This user only accepts messages from friends or followed players` [F0280] | Refusal caused by a privacy setting |
| Chat | `This command does not exist` [F0055] | Unknown command |

Rules:

1. Results go to chat; progress goes to the action bar.
2. Result messages name the quantity, the item and the amount:
   `You delivered <n> <Item> and received <$amount>`.
3. A refusal states the **reason**, not just the failure. The reference server
   tells the sender *why* a message bounced.
4. Full catalogue in `08-ui-strings.md`.

### Clickable chat (no Luanti equivalent)

Hovering a player's name in chat offers
`Click to send NearHat2738 a teleport request` [F0270, F0284, F0288]. Luanti
chat is not clickable. Substitute: the same text as a **plain hint line**
following the message, and an Accept/Deny formspec for the recipient
(`tp.confirm_menu`, `f08`). Do not attempt to fake clickable text.

---

## 4.9 Formspec construction

| Kit element | Formspec |
|---|---|
| Container menu | `formspec_version[6]` `size[9,N]`, `list[current_player;main;...]`, `mcl_formspec.get_itemslot_bg_v4` for slot backgrounds |
| Prompt menu | `formspec_version[6]`, `bgcolor[#000000C0]` for the translucent dark background, no inventory list |
| Item-as-button | `item_image_button[x,y;1,1;<itemstring>;<name>;]` + `tooltip[<name>;<line1>\n<line2>]` |
| Toggle row | `button[x,y;w,0.8;toggle_<id>;<Label>: <Value>]` + `tooltip[toggle_<id>;Click to toggle]` |
| Value prompt | `field[x,y;w,0.8;<name>;<Label>;<default>]` + `field_close_on_enter[<name>;false]` |
| Coloured button | `style[<name>;bgcolor=red]` / `bgcolor=green` for `Cancel` / `Search` |
| Paged list | `button[prev]`, `button[next]`, title carries `(Page N)` |
| Scrolling item list | `textlist[]` for name-only lists (`Choose Icon`), or a paged `item_image_button[]` grid where icons matter |
| Title | `label[]` at the top; no formspec titlebar |

Session state for every menu lives server-side (`02-architecture.md §2.4`).
Re-validate on every received field: the page number, the selected id and the
amount are all untrusted.
