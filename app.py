#!/usr/bin/env python3
"""Hospital SQL Workbench (local version).

Run:   python app.py        (Windows: double-click run.bat)
Needs: Python 3.8+ only for the SQLite mode (no packages, no internet).
       For MySQL mode also:  pip install pymysql

It serves the web page on http://127.0.0.1:8000 and runs every SQL statement
either with the SQLite built into Python (each browser tab gets its own
in-memory database, nothing on disk is changed) or on a MySQL server you
connect to from the page (tables are real and stay after you close the page).
"""
import argparse
import datetime
import decimal
import json
import re
import sqlite3
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

try:
    import pymysql  # optional: only needed for MySQL mode
except ImportError:  # pragma: no cover
    pymysql = None

try:
    sys.stdout.reconfigure(errors="replace")
except Exception:
    pass

HERE = Path(__file__).resolve().parent
MAX_DBS = 20
MAX_BODY = 2 * 1024 * 1024
DB_NAME_RE = re.compile(r"^[A-Za-z0-9_$]{1,64}$")

# The page expects a sql.js-like object; this tiny shim forwards it to the API below.
ENGINE_JS = r"""
function post(path, obj) {
  var x = new XMLHttpRequest();
  x.open('POST', path, false);
  x.setRequestHeader('Content-Type', 'application/json');
  x.send(JSON.stringify(obj));
  if (x.status !== 200) throw new Error('server error ' + x.status);
  var r = JSON.parse(x.responseText);
  if (r && r.error) throw new Error(r.error);
  return r;
}
function Database(opts) {
  var r = post('/api/new', opts || {});
  this.id = r.id;
  this.engine = r.engine;
  this.version = r.version;
  this.database = r.database || '';
  this.mod = 0;
}
Database.prototype.exec = function (sql) {
  var r = post('/api/exec', { id: this.id, sql: sql });
  this.mod = r.modified;
  return r.results;
};
Database.prototype.run = function (sql) { this.exec(sql); };
Database.prototype.getRowsModified = function () { return this.mod; };
Database.prototype.schema = function () { return post('/api/schema', { id: this.id }).objects; };
Database.prototype.drop = function (targets, dry) {
  var r = post('/api/drop', { id: this.id, targets: targets, dry_run: !!dry });
  r.plan.skipped = r.skipped || [];
  return r.plan;
};
Database.prototype.reset = function () { post('/api/reset', { id: this.id }); };
Database.prototype.close = function (beacon) {
  try {
    if (beacon && navigator.sendBeacon) {
      navigator.sendBeacon('/api/close', new Blob([JSON.stringify({ id: this.id })], { type: 'application/json' }));
    } else {
      post('/api/close', { id: this.id });
    }
  } catch (e) { /* already gone */ }
};
window.initSqlJs = function () { return Promise.resolve({ Database: Database }); };
"""


class Session:
    def __init__(self, engine, conn, version, database=""):
        self.engine = engine
        self.conn = conn
        self.version = version
        self.database = database

    def close(self):
        try:
            self.conn.close()
        except Exception:
            pass


dbs = {}
lock = threading.RLock()
counter = [0]


# ---------------------------------------------------------------- helpers
def split_sql(sql):
    """Split a script into statements, ignoring ; inside quotes and comments."""
    out, buf, i, n = [], [], 0, len(sql)
    while i < n:
        ch = sql[i]
        if ch in ("'", '"', "`"):
            j = i + 1
            while j < n:
                if sql[j] == ch:
                    if j + 1 < n and sql[j + 1] == ch:
                        j += 2
                        continue
                    break
                j += 1
            buf.append(sql[i:j + 1])
            i = j + 1
        elif sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j == -1 else j
        elif sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            i = n if j == -1 else j + 2
        elif ch == ";":
            stmt = "".join(buf).strip()
            if stmt:
                out.append(stmt)
            buf = []
            i += 1
        else:
            buf.append(ch)
            i += 1
    stmt = "".join(buf).strip()
    if stmt:
        out.append(stmt)
    return out


