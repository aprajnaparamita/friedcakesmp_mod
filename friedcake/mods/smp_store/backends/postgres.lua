-- FriedcakeSMP — smp_store postgres backend (STUB)
--
-- The Lua sandbox cannot open a TCP socket. Direct Postgres from a mod
-- is not possible. The eventual driver goes over core.request_http_api()
-- to a local pgwire proxy, which translates HTTP/JSON into the Postgres
-- wire protocol and back. This file exists to:
--
--   * Lock in the driver interface (the SQLite file is the contract)
--   * Fail loudly with an actionable message when an operator asks for it
--   * Give the real driver author a known entry point to edit
--
-- To wire a real driver: implement the same `driver` table the SQLite
-- backend returns, but translate each call into an HTTP request against
-- the local proxy (e.g. POST /smp_store/{op} with JSON body). The proxy
-- owns connection pooling, retries, and schema migrations. The schema in
-- this backend's comment is the source of truth for what the proxy must
-- expose.
--
-- Schema (mirrors the SQLite file):
--
--   CREATE TABLE players (
--     name TEXT PRIMARY KEY,
--     first_join BIGINT NOT NULL,
--     money BIGINT NOT NULL DEFAULT 0,
--     shards BIGINT NOT NULL DEFAULT 0,
--     playtime BIGINT NOT NULL DEFAULT 0,
--     rank_json JSONB NOT NULL DEFAULT '{}',
--     homes_json JSONB NOT NULL DEFAULT '{}',
--     stats_json JSONB NOT NULL DEFAULT '{}',
--     social_json JSONB NOT NULL DEFAULT '{}',
--     quickbuy_json JSONB NOT NULL DEFAULT '{}',
--     keys_json JSONB NOT NULL DEFAULT '{}'
--   );
--   CREATE TABLE ledger (
--     id BIGSERIAL PRIMARY KEY,
--     time BIGINT NOT NULL,
--     type TEXT NOT NULL,
--     actor TEXT NOT NULL,
--     counterparty TEXT NOT NULL DEFAULT '',
--     amount BIGINT NOT NULL DEFAULT 0,
--     currency TEXT NOT NULL DEFAULT 'money',
--     item_key TEXT NOT NULL DEFAULT '',
--     qty BIGINT NOT NULL DEFAULT 0,
--     ref TEXT NOT NULL DEFAULT '',
--     flags_json JSONB NOT NULL DEFAULT '{}'
--   );
--   CREATE INDEX ledger_actor_time ON ledger(actor, time DESC);
--   CREATE INDEX ledger_time       ON ledger(time DESC);
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = S or function(s, ...) return s end

local reason = "[smp_store:postgres] not implemented yet. "
	.. "The eventual driver goes through core.request_http_api() to a local "
	.. "pgwire proxy. Until then, set `store.backend = sqlite` or "
	.. "`store.backend = mod_storage` in minetest.conf."

core.log("error", reason)

-- A driver that errors on every call. We don't fail at load time because
-- the operator may not have asked for postgres; smp_store only loads us
-- when it does. The error message above is the operator-facing explanation.
local function not_implemented() error(reason, 2) end

local driver = {
	migrate            = not_implemented,
	get_player         = not_implemented,
	upsert_player      = not_implemented,
	all_player_names   = not_implemented,
	update_player_field = not_implemented,
	append_ledger      = not_implemented,
	ledger_for         = not_implemented,
	flush              = function() end,
	close              = function() end,
}

return driver
