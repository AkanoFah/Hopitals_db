#!/usr/bin/env python3
"""Hospital SQL Workbench (local version).

Run:   python app.py        (Windows: double-click run.bat)
Needs: Python 3.8+ only. No packages to install, no internet needed.

It serves the web page on http://127.0.0.1:8000 and runs every SQL statement
with the SQLite built into Python. Each browser tab gets its own in-memory
database, so nothing on disk is changed.
"""
import argparse
import json
import sqlite3
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

try:
    sys.stdout.reconfigure(errors="replace")
except Exception:
    pass

HERE = Path(__file__).resolve().parent
MAX_DBS = 20
MAX_BODY = 2 * 1024 * 1024

# The page expects a sql.js-like object; this tiny shim forwards it to the API below.
ENGINE_JS = r"""
function post(path, obj) {
  var x = new XMLHttpRequest();
  x.open('POST', path, false);
  x.setRequestHeader('Content-Type', 'application/json');
  x.send(JSON.stringify(obj));
  if (x.status !== 200) throw new Error('server error ' + x.status);
  return JSON.parse(x.responseText);
}
window.initSqlJs = function () {
  return Promise.resolve({ Database: function () {
    this.id = post('/api/new', {}).id;
    this.mod = 0;
    this.exec = function (sql) {
      var r = post('/api/exec', { id: this.id, sql: sql });
      if (r.error) throw new Error(r.error);
      this.mod = r.modified;
      return r.results;
    };
    this.run = function (sql) { this.exec(sql); };
    this.getRowsModified = function () { return this.mod; };
  } });
};
"""

dbs = {}
lock = threading.Lock()
counter = [0]


def split_sql(sql):
    """Split a script into statements, ignoring ; inside quotes and comments."""
    out, buf, i, n = [], [], 0, len(sql)
    while i < n:
        ch = sql[i]
        if ch in ("'", '"'):
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


def new_db():
    with lock:
        counter[0] += 1
        db_id = counter[0]
        conn = sqlite3.connect(":memory:", isolation_level=None, check_same_thread=False)
        dbs[db_id] = conn
        while len(dbs) > MAX_DBS:
            oldest = min(dbs)
            dbs.pop(oldest).close()
        return db_id


def run_sql(db_id, sql):
    conn = dbs.get(db_id)
    if conn is None:
        return {"results": [], "error": "database session expired, reload the page", "modified": 0}
    results, error, modified = [], None, 0
    with lock:
        try:
            for stmt in split_sql(sql):
                cur = conn.execute(stmt)
                if cur.description:
                    rows = cur.fetchall()
                    if rows:
                        results.append({"columns": [d[0] for d in cur.description],
                                        "values": [list(r) for r in rows]})
            modified = conn.execute("select changes()").fetchone()[0]
        except sqlite3.Error as e:
            error = str(e)
    return {"results": results, "error": error, "modified": modified}


class Handler(BaseHTTPRequestHandler):
    server_version = "HospitalSQL/1.0"

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
        if self.path == "/api/new":
            out = {"id": new_db()}
        elif self.path == "/api/exec":
            out = run_sql(data.get("id"), str(data.get("sql", "")))
        else:
            return self._send(404, b"not found", "text/plain")
        body = json.dumps(out, ensure_ascii=False, default=lambda o: "<blob %d bytes>" % len(o)).encode("utf-8")
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
