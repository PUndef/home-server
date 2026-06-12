# `phoneserver` — postmarketOS на Redmi Note 9 Pro

Скрипты для установки и сопровождения второго узла домашней инфраструктуры — Xiaomi Redmi Note 9 Pro Global (codename `joyeuse`, SoC SM7125), переделанного под headless-сервер на postmarketOS.

Подробная история установки и текущий статус железа: [`docs/phoneserver/pmos-setup.md`](../../docs/phoneserver/pmos-setup.md).

Целевая конфигурация — pmaports **`v25.06`** stable, `device-xiaomi-miatoll-kernel-joyeuse_tianma`, Linux 6.12.1, классический Android boot.img в стандартный `boot` partition. Возня с edge-схемой (кастомный boot.img из EFI zboot, патчи pmbootstrap и т.п.) теперь не нужна — оставлена как fallback в [`diag/`](diag/).

---

## Когда что запускать

Все скрипты гоняются из **WSL Ubuntu 24.04** на основном Windows-ПК. Подразумевается, что:

- `pmbootstrap` 3.x установлен в WSL и инициализирован
- public-ключ для phoneserver лежит в `~/.ssh/phoneserver_nopass{,.pub}` (создаётся через `setup-ssh-key.sh`)
- IP и хост по умолчанию — из [`hosts.yaml`](hosts.yaml) (`default_host` → `lan_ip`); переопределение: `PHONE_HOST=joyeuse`, `PHONE_IP=...`
- `phone-defaults.sh` подставляет `PHONE_IP` / `SSH_KEY` во все shell-скрипты; `PHONE_DEFAULT=usb` для install/diag по USB
- LAN eth — `192.168.1.227` (USB-Ethernet хаб → Mercusys, DHCP-резерв OpenWrt); USB fallback — `172.16.42.1`
- USB-устройство при необходимости проброшено в WSL через `usbipd attach --wsl --busid <id>` (из PowerShell **от админа**)

### При обычной работе

| Скрипт | Когда запускать |
|---|---|
| `wsl-usbnet-up.sh` | После переподключения USB / нового `usbipd attach` — поднимает USB-cdc интерфейс в WSL, ставит ему `172.16.42.2/24`, проверяет ssh до телефона. Не нужно если phoneserver доступен по LAN `.227`. |
| `wsl-share-internet.sh` | Только при первичной установке: интернет через WSL до появления eth в LAN. |
| `status.sh` | Снять текущую сводку с телефона (kernel, uptime, диск, сервисы, сеть). |
| `fix-beszel-agent-lan.sh` | Убрать зависимость `phoneserver-wifi` с beszel-agent, перезапустить агент. |
| `install-beszel-agent.ps1` / `.sh` | Переустановка Beszel agent (TOKEN из UI hub). |
| `install-uptime-kuma.sh` | **Устарело на phoneserver** — Kuma живёт на `static-sites` (`192.168.50.35:3001`). См. `scripts/proxmox/install-uptime-kuma.sh`. |
| `disable-uptime-kuma.sh` | Снять Kuma с phoneserver (`pkill`, не `rc-service stop`). |
| `seed-kuma-monitors.sh` | Залить мониторы из `kuma-monitors.json` → `http://192.168.50.35:3001/` (venv `.venv-kuma`). |
| `pin-dns-and-ntp.sh` | Публичный DNS (1.1.1.1), не dnsmasq роутера; `chronyc makestep`. |
| `fix-kuma-monitors-phone.sh` | На phoneserver: `/etc/hosts` для `*.mooo.com` → `192.168.50.34` + перезапуск Kuma. |

Kuma на `192.168.50.35` — не добавляй self-ping мониторы на `127.0.0.1`.

### При первичной установке (по порядку)

| Шаг | Скрипт | Что делает |
|---|---|---|
| 1 | `install/pmbootstrap-init.exp` | Прогон `pmbootstrap init` non-interactively с правильными ответами для joyeuse (UI=none, hostname=phoneserver, kernel=joyeuse_tianma). |
| 2 | вручную: `cd ~/.local/var/pmbootstrap/cache_git/pmaports && git checkout v25.06` | Переключить pmaports на stable канал — на `main` (edge) у `xiaomi-miatoll` сейчас регрессии (см. setup-doc). |
| 3 | вручную: `pmbootstrap config kernel joyeuse_tianma; pmbootstrap config boot_size 128` | Подогнать конфиг под joyeuse. |
| 4 | `pmbootstrap install --no-fde --password changemenow --split --add device-xiaomi-miatoll-kernel-joyeuse_tianma` | Сборка boot.img (~18 MB sparse, 128 MiB partition) и rootfs.img (570 MB → растягиваем потом). |
| 5 | `fastboot erase dtbo; pmbootstrap flasher flash_kernel; sudo fastboot flash userdata ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-root.img; fastboot reboot` | Прошить и перезагрузить. `dtbo erase` обязателен — иначе Xiaomi overlay ломает наш DTB. |
| 6 | `setup-ssh-key.sh` | Сгенерировать `~/.ssh/phoneserver_nopass`, положить в `pmos@phoneserver:~/.ssh/authorized_keys`. |
| 7 | `wsl-share-internet.sh` | Дать phone интернет через WSL до появления eth в LAN. |
| 8 | `install/enable-passwordless-doas.sh` | Pmos v25.06 ставит `doas+doas-sudo-shim`, наш `sudo -S` не работает. Скрипт ставит настоящий sudo, удаляет shim, кладёт `/etc/sudoers.d/pmos-nopasswd`. После этого все остальные `sudo $cmd` через ssh-key работают без password. |
| 9 | `install/resize-root.sh` | Расширить ext4 на `/dev/sda18` до 103 GiB. На v25.06 pmOS делает это сам при первом mount, скрипт скорее no-op. |
| 10 | `install/lan-setup.sh` | После DHCP на eth0: dhcpcd в default runlevel, chrony NTP, public DNS в `/etc/resolv.conf`. |
| 11 | `pin-dns-and-ntp.sh` | Запретить dhcpcd перезаписывать resolv.conf (`nohook resolv.conf` в `dhcpcd.conf`). |
| 12 | `fix-dns-and-apk.sh` | На случай если apk завис из-за подкопа / fake-IP — переставляет DNS и поднимает базовые tools (`curl`). |

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