def to_json_value(o):
    """Make values coming from MySQL (Decimal, datetime, ...) JSON friendly."""
    if isinstance(o, decimal.Decimal):
        return float(o)
    if isinstance(o, (datetime.datetime, datetime.date)):
        return str(o)
    if isinstance(o, datetime.timedelta):  # MySQL TIME
        total = int(o.total_seconds())
        sign = "-" if total < 0 else ""
        total = abs(total)
        return "%s%02d:%02d:%02d" % (sign, total // 3600, total % 3600 // 60, total % 60)
    if isinstance(o, (bytes, bytearray)):
        try:
            return bytes(o).decode("utf-8")
        except UnicodeDecodeError:
            return "<blob %d bytes>" % len(o)
    return str(o)


def text(v):
    return v.decode("utf-8") if isinstance(v, (bytes, bytearray)) else v


def fmt_error(e):
    args = getattr(e, "args", ())
    if len(args) == 2 and isinstance(args[0], int):
        return "(%d) %s" % (args[0], args[1])
    return str(e)


def qid(engine, name):
    if engine == "mysql":
        return "`" + name.replace("`", "``") + "`"
    return '"' + name.replace('"', '""') + '"'


# ---------------------------------------------------------------- sessions
def open_session(opts):
    engine = str(opts.get("engine") or "sqlite")
    if engine == "mysql":
        if pymysql is None:
            raise RuntimeError("ยังไม่ได้ติดตั้งไดรเวอร์ MySQL: เปิด Terminal แล้วพิมพ์  pip install pymysql  จากนั้นเปิดโปรแกรมใหม่")
        host = str(opts.get("host") or "127.0.0.1")
        port = int(opts.get("port") or 3306)
        user = str(opts.get("user") or "root")
        password = str(opts.get("password") or "")
        database = str(opts.get("database") or "hospital_db")
        if not DB_NAME_RE.match(database):
            raise RuntimeError("ชื่อฐานข้อมูลใช้ได้เฉพาะตัวอักษรอังกฤษ ตัวเลข _ และ $ (ไม่เกิน 64 ตัว)")
        conn = pymysql.connect(host=host, port=port, user=user, password=password,
                               charset="utf8mb4", autocommit=True, connect_timeout=8)
        try:
            cur = conn.cursor()
            try:
                cur.execute("CREATE DATABASE IF NOT EXISTS `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci" % database)
            except Exception:
                pass  # no CREATE privilege: USE below works if the database already exists
            cur.execute("USE `%s`" % database)
            cur.execute("SET NAMES utf8mb4")
            cur.execute("SELECT VERSION()")
            version = text(cur.fetchone()[0])
        except Exception:
            conn.close()
            raise
        return Session("mysql", conn, version, database)
    conn = sqlite3.connect(":memory:", isolation_level=None, check_same_thread=False)
    conn.execute("PRAGMA foreign_keys = ON")
    return Session("sqlite", conn, sqlite3.sqlite_version)


def new_db(opts):
    sess = open_session(opts)
    with lock:
        counter[0] += 1
        db_id = counter[0]
        dbs[db_id] = sess
        while len(dbs) > MAX_DBS:
            oldest = min(dbs)
            dbs.pop(oldest).close()
    return {"id": db_id, "engine": sess.engine, "version": sess.version, "database": sess.database}


def close_db(db_id):
    with lock:
        sess = dbs.pop(db_id, None)
    if sess:
        sess.close()
    return {"ok": True}


def get_session(db_id):
    sess = dbs.get(db_id)
    if sess is None:
        raise RuntimeError("database session expired, reload the page")
    return sess


# ---------------------------------------------------------------- run SQL
def run_sql(db_id, sql):
    results, error, modified = [], None, 0
    with lock:
        try:
            sess = get_session(db_id)
            if sess.engine == "sqlite":
                for stmt in split_sql(sql):
                    cur = sess.conn.execute(stmt)
                    if cur.description:
                        rows = cur.fetchall()
                        if rows:
                            results.append({"columns": [d[0] for d in cur.description],
                                            "values": [list(r) for r in rows]})
                modified = sess.conn.execute("select changes()").fetchone()[0]
            else:
                cur = sess.conn.cursor()
                last = 0
                for stmt in split_sql(sql):
                    cur.execute(stmt)
                    if cur.description:
                        rows = cur.fetchall()
                        if rows:
                            results.append({"columns": [d[0] for d in cur.description],
                                            "values": [list(r) for r in rows]})
                        last = 0
                    else:
                        last = cur.rowcount
                modified = max(last, 0)
        except Exception as e:
            error = fmt_error(e)
    return {"results": results, "error": error, "modified": modified}


# ---------------------------------------------------------------- schema info
def read_meta(sess):
    """Tables, views, FK edges (child, parent) and indexes of the current database."""
    c = sess.conn
    if sess.engine == "sqlite":
        tables = [r[0] for r in c.execute(
            "select name from sqlite_master where type='table' and name not like 'sqlite_%' order by rowid")]
        views = {r[0]: r[1] or "" for r in c.execute(
            "select name, sql from sqlite_master where type='view' order by rowid")}
        indexes = [(r[0], r[1]) for r in c.execute(
            "select name, tbl_name from sqlite_master where type='index' and name not like 'sqlite_%'")]
        raw_edges = []
        for t in tables:
            for r in c.execute("PRAGMA foreign_key_list(%s)" % qid("sqlite", t)):
                raw_edges.append((t, r[2]))
    else:
        cur = c.cursor()
        cur.execute("SELECT TABLE_NAME, TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() "
                    "ORDER BY CREATE_TIME, TABLE_NAME")
        rows = [(text(a), text(b)) for a, b in cur.fetchall()]
        tables = [a for a, b in rows if b != "VIEW"]
        cur.execute("SELECT TABLE_NAME, VIEW_DEFINITION FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE()")
        views = {text(a): text(b) or "" for a, b in cur.fetchall()}
        for a, b in rows:
            if b == "VIEW" and a not in views:
                views[a] = ""
        cur.execute("SELECT DISTINCT INDEX_NAME, TABLE_NAME FROM information_schema.STATISTICS "
                    "WHERE TABLE_SCHEMA = DATABASE() AND INDEX_NAME <> 'PRIMARY'")
        indexes = [(text(a), text(b)) for a, b in cur.fetchall()]
        cur.execute("SELECT TABLE_NAME, REFERENCED_TABLE_NAME FROM information_schema.KEY_COLUMN_USAGE "
                    "WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL")
        raw_edges = [(text(a), text(b)) for a, b in cur.fetchall()]
    low = {t.lower(): t for t in tables}
    edges = [(low.get(ch.lower(), ch), low.get(pa.lower(), pa)) for ch, pa in raw_edges]
    return {"tables": tables, "views": views, "indexes": indexes, "edges": edges}


def build_schema(db_id):
    with lock:
        sess = get_session(db_id)
        meta = read_meta(sess)
        c = sess.conn
        out = []
        names = [(t, "table") for t in meta["tables"]] + [(v, "view") for v in meta["views"]]
        for name, kind in names:
            cols, fks = [], {}
            if sess.engine == "sqlite":
                for r in c.execute("PRAGMA table_info(%s)" % qid("sqlite", name)):
                    cols.append({"name": r[1], "type": r[2] or "", "pk": bool(r[5]), "notnull": bool(r[3])})
                for r in c.execute("PRAGMA foreign_key_list(%s)" % qid("sqlite", name)):
                    fks[r[3]] = "%s.%s" % (r[2], r[4])
                rows = c.execute("select count(*) from %s" % qid("sqlite", name)).fetchone()[0]
            else:
                cur = c.cursor()
                cur.execute("SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY FROM information_schema.COLUMNS "
                            "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s ORDER BY ORDINAL_POSITION", (name,))
                for a, b, nn, key in cur.fetchall():
                    cols.append({"name": text(a), "type": text(b) or "", "pk": text(key) == "PRI",
                                 "notnull": text(nn) == "NO"})
                cur.execute("SELECT COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME "
                            "FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA = DATABASE() "
                            "AND TABLE_NAME = %s AND REFERENCED_TABLE_NAME IS NOT NULL", (name,))
                for a, b, d in cur.fetchall():
                    fks[text(a)] = "%s.%s" % (text(b), text(d))
                cur.execute("SELECT COUNT(*) FROM %s" % qid("mysql", name))
                rows = cur.fetchone()[0]
            out.append({"name": name, "type": kind, "rows": rows, "columns": cols, "fks": fks})
        return {"objects": out}


# ---------------------------------------------------------------- drop / reset
def plan_drop(meta, targets):
    """Work out what must be dropped: requested objects + tables that reference them
    (children first) + views that mention a dropped table."""
    low_t = {t.lower(): t for t in meta["tables"]}
    low_v = {v.lower(): v for v in meta["views"]}
    low_i = {n.lower(): (n, t) for n, t in meta["indexes"]}
    drop_t, drop_v, drop_i = set(), set(), []
    for tg in targets:
        kind = str(tg.get("type", "")).lower()
        name = str(tg.get("name", "")).lower()
        if kind == "table" and name in low_t:
            drop_t.add(low_t[name])
        elif kind == "view" and name in low_v:
            drop_v.add(low_v[name])
        elif kind == "index" and name in low_i:
            drop_i.append(low_i[name])
    changed = True
    while changed:
        changed = False
        for child, parent in meta["edges"]:
            if parent in drop_t and child not in drop_t:
                drop_t.add(child)
                changed = True
    for v, definition in meta["views"].items():
        if any(re.search(r"\b" + re.escape(t) + r"\b", definition, re.I) for t in drop_t):
            drop_v.add(v)
    order, remaining = [], set(drop_t)
    while remaining:
        ready = [t for t in sorted(remaining)
                 if not any(p == t and c in remaining and c != t for c, p in meta["edges"])]
        pick = (ready or sorted(remaining))[0]
        order.append(pick)
        remaining.discard(pick)
    plan = [{"type": "index", "name": n, "table": t} for n, t in drop_i if t not in drop_t]
    plan += [{"type": "view", "name": v} for v in sorted(drop_v)]
    plan += [{"type": "table", "name": t} for t in order]
    return plan


def drop_statement(engine, item):
    if item["type"] == "table":
        return "DROP TABLE %s" % qid(engine, item["name"])
    if item["type"] == "view":
        return "DROP VIEW %s" % qid(engine, item["name"])
    if engine == "mysql":
        return "DROP INDEX %s ON %s" % (qid(engine, item["name"]), qid(engine, item["table"]))
    return "DROP INDEX %s" % qid(engine, item["name"])


def drop_objects(db_id, targets, dry_run):
    with lock:
        sess = get_session(db_id)
        plan = plan_drop(read_meta(sess), targets)
        if dry_run:
            return {"plan": plan}
        cur = sess.conn.cursor() if sess.engine == "mysql" else sess.conn
        done, skipped = [], []
        for item in plan:
            try:
                cur.execute(drop_statement(sess.engine, item))
            except Exception as e:
                code = e.args[0] if getattr(e, "args", None) and isinstance(e.args[0], int) else None
                if sess.engine == "mysql" and item["type"] == "index" and code == 1553:
                    skipped.append(item["name"])  # MySQL: index is needed by a foreign key
                    continue
                raise
            done.append(item)
        return {"plan": done, "skipped": skipped}


def reset_db(db_id):
    """SQLite: brand-new empty in-memory database. MySQL: drop every view and table
    in the connected database."""
    with lock:
        sess = get_session(db_id)
        if sess.engine == "sqlite":
            sess.close()
            fresh = open_session({"engine": "sqlite"})
            sess.conn = fresh.conn
            return {"ok": True}
        meta = read_meta(sess)
        cur = sess.conn.cursor()
        cur.execute("SET FOREIGN_KEY_CHECKS = 0")
        try:
            for v in meta["views"]:
                cur.execute("DROP VIEW IF EXISTS %s" % qid("mysql", v))
            for t in meta["tables"]:
                cur.execute("DROP TABLE IF EXISTS %s" % qid("mysql", t))
        finally:
            cur.execute("SET FOREIGN_KEY_CHECKS = 1")
        return {"ok": True}


# ---------------------------------------------------------------- HTTP
class Handler(BaseHTTPRequestHandler):
    server_version = "HospitalSQL/2.0"

    def log_message(self, fmt, *args):
        pass

    def _host_ok(self):
        host = (self.headers.get("Host") or "").split(":")[0].lower()
        return host in ("127.0.0.1", "localhost", "[::1]")

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self._host_ok():
            return self._send(403, b"forbidden", "text/plain")
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            return self._send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        if path == "/engine.js":
            return self._send(200, ENGINE_JS.encode("utf-8"), "application/javascript; charset=utf-8")
        return self._send(404, b"not found", "text/plain")

    def do_POST(self):
        if not self._host_ok():
            return self._send(403, b"forbidden", "text/plain")
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            return self._send(413, b"too large", "text/plain")
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return self._send(400, b"bad json", "text/plain")
        try:
            if self.path == "/api/new":
                out = new_db(data)
            elif self.path == "/api/exec":
                out = run_sql(data.get("id"), str(data.get("sql", "")))
            elif self.path == "/api/schema":
                out = build_schema(data.get("id"))
            elif self.path == "/api/drop":
                out = drop_objects(data.get("id"), data.get("targets") or [], bool(data.get("dry_run")))
            elif self.path == "/api/reset":
                out = reset_db(data.get("id"))
            elif self.path == "/api/close":
                out = close_db(data.get("id"))
            else:
                return self._send(404, b"not found", "text/plain")
        except Exception as e:
            out = {"error": fmt_error(e)}
        body = json.dumps(out, ensure_ascii=False, default=to_json_value).encode("utf-8")
        self._send(200, body, "application/json; charset=utf-8")


def main():
    ap = argparse.ArgumentParser(description="Hospital SQL Workbench (local)")
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--no-browser", action="store_true", help="do not open the browser automatically")
    args = ap.parse_args()

    server = None
    for port in range(args.port, args.port + 20):
        try:
            server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
            break
        except OSError:
            continue
    if server is None:
        print("Could not find a free port near %d." % args.port)
        sys.exit(1)

    url = "http://127.0.0.1:%d/" % server.server_address[1]
    print("Hospital SQL Workbench is running (SQLite %s)." % sqlite3.sqlite_version)
    print("MySQL mode: %s" % ("ready (pymysql found)" if pymysql else "needs  pip install pymysql"))
    print("Open:  " + url)
    print("Press Ctrl+C to stop.")
    if not args.no_browser:
        threading.Timer(0.6, webbrowser.open, [url]).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
