# `phoneserver` — postmarketOS на Redmi Note 9 Pro

Скрипты для установки и сопровождения второго узла домашней инфраструктуры — Xiaomi Redmi Note 9 Pro Global (codename `joyeuse`, SoC SM7125), переделанного под headless-сервер на postmarketOS.

Подробная история и текущий статус: [`docs/phoneserver/pmos-setup.md`](../../docs/phoneserver/pmos-setup.md).  
Миграция / переустановка **v25.12**: [`migrate-v2512/README.md`](migrate-v2512/README.md).

**Текущая конфигурация (2026-06-12):** pmaports **`v25.12`**, ядро **6.14.7-sm7125** (asidko), **fastboot-bootpart** (`cache`=kernel, `boot`=U-Boot), панель **Huaxing**, пользователь SSH **`user`**, systemd. Зарядка и PD — **pm6150-charger v0.6.2**, лимит батареи **80%**.

Legacy **v25.06** / 6.12.1 / OpenRC / `pmos` — только [`install/`](install/) (историческая схема Android boot.img).

---

## Когда что запускать

Все скрипты гоняются из **WSL Ubuntu 24.04** на основном Windows-ПК. Подразумевается, что:

- `pmbootstrap` 3.x установлен в WSL и инициализирован
- public-ключ для phoneserver лежит в `~/.ssh/phoneserver_nopass{,.pub}` (создаётся через `setup-ssh-key.sh`)
- IP и хост по умолчанию — из [`hosts.yaml`](hosts.yaml) (`srv_ip` → `wifi_ip`); переопределение: `PHONE_HOST=joyeuse`, `PHONE_IP=...`, `PHONE_DEFAULT=usb`
- `phone-defaults.sh` подставляет `PHONE_IP`, `SSH_USER`, `SSH_REMOTE` (`user@…` по умолчанию)
- **eth (srv):** `192.168.50.127` — основной (HA UI, Kuma, Beszel, SSH с Proxmox)
- **wlan (lan):** `192.168.1.227` — Voice PE `internal_url`, Groq PBR
- USB fallback — `172.16.42.1` (`PHONE_DEFAULT=usb`)
- USB-устройство при необходимости проброшено в WSL через `usbipd attach --wsl --busid <id>` (из PowerShell **от админа**)

### При обычной работе

| Скрипт | Когда запускать |
|---|---|
| `disable-usb-gadget.sh` + `.service` | Освободить UDC для USB host (хаб eth + PD). Установить на телефон при post-flash. |
| `wsl-usbnet-up.sh` | После `usbipd attach` — USB-cdc в WSL, ssh до `172.16.42.1`. |
| `status.sh` | Снять текущую сводку с телефона (kernel, uptime, диск, сервисы, сеть). |
| `fix-beszel-agent-lan.sh` | Убрать зависимость `phoneserver-wifi` с beszel-agent, перезапустить агент. |
| `install-beszel-agent.ps1` / `.sh` | Переустановка Beszel agent (TOKEN из UI hub). |
| `install-uptime-kuma.sh` | **Устарело на phoneserver** — Kuma живёт на `static-sites` (`192.168.50.35:3001`). См. `scripts/proxmox/install-uptime-kuma.sh`. |
| `disable-uptime-kuma.sh` | Снять Kuma с phoneserver (`pkill`, не `rc-service stop`). |
| `seed-kuma-monitors.sh` | Залить мониторы из `kuma-monitors.json` → `http://192.168.50.35:3001/` (venv `.venv-kuma`). |
| `pin-dns-and-ntp.sh` | Публичный DNS (1.1.1.1), не dnsmasq роутера; `chronyc makestep`. |
| `fix-kuma-monitors-phone.sh` | На phoneserver: `/etc/hosts` для `*.mooo.com` → `192.168.50.34` + перезапуск Kuma. |

Kuma на `192.168.50.35` — не добавляй self-ping мониторы на `127.0.0.1`.

### При первичной установке / переустановке

**Актуальный путь — v25.12:** см. [`migrate-v2512/README.md`](migrate-v2512/README.md) (сборка на Proxmox, fastboot, asidko charger, smoke-test, restore HA).

