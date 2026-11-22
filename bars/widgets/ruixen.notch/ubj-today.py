#!/usr/bin/env python3
"""Read-only UBJ Today & Attention snapshot helper for Ruixen Notch.

Reads local UBJ config (~/.config/UseBestJudgment/config.json or UBJ_CONFIG_PATH)
for api_port and api_key, queries localhost /api/office and /api/autonomy/priorities
with strict loopback-only, no-proxy, no-redirect GET requests, and prints a
compact JSON summary to stdout. Never prints or echoes api_key.

Optional endpoints (/api/autonomy/priorities, /api/backlog/board) use a shorter
per-request timeout (OPTIONAL_TIMEOUT) so a slow optional endpoint degrades to an
empty section instead of stalling the panel.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request


OFFICE_TIMEOUT = 3.0
OPTIONAL_TIMEOUT = 2.0


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, "redirects refused", headers, fp)


def _config_path() -> str:
    override = os.environ.get("UBJ_CONFIG_PATH")
    if override:
        return override
    xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(xdg, "UseBestJudgment", "config.json")


def _load_connection() -> tuple[int, str]:
    port = 7742
    api_key = ""
    path = _config_path()
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                cfg = json.load(fh)
            if isinstance(cfg, dict):
                try:
                    p = int(cfg.get("api_port") or 7742)
                    if 1 <= p <= 65535:
                        port = p
                except (TypeError, ValueError):
                    pass
                api_key = str(cfg.get("api_key") or "").strip()
        except (OSError, ValueError):
            pass
    env_port = os.environ.get("UBJ_API_PORT")
    if env_port:
        try:
            p = int(env_port)
            if 1 <= p <= 65535:
                port = p
        except ValueError:
            pass
    return port, api_key


def _get_json(port: int, api_key: str, path: str, timeout: float = OFFICE_TIMEOUT) -> dict:
    url = f"http://127.0.0.1:{port}{path}"
    headers = {"Accept": "application/json"}
    if api_key:
        headers["X-API-Key"] = api_key
    req = urllib.request.Request(url, headers=headers, method="GET")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())
    with opener.open(req, timeout=timeout) as resp:
        raw = resp.read(512 * 1024)
    data = json.loads(raw.decode("utf-8", errors="replace"))
    return data if isinstance(data, dict) else {}


def _scrub(text: str, api_key: str) -> str:
    out = str(text or "")
    if api_key and api_key in out:
        out = out.replace(api_key, "[redacted]")
    return out[:200]


def build_snapshot() -> dict:
    port, api_key = _load_connection()
    try:
        office = _get_json(port, api_key, "/api/office?days=7")
    except urllib.error.HTTPError as exc:
        msg = "UBJ rejected API key (HTTP 401)" if exc.code == 401 else f"UBJ returned HTTP {exc.code}"
        return {"online": False, "error": _scrub(msg, api_key), "summary": {}, "attention": [], "compute": {}}
    except Exception as exc:
        return {
            "online": False,
            "error": _scrub(f"UBJ offline on 127.0.0.1:{port} ({type(exc).__name__})", api_key),
            "summary": {},
            "attention": [],
            "compute": {},
        }

    totals = office.get("totals") if isinstance(office.get("totals"), dict) else {}
    summary = {
        "working": int(totals.get("working") or 0),
        "waiting_on_user": int(totals.get("waiting_on_user") or 0),
        "stalled": int(totals.get("stalled") or 0),
        "failing_checks": int(totals.get("failing_checks") or 0),
        "unpushed_projects": int(totals.get("unpushed_projects") or 0),
        "rooms": int(totals.get("rooms") or 0),
    }

    attention: list[dict] = []
    for room in office.get("rooms") or ():
        if not isinstance(room, dict):
            continue
        name = str(room.get("name") or room.get("project_id") or "Project")[:48]
        waiting = int(room.get("waiting_on_user") or 0)
        if waiting > 0:
            attention.append({
                "kind": "waiting",
                "project": name,
                "detail": f"{waiting} session{'s' if waiting != 1 else ''} waiting on you",
            })
        if room.get("check") == "failing":
            attention.append({
                "kind": "failing",
                "project": name,
                "detail": "verification check failing",
            })
        git = room.get("git") if isinstance(room.get("git"), dict) else {}
        unpushed = int(git.get("unpushed") or 0)
        if unpushed > 0:
            attention.append({
                "kind": "unpushed",
                "project": name,
                "detail": f"{unpushed} unpushed commit{'s' if unpushed != 1 else ''}",
            })
    for cab in office.get("archive") or ():
        if not isinstance(cab, dict):
            continue
        name = str(cab.get("name") or cab.get("project_id") or "Project")[:48]
        if cab.get("check") == "failing":
            attention.append({
                "kind": "failing",
                "project": name,
                "detail": "verification check failing",
            })
        unpushed = int(cab.get("unpushed") or 0)
        if unpushed > 0:
            attention.append({
                "kind": "unpushed",
                "project": name,
                "detail": f"{unpushed} unpushed commit{'s' if unpushed != 1 else ''}",
            })

    compute: dict = {}
    try:
        pri = _get_json(port, api_key, "/api/autonomy/priorities?limit=5", timeout=OPTIONAL_TIMEOUT)
        pol = pri.get("policy") if isinstance(pri.get("policy"), dict) else {}
        sup = pri.get("supply") if isinstance(pri.get("supply"), dict) else {}
        alloc = pri.get("allocation") if isinstance(pri.get("allocation"), dict) else {}
        budget = sup.get("budget") if isinstance(sup.get("budget"), dict) else {}
        agents = sup.get("agents") if isinstance(sup.get("agents"), dict) else {}
        adm = sup.get("admission") if isinstance(sup.get("admission"), dict) else {}
        hm = agents.get("headroom") if isinstance(agents.get("headroom"), dict) else {}
        elig = [
            f"{a} ({int(round(float(hm[a])))}%)" if a in hm else str(a)
            for a in (agents.get("eligible") or ())
        ]
        slots = [
            {
                "slot": int(s.get("slot") or 0),
                "wave": int(s.get("wave") or 1),
                "project": str(s.get("project_name") or s.get("project_id") or "")[:40],
                "agent": str(s.get("assigned_agent") or "none"),
                "title": str(s.get("title") or "")[:72],
            }
            for s in (alloc.get("allocated") or ())[:4]
            if isinstance(s, dict)
        ]
        compute = {
            "mode": str(pol.get("compute_distribution_mode") or "quota_weighted"),
            "admission": str(adm.get("detail") or adm.get("status") or ""),
            "budget_remaining": int(budget.get("remaining") or 0),
            "budget_total": int(budget.get("total") or 0),
            "eligible_agents": elig,
            "slots": slots,
        }
    except Exception:
        compute = {}

    backlog: dict = {}
    try:
        bd = _get_json(port, api_key, "/api/backlog/board", timeout=OPTIONAL_TIMEOUT)
        counts = bd.get("counts") if isinstance(bd.get("counts"), dict) else {}
        cols = bd.get("columns") if isinstance(bd.get("columns"), dict) else {}
        flagged = sum(
            1 for col_list in cols.values() if isinstance(col_list, list)
            for c in col_list if isinstance(c, dict) and c.get("flagged")
        )
        backlog = {
            "ready": int(counts.get("ready") or 0),
            "blocked": int(counts.get("blocked") or 0),
            "held": int(counts.get("held") or 0),
            "in_progress": int(counts.get("in_progress") or 0),
            "done": int(counts.get("done") or 0),
            "flagged": flagged,
        }
    except Exception:
        backlog = {}

    return {
        "online": True,
        "error": "",
        "summary": summary,
        "attention": attention[:6],
        "compute": compute,
        "backlog": backlog,
    }


def main() -> int:
    print(json.dumps(build_snapshot(), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
