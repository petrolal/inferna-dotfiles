#!/usr/bin/python3
"""Omarchy's Codex usage collector with a fixed RPC reader.

Upstream (`/usr/share/omarchy/bin/omarchy-agent-usage-codex`) waits on
select() but reads with the buffered TextIOWrapper.readline(). When Codex sends
the account/read reply in the same chunk as its notifications, the reply sits in
Python's buffer while select() sees an empty pipe, so the call times out and the
panel shows "account/read". This wrapper reuses the upstream module unchanged
and only swaps rpc_request for one that reads the raw fd and keeps its own line
buffer. Remove it once Omarchy ships a fix.

It also adds `resetCredits` {available, credits[]} to the record: the banked
"Full reset" credits that the same account/rateLimits/read reply carries.
codex-reset.py redeems one.
"""
import importlib.util
import json
import os
import select
import sys
import time
from importlib.machinery import SourceFileLoader

core_dir = os.environ.get("INFERNA_PATH") or os.environ.get("OMARCHY_PATH") or (os.path.expanduser("~") + "/inferna-dotfiles/core")
UPSTREAM = os.path.join(core_dir, "bin/inferna-agent-usage-codex")
if not os.path.exists(UPSTREAM):
    UPSTREAM = os.path.join(core_dir, "bin/omarchy-agent-usage-codex")
spec = importlib.util.spec_from_loader("omarchy_codex_usage", SourceFileLoader("omarchy_codex_usage", UPSTREAM))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

_buffers = {}


def rpc_request(proc, request_id, method, params=None, timeout=8):
  payload = {"id": request_id, "method": method, "params": params or {}}
  proc.stdin.write(json.dumps(payload) + "\n")
  proc.stdin.flush()
  fd = proc.stdout.fileno()
  buf = _buffers.setdefault(id(proc), b"")
  deadline = time.time() + timeout
  while True:
    while b"\n" in buf:
      line, buf = buf.split(b"\n", 1)
      try:
        message = json.loads(line)
      except Exception:
        continue
      if message.get("id") == request_id:
        _buffers[id(proc)] = buf
        return message
    remaining = deadline - time.time()
    if remaining <= 0:
      break
    ready, _, _ = select.select([fd], [], [], min(0.25, remaining))
    if not ready:
      continue
    chunk = os.read(fd, 65536)
    if not chunk:
      break
    buf += chunk
  _buffers[id(proc)] = buf
  raise TimeoutError(method)


_last_results = {}


def recording_rpc_request(proc, request_id, method, params=None, timeout=8):
  message = rpc_request(proc, request_id, method, params, timeout)
  _last_results[method] = message.get("result") or {}
  return message


def reset_credits_summary(result):
  """Banked rate-limit resets ("Full reset" credits) from account/rateLimits/read."""
  raw = result.get("rateLimitResetCredits")
  if not isinstance(raw, dict):
    return None
  credits = []
  for credit in raw.get("credits") or []:
    if not isinstance(credit, dict) or credit.get("status") not in (None, "available"):
      continue
    credits.append({
      "id": str(credit.get("id") or ""),
      "title": str(credit.get("title") or "Full reset"),
      "description": str(credit.get("description") or ""),
      "grantedAt": credit.get("grantedAt"),
      "expiresAt": credit.get("expiresAt"),
    })
  return {"available": int(raw.get("availableCount") or 0), "credits": credits}


_upstream_fetch = mod.fetch_codex_rpc


def fetch_codex_rpc():
  _last_results.clear()
  result = _upstream_fetch()
  summary = reset_credits_summary(_last_results.get("account/rateLimits/read") or {})
  if summary is not None:
    result["resetCredits"] = summary
  return result


mod.rpc_request = recording_rpc_request
mod.fetch_codex_rpc = fetch_codex_rpc

if __name__ == "__main__":
  sys.argv[0] = UPSTREAM
  mod.main()
