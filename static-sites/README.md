# Static-sites

Исходники и конфигурация для LXC **static-sites** (VMID 102, `192.168.50.35`): маленькие фронты на Vite + React, отдача через Caddy.

Подробная инфраструктурная инструкция (создание LXC, DNS, HTTPS edge) — [`docs/proxmox/static-sites-lxc.md`](../docs/proxmox/static-sites-lxc.md).

## Структура

```text
static-sites/
├── README.md           # этот файл
├── Caddyfile           # маршрутизация на LXC (источник правды)
├── deploy.ps1          # деплой одного или всех приложений
├── shared/             # общий код (@shared alias во всех apps)
├── warframe/           # разводящая страница (карточки)
├── requiem/            # Requiem Helper
├── wf-farm/            # WF Farm Helper
└── wf-twitch/          # WF Twitch Drops tracker
```

Имена каталогов здесь **совпадают** с путями на сервере (`/srv/static-sites/<name>/`) и с path-префиксами Caddy (`/warframe/`, `/requiem/`, `/wf-farm/`).

## Приложения


| Каталог     | Назначение           | LAN (корень)            | Path / HTTPS                             |
| ----------- | -------------------- | ----------------------- | ---------------------------------------- |
| `warframe/` | Hub, карточки ссылок | `http://warframe.home/` | `https://apps-pundef.mooo.com/warframe/` |
| `requiem/`  | Requiem Helper       | `http://requiem.home/`  | `https://apps-pundef.mooo.com/requiem/`  |
| `wf-farm/`  | Farm / Drops lookup  | `http://wffarm.home/`   | `https://apps-pundef.mooo.com/wf-farm/`  |
| `wf-twitch/`| Twitch Drops schedule| `http://wftwitch.home/` | `https://apps-pundef.mooo.com/wf-twitch/` |


Beszel hub (`/beszel/`) — не статика, reverse proxy на `127.0.0.1:8090`; см. [`docs/proxmox/beszel-monitoring-setup.md`](../docs/proxmox/beszel-monitoring-setup.md).

## Быстрый старт

Локальная разработка (из каталога приложения):

```powershell
cd static-sites\requiem   # или wf-farm, warframe
npm ci
npm run dev
```

Деплой одного приложения:

```powershell
.\static-sites\requiem\scripts\deploy.ps1
.\static-sites\wf-farm\scripts\deploy.ps1
.\static-sites\wf-twitch\scripts\deploy.ps1
.\static-sites\warframe\scripts\deploy.ps1
```

Деплой всего сразу:

```powershell
.\static-sites\deploy.ps1
# или только hub + helpers:
.\static-sites\deploy.ps1 -App warframe
```

После правок `Caddyfile`:

```powershell
.\scripts\static-sites\apply-caddyfile.ps1
```

## Конвенции

- **Vite `base: "./"`** — один `dist` работает и с корня hostname (`requiem.home`), и под префиксом (`/requiem/`).
- **Ссылки между приложениями** — канон `static-sites/shared/site-urls.ts`, импорт через `@shared/site-urls` (alias в Vite/tsconfig). Breadcrumb — одинаковый компонент в requiem/wf-farm, тоже тянет `@shared/site-urls`.
- **UI** — shadcn, пресет `radix-mira` / `stone` (см. `components.json` в каждом приложении).
- **Deploy** — `npm ci && npm run build`, tar + scp на `deploy@192.168.50.35`, распаковка в `/srv/static-sites/<name>/`.
- **Новое приложение** — каталог `static-sites/<name>/`, блок в `Caddyfile` (`handle_path` + опционально `*.home` vhost), split-horizon DNS на OpenWrt, строка в таблице выше.

## DNS (OpenWrt, split-horizon)

```sh
uci add_list dhcp.@dnsmasq[0].address='/warframe.home/192.168.50.35'
uci add_list dhcp.@dnsmasq[0].address='/requiem.home/192.168.50.35'
uci add_list dhcp.@dnsmasq[0].address='/wffarm.home/192.168.50.35'
uci add_list dhcp.@dnsmasq[0].address='/wftwitch.home/192.168.50.35'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

Внешний edge: `apps-pundef.mooo.com` → Apache на nextcloud-vm → Caddy LXC; см. [`docs/proxmox/static-sites-lxc.md`](../docs/proxmox/static-sites-lxc.md).