**Legacy v25.06** (Android boot.img, OpenRC, `pmos`): [`install/README.md`](install/README.md) — только для истории / отката.

---

## Uptime Kuma (seed)

**Windows (рекомендуется, без WSL):**

```powershell
# из корня репо d:\repositories\home-server
# 1) admin в http://192.168.50.35:3001/
$env:KUMA_USERNAME = 'admin'
$env:KUMA_PASSWORD = '...'
.\scripts\phoneserver\seed-kuma-monitors.ps1
# -DryRun — только показать, что добавится
```

**WSL/Linux** (если есть venv): `KUMA_URL=http://192.168.50.35:3001 KUMA_USERNAME=admin KUMA_PASSWORD='...' ./seed-kuma-monitors.sh`

Пакет: `uptime-kuma-api-v2` (не `uptime-kuma-api` 1.x — только Kuma 1.21–1.23).

**OwnCord без пароля API** (hosts + три монитора в `kuma.db`, idempotent):

```bash
# из WSL на ПК:
bash scripts/phoneserver/run-owncord-kuma-remote.sh
```

Полный seed из `kuma-monitors.json` по-прежнему через `seed-kuma-monitors.sh` (нужен `KUMA_USERNAME` / `KUMA_PASSWORD`).

**Проверить:** в UI мониторы Public HTTPS зелёные.

---

## Home Assistant (Container, не HA OS)

На phoneserver HA ставится как **Docker Compose** (`scripts/phoneserver/homeassistant/compose.yaml`), без магазина Add-ons.

**Голосовой ассистент (актуально):** [docs/phoneserver/voice-assistant.md](../../docs/phoneserver/voice-assistant.md)  
**Spotify / музыка (план на будущее):** тот же doc, раздел «Spotify / музыка — план на будущее»

| Слой | Рабочая схема |
|------|----------------|
| STT / TTS | **Yandex SpeechKit** (облако, `marina`) |
| LLM | **Groq** `llama-3.3-70b-versatile` (облако, pbr awg2) |
| Wake / железо | **Voice PE** + Okay Nabu |
| Локальный Wyoming | **не используется** (профиль `local` в compose — только для экспериментов) |

Установка HA: `PHONE_IP=192.168.50.127 bash scripts/phoneserver/install-homeassistant.sh` (или wlan `.227` при первичной настройке до eth).

Остановить старые whisper/piper: `bash scripts/phoneserver/stop-local-voice-backends.sh`.

Docker: `/etc/docker/daemon.json` с `"iptables": false` — `fix-docker-iptables.sh`.

**UI:** `http://192.168.50.127:8123/` (основной) · wlan `http://192.168.1.227:8123/` (Voice PE `internal_url`)

Погода в Assist: `sudo python3 /tmp/expose-ha-weather.py` (из `expose-ha-weather.py`).

### Home Assistant Voice Preview Edition

