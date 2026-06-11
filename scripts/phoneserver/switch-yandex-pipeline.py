#!/usr/bin/env python3
"""Point Voice Assistant to Yandex SpeechKit STT + TTS. Run after API key in HA UI."""
from __future__ import annotations

import json
from pathlib import Path

CONFIG = Path("/opt/homeassistant/config/.storage")
PIPELINE = CONFIG / "assist_pipeline.pipelines"
REGISTRY = CONFIG / "core.entity_registry"
PIPELINE_ID = "01ktvvbj6y54nvp648kmsmny4r"
VOICE = "marina"


def find_entity(reg: dict, prefix: str) -> str | None:
    for ent in reg["data"]["entities"]:
        if ent.get("platform") == "yandex_speechkit" and ent.get("entity_id", "").startswith(
            f"{prefix}."
        ):
            return ent["entity_id"]
    return None


def main() -> None:
    reg = json.loads(REGISTRY.read_text(encoding="utf-8"))
    stt_entity = find_entity(reg, "stt")
    tts_entity = find_entity(reg, "tts")
    if not stt_entity or not tts_entity:
        raise SystemExit(
            f"Yandex SpeechKit missing: stt={stt_entity!r} tts={tts_entity!r}. Add integration first."
        )

    pipeline = json.loads(PIPELINE.read_text(encoding="utf-8"))
    for item in pipeline["data"]["items"]:
        if item.get("id") == PIPELINE_ID:
            item["stt_engine"] = stt_entity
            item["stt_language"] = "ru-RU"
            item["tts_engine"] = tts_entity
            item["tts_language"] = "ru-RU"
            item["tts_voice"] = VOICE
            item["prefer_local_intents"] = True
            break
    else:
        raise SystemExit(f"Pipeline {PIPELINE_ID} not found")

    PIPELINE.write_text(json.dumps(pipeline, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"OK: STT -> {stt_entity} (ru-RU); TTS -> {tts_entity} voice={VOICE}")


if __name__ == "__main__":
    main()
