# OwnCord — план развёртывания в home-server

> **Статус:** plan (в работе)  
> **Репозиторий:** [Restezzz/OwnCord](https://github.com/Restezzz/OwnCord) — **Linux deploy**, invite, HTTPS, WebRTC  
> **Гайд:** [deploy/DEPLOY.md](https://github.com/Restezzz/OwnCord/blob/main/deploy/DEPLOY.md)

Ранее в этом репозитории фигурировал [J3vb/OwnCord](https://github.com/J3vb/OwnCord) (Windows-only) — **это другой форк**. Статус «blocked — только Windows» относился к **J3vb**, не к **Restezzz**.

Стеки **Stoat/Revolt** и **Spacebar/Fermi** сняты с LXC 103 (2026-06-01); артефакты удалены из git.

---

## Схема homelab

```text
Internet / LAN
    -> OpenWrt split-horizon: owncord-pundef.mooo.com -> 192.168.50.34
    -> nextcloud-vm (101) Apache HTTPS (Let's Encrypt)
    -> LXC 103 (192.168.50.36) OwnCord :3001 (127.0.0.1, systemd owncord)
```

| Параметр | Значение |
|----------|----------|
| LXC | 103, IP `192.168.50.36` |
| Backend | `/opt/owncord`, `systemctl status owncord` |
| Публичный URL | `https://owncord-pundef.mooo.com` |
| Клиент | браузер (без отдельного exe) |
| Регистрация | `REGISTRATION_CODE` в `server/.env` |

---

## Скрипты в репозитории

Всё в каталоге [`owncord/`](README.md) (см. [README.md](README.md#структура)).

| Файл | Назначение |
|------|------------|
| `owncord/scripts/proxmox/install.sh` | Клон + `deploy/install.sh` внутри LXC 103 |
| `owncord/scripts/proxmox/edge-setup.sh` | Apache vhost + self-signed TLS на VM 101 |
| `owncord/apache/owncord-pundef.conf` | Исходник vhost |
| `owncord/scripts/openwrt/enable-dns.sh` | Split-horizon DNS → edge (`/etc/dnsmasq.conf`, не uci — см. ниже) |

---

## Деплой с Windows (PowerShell)

```powershell
# 1) OwnCord на LXC 103 (сборка 5–15 мин)
py -3 scripts/proxmox/upload.py owncord/scripts/proxmox/install.sh /tmp/owncord-install.sh --chmod 755
py -3 scripts/proxmox/proxmox_exec.py "pct push 103 /tmp/owncord-install.sh /tmp/owncord-install.sh --perms 0755; pct exec 103 -- sed -i 's/\r$//' /tmp/owncord-install.sh; pct exec 103 -- env REGISTRATION_CODE=YOUR_CODE bash /tmp/owncord-install.sh"

# 2) Apache edge на VM 101
py -3 scripts/proxmox/upload.py owncord/apache/owncord-pundef.conf /tmp/owncord-pundef.conf
py -3 scripts/proxmox/upload.py scripts/proxmox/apply-vm-file.sh /tmp/apply-vm-file.sh --chmod 755
py -3 scripts/proxmox/upload.py owncord/scripts/proxmox/edge-setup.sh /tmp/owncord-edge-setup.sh --chmod 755
py -3 scripts/proxmox/proxmox_exec.py "sed -i 's/\r$//' /tmp/owncord-edge-setup.sh; bash /tmp/owncord-edge-setup.sh"

# 3) DNS на OpenWrt
py -3 scripts/openwrt/upload.py owncord/scripts/openwrt/enable-dns.sh /tmp/enable-owncord-dns.sh --chmod 755
py -3 scripts/openwrt/openwrt_exec.py "sed -i 's/\r$//' /tmp/enable-owncord-dns.sh; sh /tmp/enable-owncord-dns.sh"
```

**Проверить:**

```powershell
python scripts/proxmox/check_vms.py
python start.py check_stack
py -3 scripts/proxmox/proxmox_exec.py "pct exec 103 -- curl -fsS http://127.0.0.1:3001/api/health"
curl.exe -fsS https://owncord-pundef.mooo.com/api/health
```

`check_vms.py` — LXC 103 (systemd, `/api/health`, TURN, homelab-патчи) и edge на VM 101.  
`check_stack.py` — split-horizon DNS, HTTPS `/api/health`, DHCP-lease `.36`.  
**Uptime Kuma** — см. ниже [Мониторинг в Kuma](#мониторинг-в-kuma).

Друзья открывают `https://owncord-pundef.mooo.com`, вводят registration code при регистрации.

### DNS на OpenWrt (важно)

`uci add_list dhcp.@dnsmasq[0].address=...` **сбрасывается** при `dnsmasq reload` (podkop/pbr). Скрипт `owncord/scripts/openwrt/enable-dns.sh` пишет строку в **`/etc/dnsmasq.conf`** — так же, как для других homelab-доменов, это переживает reload.

---

## Порты (из DEPLOY.md)

| Назначение | Порт |
|------------|------|
| HTTPS + WebSocket | 443 (через Apache) |
| Backend (локально) | 3001 |
| TURN (опционально) | 3478 tcp/udp, 49152–65535 udp |

Голос/видео — WebRTC (не через Apache). По умолчанию только Google STUN; на homelab поднят **coturn** на LXC 103:

| Параметр | Значение |
|----------|----------|
| TURN | `turn:192.168.50.36:3478` (логин/пароль в `/opt/owncord/server/.env`) |
| Скрипт | `owncord/scripts/proxmox/turn-install.sh` |
| WAN DNAT (опц.) | `owncord/scripts/openwrt/enable-turn.sh` |

После смены TURN — **обновить страницу** (F5) на всех клиентах.

**Голос без микрофона:** если `getUserMedia` не находит микрофон (или доступ запрещён), клиент входит в **режим прослушивания** — микрофон выключен, остальные участники слышны. Патч: `owncord/scripts/proxmox/patch-voice-media.sh` (на 103: `pct push` + `pct exec … bash /tmp/patch-voice-media.sh`). Для звонка без камеры выбирайте обычный голосовой канал, не видео.

**Демонстрация экрана:** в модалке по умолчанию включён «Звук экрана»; в системном диалоге браузера тоже нужна галочка «Поделиться звуком». Для **одного окна** в веб-клиенте звук часто недоступен (ограничение Chrome) — шарьте **весь экран** или **вкладку** с галочкой звука. Полноэкранный просмотр чужого видео/демки: кнопка ⛶ при наведении на плитку или двойной клик. Патч: `owncord/scripts/proxmox/patch-screen-fs-audio.sh`.

### Мониторинг в Kuma

Шаблон: [`scripts/phoneserver/kuma-monitors.json`](../scripts/phoneserver/kuma-monitors.json) — два монитора:

| Имя | Тип | URL / target |
|-----|-----|----------------|
| OwnCord | HTTP (Public HTTPS) | `https://owncord-pundef.mooo.com/api/health` — ждёт `{"ok":true}` |
| OwnCord backend (LAN) | HTTP | `http://192.168.50.36:3001/api/health` |

**Автоматически** (Kuma на LXC `http://192.168.50.35:3001/`):

```bash
cd scripts/phoneserver
KUMA_USERNAME=admin KUMA_PASSWORD='...' ./seed-kuma-monitors.sh --dry-run
KUMA_USERNAME=admin KUMA_PASSWORD='...' ./seed-kuma-monitors.sh
```

Скрипт идемпотентен по имени: существующие не дублирует, **OwnCord** добавит, если его ещё нет.

**Важно для Public HTTPS:** на **LXC Kuma** (`192.168.50.35`) в `/etc/hosts` — см. `scripts/proxmox/fix-kuma-monitors-lxc.sh` (cloud/apps/owncord → `.34`).

**Проверить:**

```bash
curl -fsS http://192.168.50.35:3001/api/health  # Kuma UI
curl -fsS https://owncord-pundef.mooo.com/api/health
```

В UI Kuma: группа **Public HTTPS** — **OwnCord** зелёный; **srv** — ping `owncord LXC` + **OwnCord backend (LAN)**.

**Вручную в UI** (если без seed): Add New Monitor → HTTP(s) → URL `https://owncord-pundef.mooo.com/api/health`, interval 60s, group Public HTTPS; второй — `http://192.168.50.36:3001/api/health`, group srv.

### TLS (Let's Encrypt)

Сейчас на edge может быть **self-signed** (предупреждение в браузере). Для нормального сертификата, как у `apps-pundef` / `cloud-pundef`:

1. **FreeDNS:** A-запись `owncord-pundef` → `mooo.com` → белый IP (`5.189.245.251`), Dynamic update URL для DDNS.
2. Проверка: `Resolve-DnsName owncord-pundef.mooo.com -Type A -Server 8.8.8.8` → белый IP.
3. (Опц.) `OWNCORD_DDNS_URL='...' sh owncord/scripts/openwrt/enable-ddns.sh` (на роутере через `openwrt_exec.py`)
4. С Proxmox-хоста:
   ```powershell
   py -3 scripts/proxmox/upload.py owncord/apache/owncord-pundef.conf /tmp/owncord-pundef.conf
   py -3 scripts/proxmox/upload.py scripts/proxmox/apply-vm-file.sh /tmp/apply-vm-file.sh --chmod 755
   py -3 scripts/proxmox/upload.py owncord/scripts/proxmox/qm-guest.sh /tmp/qm-guest.sh --chmod 755
   py -3 scripts/proxmox/upload.py owncord/scripts/proxmox/le-cert.sh /tmp/owncord-le-cert.sh --chmod 755
   py -3 scripts/proxmox/proxmox_exec.py "sed -i 's/\r$//' /tmp/qm-guest.sh /tmp/owncord-le-cert.sh; bash /tmp/owncord-le-cert.sh"
   ```
5. LAN split-horizon (`enable-dns.sh`) не трогать — он по-прежнему указывает на `192.168.50.34`, LE только для имени сертификата и внешних клиентов.

Автопродление: тот же `certbot.timer` на nextcloud-vm, что и для других vhost'ов.

---

## Сделано (история)

| Дата | Изменение |
|------|-----------|
| 2026-05-24 | План под J3vb/OwnCord (Windows blocker) |
| 2026-06-01 | Stoat/Spacebar сняты; git очищен; Restezzz/OwnCord + скрипты homelab |
| 2026-06-01 | Всё собрано в каталог `owncord/` (setup, apache, scripts) |
