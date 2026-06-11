#!/usr/bin/env python3
"""Fix Yandex TTS mid-sentence cutoff: enable long-text mode + shorter Groq replies."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

CONFIG = Path("/opt/homeassistant/config/.storage")
ENTRIES = CONFIG / "core.config_entries"
GROQ_ENTRY = "01KTVY5V5Y3M66AQWZK8VQ3K6K"
YANDEX_ENTRY = "01KTW0ACXXY0ES9PDKF0WP6YSV"

GROQ_PROMPT = """Ты голосовой помощник. Отвечай по-русски.
Один короткий ответ: максимум 1–2 предложения, до 20 слов. Без списков и без длинных пояснений.
На анекдот — короткий анекдот, не представляйся.
Управляй домом когда просят."""

GROQ_OPTIONS = {
    "chat_model": "llama-3.3-70b-versatile",
    "llm_hass_api": ["assist"],
    "max_tokens": 80,
    "prompt": GROQ_PROMPT,
    "temperature": 0.5,
    "top_p": 1.0,
}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> None:
    data = json.loads(ENTRIES.read_text(encoding="utf-8"))
    groq_ok = yandex_ok = False
    for entry in data["data"]["entries"]:
        if entry.get("entry_id") == GROQ_ENTRY:
            entry["options"] = GROQ_OPTIONS
            entry["modified_at"] = now_iso()
            groq_ok = True
        if entry.get("entry_id") == YANDEX_ENTRY:
            entry["options"] = {**entry.get("options", {}), "tts_unsafe": True}
            entry["modified_at"] = now_iso()
            yandex_ok = True
    if not groq_ok or not yandex_ok:
        raise SystemExit(f"missing entry groq={groq_ok} yandex={yandex_ok}")
    ENTRIES.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("OK: yandex tts_unsafe=true, groq max_tokens=80, shorter prompt")


if __name__ == "__main__":
    main()
