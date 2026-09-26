-- FriedcakeSMP — smp_store postgres backend
--
-- The Lua sandbox cannot open a TCP socket, so this driver does not speak
-- the Postgres wire protocol itself. It talks HTTP/JSON to a local proxy
-- (pg_proxy.py, shipped next to this file) which owns the PostgreSQL
-- connection, retries, and schema. See STORAGE.md §"postgres" for setup.
--
-- Requirements:
--   * pg_proxy.py running and reachable at `store.postgres_proxy_url`
--   * `smp_store` listed in `secure.http_mods` (or `secure.trusted_mods`)
--     in minetest.conf, otherwise `core.request_http_api()` returns nil
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = S or function(s, ...) return s end

local proxy_url = (cfg and cfg.postgres_proxy_url)
	or core.settings:get("store.postgres_proxy_url")
	or "http://127.0.0.1:8457"
proxy_url = proxy_url:gsub("/+$", "")

local http = http_api
if not http then
	error("[smp_store:postgres] core.request_http_api() denied. Add "
		.. "`secure.http_mods = smp_store` (or `secure.trusted_mods = "
		.. "smp_store`) to minetest.conf and restart.")
end

-- The engine only exposes async HTTP on a server; mirror its own
-- fetch_sync (a poll loop). The proxy is localhost so each poll is ~1 ms.
local function sync_request(op, payload)
	local body = core.write_json(payload or {})
	local handle = http.fetch_async({
		url = proxy_url .. "/" .. op,
		method = "POST",
		data = body,
		timeout = 10,
		extra_headers = { "Content-Type: application/json" },
	})
	if not handle then
		error("[smp_store:postgres] fetch_async returned no handle")
	end

	local deadline = os.clock() + 15
	local res
	repeat
		res = http.fetch_async_get(handle)
		if res and res.completed then break end
		if os.clock() > deadline then
			error("[smp_store:postgres] proxy timed out on " .. op)
		end
	until false

	if not res.succeeded then
		error("[smp_store:postgres] proxy request failed on " .. op
			.. ": code=" .. tostring(res.code)
			.. " timeout=" .. tostring(res.timeout)
			.. " data=" .. tostring(res.data))
	end
	if res.code ~= 200 then
		error("[smp_store:postgres] proxy returned HTTP " .. tostring(res.code)
			.. " on " .. op .. ": " .. tostring(res.data))
	end
	local ok, parsed = pcall(core.parse_json, res.data)
	if not ok or type(parsed) ~= "table" then
		error("[smp_store:postgres] bad JSON from proxy on " .. op
			.. ": " .. tostring(res.data))
	end
	if not parsed.ok then
		error("[smp_store:postgres] proxy op " .. op .. " failed: "
			.. tostring(parsed.error or "unknown error"))
	end
	return parsed
end

----------------------------------------------------------------------
-- Driver
----------------------------------------------------------------------

local driver = {}

function driver.migrate()
	sync_request("migrate", {})
	return true
end

function driver.get_player(name)
	if not name or name == "" then return nil end
	local r = sync_request("get_player", { name = name })
	if not r.record then return nil end
	return r.record
end

function driver.upsert_player(record)
	if not record or not record.name then return end
	sync_request("upsert_player", { record = record })
end

function driver.all_player_names()
	local r = sync_request("all_player_names", {})
	return r.names or {}
end

function driver.update_player_field(name, key, value)
	sync_request("update_player_field", { name = name, key = key, value = value })
end

function driver.append_ledger(entry)
	local r = sync_request("append_ledger", { entry = entry })
	return tonumber(r.id)
end

function driver.ledger_for(actor, page, size)
	size = size or 20
	page = page or 1
	local r = sync_request("ledger_for", { actor = actor, page = page, size = size })
	return r.entries or {}, r.total_pages or 1
end

function driver.append_history(kind, name, entry, cap)
	local r = sync_request("append_history",
		{ kind = kind, name = name, entry = entry, cap = cap })
	return tonumber(r.id)
end

function driver.flush()
	-- The proxy commits per request; nothing to flush.
end

function driver.close()
	-- Nothing to close on the Lua side.
end

return driver
