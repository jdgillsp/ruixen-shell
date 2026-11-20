#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
helper="$repo_dir/bars/widgets/ruixen.notch/ubj-today.py"
panel="$repo_dir/bars/widgets/ruixen.notch/UbjTodayPanel.qml"
kanban="$repo_dir/bars/widgets/ruixen.notch/KanbanContent.qml"

pass=0
fail=0
check() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf '  PASS  %s\n' "$label"
    pass=$((pass + 1))
  else
    printf '  FAIL  %s (got %q, want %q)\n' "$label" "$got" "$want" >&2
    fail=$((fail + 1))
  fi
}

check "ubj-today.py exists and is executable" "$([[ -x "$helper" ]] && echo yes || echo no)" "yes"
check "UbjTodayPanel.qml gates Timer on active && visible" "$(grep -c 'running: root.active && root.visible' "$panel")" "1"
check "KanbanContent.qml wires UbjTodayPanel with active guard" "$(grep -c 'active: root.active && root.viewMode === "ubj"' "$kanban")" "1"

python3 - "$helper" <<'PY'
import http.server, json, os, socketserver, subprocess, sys, tempfile, threading

helper = sys.argv[1]
secret = "ubj-secret-test-key-999"

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        if self.headers.get("X-API-Key") != secret:
            self.send_response(401)
            self.end_headers()
            return
        if self.path.startswith("/api/office"):
            payload = {
                "totals": {"working": 2, "waiting_on_user": 1, "stalled": 0, "failing_checks": 1, "unpushed_projects": 1, "rooms": 2},
                "rooms": [
                    {"name": "UseBestJudgement", "waiting_on_user": 1, "check": "passing", "git": {"unpushed": 0}},
                    {"name": "ruixen-shell", "waiting_on_user": 0, "check": "failing", "git": {"unpushed": 2}},
                ],
                "archive": [],
            }
        elif self.path.startswith("/api/autonomy/priorities"):
            payload = {
                "policy": {"compute_distribution_mode": "quota_weighted"},
                "supply": {
                    "admission": {"status": "disabled", "detail": "Nightly autonomy disabled"},
                    "budget": {"remaining": 1, "total": 2},
                    "agents": {"eligible": ["claude"], "headroom": {"claude": 97.0}},
                },
                "allocation": {
                    "allocated": [{"slot": 1, "wave": 1, "project_name": "UseBestJudgement", "assigned_agent": "claude", "title": "Fix quiescence"}],
                },
            }
        else:
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as srv:
    port = srv.server_address[1]
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    with tempfile.TemporaryDirectory() as tmp:
        cfg_path = os.path.join(tmp, "config.json")
        with open(cfg_path, "w") as fh:
            json.dump({"api_port": port, "api_key": secret}, fh)
        env = {**os.environ, "UBJ_CONFIG_PATH": cfg_path}
        out = subprocess.check_output(["python3", helper], env=env, text=True)
        assert secret not in out, "API key leaked into stdout!"
        data = json.loads(out)
        assert data["online"] is True, data
        assert data["summary"]["waiting_on_user"] == 1
        assert len(data["attention"]) == 3
        assert data["compute"]["eligible_agents"] == ["claude (97%)"]
        assert data["compute"]["slots"][0]["agent"] == "claude"

        # Bad key returns offline cleanly without leaking secret
        with open(cfg_path, "w") as fh:
            json.dump({"api_port": port, "api_key": "wrong-key"}, fh)
        out_401 = subprocess.check_output(["python3", helper], env=env, text=True)
        d401 = json.loads(out_401)
        assert d401["online"] is False
        assert "401" in d401["error"]
    srv.shutdown()

# Offline port degrades cleanly
env_off = {**os.environ, "UBJ_CONFIG_PATH": "/nonexistent/ubj/config.json", "UBJ_API_PORT": "1"}
out_off = subprocess.check_output(["python3", helper], env=env_off, text=True)
doff = json.loads(out_off)
assert doff["online"] is False
assert "offline" in doff["error"].lower()
print("  PASS  ubj-today.py authenticated online, 401, and offline paths")
PY

printf '%d passed, %d failed\n' "$pass" "$fail"
exit "$fail"
