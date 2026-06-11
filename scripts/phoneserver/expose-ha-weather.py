#!/usr/bin/env python3
"""Expose Met weather entity to Home Assistant Assist."""
import json
from pathlib import Path

CONFIG = Path("/opt/homeassistant/config/.storage")

exposed_path = CONFIG / "homeassistant.exposed_entities"
with exposed_path.open(encoding="utf-8") as f:
    exposed = json.load(f)

exposed["data"]["exposed_entities"]["weather.forecast_home_assistant"] = {
    "assistants": {"conversation": {"should_expose": True}}
}
with exposed_path.open("w", encoding="utf-8") as f:
    json.dump(exposed, f, indent=2)
print("exposed_entities: weather.forecast_home_assistant -> True")

registry_path = CONFIG / "core.entity_registry"
with registry_path.open(encoding="utf-8") as f:
    registry = json.load(f)

for entity in registry["data"]["entities"]:
    if entity.get("entity_id") == "weather.forecast_home_assistant":
        entity.setdefault("options", {}).setdefault("conversation", {})[
            "should_expose"
        ] = True
        print("entity_registry: weather.forecast_home_assistant -> True")
        break
else:
    raise SystemExit("weather entity not found")

with registry_path.open("w", encoding="utf-8") as f:
    json.dump(registry, f, indent=2)
