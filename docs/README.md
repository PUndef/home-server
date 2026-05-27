# Документация home-server

Индекс markdown-файлов репозитория. Статусы: **living reference** (поддерживать актуальным), **completed setup** (завершённый runbook), **plan** (backlog), **archive** (история), **incident** (разовый runbook).

---

## Обзор

| Документ | Статус | Описание |
|----------|--------|----------|
| [overview/hardware-and-env.md](overview/hardware-and-env.md) | living reference | CPU, RAM, ВМ/LXC, сервисы, сеть, VPS — главный контекст для AI и человека |

---

## Сеть

| Документ | Статус | Описание |
|----------|--------|----------|
| [network/router-openwrt-x3000t.md](network/router-openwrt-x3000t.md) | living reference | OpenWrt X3000T: pbr, podkop, zapret, awg, workvpn, DNS |
| [network/router-resilience.md](network/router-resilience.md) | living reference | Отказоустойчивость: критический путь srv, протокол правок, recovery после reboot |
| [network/incidents/zapret-bypass-pundef-pc-2026-05-27.md](network/incidents/zapret-bypass-pundef-pc-2026-05-27.md) | incident | Bypass zapret для `pundef-pc` (Cursor Remote SSH) |

Скрипты: [`scripts/openwrt/`](../scripts/openwrt/)

---

## Proxmox / LXC

| Документ | Статус | Описание |
|----------|--------|----------|
| [proxmox/static-sites-lxc.md](proxmox/static-sites-lxc.md) | completed setup | LXC 102, Caddy, DNS, HTTPS edge |
| [proxmox/beszel-monitoring-setup.md](proxmox/beszel-monitoring-setup.md) | completed setup | Beszel hub + agents по инфраструктуре |

Код и deploy: [`static-sites/`](../static-sites/README.md)  
Скрипты: [`scripts/proxmox/`](../scripts/proxmox/), [`scripts/static-sites/`](../scripts/static-sites/)

---

## Nextcloud

| Документ | Статус | Описание |
|----------|--------|----------|
| [nextcloud/setup.md](nextcloud/setup.md) | completed setup | Установка и настройка Nextcloud |
| [nextcloud/onlyoffice.md](nextcloud/onlyoffice.md) | completed setup | ONLYOFFICE Document Server |
| [nextcloud/google-replacement-plan.md](nextcloud/google-replacement-plan.md) | plan | План замены Google-сервисов |

Edge-конфиг: [`nextcloud-vm/apache/`](../nextcloud-vm/apache/)

---

## Phoneserver

| Документ | Статус | Описание |
|----------|--------|----------|
| [phoneserver/pmos-setup.md](phoneserver/pmos-setup.md) | living reference | postmarketOS на Redmi Note 9 Pro |
| [phoneserver/operations.md](phoneserver/operations.md) | living reference | Повседневная эксплуатация, reboot, смена IP |

Скрипты: [`scripts/phoneserver/README.md`](../scripts/phoneserver/README.md)

---

## Планы (backlog)

| Документ | Статус | Описание |
|----------|--------|----------|
| [plans/owncord-setup.md](plans/owncord-setup.md) | plan (blocked) | Self-hosted Discord-аналог OwnCord |

---

## Правила оформления

Пошаговые setup-документы следуют [`.cursor/rules/home-server-docs.mdc`](../.cursor/rules/home-server-docs.mdc): один шаг — один блок, обязательный «Проверить», секция «Сделано (история)», единые статусы ✅ / пропущено / ⬜.
