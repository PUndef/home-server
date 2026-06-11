#!/usr/bin/env python3
"""Deprecated: use switch-yandex-pipeline.py (STT + TTS)."""
from __future__ import annotations

import json
from pathlib import Path

CONFIG = Path("/opt/homeassistant/config/.storage")
PIPELINE = CONFIG / "assist_pipeline.pipelines"
REGISTRY = CONFIG / "core.entity_registry"
PIPELINE_ID = "01ktvvbj6y54nvp648kmsmny4r"
VOICE = "marina"  # ru-RU neural; alternatives: alena, filipp, dasha


def main() -> None:
    reg = json.loads(REGISTRY.read_text(encoding="utf-8"))
    tts_entity = None
    for ent in reg["data"]["entities"]:
        if ent.get("platform") == "yandex_speechkit" and ent.get("entity_id", "").startswith("tts."):
            tts_entity = ent["entity_id"]
            break
    if not tts_entity:
        raise SystemExit(
            "Yandex SpeechKit TTS not found. Add integration in HA UI first, then rerun."
        )

    pipeline = json.loads(PIPELINE.read_text(encoding="utf-8"))
    for item in pipeline["data"]["items"]:
        if item.get("id") == PIPELINE_ID:
            item["tts_engine"] = tts_entity
            item["tts_language"] = "ru-RU"
            item["tts_voice"] = VOICE
            break
    else:
        raise SystemExit(f"Pipeline {PIPELINE_ID} not found")

    PIPELINE.write_text(json.dumps(pipeline, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"OK: TTS -> {tts_entity} voice={VOICE}")


if __name__ == "__main__":
    main()
