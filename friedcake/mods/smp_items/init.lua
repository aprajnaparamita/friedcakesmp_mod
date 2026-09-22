-- FriedcakeSMP — smp_items (STUB)
-- Reserved slot. See spec/shared/02-architecture.md §2.5 (canonical item
-- keys and matching levels). No commands, no business logic yet.
--
-- The owner of the item-matching work adds their real implementation here.
-- They MUST:
--   * depend on smp_store (records live there)
--   * depend on mcl_enchanting for the enchantment API (00-conventions.md §0.5)
--   * use the smp_core formatter for any currency or quantity rendered
--   * never modify smp_core / smp_store / smp_admin
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

core.log("action", "[smp_items] stub loaded — owner: shared/02-architecture.md §2.5")
