#!/usr/bin/env bash
set -euo pipefail
image=${1:?usage: smoke-container.sh IMAGE EXPECTED_VERSION}
expected=${2:?expected version required}
container=$(docker run -d --read-only --cap-drop=ALL --security-opt=no-new-privileges -p 127.0.0.1::8000 "$image")
cleanup() { docker logs "$container"; docker rm -f "$container" >/dev/null; }
trap cleanup EXIT
port=$(docker port "$container" 8000/tcp | awk -F: '{print $NF}')
python3 - "$port" "$expected" <<'PY'
import http.client
import json
import sys
import time
import urllib.error
import urllib.request

base = f"http://127.0.0.1:{sys.argv[1]}"
for attempt in range(60):
    try:
        with urllib.request.urlopen(base + "/health", timeout=2) as response:
            assert response.status == 200
            assert json.load(response) == {"status": "ok"}
        break
    except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.HTTPException):
        time.sleep(1)
else:
    raise SystemExit("Container never became ready")
with urllib.request.urlopen(base + "/version", timeout=2) as response:
    assert response.status == 200
    assert json.load(response) == {"version": sys.argv[2]}
print("Container health and baked-in release version passed")
PY
uid=$(docker exec "$container" id -u)
test "$uid" = 10001
printf 'Container runs as UID %s\n' "$uid"
