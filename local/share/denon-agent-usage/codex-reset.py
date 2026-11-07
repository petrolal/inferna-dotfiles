#!/usr/bin/env python3
"""Redeem one banked Codex rate-limit reset ("Full reset" credit).

Usage: codex-reset.py [CREDIT_ID]
Prints one JSON line: {"outcome": "reset" | "nothingToReset" | "noCredit" |
"alreadyRedeemed"} or {"error": "..."}. Without CREDIT_ID the backend picks the
next available credit. Calls Codex's own app-server
(account/rateLimitResetCredit/consume), the same path the Codex TUI uses.
"""
import importlib.util
import json
import os
import subprocess
import sys
import uuid
from importlib.machinery import SourceFileLoader

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_loader("denon_codex_collector", SourceFileLoader("denon_codex_collector", os.path.join(HERE, "codex-collector.py")))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
mod = collector.mod


def main():
  credit_id = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
  codex = mod.find_command("codex")
  if not codex:
    print(json.dumps({"error": "codex not found in PATH"}))
    return 1
  proc = subprocess.Popen([codex, "-s", "read-only", "-a", "on-request", "app-server"],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=mod.ENV)
  try:
    collector.rpc_request(proc, 1, "initialize", {"clientInfo": {"name": "inferna-agent-usage", "version": "1"}}, timeout=8)
    proc.stdin.write(json.dumps({"method": "initialized", "params": {}}) + "\n")
    proc.stdin.flush()
    params = {"idempotencyKey": str(uuid.uuid4())}
    if credit_id:
      params["creditId"] = credit_id
    reply = collector.rpc_request(proc, 2, "account/rateLimitResetCredit/consume", params, timeout=20)
    if reply.get("error"):
      print(json.dumps({"error": str((reply["error"] or {}).get("message") or reply["error"])}))
      return 1
    print(json.dumps({"outcome": str((reply.get("result") or {}).get("outcome") or "unknown")}))
    return 0
  except Exception as exc:
    print(json.dumps({"error": str(exc) or type(exc).__name__}))
    return 1
  finally:
    try:
      proc.terminate(); proc.wait(timeout=1)
    except Exception:
      proc.kill()


if __name__ == "__main__":
  sys.exit(main())
