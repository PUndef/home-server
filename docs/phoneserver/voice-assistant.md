# Голосовой ассистент (Voice PE + HA на phoneserver)

> **Статус:** рабочая конфигурация, 2026-06-11  
> **HA UI:** `http://192.168.1.227:8123/` (eth) · Voice PE: `192.168.1.171`  
> **Скрипты:** [scripts/phoneserver/](../../scripts/phoneserver/README.md)

---

## Сделано (история)

Пункты, которые уже выполнены. Оставлены для истории; в текущем плане не повторять.

| Когда | Что сделано |
|-------|-------------|
| 2026-06 | **HA Container** на phoneserver (`/opt/homeassistant`, Docker host network) |
| 2026-06 | **Voice PE** перепрошит, wake word **Okay Nabu**, pipeline **Voice Assistant** (русский) |
| 2026-06 | **Yandex SpeechKit** — STT `ru-RU` + TTS голос `marina` (облако) |
| 2026-06 | **Groq** `llama-3.3-70b-versatile` — умные ответы (облако, egress phoneserver через awg2) |
| 2026-06 | **prefer_local_intents: true** — таймеры/свет без Groq |
| 2026-06 | OpenWrt pbr **`phoneserver AI via awg2`** для `192.168.1.227` |
| 2026-06 | Whisper/Piper **сняты** из compose — локальный STT/TTS на телефоне не использовались |

---

## Текущий пайплайн (рабочий)

```text
Voice PE (Okay Nabu)
    → Yandex SpeechKit STT (ru-RU, облако)
    → [локальные intent'ы] ИЛИ Groq LLM
    → Yandex SpeechKit TTS (marina, облако)
    → динамик Voice PE
```

| Слой | Значение | Где настроено |
|------|----------|---------------|
| Wake word | Okay Nabu | Voice PE / ESPHome |
| STT | `stt.yandex_speechkit`, `ru-RU` | Голосовые ассистенты → Voice Assistant |
| TTS | `tts.yandex_speechkit`, `marina` | то же |
| LLM | `conversation.groq_cloud_api`, 70b | то же + интеграция Groq |
| Локальные команды | вкл. | `prefer_local_intents: true` |
| internal_url HA | `http://192.168.1.227:8123` | Настройки → Система → Сеть |

**Проверить:** «Okay Nabu» → «проверка» (intent_script) · «какая погода» · «расскажи короткий анекдот».

---

## Почему не Whisper / Piper на телефоне

| Вариант | Проблема на SM7125 |
|---------|-------------------|
| Whisper `base` | Ошибки STT («2026 год» вместо «расскажи анекдот») |
| Whisper `small-int8` | Лучше, но всё равно медленнее и слабее облака |
| Piper `irina` | Роботизированный русский vs Yandex `marina` |
| Локальный LLM | 6 ГБ RAM — не для 70B; N150 тоже не вариант |

**Вывод:** STT+TTS в облаке (Yandex), «мозг» в облаке (Groq). Телефон — только HA + Voice PE satellite. Локальные Wyoming-контейнеры **не нужны** в текущей схеме.

Восстановить локальный бэкенд (эксперимент): профиль `local` в `compose.yaml` → `docker compose --profile local up -d`.

---

## Напоминания: только бип, без текста

### Симптом

«Напомни …» → короткий звук, без фразы «таймер поставлен» / «напоминание создано».

### Причина

С HA **2025.10** при **локальных** командах в той же **зоне (area)**, что и Voice PE, Assist отвечает **коротким бипом** вместо TTS — это штатное поведение, не поломка.

У вас `prefer_local_intents: true` → таймеры обрабатываются локально → бип.

### Что делать

**Вариант A — таймер (встроенно, по-русски):**

