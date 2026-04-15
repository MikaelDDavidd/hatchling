#!/bin/bash
# Hatchling statusline wrapper.
#
# Claude Code v2.1.80+ pipes a JSON object on stdin to the configured
# statusline script. That JSON contains `rate_limits.{five_hour,seven_day}`
# with `used_percentage` and `resets_at` — the actual session/weekly usage.
#
# This wrapper:
#   1. Captures stdin JSON
#   2. Persists `rate_limits` (+ session id, model) to ~/.codeisland/rate-limits.json
#   3. Delegates to the user's previous statusline command (saved in
#      ~/.codeisland/statusline-original.cmd at install time), passing the
#      same stdin and forwarding stdout untouched.
#
# Failure-tolerant: any error in the capture step is swallowed so the
# user's statusline keeps working.

set -e

CACHE_DIR="$HOME/.codeisland"
CACHE_FILE="$CACHE_DIR/rate-limits.json"
ORIG_FILE="$CACHE_DIR/statusline-original.cmd"

mkdir -p "$CACHE_DIR" 2>/dev/null || true

INPUT=$(cat)

# Debug: persist raw JSON so we can introspect what Claude Code is actually sending.
# Safe to keep — it's just the most recent payload, ~few KB.
{ printf '%s' "$INPUT" > "$CACHE_DIR/statusline-last-input.json"; } 2>/dev/null || true

# 1. Capture rate_limits (best-effort)
{
  printf '%s' "$INPUT" | /usr/bin/python3 - "$CACHE_FILE" <<'PY' 2>/dev/null || true
import json, sys, time, os
try:
    raw = sys.stdin.read()
    d = json.loads(raw) if raw.strip() else {}
    rl = d.get("rate_limits") or {}
    out = {
        "capturedAt": time.time(),
        "session_id": d.get("session_id"),
        "model": (d.get("model") or {}).get("id") if isinstance(d.get("model"), dict) else d.get("model"),
        "rate_limits": rl,
    }
    path = sys.argv[1]
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(out, f)
    os.replace(tmp, path)
except Exception:
    pass
PY
} || true

# 2. Delegate to the original statusline (if any)
if [ -s "$ORIG_FILE" ]; then
  ORIG_CMD=$(cat "$ORIG_FILE")
  printf '%s' "$INPUT" | bash -c "$ORIG_CMD"
else
  # No previous statusline — print a minimal default so Claude Code
  # has something visible. The user can disable Hatchling capture
  # in Settings if they want a fully blank statusline.
  printf ''
fi
