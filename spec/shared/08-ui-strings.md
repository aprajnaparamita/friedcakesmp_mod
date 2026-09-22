# 8. Verbatim UI String Catalogue

Every string observed in the source video, for translation and for fidelity
checking. Reproduce exactly (`00-conventions.md §0.5`), including the
irregularities noted.

`@1`, `@2` … are `core.get_translator` placeholders. Strings marked
**single frame** rest on one VLM reading and are the likeliest to be slightly
wrong; verify before shipping.

---

## 8.1 Menu titles

| String | Kind | Frames |
|---|---|---|
| `Homes` | prompt | F0061 |
| `Home 2` (a home's own name) | prompt | F0063, F0064, F0067, F0068, F0070 |
| `rock` (a renamed home) | prompt | F0075 |
| `Choose Icon` | prompt | F0066 |
| `Rename` | prompt | F0071, F0074 |
| `Sell` | container | F0093, F0094, F0096 |
| `Auction (Page @1)` | container | F0107–F0129 |
| `Search Auction` | prompt | F0114 |
| `Auction > Your Items` | container | F0131 |
| `Insert Item` | container | F0132, F0136 |
| `Edit Sign Message` | prompt (substituted) | F0139, F0140, F0141 |
| `Confirm Listing` | container | F0142 |
| `Orders (Page @1)` | container | F0156–F0212 |
| `Orders -> Your Orders` | container | F0190 |
| `Orders -> Deliver Items` | container | F0214, F0215, F0216 |
| `Orders -> Confirm Delivery` | container | F0218, F0219, F0222 |
| `Choose Item` | prompt | F0191, F0192, F0194, F0196, F0197 |
| `Choose Item (@1 results)` | prompt | F0198 |
| `How many?` | prompt | F0199 |
| `Price per item?` | prompt | F0202, F0203 |
| `Review Order` | prompt | F0204–F0208 |
| `Settings` | prompt | F0236–F0241, F0253 |
| `Settings - Chat` | prompt | F0242–F0246, F0254, F0255 |
| `Inventory` (section label in every container menu) | label | F0093, F0108, F0158, F0214 |

## 8.2 Buttons

| String | Screen | Frames |
|---|---|---|
| `Teleport` | home submenu | F0063–F0075 |
| `Change Icon` | home submenu | F0063–F0075 |
| `Rename` | home submenu | F0063–F0075 |
| `Delete` | home submenu | F0063–F0075 |
| `Back` | home submenu, `Settings - Chat` | F0063–F0075, F0242 |
| `New Home` | `Homes` tab row | F0061 |
| `Show More` | `Homes` tab row | F0061 |
| `Search` | `Choose Icon`, `Choose Item`, `Search Auction` | F0066, F0192, F0114 |
| `Default` | `Choose Icon` | F0066 |
| `Save` | `Rename` | F0071, F0074 |
| `Cancel` | `Rename`, `Choose Item`, `How many?`, `Search Auction` | F0071, F0192, F0199, F0114 |
| `Cancel!` | `Review Order` — **note the exclamation mark** | F0204 |
| `Next` | `How many?` | F0199 |
| `Done` | `Edit Sign Message` | F0139, F0140 |
| `Change Item` | `Review Order` | F0204 |
| `Change Amount` | `Review Order` | F0204 |
| `Change Price` | `Review Order` | F0204 |
| `Create Order` | `Review Order` | F0204 |
| `Chat` | `Settings` | F0236–F0241 |
| `Notifications` | `Settings` | F0236–F0241 |
| `PvP` | `Settings` | F0236–F0241 |
| `Visuals` | `Settings` | F0236–F0241 |
| `Privacy` | `Settings` | F0236–F0241 |
| `Scoreboard` | `Settings` — read as `Social` once [F0240]; majority reading wins | F0237, F0238, F0239, F0241 |
| `General` | `Settings` | F0236–F0241 |

## 8.3 Labels and prompts

| String | Screen | Frames |
|---|---|---|
| `Choose a category to change your @1 settings` | `Settings` — `@1` is `server.name` (§0.5) | F0236–F0241 |
| `New Name` | `Rename` | F0071, F0074 |
| `Amount` | `How many?` | F0199 |
| `Search` | above search fields | F0066, F0114, F0192 |
| `Type price` | `Edit Sign Message` | F0139, F0140, F0141 |
| `Item: @1` | `Review Order` | F0204 |
| `Amount: @1` | `Review Order` | F0204 |
| `Price: $ @1 each` | `Review Order` | F0204 |
| `Total: $ @1` | `Review Order` | F0204 |
| `@1 requested` | `Orders -> Confirm Delivery` | F0219 |
| `You're delivering @1 @2` | `Orders -> Confirm Delivery` | F0219 |

## 8.4 Toggle rows (`Settings - Chat`)

| String | Observed values | Frames |
|---|---|---|
| `Public Chat: @1` | `ON`, `OFF` | F0242, F0245 |
| `Private Messages: @1` | `Friends/Followed` | F0242–F0246 |
| `Server Chat Messages: @1` | `ON` | F0242–F0246 |
| `Server Hotbar Messages: @1` | `ON` — read once as `Server nowar messages` [F0242]; majority reading wins | F0243, F0245, F0246, F0254 |
| `Death Messages: @1` | `Friends/Followed` | F0242–F0246 |
| `Advancement Messages: @1` | `Friends/Followed` | F0242–F0246 |
| `Join/Leave Messages: @1` | `Friends/Followed` | F0242–F0246 |

Only three values were ever on screen: `ON`, `OFF`, `Friends/Followed`.

## 8.5 Tooltips

| String | Attached to | Frames |
|---|---|---|
| `Click to manage` | a home tab | F0061 |
| `Click to toggle` | a settings toggle | F0242, F0245, F0254 |
| `Click to search` | the `Search` sign | F0111, F0125 |
| `Click to change` | the `Filter` hopper | F0118–F0123, F0180, F0181 |
| `Click to view` | `Your Items`, `Shard Shop` | F0126–F0129, F0179, F0182 |
| `Click to sell an item` | the `List` pane | F0131 |
| `Click to deliver items` | an open order | F0159–F0166, F0212 |
| `Click to deliver items ($@1)` | the delivery `Confirm` pane | F0222 |
| `Request and deliver items` | the `Orders` book | F0156, F0158 |
| `Search` | the search sign, line 1 | F0111, F0125 |
| `Filter` | the filter hopper, line 1 | F0118–F0123, F0180 |
| `Your Items` | the auction chest, line 1 | F0126–F0129 |
| `Your Orders` | the orders chest, line 1 | F0186 |
| `Orders` | the orders book, line 1 | F0156, F0158 |
| `Shard Shop` | the amethyst shard, line 1 | F0179, F0182 |
| `List` | the list pane, line 1 | F0131 |
| `Confirm` | the delivery pane, line 1 | F0222 |
| `@1 each` (price) | order tooltips | F0159, F0160, F0164, F0212 |
| `@1/@2 Delivered` | order tooltips | F0159, F0160, F0164, F0212 |

### Filter option lists

| Screen | Options | Frames |
|---|---|---|
| Auction | `Lowest Price`, `Highest Price`, `Recently Listed` | F0118–F0123 |
| Orders | `Most Per Item`, `Most Paid`, `Recently Listed` | F0180, F0181 |

Rendered as a bulleted list under `Click to change`. **The auction list has no
fourth option**, although the official API documents a fourth sort [S23] — see
`plan/open-questions.md` V-06.

## 8.6 Chat messages

| String | Meaning | Frames |
|---|---|---|
| `Home set` | `/sethome` succeeded | F0055, F0088–F0092 |
| `Home deleted` | a home was deleted | F0055, F0088–F0092 |
| `Home does not exist` | unknown home id | F0055, F0088–F0092 |
| `You reached home limits` | home slots exhausted — **note the plural "limits"** | F0055, F0089 |
| `You renamed your home to @1` | rename succeeded — **single frame, partly OCR-garbled** (`You raamup your home to rock` [F0089]); reconstructed | F0089 |
| `You earned 1 Shard for playing the server` | periodic shard award | F0037, F0055, F0088–F0092 |
| `You bought 1 Ender Chest for $ 5.1K` | purchase result; generalises to `You bought @1 @2 for $ @3` | F0037, F0055 |
| `This item was already bought` | lost race on a purchase | F0037, F0055 |
| `You delivered 1 Totem of Undying and received $30K` | delivery result; generalises to `You delivered @1 @2 and received $@3` | F0227, F0229 |
| `This user only accepts messages from friends or followed players` | `/msg` refused by the recipient's privacy setting | F0276–F0285 |
| `Click to send @1 a teleport request` | clickable-chat affordance on a player name; **no Luanti equivalent**, see `04-ui-kit.md §4.8` | F0270–F0274, F0284, F0288, F0290 |
| `This command does not exist` | unknown command | F0055, F0088–F0092 |

## 8.7 Action bar

| String | Meaning | Frames |
|---|---|---|
| `Delivering...` | delivery in progress | F0226 |

## 8.8 Chat line format

Public chat is `<@1> @2` — angle brackets around the name, a space, the
message [F0269, F0282, F0283]:

```
<FoxBuddy2> ah
<robieto_faze> TPA FOR TEAM OR 1V1
<loldarr> rating bases and neth ingot each and dragon head for very good base
```

**No rank prefix appears on any observed chat line.** v0.1 §8.1 specified
`[Rank] Name: message`. Either ranked players do not carry a chat prefix, or no
ranked player spoke during the recording. Treated as unresolved — see
`plan/open-questions.md` V-24.

## 8.9 Strings deliberately NOT reproduced

| String | Why |
|---|---|
| `15 component(s)`, `20 component(s)`, `14 component(s)` | Java data-component count; no Luanti meaning (§0.5.1) |
| `Unknown or incomplete command. See below for error at position 1: /<--[HERE]` | Generated by the Minecraft client parser, not the server |
| `Version 1.21.11 (v2.22.23-2630)`, `LUNAR CLIENT`, `[Sprinting (Toggled)]` | Lunar Client HUD |
| `X: …  Y: …  Z: …  C: …  Biome: …` | Lunar Client coordinate readout |
| `When in Main Hand:`, `5.5 Attack Damage`, `1 Attack Speed` | Vanilla client tooltip; Mineclonia has its own conventions |