Фразы из [официальных русских intent'ов](https://github.com/home-assistant/intents/tree/main/sentences/ru):

- «**поставь таймер на 5 минут**»
- «**установи таймер пицца на 20 минут**»
- «**через 10 минут выключи свет**» (отложенная команда)

После бипа таймер **работает**. Статус: «**сколько осталось на таймере пицца**».

**Вариант B — напоминание с датой/временем (как у Google):**

Встроенного «напомни в 15:00 купить молоко» **нет**. Нужно отдельно:

1. HA → **Настройки → Области, зоны и ярлыки → Списки дел** — создать список (например «Напоминания»).
2. Подключить [blueprint Reminders](https://community.home-assistant.io/t/reminders-create-and-list-tasks-with-conversational-commands/820470) или свои custom sentences.
3. Уведомление в момент срока — через `notify.mobile_app_*` или TTS.

**Вариант C — снова слышать голосовое подтверждение:**

- Перенести Voice PE в **другую area**, чем управляемые устройства (костыль, ломает «комнатный» контекст), **или**
- Ждать настройку отключения бипа в HA (пока [нет официального тумблера](https://github.com/home-assistant/core/issues/154417)).

---

## Spotify с говорилки

### Коротко

**Да, можно**, но не «из коробки» с текущим Groq-агентом.

| Требование | Детали |
|------------|--------|
| Аккаунт | **Spotify Premium** (с 2026 dev portal только Premium) |
| Интеграция HA | Официальная [Spotify](https://www.home-assistant.io/integrations/spotify/) (OAuth в UI) |
| Куда играть | Нужен **media_player** с Spotify Connect: телефон, колонка, Chromecast, WiiM, ПК с Spotify… |
| Голос | Текущий **Groq Cloud API** — только текст, **без** вызова Spotify |

### Пути по сложности

**1. Простые фразы (без LLM)** — если есть `media_player`:

Custom sentences / intent_script: «включи музыку на `<плеер>`» → `media_player.play_media` или сценарий.

**2. Music Assistant (рекомендуется для голоса)** — отдельный Docker-сервис рядом с HA:

- Провайдер Spotify, очереди, «играй X на кухне».
- Документация: [music-assistant.io](https://www.music-assistant.io/).
- На phoneserver потянет как лёгкий сервис; тяжёлая часть — на стороне Spotify API.

**3. Natural language + Spotify** — custom [spotify-voice-assistant](https://github.com/cauld/spotify-voice-assistant) + агент с **function calling** (Extended OpenAI Conversation и т.п.). С простым Groq-интегратором **не совместимо** без доработки.

### Шаги, если решишь подключать Spotify

1. Создать приложение в [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
2. HA → **Устройства и службы → + → Spotify** → OAuth.
3. Выбрать/настроить `media_player` (куда играть).
4. Проверить из UI: воспроизведение плейлиста.
5. Добавить голос (Music Assistant или custom sentences).

**Проверить:** в HA появился `media_player.spotify_*`; тестовый трек играет на выбранном устройстве.

---

## OpenWrt и Groq

Трафик **с IP phoneserver** (`192.168.1.227`) к AI должен идти через **awg2** (NL), иначе Groq даёт `403`.

```bash
# На роутере
sh /tmp/enable-phoneserver-ai-pbr.sh   # scripts/openwrt/enable-phoneserver-ai-pbr.sh
```

**Проверить с phoneserver:**

```bash
wget -qO- https://ifconfig.me/ip          # ожидается NL IP awg2, не 5.189.x
sudo python3 /tmp/test-groq-api.py        # models.list: OK
```

При `403 error code: 1010` — новый ключ в [console.groq.com](https://console.groq.com) → HA → Groq → Перенастроить.

---

## Скрипты обслуживания

| Скрипт | Назначение |
|--------|------------|
| `install-homeassistant.sh` | HA Container (только homeassistant) |
| `install-groq-ha.sh` | Custom integration Groq |
| `install-yandex-speechkit-ha.sh` | Custom integration Yandex SpeechKit |
| `switch-yandex-pipeline.py` | STT+TTS → Yandex в pipeline Voice Assistant |
| `fix-voice-pe-audio.py` | internal_url + короткие ответы Groq |
| `fix-tts-cutoff.py` | `tts_unsafe` Yandex + лимит токенов Groq |
| `patch-groq-error-ru.py` | Русское сообщение при сбое Groq |
| `expose-ha-weather.py` | Погода в Assist |
| `test-groq-api.py` | Диагностика ключа с phoneserver |

Устарело (локальный Wyoming): `tune-voice-pipeline.py`, `switch-tts-yandex.py`.

---

## Альтернативы, если Groq снова отвалится

| Вариант | Плюсы | Минусы |
|---------|-------|--------|
| **YandexGPT** | РФ, один биллинг с SpeechKit | Настройка API, платный tier |
| **OpenRouter** | Много моделей | Нужна карта / лимиты |
| Только локальные intent'ы | Бесплатно, быстро | Нет «болтовни» и анекдотов |

---

## Связанные файлы

- Compose: [scripts/phoneserver/homeassistant/compose.yaml](../../scripts/phoneserver/homeassistant/compose.yaml)
- PBR: [scripts/openwrt/enable-phoneserver-ai-pbr.sh](../../scripts/openwrt/enable-phoneserver-ai-pbr.sh)
- Voice PE: [voice-pe.home-assistant.io](https://voice-pe.home-assistant.io/)
