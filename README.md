# home-server

Документация, скрипты и исходники домашней инфраструктуры: Proxmox, OpenWrt, Nextcloud, static-sites, phoneserver.

**Точка входа в документацию:** [`docs/README.md`](docs/README.md)  
**Живой контекст (железо, IP, сервисы):** [`docs/overview/hardware-and-env.md`](docs/overview/hardware-and-env.md)

---

## Инвентарь узлов

| VMID / узел | Имя | IP | Роль |
|-------------|-----|-----|------|
| 100 | haos17.0 | 192.168.50.51 | Home Assistant |
| 101 | nextcloud-vm | 192.168.50.34 | Nextcloud, ONLYOFFICE, Apache edge (`apps-pundef.mooo.com`) |
| 102 | static-sites (LXC) | 192.168.50.35 | Caddy, Warframe apps, Beszel hub |
| — | pundef (Proxmox host) | 192.168.50.9 | Гипервизор |
| — | phoneserver | 192.168.1.116 | postmarketOS: Beszel agent, Uptime Kuma |
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
├── start.py               # интерактивный запуск OpenWrt-скриптов
└── README.md              # этот файл
```

---

## Частые команды

| Задача | Команда |
|--------|---------|
| Сводка по ВМ/LXC | `python scripts/proxmox/check_vms.py` |
| Health-check роутера | `python start.py check_stack` |
| Деплой static-sites | `.\static-sites\deploy.ps1` |
| Применить Caddyfile | `.\scripts\static-sites\apply-caddyfile.ps1` |
| Деплой одного app | `.\static-sites\requiem\scripts\deploy.ps1` |
| SSH на OpenWrt | `python scripts/openwrt/openwrt_exec.py "<cmd>"` |
| SSH на Proxmox | `python scripts/proxmox/proxmox_exec.py "<cmd>"` |

Полный каталог скриптов — в [`docs/README.md`](docs/README.md) и README внутри `scripts/*/`.