Установка HA: `PHONE_IP=192.168.1.227 bash scripts/phoneserver/install-homeassistant.sh` (из WSL).

Остановить старые whisper/piper на уже развёрнутом узле: `bash scripts/phoneserver/stop-local-voice-backends.sh`.

Docker на pmOS: `/etc/docker/daemon.json` с `"iptables": false` (см. `fix-docker-iptables.sh`) — host network, роутер не трогаем.

UI: `http://192.168.1.227:8123/`

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
# Подключиться по LAN:
ssh -i ~/.ssh/phoneserver_nopass pmos@192.168.1.227

# Подключиться по USB (резерв; когда USB проброшен в WSL):
ssh -i ~/.ssh/phoneserver_nopass pmos@172.16.42.1

# Снять статус:
./status.sh

# Если phone сменил IP / переустановили pmOS:
./setup-ssh-key.sh
```

---

## Известные особенности

- **Сеть после reboot** — eth0 через USB-Ethernet хаб; `dhcpcd` в default runlevel. Beszel agent зависит только от `net`, не от Wi-Fi.
- **`/etc/resolv.conf`** на phone должен указывать на **public DNS** (1.1.1.1 / 8.8.8.8), а не на dnsmasq роутера. Иначе срабатывает sing-box-подкоп для некоторых доменов и часть apk/curl-запросов зависает.
- **doas vs sudo.** v25.06 по умолчанию `doas`. Запускай `install/enable-passwordless-doas.sh` сразу после первой установки, иначе остальные скрипты будут падать на `sudo -S`.
- **Зарядка** работает только от полноценного USB-C PD-источника. ПК через USB-A или короткий «попытался зарядить» от PC USB-C — не работает, Type-C port уходит в `source` role (Linux mainline driver `qcom,pmic-typec` пока без write-callback для role-switch).
- **RTC battery отсутствует** — после reboot часы откатываются в 1975 год. `chrony` синхронизирует за секунды после поднятия сети.
- **Uptime Kuma** на **static-sites LXC** (`192.168.50.35:3001`), не на phoneserver. Установка: `scripts/proxmox/install-uptime-kuma.sh`. На phoneserver — `disable-uptime-kuma.sh` если ещё не сняли.
- **Kuma: HTTPS `*.mooo.com`.** На LXC в `/etc/hosts` (`fix-kuma-monitors-lxc.sh`): `192.168.50.34 cloud-pundef.mooo.com apps-pundef.mooo.com owncord-pundef.mooo.com`.
- **Beszel agent** на phoneserver — WebSocket к hub (`192.168.50.35`), порт **45876 не слушается** (это нормально, не port-monitor).
- **VPS NL (`45.154.35.222`)** — ICMP с phoneserver не проходит (фаервол хостера); в `kuma-monitors.json` — **Port :22**, не Ping.

---

## Edge-only скрипты (как fallback)

Лежат в [`install/`](install/). Не нужны при штатной установке на `v25.06`, но **могут пригодиться** если pmaports опять перейдут на edge-схему:

| Скрипт | Зачем |
|---|---|
| `install/build-bootimg.sh` | Собирает Android boot.img из артефактов pmOS вручную через `mkbootimg-osm0sis` в `pmbootstrap chroot`. На v25.06 pmbootstrap сам это делает. |
| `install/extract-kernel-from-zboot.py` | Распаковывает Linux Image из EFI zboot wrapper (PE/COFF + gzip-payload). |
| `install/flash-bootimg-via-ssh.sh` | Заливает boot.img на phone и пишет dd в `/dev/disk/by-partlabel/boot`. |
| `install/patch-pmbootstrap-bootsize.sh` | Снимает hardcoded sanity-check `boot_size >= 512 MiB` в `pmbootstrap 3.10.1`. |
