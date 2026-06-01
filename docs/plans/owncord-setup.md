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

| Файл | Назначение |
|------|------------|
| `scripts/proxmox/owncord-install.sh` | Клон + `deploy/install.sh` внутри LXC 103 |
| `scripts/proxmox/owncord-edge-setup.sh` | Apache vhost + self-signed TLS на VM 101 |
| `nextcloud-vm/apache/owncord-pundef.conf` | Исходник vhost |
| `scripts/openwrt/enable-owncord-dns.sh` | Split-horizon DNS → edge (`/etc/dnsmasq.conf`, не uci — см. ниже) |

---

## Деплой с Windows (PowerShell)

```powershell
# 1) OwnCord на LXC 103 (сборка 5–15 мин)
py -3 scripts/proxmox/upload.py scripts/proxmox/owncord-install.sh /tmp/owncord-install.sh --chmod 755
py -3 scripts/proxmox/proxmox_exec.py "pct push 103 /tmp/owncord-install.sh /tmp/owncord-install.sh --perms 0755; pct exec 103 -- sed -i 's/\r$//' /tmp/owncord-install.sh; pct exec 103 -- env REGISTRATION_CODE=YOUR_CODE bash /tmp/owncord-install.sh"

# 2) Apache edge на VM 101
py -3 scripts/proxmox/upload.py nextcloud-vm/apache/owncord-pundef.conf /tmp/owncord-pundef.conf
py -3 scripts/proxmox/upload.py scripts/proxmox/apply-vm-file.sh /tmp/apply-vm-file.sh --chmod 755
py -3 scripts/proxmox/upload.py scripts/proxmox/owncord-edge-setup.sh /tmp/owncord-edge-setup.sh --chmod 755
py -3 scripts/proxmox/proxmox_exec.py "sed -i 's/\r$//' /tmp/owncord-edge-setup.sh; bash /tmp/owncord-edge-setup.sh"

# 3) DNS на OpenWrt
py -3 scripts/openwrt/upload.py scripts/openwrt/enable-owncord-dns.sh /tmp/enable-owncord-dns.sh --chmod 755
py -3 scripts/openwrt/openwrt_exec.py "sed -i 's/\r$//' /tmp/enable-owncord-dns.sh; sh /tmp/enable-owncord-dns.sh"
```

**Проверить:**

```powershell
py -3 scripts/proxmox/proxmox_exec.py "pct exec 103 -- curl -fsS http://127.0.0.1:3001/api/health"
curl.exe -fsS https://owncord-pundef.mooo.com/api/health
```

Друзья открывают `https://owncord-pundef.mooo.com`, вводят registration code при регистрации.

### DNS на OpenWrt (важно)

`uci add_list dhcp.@dnsmasq[0].address=...` **сбрасывается** при `dnsmasq reload` (podkop/pbr). Скрипт `enable-owncord-dns.sh` пишет строку в **`/etc/dnsmasq.conf`** — так же, как для других homelab-доменов, это переживает reload.

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
| Скрипт | `scripts/proxmox/owncord-turn-install.sh` |
| WAN DNAT (опц.) | `scripts/openwrt/enable-owncord-turn.sh` |

После смены TURN — **обновить страницу** (F5) на всех клиентах.

**Голос без микрофона:** если `getUserMedia` не находит микрофон (или доступ запрещён), клиент входит в **режим прослушивания** — микрофон выключен, остальные участники слышны. Патч: `scripts/proxmox/owncord-patch-voice-media.sh` (на 103: `pct push` + `pct exec … bash /tmp/owncord-patch-voice-media.sh`). Для звонка без камеры выбирайте обычный голосовой канал, не видео.

**Демонстрация экрана:** в модалке по умолчанию включён «Звук экрана»; в системном диалоге браузера тоже нужна галочка «Поделиться звуком». Для **одного окна** в веб-клиенте звук часто недоступен (ограничение Chrome) — шарьте **весь экран** или **вкладку** с галочкой звука. Полноэкранный просмотр чужого видео/демки: кнопка ⛶ при наведении на плитку или двойной клик. Патч: `scripts/proxmox/owncord-patch-screen-fs-audio.sh`.

### TLS (Let's Encrypt)

Сейчас на edge может быть **self-signed** (предупреждение в браузере). Для нормального сертификата, как у `apps-pundef` / `cloud-pundef`:

1. **FreeDNS:** A-запись `owncord-pundef` → `mooo.com` → белый IP (`5.189.245.251`), Dynamic update URL для DDNS.
2. Проверка: `Resolve-DnsName owncord-pundef.mooo.com -Type A -Server 8.8.8.8` → белый IP.
3. (Опц.) `OWNCORD_DDNS_URL='...' sh scripts/openwrt/enable-owncord-ddns.sh`
4. С Proxmox-хоста:
   ```powershell
   py -3 scripts/proxmox/upload.py nextcloud-vm/apache/owncord-pundef.conf /tmp/owncord-pundef.conf
   py -3 scripts/proxmox/upload.py scripts/proxmox/apply-vm-file.sh /tmp/apply-vm-file.sh --chmod 755
   py -3 scripts/proxmox/upload.py scripts/proxmox/qm-guest.sh /tmp/qm-guest.sh --chmod 755
   py -3 scripts/proxmox/upload.py scripts/proxmox/owncord-le-cert.sh /tmp/owncord-le-cert.sh --chmod 755
   py -3 scripts/proxmox/proxmox_exec.py "sed -i 's/\r$//' /tmp/qm-guest.sh /tmp/owncord-le-cert.sh; bash /tmp/owncord-le-cert.sh"
   ```
5. LAN split-horizon (`enable-owncord-dns.sh`) не трогать — он по-прежнему указывает на `192.168.50.34`, LE только для имени сертификата и внешних клиентов.

Автопродление: тот же `certbot.timer` на nextcloud-vm, что и для других vhost'ов.

---

## Сделано (история)

| Дата | Изменение |
|------|-----------|
| 2026-05-24 | План под J3vb/OwnCord (Windows blocker) |
| 2026-06-01 | Stoat/Spacebar сняты; git очищен; Restezzz/OwnCord + скрипты homelab |
