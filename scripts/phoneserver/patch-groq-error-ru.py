#!/usr/bin/env python3
from pathlib import Path

p = Path("/opt/homeassistant/config/custom_components/groq_cloud_api/conversation.py")
text = p.read_text(encoding="utf-8")
old = 'f"Sorry, I had a problem talking to Groq: {err}"'
new = '"Извини, Groq сейчас недоступен. Попробуй через минуту."'
if old not in text:
    raise SystemExit("pattern not found")
p.write_text(text.replace(old, new), encoding="utf-8")
print("OK: groq error message -> Russian")
