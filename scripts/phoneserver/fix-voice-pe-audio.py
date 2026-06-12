#!/usr/bin/env python3
"""Fix Voice PE TTS cutoff: HA internal URL + short Groq replies for voice."""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path

CONFIG = Path("/opt/homeassistant/config/.storage")
CORE = CONFIG / "core.config"
ENTRIES = CONFIG / "core.config_entries"
GROQ_ENTRY = "01KTVY5V5Y3M66AQWZK8VQ3K6K"
HA_INTERNAL_URL = os.environ.get("HA_INTERNAL_URL", "http://192.168.50.127:8123")

GROQ_PROMPT = """Ты голосовой помощник. Отвечай по-русски.
Максимум 1–2 коротких предложения, до 15 слов. Полный ответ, не обрывай мысль на полуслове.
Анекдот — только короткий (setup + punchline в двух фразах), без длинных историй.
Не представляйся. Управляй домом когда просят."""

GROQ_OPTIONS = {
    "chat_model": "llama-3.3-70b-versatile",
    "llm_hass_api": ["assist"],
    "max_tokens": 50,
    "prompt": GROQ_PROMPT,
    "temperature": 0.4,
    "top_p": 1.0,
}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> None:
    core = json.loads(CORE.read_text(encoding="utf-8"))
    core["data"]["internal_url"] = HA_INTERNAL_URL
    CORE.write_text(json.dumps(core, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    entries = json.loads(ENTRIES.read_text(encoding="utf-8"))
    ok = False
    for entry in entries["data"]["entries"]:
        if entry.get("entry_id") == GROQ_ENTRY:
            entry["options"] = GROQ_OPTIONS
            entry["modified_at"] = now_iso()
            ok = True
    if not ok:
        raise SystemExit("Groq entry not found")
    ENTRIES.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"OK: internal_url={HA_INTERNAL_URL}, groq max_tokens=50, short-joke prompt")


if __name__ == "__main__":
    main()
