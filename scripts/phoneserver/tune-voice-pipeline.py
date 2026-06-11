#!/usr/bin/env python3
"""DEPRECATED: production uses Yandex STT/TTS — see docs/phoneserver/voice-assistant.md."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

CONFIG = Path("/opt/homeassistant/config/.storage")
PIPELINE = CONFIG / "assist_pipeline.pipelines"
ENTRIES = CONFIG / "core.config_entries"

GROQ_ENTRY = "01KTVY5V5Y3M66AQWZK8VQ3K6K"
PIPELINE_ID = "01ktvvbj6y54nvp648kmsmny4r"

GROQ_PROMPT = """Ты голосовой помощник. Всегда отвечай по-русски, одним-двумя короткими предложениями.
На просьбу рассказать анекдот, шутку или историю — рассказывай, не объясняй кто ты.
Не представляйся и не говори что ты связан с умным домом, если об этом не спрашивают.
Управляй домом когда просят; на свободные вопросы отвечай по существу."""

GROQ_OPTIONS = {
    "chat_model": "llama-3.3-70b-versatile",
    "llm_hass_api": ["assist"],
    "max_tokens": 120,
    "prompt": GROQ_PROMPT,
    "temperature": 0.5,
    "top_p": 1.0,
}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def remove_edge_tts(entries: dict) -> None:
    entries["data"]["entries"] = [
        e for e in entries["data"]["entries"] if e.get("domain") != "edge_tts"
    ]


def tune_groq(entries: dict) -> None:
    for entry in entries["data"]["entries"]:
        if entry.get("entry_id") == GROQ_ENTRY and entry.get("domain") == "groq_cloud_api":
            entry["options"] = GROQ_OPTIONS
            entry["modified_at"] = now_iso()
            return
    raise SystemExit(f"Groq entry {GROQ_ENTRY} not found")


def tune_pipeline(pipeline: dict) -> None:
    for item in pipeline["data"]["items"]:
        if item.get("id") == PIPELINE_ID:
            item["tts_engine"] = "tts.piper"
            item["tts_language"] = "ru_RU"
            item["tts_voice"] = "ru_RU-irina-medium"
            item["prefer_local_intents"] = True
            return
    raise SystemExit(f"Pipeline {PIPELINE_ID} not found")


def main() -> None:
    pipeline = load(PIPELINE)
    entries = load(ENTRIES)
    remove_edge_tts(entries)
    tune_groq(entries)
    tune_pipeline(pipeline)
    save(ENTRIES, entries)
    save(PIPELINE, pipeline)
    print("OK: Groq 70b + Piper irina + prompt fixed")


if __name__ == "__main__":
    main()
