# home-server

Документация, скрипты и исходники домашней инфраструктуры: Proxmox, OpenWrt, Nextcloud, static-sites, phoneserver.

**Точка входа в документацию:** [`docs/README.md`](docs/README.md)  
**Живой контекст (железо, IP, сервисы):** [`docs/overview/hardware-and-env.md`](docs/overview/hardware-and-env.md)

---

## Инвентарь узлов

| VMID / узел | Имя | IP | Роль |
|-------------|-----|-----|------|
| 100 | haos17.0 | 192.168.50.51 | Home Assistant (остановлен, onboot 0) |
| 101 | nextcloud-vm | 192.168.50.34 | Nextcloud, ONLYOFFICE, Apache edge (`apps-pundef.mooo.com`) |
| 102 | static-sites (LXC) | 192.168.50.35 | Caddy, Warframe apps, Beszel hub |
| 103 | owncord (LXC) | 192.168.50.36 | OwnCord — [owncord/setup.md](owncord/setup.md) |
| — | pundef (Proxmox host) | 192.168.50.9 | Гипервизор |
| — | phoneserver | eth `192.168.50.127`, wlan `192.168.1.227` | postmarketOS v25.12: HA Docker, Beszel agent, Voice PE backend |
| — | OpenWrt X3000T | 192.168.1.1 / 192.168.50.1 | Роутер, VPN, NAT, DDNS |

Публичные URL static-sites: `https://apps-pundef.mooo.com/warframe/`, `/requiem/`, `/wf-farm/`, `/beszel/`  
Nextcloud: `https://cloud-pundef.mooo.com`

---

## Структура репозитория

```text
home-server/
├── docs/                  # вся markdown-документация (по категориям)
├── static-sites/          # Vite-приложения + Caddyfile + deploy
├── scripts/               # OpenWrt, Proxmox, phoneserver, VPS helpers
├── nextcloud-vm/          # Apache vhost для edge-прокси
├── kb-remote-ui/          # Mac-side dashboard для Mutagen + autossh туннелей к WSL
├── start.py               # интерактивный запуск OpenWrt-скриптов
└── README.md              # этот файл
```

---

## Частые команды

| Задача | Команда |
|--------|---------|
| Сводка по ВМ/LXC | `python scripts/proxmox/check_vms.py` |
| Health-check роутера | `python start.py check_stack` |
| Runbook: роутер не уронил srv | [`docs/network/router-resilience.md`](docs/network/router-resilience.md) |
| Деплой static-sites | `.\static-sites\deploy.ps1` |
| Применить Caddyfile | `.\scripts\static-sites\apply-caddyfile.ps1` |
| Деплой одного app | `.\static-sites\requiem\scripts\deploy.ps1` |
| SSH на OpenWrt | `python scripts/openwrt/openwrt_exec.py "<cmd>"` |
| SSH на Proxmox | `python scripts/proxmox/proxmox_exec.py "<cmd>"` |

Полный каталог скриптов — в [`docs/README.md`](docs/README.md) и README внутри `scripts/*/`.
