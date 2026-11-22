#!/usr/bin/env python3
"""Inferna AI Telemetry Collector (Claude Code, Antigravity, Ollama).

Writes an atomic, display-ready JSON snapshot to ~/.cache/inferna-ai/usage.json
for the GNOME 51 `ai-telemetry@inferna` top-bar extension, and supports
`--pretty` for a quick Inferna-colored terminal summary.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

CACHE_DIR = Path.home() / ".cache" / "inferna-ai"
OUT_FILE = CACHE_DIR / "usage.json"
LIMITS_CACHE_FILE = CACHE_DIR / "limits-cache.json"

CLAUDE_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
AGY_CLOUD_CODE_URL = "https://daily-cloudcode-pa.googleapis.com"
OLLAMA_BALANCE_URL = "https://ollama.com/api/balance"

DEFAULT_COOLDOWN_SEC = 180


def now_ms() -> int:
    return int(time.time() * 1000)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def write_json_atomic(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, path)


def parse_iso_time(raw: Any) -> dt.datetime | None:
    if not raw or not isinstance(raw, str):
        return None
    text = raw.strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(text)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc)
    except Exception:
        return None


def http_json(url: str, headers: dict[str, str], body: dict[str, Any] | None = None, timeout: int = 8) -> tuple[int, Any, str]:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(raw) if raw.strip() else {}, ""
    except urllib.error.HTTPError as err:
        return err.code, None, str(err.reason or err.code)
    except Exception as err:
        return 0, None, str(err)


def clamp_pct(val: Any) -> int | None:
    if val is None or isinstance(val, bool):
        return None
    try:
        num = float(val)
    except Exception:
        return None
    if not math.isfinite(num):
        return None
    # Anthropic returns 0..100 (occasionally 0..1); normalize cleanly
    if 0.0 < num <= 1.0:
        # Leave 1.0 as 1% only if clearly 0..100, caller handles scale explicitly
        pass
    return int(max(0, min(100, round(num))))


def format_reset_delta(iso_str: str) -> str:
    target = parse_iso_time(iso_str)
    if not target:
        return ""
    secs = int((target - dt.datetime.now(dt.timezone.utc)).total_seconds())
    if secs <= 0:
        return "agora"
    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    mins = rem // 60
    if days > 0:
        return f"{days}d {hours}h"
    if hours > 0:
        return f"{hours}h {mins:02d}m"
    return f"{max(1, mins)}m"


# ---------------------------------------------------------------------------
# 1) Claude Code collector
# ---------------------------------------------------------------------------
def scan_claude_local(claude_dir: Path) -> dict[str, Any]:
    now = time.time()
    today_start = dt.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    week_start = now - 7 * 86400
    sessions_today = 0
    sessions_week = 0
    prompts_today = 0
    prompts_week = 0

    projects = claude_dir / "projects"
    if projects.is_dir():
        for path in projects.rglob("*.jsonl"):
            try:
                st = path.stat()
            except OSError:
                continue
            if st.st_mtime < week_start:
                continue
            sessions_week += 1
            if st.st_mtime >= today_start:
                sessions_today += 1

    history = claude_dir / "history.jsonl"
    if history.is_file():
        try:
            with history.open("r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except Exception:
                        continue
                    ts = rec.get("timestamp")
                    if isinstance(ts, (int, float)):
                        ts_s = ts / 1000.0 if ts > 1e12 else float(ts)
                        if ts_s >= week_start:
                            prompts_week += 1
                            if ts_s >= today_start:
                                prompts_today += 1
        except OSError:
            pass

    return {
        "sessionsToday": sessions_today,
        "sessionsWeek": sessions_week,
        "promptsToday": prompts_today,
        "promptsWeek": prompts_week,
    }


def collect_claude(cache: dict[str, Any], force: bool) -> dict[str, Any]:
    claude_dir = Path.home() / ".claude"
    installed = shutil.which("claude") is not None or claude_dir.is_dir()
    local = scan_claude_local(claude_dir)

    creds = read_json(claude_dir / ".credentials.json") or {}
    oauth = creds.get("claudeAiOauth") if isinstance(creds, dict) else None
    access_token = str(oauth.get("accessToken") or "") if isinstance(oauth, dict) else ""
    sub_type = str(oauth.get("subscriptionType") or "") if isinstance(oauth, dict) else ""
    rate_tier = str(oauth.get("rateLimitTier") or "") if isinstance(oauth, dict) else ""

    plan = ""
    low_tier = f"{sub_type} {rate_tier}".lower()
    if "max" in low_tier:
        plan = "Max"
    elif "pro" in low_tier:
        plan = "Pro"
    elif "team" in low_tier:
        plan = "Team"
    elif "enterprise" in low_tier:
        plan = "Enterprise"
    elif sub_type:
        plan = sub_type.capitalize()

    prev = cache.get("claude") if isinstance(cache.get("claude"), dict) else {}
    age_s = (now_ms() - int(prev.get("fetchedAtMs") or 0)) / 1000.0
    limits = prev.get("limits") if isinstance(prev.get("limits"), list) else []
    status = "ok"
    note = ""

    if not access_token:
        status = "no_auth"
        note = "Execute `claude auth login` para exibir limites."
    elif not force and limits and age_s < DEFAULT_COOLDOWN_SEC:
        status = "cached"
    else:
        code, payload, err = http_json(
            CLAUDE_USAGE_URL,
            headers={
                "Authorization": f"Bearer {access_token}",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
                "User-Agent": "inferna-ai-telemetry/1.0",
            },
            timeout=8,
        )
        if code == 200 and isinstance(payload, dict):
            parsed: list[dict[str, Any]] = []
            for key, label in [
                ("five_hour", "Sessão 5h"),
                ("seven_day", "Semanal 7d"),
                ("seven_day_opus", "Opus 7d"),
                ("seven_day_sonnet", "Sonnet 7d"),
            ]:
                bucket = payload.get(key)
                if not isinstance(bucket, dict):
                    continue
                util = bucket.get("utilization")
                if util is None or isinstance(util, bool):
                    continue
                try:
                    uval = float(util)
                except Exception:
                    continue
                if not math.isfinite(uval):
                    continue
                pct = int(max(0, min(100, math.floor(uval))))
                if key in ("seven_day_opus", "seven_day_sonnet") and pct <= 0:
                    continue
                resets_at = ""
                parsed_reset = parse_iso_time(bucket.get("resets_at"))
                if parsed_reset:
                    resets_at = parsed_reset.isoformat()
                parsed.append({
                    "label": label,
                    "percent": pct,
                    "resetsAt": resets_at,
                    "resetsIn": format_reset_delta(resets_at),
                })
            if parsed:
                limits = parsed
                cache["claude"] = {"fetchedAtMs": now_ms(), "limits": limits}
                status = "live"
            else:
                status = "stale" if limits else "empty"
                note = "Sem janelas de limite retornadas."
        elif code == 429:
            status = "stale" if limits else "rate_limited"
            note = "Rate limit da API de uso (mostrando último valor)."
        elif code in (401, 403):
            status = "expired"
            note = "Sessão expirada — abra `claude` ou rode `claude auth login`."
        else:
            status = "stale" if limits else "offline"
            note = f"Falha ao consultar API ({err or code})."

    # Refresh relative countdown strings even on cached limits
    for lim in limits:
        lim["resetsIn"] = format_reset_delta(lim.get("resetsAt", ""))

    return {
        "id": "claude",
        "name": "Claude Code",
        "installed": installed,
        "plan": plan,
        "status": status,
        "note": note,
        "launchCmd": "ghostty -e claude",
        "limits": limits,
        "local": local,
    }


# ---------------------------------------------------------------------------
# 2) Antigravity (agy) collector
# ---------------------------------------------------------------------------
def scan_agy_local(agy_dir: Path) -> dict[str, Any]:
    now = time.time()
    today_start = dt.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    week_start = now - 7 * 86400
    sessions_today = 0
    sessions_week = 0

    brain = agy_dir / "brain"
    if brain.is_dir():
        for entry in brain.iterdir():
            if not entry.is_dir():
                continue
            try:
                mt = entry.stat().st_mtime
                # Check newest transcript log inside conversation if present
                log = entry / ".system_generated" / "logs" / "transcript.jsonl"
                if log.is_file():
                    mt = max(mt, log.stat().st_mtime)
            except OSError:
                continue
            if mt >= week_start:
                sessions_week += 1
                if mt >= today_start:
                    sessions_today += 1

    return {
        "sessionsToday": sessions_today,
        "sessionsWeek": sessions_week,
    }


def agy_access_token(agy_dir: Path) -> str:
    data = None
    if shutil.which("secret-tool"):
        try:
            raw = subprocess.check_output(
                ["secret-tool", "lookup", "service", "gemini", "username", "antigravity"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=3,
            )
            if raw.strip():
                data = json.loads(raw)
        except Exception:
            data = None
    if not isinstance(data, dict):
        data = read_json(agy_dir / "antigravity-oauth-token")
    if not isinstance(data, dict):
        return ""
    tok = data.get("token") if isinstance(data.get("token"), dict) else {}
    return str(tok.get("access_token") or data.get("access_token") or "")


def agy_bucket_used_pct(bucket: dict[str, Any]) -> int | None:
    if bucket.get("disabled") is True:
        return None
    rem = bucket.get("remainingFraction", bucket.get("remaining_fraction"))
    amount = bucket.get("remainingAmount", bucket.get("remaining_amount"))
    has_reset = bool(bucket.get("resetTime") or bucket.get("reset_time"))
    if rem is None and amount is not None and amount in (0, "0") and not isinstance(amount, bool):
        return 100
    if rem is None and has_reset:
        return 100
    if rem is None or isinstance(rem, bool):
        return None
    try:
        f = float(rem)
    except Exception:
        return None
    if not math.isfinite(f):
        return None
    return int(max(0, min(100, round((1.0 - f) * 100.0))))


def agy_extract_tier(assist: dict[str, Any]) -> str:
    for key in ("paidTier", "currentTier"):
        tier = assist.get(key)
        if isinstance(tier, dict):
            name = str(tier.get("name") or tier.get("id") or "").strip()
            if name:
                low = name.lower()
                if "ultra" in low:
                    return "Ultra"
                if "pro" in low:
                    return "Pro"
                if "standard" in low or "free" in low:
                    return "Standard"
                return name
    return ""


def collect_agy(cache: dict[str, Any], force: bool) -> dict[str, Any]:
    agy_dir = Path(os.environ.get("AGY_DIR") or (Path.home() / ".gemini" / "antigravity-cli"))
    installed = shutil.which("agy") is not None or agy_dir.is_dir()
    local = scan_agy_local(agy_dir)

    prev = cache.get("agy") if isinstance(cache.get("agy"), dict) else {}
    age_s = (now_ms() - int(prev.get("fetchedAtMs") or 0)) / 1000.0
    limits = prev.get("limits") if isinstance(prev.get("limits"), list) else []
    plan = str(prev.get("plan") or "")
    status = "ok"
    note = ""

    token = agy_access_token(agy_dir)
    if not token:
        status = "no_auth"
        note = "Abra `agy` para autenticar e exibir cotas."
    elif not force and (limits or plan) and age_s < DEFAULT_COOLDOWN_SEC:
        status = "cached"
    else:
        base = (os.environ.get("CLOUD_CODE_URL") or AGY_CLOUD_CODE_URL).rstrip("/")
        if not base.startswith("https://"):
            base = AGY_CLOUD_CODE_URL
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "antigravity",
        }
        code_a, assist, err_a = http_json(f"{base}/v1internal:loadCodeAssist", headers, body={}, timeout=8)
        if code_a == 200 and isinstance(assist, dict):
            plan = agy_extract_tier(assist) or plan
            proj = assist.get("cloudaicompanionProject")
            if isinstance(proj, dict):
                proj = proj.get("id")
            qbody = {"project": proj.strip()} if isinstance(proj, str) and proj.strip() else {}
            code_q, qdata, err_q = http_json(f"{base}/v1internal:retrieveUserQuotaSummary", headers, body=qbody, timeout=8)
            if code_q == 200 and isinstance(qdata, dict) and "error" not in qdata:
                groups = [g for g in (qdata.get("groups") or []) if isinstance(g, dict)]
                if not groups and isinstance(qdata.get("buckets"), list):
                    groups = [{"displayName": "Gemini", "buckets": qdata["buckets"]}]

                parsed: list[dict[str, Any]] = []
                gemini = next((g for g in groups if "gemini" in str(g.get("displayName") or "").lower()), groups[0] if groups else None)
                if gemini and isinstance(gemini.get("buckets"), list):
                    gem_rows: list[tuple[int, dict[str, Any]]] = []
                    for bucket in gemini["buckets"]:
                        if not isinstance(bucket, dict):
                            continue
                        pct = agy_bucket_used_pct(bucket)
                        if pct is None:
                            continue
                        w = str(bucket.get("window") or "").lower()
                        bid = str(bucket.get("bucketId") or "").lower()
                        bname = str(bucket.get("displayName") or "").lower()
                        if w == "5h" or "5h" in bid or "five" in bname:
                            lbl, order = "Sessão 5h", 0
                        elif w == "weekly" or "weekly" in bid or "week" in bname:
                            lbl, order = "Semanal 7d", 1
                        else:
                            lbl, order = str(bucket.get("displayName") or "Gemini").strip(), 2
                        rt = parse_iso_time(bucket.get("resetTime") or bucket.get("reset_time"))
                        r_iso = rt.isoformat() if rt else ""
                        gem_rows.append((order, {"label": lbl, "percent": pct, "resetsAt": r_iso, "resetsIn": format_reset_delta(r_iso)}))
                    gem_rows.sort(key=lambda pair: pair[0])
                    parsed.extend(item for _, item in gem_rows)

                for grp in groups:
                    if grp is gemini:
                        continue
                    gname = str(grp.get("displayName") or "").strip()
                    short = "Claude/GPT" if "claude" in gname.lower() else (gname or "3P")
                    for bucket in (grp.get("buckets") or []):
                        if not isinstance(bucket, dict):
                            continue
                        pct = agy_bucket_used_pct(bucket)
                        if pct is None or pct <= 0:
                            continue
                        w = str(bucket.get("window") or "").lower()
                        lbl = f"{short} {'7d' if 'week' in w else '5h'}"
                        rt = parse_iso_time(bucket.get("resetTime") or bucket.get("reset_time"))
                        r_iso = rt.isoformat() if rt else ""
                        parsed.append({"label": lbl, "percent": pct, "resetsAt": r_iso, "resetsIn": format_reset_delta(r_iso)})

                limits = parsed
                cache["agy"] = {"fetchedAtMs": now_ms(), "limits": limits, "plan": plan}
                status = "live"
            elif code_q in (401, 403):
                status = "expired"
                note = "Token expirado — abra `agy` para renovar."
            else:
                status = "stale" if limits else "offline"
                note = f"Cota indisponível ({err_q or code_q})."
        elif code_a in (401, 403):
            status = "expired"
            note = "Token expirado — abra `agy` para renovar."
        else:
            status = "stale" if limits else "offline"
            note = f"Serviço indisponível ({err_a or code_a})."

    for lim in limits:
        lim["resetsIn"] = format_reset_delta(lim.get("resetsAt", ""))

    return {
        "id": "agy",
        "name": "Antigravity",
        "installed": installed,
        "plan": plan,
        "status": status,
        "note": note,
        "launchCmd": "ghostty -e agy",
        "limits": limits,
        "local": local,
    }


# ---------------------------------------------------------------------------
# 3) Ollama collector (local daemon + optional Ollama Cloud balance)
# ---------------------------------------------------------------------------
def collect_ollama() -> dict[str, Any]:
    installed = shutil.which("ollama") is not None
    active = False
    try:
        res = subprocess.run(
            ["systemctl", "is-active", "--quiet", "ollama.service"],
            timeout=2,
            check=False,
        )
        active = res.returncode == 0
    except Exception:
        active = False

    loaded_models: list[str] = []
    installed_count = 0
    if active:
        code_ps, ps_data, _ = http_json("http://127.0.0.1:11434/api/ps", headers={}, timeout=2)
        if code_ps == 200 and isinstance(ps_data, dict):
            for m in ps_data.get("models") or []:
                if isinstance(m, dict) and m.get("name"):
                    loaded_models.append(str(m["name"]))
        code_tags, tags_data, _ = http_json("http://127.0.0.1:11434/api/tags", headers={}, timeout=2)
        if code_tags == 200 and isinstance(tags_data, dict):
            installed_count = len(tags_data.get("models") or [])

    note = ""
    if active:
        if loaded_models:
            note = "VRAM: " + ", ".join(loaded_models[:2])
        else:
            note = f"Pronto ({installed_count} modelo{'s' if installed_count != 1 else ''})"
    else:
        note = "Sob demanda (sudo systemctl start ollama)"

    return {
        "id": "ollama",
        "name": "Ollama",
        "installed": installed,
        "plan": "Ativo" if active else "Parado",
        "status": "live" if active else "idle",
        "note": note,
        "launchCmd": "ghostty -e fish -c 'ollama list; exec fish'",
        "limits": [],
        "local": {
            "active": active,
            "loadedModels": loaded_models,
            "installedCount": installed_count,
        },
    }


def print_pretty(snapshot: dict[str, Any]) -> None:
    R = "\x1b[0m"
    B = "\x1b[1m"
    CRIMSON = "\x1b[38;2;200;40;20m"
    EMBER = "\x1b[38;2;255;98;46m"
    GOLD = "\x1b[38;2;242;169;73m"
    IVORY = "\x1b[38;2;245;234;220m"
    MUTED = "\x1b[38;2;148;122;108m"

    print(f"{B}{EMBER}󰈸 Inferna AI Telemetry{R}  {MUTED}({snapshot['updatedAtLocal']}){R}")
    print(f"{CRIMSON}{'─' * 50}{R}")
    for ag in snapshot["agents"]:
        plan = f" {MUTED}[{ag['plan']}]{R}" if ag.get("plan") else ""
        print(f"  {B}{GOLD}{ag['name']}{R}{plan}")
        for lim in ag.get("limits") or []:
            pct = int(lim.get("percent", 0))
            col = CRIMSON if pct >= 85 else (EMBER if pct >= 60 else GOLD)
            filled = round(pct / 10)
            bar = f"{col}{'━' * filled}\x1b[38;2;68;46;38m{'━' * (10 - filled)}{R}"
            rst = f"  {MUTED}reseta em {lim['resetsIn']}{R}" if lim.get("resetsIn") else ""
            print(f"    {IVORY}{lim['label']:<12}{R} {bar} {col}{pct:3d}%{R}{rst}")
        if ag.get("note"):
            print(f"    {MUTED}{ag['note']}{R}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect Inferna AI CLI telemetry.")
    parser.add_argument("--force", action="store_true", help="Bypass rate-limit cache cooldown")
    parser.add_argument("--pretty", action="store_true", help="Print an Inferna summary table to stdout")
    parser.add_argument("--json", action="store_true", help="Print collected JSON to stdout")
    args = parser.parse_args()

    cache = read_json(LIMITS_CACHE_FILE)
    if not isinstance(cache, dict):
        cache = {}

    agents = [
        collect_claude(cache, args.force),
        collect_agy(cache, args.force),
        collect_ollama(),
    ]
    agents = [a for a in agents if a["installed"]]

    max_pct = -1
    max_agent = ""
    for ag in agents:
        for lim in ag.get("limits") or []:
            p = int(lim.get("percent", -1))
            if p > max_pct:
                max_pct = p
                max_agent = ag["id"]

    sessions_today = sum(int((a.get("local") or {}).get("sessionsToday") or 0) for a in agents)
    sessions_week = sum(int((a.get("local") or {}).get("sessionsWeek") or 0) for a in agents)

    snapshot = {
        "updatedAtMs": now_ms(),
        "updatedAtLocal": dt.datetime.now().strftime("%H:%M"),
        "maxPercent": max_pct,
        "maxAgent": max_agent,
        "summary": {
            "sessionsToday": sessions_today,
            "sessionsWeek": sessions_week,
        },
        "agents": agents,
    }

    write_json_atomic(LIMITS_CACHE_FILE, cache)
    write_json_atomic(OUT_FILE, snapshot)

    if args.json:
        print(json.dumps(snapshot, ensure_ascii=False, indent=2))
    elif args.pretty:
        print_pretty(snapshot)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
