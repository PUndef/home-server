# Голосовой ассистент (Voice PE + HA на phoneserver)

> **Статус:** рабочая конфигурация  
> **Последняя проверка:** 2026-06-12  
> **HA UI:** `http://192.168.50.127:8123/` (srv eth) · `http://192.168.1.227:8123/` (wlan, Voice PE internal_url) · Voice PE: `192.168.1.171`  
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
| 2026-06-12 | Миграция **v25.12** / 6.14.7; eth HA UI `192.168.50.127`; wlan `internal_url` `.227`; pbr для **обоих** IP |
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
| internal_url HA | `http://192.168.1.227:8123` (wlan, static) | Настройки → Система → Сеть |
| HA UI (браузер, Kuma) | `http://192.168.50.127:8123` (eth srv) | Основной адрес с homelab |

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

## Spotify / музыка с говорилки — ⬜ план на будущее

> **Статус:** не делали; подписка Spotify **Individual** (Premium) есть.  
> **Сейчас:** колонки и отдельного плеера нет — только Voice PE + phoneserver.  
> **Идея:** позже собрать сценарий «как у Алисы» (включи конкретный трек/исполнителя) **без Groq** для музыки.

### Почему не на сам Voice PE

Voice PE — **голосовой спутник** (микрофон + короткий TTS), не Spotify Connect плеер. Spotify отдаёт поток на Connect-устройства; прошивка Voice PE этого не умеет и не планирует.

### Почему не JBL по Bluetooth с Voice PE

Чип **ESP32-S3** — только **BLE** (настройка). Для музыки нужен **Bluetooth Classic (A2DP)** — на Voice PE его нет ([issue #332](https://github.com/esphome/home-assistant-voice-pe/issues/332)). Варианты звука с Voice PE:

| Вариант | Что даёт |
|---------|----------|
| 3.5 mm с Voice PE | Только **ответы Assist**, не Spotify |
| Voice PE → BT → JBL | **Нельзя** (нет A2DP) |
| Отдельный плеер → JBL (AUX или BT от плеера) | **Рабочий путь** |

### Целевая схема (когда появится плеер)

```text
Voice PE (Okay Nabu) — только слушает команды
phoneserver — HA + Music Assistant (Docker)
Плеер в комнате — Spotify Connect / MA player → колонка (JBL и т.п.)
STT/TTS — как сейчас (Yandex); Groq — только болтовня, не музыка
```

### Железо: что можно использовать без покупки колонки

| Вариант | Оценка |
|---------|--------|
| **Старый неиспользуемый телефон** | **Лучший бесплатный старт.** Постоянно на зарядке, Wi‑Fi 2.4 GHz, приложение Spotify → **Spotify Connect** target. Можно BT на JBL, если колонка появится. Требования: Android 8+ (лучше 10+), не умирающая батарея на постоянной зарядке ок. |
| ПК со Spotify | Уже есть; не «колонка в комнате» |
| WiiM Mini / аналог | Покупка; line-out на JBL, стабильнее старого телефона |

Старый телефон = **плеер**, Voice PE = **микрофон**. Это нормальная схема для HA.

### Этапы (когда решишь делать)

#### Этап 1 — минимум (без Music Assistant) — ⬜

**Сделать**

1. [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) → приложение, Redirect URI `https://my.home-assistant.io/redirect/oauth` (или `http://192.168.1.227:8123/auth/external/callback`).
2. HA → интеграция **Spotify** → OAuth.
3. Старый телефон: установить Spotify, залогиниться, оставить в сети; в HA выбрать его как **source** у `media_player.spotify_*`.
4. Expose `media_player.spotify_*` в Assist; плеер и Voice PE в одной **area**.

**Проверить:** из HA UI трек играет на телефоне; «Okay Nabu» → «следующий трек» / «пауза» (локально, без Groq).

#### Этап 2 — «как у Алисы», конкретные запросы — ⬜

**Сделать**

1. **Music Assistant** — Docker на phoneserver (рядом с HA).
2. Подключить Spotify Premium в MA.
3. Плеер MA: старый телефон или [MA mobile player](https://www.music-assistant.io/) на нём.
4. Blueprint [music-assistant/voice-support](https://github.com/music-assistant/voice-support):
   - **Option 1 (Local)** — без LLM, фразы вида «Play artist …» (англ. синтаксис);
   - **Option 2 (LLM Enhanced)** — свободная речь на русском, LLM **только для музыки** (отдельно от Groq в основном ассистенте).
5. Плеер и Voice PE в одной area (обязательно для «играй в гостиной»).

**Проверить:** «Okay Nabu» → «Play artist …» / русский запрос (если LLM blueprint) → музыка на телефоне/JBL.

#### Этап 3 — колонка JBL (опционально) — ⬜

- JBL с **входом AUX** → кабель от WiiM Mini или от телефона (если телефон у колонки).
- JBL только по **BT** → телефон-плеер по BT к JBL, MA/Spotify управляет телефоном.

### Что не ждать один в один от Алисы

- Каталог **Spotify**, не Яндекс.Музыка.
- Voice PE **никогда** не станет колонкой Spotify.
- Свободный русский «включи что угодно» без LLM — только через **custom sentences** на свои плейлисты или **MA LLM blueprint**.

### Ссылки

- [Spotify integration](https://www.home-assistant.io/integrations/spotify/)
- [Music Assistant](https://www.music-assistant.io/)
- [MA voice-support blueprints](https://github.com/music-assistant/voice-support)
- Voice PE и BT: [community thread](https://community.home-assistant.io/t/home-assistant-voice-pe-connection-to-bluetooth-speaker/817188)

---

## OpenWrt и Groq

Трафик **с IP phoneserver** (`192.168.50.127` eth / `192.168.1.227` wlan) к Groq/Yandex AI должен идти через **awg2** (NL), иначе Groq даёт `403`.

DHCP-резервации: `scripts/openwrt/reserve-phoneserver-dhcp.sh` (srv + wlan).

**Почему отваливается повторно:** pbr 1.2.2 не заполняет nftset для `*.groq.com`; phoneserver резолвит `api.groq.com` через `1.1.1.1` → реальные Cloudflare IP вне dnsmasq nftset. После любого `pbr restart` (hotplug `99-vpn-stack`, `pbr-workvpn-watchdog`) set пустеет.

**Устойчивость (на роутере):**

- `enable-phoneserver-ai-pbr.sh` — политика + установка `/opt/seed-phoneserver-groq-ips.sh`
- `pbr-phoneserver-groq-watchdog.sh` — cron `*/5`, пересеивает IP если set пуст
- `99-vpn-stack` — seed сразу после `pbr restart`

```bash
# Первичная настройка / восстановление (залить все 3 скрипта в /tmp/, затем):
sh /tmp/enable-phoneserver-ai-pbr.sh
```

**Проверить:** `python scripts/openwrt/check_stack.py` → группа `phoneserver` (groq-nftset, watchdog-installed).

**Проверить с phoneserver:**

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer x' https://api.groq.com/openai/v1/models
# ожидается 401 (не 403)
```

При `403 error code: 1010` — новый ключ в [console.groq.com](https://console.groq.com) → HA → Groq → Перенастроить. При просто `403` без 1010 — почти всегда пустой nftset: `sh /opt/seed-phoneserver-groq-ips.sh` на роутере.

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
