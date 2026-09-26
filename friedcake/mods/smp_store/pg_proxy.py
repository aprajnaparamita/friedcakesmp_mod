#!/usr/bin/env python3
"""FriedcakeSMP — smp_store Postgres proxy.

Luanti's server sandbox has no TCP sockets, so the smp_store postgres backend
cannot speak the Postgres wire protocol itself. This small local daemon sits
between them: it exposes the driver operations as HTTP/JSON and translates
each call into parameterised SQL against a local PostgreSQL server.

Run it next to the server:

    FRIEDCAKE_PG_DSN="dbname=friedcake user=friedcake host=127.0.0.1" \
        python3 pg_proxy.py

The Lua side talks to it at `store.postgres_proxy_url` (default
http://127.0.0.1:8457). Bind to 127.0.0.1 only — this is not an
internet-facing service.

Configuration (environment):
    FRIEDCAKE_PG_DSN     libpq connection string   (default: dbname=friedcake user=friedcake host=127.0.0.1)
    FRIEDCAKE_PG_BIND    address to listen on      (default: 127.0.0.1)
    FRIEDCAKE_PG_PORT    port to listen on         (default: 8457)
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    sys.exit("psycopg2 is required: apt install python3-psycopg2")

DSN = os.environ.get("FRIEDCAKE_PG_DSN", "dbname=friedcake user=friedcake host=127.0.0.1")
BIND = os.environ.get("FRIEDCAKE_PG_BIND", "127.0.0.1")
PORT = int(os.environ.get("FRIEDCAKE_PG_PORT", "8457"))

# Canonical schema (mirrors the sqlite backend's SCHEMA; BIGINT because money
# is integer cents up to 10^15, which overflows 32-bit INTEGER).
SCHEMA = [
    """CREATE TABLE IF NOT EXISTS players (
         name                TEXT PRIMARY KEY,
         first_join          BIGINT NOT NULL,
         money               BIGINT NOT NULL DEFAULT 0,
         shards              BIGINT NOT NULL DEFAULT 0,
         shards_for_playtime BIGINT NOT NULL DEFAULT 0,
         playtime            BIGINT NOT NULL DEFAULT 0,
         rank_json           TEXT NOT NULL DEFAULT '{}',
         homes_json          TEXT NOT NULL DEFAULT '{}',
         stats_json          TEXT NOT NULL DEFAULT '{}',
         social_json         TEXT NOT NULL DEFAULT '{}',
         quickbuy_json       TEXT NOT NULL DEFAULT '{}',
         keys_json           TEXT NOT NULL DEFAULT '{}'
       )""",
    """CREATE TABLE IF NOT EXISTS ledger (
         id           BIGSERIAL PRIMARY KEY,
         time         BIGINT NOT NULL,
         type         TEXT NOT NULL,
         actor        TEXT NOT NULL,
         counterparty TEXT NOT NULL DEFAULT '',
         amount       BIGINT NOT NULL DEFAULT 0,
         currency     TEXT NOT NULL DEFAULT 'money',
         item_key     TEXT NOT NULL DEFAULT '',
         qty          BIGINT NOT NULL DEFAULT 0,
         ref          TEXT NOT NULL DEFAULT '',
         flags_json   TEXT NOT NULL DEFAULT '{}'
       )""",
    "CREATE INDEX IF NOT EXISTS ledger_actor_time ON ledger(actor, time DESC)",
    "CREATE INDEX IF NOT EXISTS ledger_time       ON ledger(time DESC)",
    """CREATE TABLE IF NOT EXISTS history (
         kind       TEXT NOT NULL,
         name       TEXT NOT NULL,
         id         BIGINT NOT NULL,
         t          BIGINT NOT NULL,
         entry_json TEXT NOT NULL,
         PRIMARY KEY (kind, name, id)
       )""",
]

# Nested record fields serialised as JSON strings in their *_json columns.
JSON_COLS = ("rank", "homes", "stats", "social", "quickbuy", "keys")
# Atomic scalar columns updatable via update_player_field.
SCALAR_COLS = {"money": "money", "shards": "shards", "playtime": "playtime"}

_conn = None


def db():
    global _conn
    if _conn is None or _conn.closed:
        _conn = psycopg2.connect(DSN)
        _conn.autocommit = False
    return _conn


def jdump(v):
    return json.dumps(v if v is not None else {})


def jload(s, default=None):
    if s in (None, ""):
        return default if default is not None else {}
    try:
        return json.loads(s)
    except (TypeError, ValueError):
        return default if default is not None else {}


def _int(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def _record_from_row(row):
    rec = {
        "name": row["name"],
        "first_join": _int(row["first_join"]),
        "money": _int(row["money"]),
        "shards": _int(row["shards"]),
        "shards_for_playtime": _int(row["shards_for_playtime"]),
        "playtime": _int(row["playtime"]),
    }
    for col in JSON_COLS:
        rec[col] = jload(row[col + "_json"])
    return rec


def _record_to_cols(record):
    return {
        "name": record.get("name") or "",
        "first_join": _int(record.get("first_join")),
        "money": _int(record.get("money")),
        "shards": _int(record.get("shards")),
        "shards_for_playtime": _int(record.get("shards_for_playtime")),
        "playtime": _int(record.get("playtime")),
        "rank_json": jdump(record.get("rank")),
        "homes_json": jdump(record.get("homes")),
        "stats_json": jdump(record.get("stats")),
        "social_json": jdump(record.get("social")),
        "quickbuy_json": jdump(record.get("quickbuy")),
        "keys_json": jdump(record.get("keys")),
    }


def _ledger_entry_from_row(row):
    return {
        "id": _int(row["id"]),
        "time": _int(row["time"]),
        "type": row["type"],
        "actor": row["actor"],
        "counterparty": row["counterparty"],
        "amount": _int(row["amount"]),
        "currency": row["currency"],
        "item_key": row["item_key"],
        "qty": _int(row["qty"]),
        "ref": row["ref"],
        "flags": jload(row["flags_json"]),
    }


def dispatch(cur, op, p):
    if op == "migrate":
        for stmt in SCHEMA:
            cur.execute(stmt)
        return {}

    if op == "get_player":
        cur.execute(
            "SELECT name, first_join, money, shards, shards_for_playtime, playtime, "
            "rank_json, homes_json, stats_json, social_json, quickbuy_json, keys_json "
            "FROM players WHERE name = %s", (p.get("name"),))
        row = cur.fetchone()
        return {"record": _record_from_row(row) if row else None}

    if op == "upsert_player":
        c = _record_to_cols(p.get("record") or {})
        cur.execute("""
            INSERT INTO players
              (name, first_join, money, shards, shards_for_playtime, playtime,
               rank_json, homes_json, stats_json, social_json, quickbuy_json, keys_json)
            VALUES
              (%(name)s, %(first_join)s, %(money)s, %(shards)s, %(shards_for_playtime)s,
               %(playtime)s, %(rank_json)s, %(homes_json)s, %(stats_json)s,
               %(social_json)s, %(quickbuy_json)s, %(keys_json)s)
            ON CONFLICT (name) DO UPDATE SET
              first_join          = EXCLUDED.first_join,
              money               = EXCLUDED.money,
              shards              = EXCLUDED.shards,
              shards_for_playtime = EXCLUDED.shards_for_playtime,
              playtime            = EXCLUDED.playtime,
              rank_json           = EXCLUDED.rank_json,
              homes_json          = EXCLUDED.homes_json,
              stats_json          = EXCLUDED.stats_json,
              social_json         = EXCLUDED.social_json,
              quickbuy_json       = EXCLUDED.quickbuy_json,
              keys_json           = EXCLUDED.keys_json
        """, c)
        return {}

    if op == "all_player_names":
        cur.execute("SELECT name FROM players ORDER BY name")
        return {"names": [r["name"] for r in cur.fetchall()]}

    if op == "update_player_field":
        name = p.get("name")
        key = p.get("key")
        value = p.get("value")
        if key in SCALAR_COLS:
            cur.execute("UPDATE players SET %s = %%s WHERE name = %%s"
                        % SCALAR_COLS[key], (_int(value), name))
        elif key in JSON_COLS:
            cur.execute("UPDATE players SET %s_json = %%s WHERE name = %%s"
                        % key, (jdump(value), name))
        # Unknown keys are ignored, matching the sqlite backend.
        return {}

    if op == "append_ledger":
        e = p.get("entry") or {}
        flags_json = e.get("flags") if isinstance(e.get("flags"), str) else jdump(e.get("flags"))
        cur.execute("""
            INSERT INTO ledger
              (time, type, actor, counterparty, amount, currency, item_key, qty, ref, flags_json)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """, (
            _int(e.get("time")),
            e.get("type") or "admin",
            e.get("actor") or "",
            e.get("counterparty") or "",
            _int(e.get("amount")),
            e.get("currency") or "money",
            e.get("item_key") or "",
            _int(e.get("qty")),
            e.get("ref") or "",
            flags_json,
        ))
        return {"id": cur.fetchone()["id"]}

    if op == "ledger_for":
        actor = p.get("actor") or ""
        size = _int(p.get("size"), 20) or 20
        page = _int(p.get("page"), 1) or 1
        offset = (page - 1) * size

        cur.execute("SELECT COUNT(*) AS n FROM ledger WHERE (actor = %s OR %s = '')",
                    (actor, actor))
        total = _int(cur.fetchone()["n"])

        cur.execute("""
            SELECT id, time, type, actor, counterparty, amount,
                   currency, item_key, qty, ref, flags_json
            FROM ledger
            WHERE (actor = %s OR %s = '')
            ORDER BY id DESC
            LIMIT %s OFFSET %s
        """, (actor, actor, size, offset))
        entries = [_ledger_entry_from_row(r) for r in cur.fetchall()]
        return {"entries": entries, "total_pages": max(1, (total + size - 1) // size)}

    if op == "append_history":
        kind = p.get("kind")
        name = p.get("name")
        entry = p.get("entry") or {}
        cap = max(1, _int(p.get("cap"), 100) or 100)

        cur.execute("SELECT COALESCE(MAX(id), 0) AS m FROM history WHERE kind = %s AND name = %s",
                    (kind, name))
        next_id = _int(cur.fetchone()["m"]) + 1

        entry = dict(entry)
        entry["id"] = next_id
        entry["t"] = _int(entry.get("t"))
        cur.execute("INSERT INTO history (kind, name, id, t, entry_json) VALUES (%s, %s, %s, %s, %s)",
                    (kind, name, next_id, entry["t"], json.dumps(entry)))

        cur.execute("""
            DELETE FROM history
            WHERE kind = %s AND name = %s AND id <=
              (SELECT MAX(id) FROM history WHERE kind = %s AND name = %s) - %s
        """, (kind, name, kind, name, cap))
        return {"id": next_id}

    if op in ("flush", "close"):
        return {}

    raise ValueError("unknown op: %r" % op)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.strip("/") == "health":
            self._respond(200, {"ok": True})
        else:
            self._respond(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else b""
        try:
            payload = json.loads(body) if body else {}
        except Exception as exc:  # noqa: BLE001 - report any parse failure
            self._respond(400, {"ok": False, "error": "bad json: %s" % exc})
            return
        if not isinstance(payload, dict):
            payload = {}

        op = self.path.strip("/")
        conn = db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        try:
            result = dispatch(cur, op, payload)
            conn.commit()
            self._respond(200, dict({"ok": True}, **result))
        except Exception as exc:  # noqa: BLE001 - every failure is a 500 to the driver
            conn.rollback()
            self._respond(500, {"ok": False, "error": str(exc)})

    def _respond(self, code, obj):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):  # keep the proxy quiet
        sys.stderr.write("[pg_proxy] %s\n" % (fmt % args))


def main():
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    sys.stderr.write("[pg_proxy] listening on http://%s:%d (dsn=%s)\n"
                     % (BIND, PORT, DSN))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if _conn is not None and not _conn.closed:
            _conn.close()


if __name__ == "__main__":
    main()
