#!/usr/bin/env python3
import json
import urllib.error
import urllib.request
from pathlib import Path

entries = json.loads(Path("/opt/homeassistant/config/.storage/core.config_entries").read_text())
key = next(
    e["data"]["api_key"]
    for e in entries["data"]["entries"]
    if e["domain"] == "groq_cloud_api"
)

req0 = urllib.request.Request(
    "https://api.groq.com/openai/v1/models",
    headers={"Authorization": f"Bearer {key}"},
)
try:
    with urllib.request.urlopen(req0, timeout=20) as r:
        print(f"models.list: OK {r.status}")
except urllib.error.HTTPError as e:
    print(f"models.list: FAIL {e.code} {e.read().decode()[:400]}")

for model in ("llama-3.3-70b-versatile", "llama-3.1-8b-instant"):
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": "привет"}],
            "max_tokens": 20,
        }
    ).encode()
    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            print(f"{model}: OK {r.status}")
    except urllib.error.HTTPError as e:
        print(f"{model}: FAIL {e.code} {e.read().decode()[:400]}")
