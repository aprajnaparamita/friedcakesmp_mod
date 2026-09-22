-- FriedcakeSMP — smp_ranks (STUB)
-- Reserved slot. See spec/features/f13-ranks.md and spec/shared/02-architecture.md §2.1.
-- This file exists so the load order is fixed and parallel agents have a
-- directory to claim. No commands, no business logic, no menu yet.
--
-- The owner of f13-ranks.md adds their real implementation here. They MUST:
--   * depend on smp_store (records live there)
--   * add `load_mod = smp_ranks` to friedcake/modpack.conf (already there)
--   * never modify smp_core / smp_store / smp_admin
--   * send a "Proposed shared changes" note to the integrator if they need
--     to add config keys or commands that affect shared/05 or shared/06.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

core.log("action", "[smp_ranks] stub loaded — owner: f13-ranks.md")