Официальный гайд: [voice-pe.home-assistant.io](https://voice-pe.home-assistant.io/). У нас **HA Container**, не HA OS — add-ons нет; STT/TTS через **Yandex SpeechKit** (см. [voice-assistant.md](../../docs/phoneserver/voice-assistant.md)).

**Перед стартом**

- Voice PE и phoneserver в одной сети **`192.168.1.x`**, Wi‑Fi **2.4 GHz** (не guest).
- HA UI: `http://192.168.1.227:8123/` — этот адрес должен быть в Companion app на телефоне.
- Если Voice PE раньше был привязан к старому HA (`haos17.0` / `50.51`) — [factory reset](https://voice-pe.home-assistant.io/) (иначе ключ шифрования не совпадёт).
- Bluetooth на phoneserver в HA **сломан** — onboarding только через **Companion app** на телефоне (BLE), не через браузер на ПК.

**Шаги**

1. Подключи Voice PE к USB‑C питанию → LED «twinkle», готов к pairing.
2. На телефоне: **Home Assistant Companion** → сервер `http://192.168.1.227:8123`.
   - Android: разрешения **Location (precise)** и **Nearby devices** (нужны только для onboarding).
3. В app: **Настройки → Устройства и службы → Обнаружено** → `home-assistant-… Improv via BLE` → **Добавить**.
4. SSID/пароль **2.4 GHz** Wi‑Fi → **Подключить** → нажми **центральную кнопку** на Voice PE.
5. Снова **Обнаружено** → `Home Assistant Voice …` (ESPHome) → **Добавить** → Submit.
6. Мастер спросит Cloud vs DIY:
   - **Не** Home Assistant Cloud.
   - **Do it yourself** — **не** «Setup with apps» (это add-ons для HA OS). Wyoming уже настроен; мастер можно пропустить/закрыть.
   - Если просит host/IP устройства — IP Voice PE из роутера (`192.168.1.x`), не IP phoneserver.
7. На странице устройства Voice PE:
   - сущность **Assist** → pipeline **Voice Assistant** (русский, Yandex + Groq);
   - wake word: **Okay Nabu** (на устройстве по умолчанию).
8. Тест: «Okay Nabu» → «какая погода» / «проверка».

Переустановка прошивки (если onboarding сломался): [esphome.github.io/home-assistant-voice-pe](https://esphome.github.io/home-assistant-voice-pe/) (Chrome, USB к ПК).

**Просит encryption key** — старый HA; factory reset иногда **не** стирает ключ. **Не жми «Добавить»** на плашке `Home Assistant` в Обнаружено.

1. **Отключи питание** Voice PE (чтобы не торчал в Wi‑Fi со старым ключом).
2. В HA: **⋮** у плашки в Обнаружено → **Игнорировать** (если есть).
3. **Перепрошивка USB** (Chrome/Edge): [esphome.github.io/home-assistant-voice-pe](https://esphome.github.io/home-assistant-voice-pe/) — версия **25.12.4** (не pre-release). Кабель USB‑C с **данными** в ПК.
4. В мастере прошивки **не пропускай Wi‑Fi** — настрой сеть и привязку к HA **в том же мастере** (URL `http://192.168.1.227:8123`). Пропуск Wi‑Fi + Companion app снова даёт запрос ключа ([thread](https://community.home-assistant.io/t/factory-reset-issue-with-home-assistant-voice-preview-edition-device-blinking-blue-instead-of-white/866308)).
5. Если installer завис на «preparing» — другой браузер, без расширений, bootloader: питание выкл → держать кнопку → подключить USB → отпустить → Connect на странице installer.

После прошивки: twinkle → Improv BLE в Companion **или** сразу добавление из мастера. Плашку с ключом не трогать.

---

## Короткая шпаргалка

```bash
# eth (srv, по умолчанию в hosts.yaml):
ssh -i ~/.ssh/phoneserver_nopass user@192.168.50.127

# wlan (Voice PE / из lan):
ssh -i ~/.ssh/phoneserver_nopass user@192.168.1.227

# USB (резерв):
ssh -i ~/.ssh/phoneserver_nopass user@172.16.42.1

# Статус:
./status.sh
```

---

## Известные особенности

- **Dual-homed:** eth `.127` (srv) + wlan `.227` (lan). Разные роли — см. [operations.md](../../docs/phoneserver/operations.md).
- **USB gadget vs host:** без `phoneserver-disable-usb-gadget` хаб не поднимет eth0.
- **Перетык хаба** после cold boot часто обязателен для xhci.
- **`/etc/resolv.conf`** — public DNS (1.1.1.1 / 8.8.8.8), не dnsmasq роутера.
- **Зарядка 24/7:** `term_capacity=80` в `pm6150_chgr_minimal`; PD-хаб с passthrough.
- **RTC нет** — `chronyd` после boot.
- **Uptime Kuma** на LXC `192.168.50.35:3001`, не на телефоне.
- **Beszel agent** — systemd, WebSocket к hub; порт 45876 не слушается (норма).
- **Legacy-скрипты** с `pmos@` — постепенно заменяются на `SSH_REMOTE` из `phone-defaults.sh`.

---

## Edge-only / legacy скрипты

[`install/`](install/) — **v25.06** (Android boot.img). [`migrate-v2512/`](migrate-v2512/) — **текущая** v25.12. [`diag/`](diag/) — диагностика Type-C, зарядки, NTP.
