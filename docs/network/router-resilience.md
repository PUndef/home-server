# Отказоустойчивость роутера и восстановление инфраструктуры

> **Статус:** living reference  
> **Последняя проверка:** 2026-05-28  
> **Связано:** [`router-openwrt-x3000t.md`](router-openwrt-x3000t.md), [`hardware-and-env.md`](../overview/hardware-and-env.md)

Домашняя инфраструктура (Proxmox, Nextcloud, Home Assistant, static-sites, мониторинг) **зависит от OpenWrt X3000T** не меньше, чем от самого Proxmox. Роутер — единственный шлюз для сегмента `srv` (`192.168.50.0/24`), DHCP, DNS split-horizon, NAT на Nextcloud и hotplug-восстановление VPN-стека. Ошибка в firewall, pbr, podkop или zapret может обрубить **весь** серверный сегмент, хотя `lan` (`192.168.1.0/24`) при этом остаётся живым.

Этот документ — runbook: как не уронить критичную инфраструктуру при правках и как поднять её после reboot или сбоя.

---

## Критический путь

```text
Провайдер (WAN)
    ↓
OpenWrt X3000T
    ├── lan 192.168.1.0/24  — клиенты, VPN/DPI (pbr, podkop, sing-box, zapret, awg*)
    └── srv 192.168.50.0/24 — Proxmox .9, nextcloud .34, haos .51, static-sites .35
            ↑
    физический порт lan2 (интерфейс srv на роутере)
```

**Что должно работать всегда для «живой» инфраструктуры:**

| Компонент | Проверка | Если сломано |
|-----------|----------|--------------|
| Интерфейс `srv` / `lan2` UP | `ifstatus srv` на роутере | Proxmox и все ВМ без маршрута наружу и без доступа с `lan` |
| DHCP leases на `srv` | `/tmp/dhcp.leases` содержит `.34`, `.35`, `.51` | ВМ теряют IP или не поднимаются после reboot |
| Forwarding `lan→srv`, `srv→wan` | LuCI Firewall / `nft list chain inet fw4 forward` | Nextcloud, HA, Proxmox UI недоступны с ПК |
| **Нет** forwarding `srv→awg1/awg2/workvpn` | `check_stack.py` → `vm-isolation-from-tunnels` | VM-трафик уходит в туннели / ломается DNS |
| zapret bypass для `192.168.50.0/24` | nft `zapret-ct-bypass-srv` | Серверный трафик модифицируется nfqws → странные обрывы HTTPS |
| Split-horizon DNS | `cloud-pundef.mooo.com` → `192.168.50.34` с роутера | Клиенты LAN не попадают на Nextcloud по домену |

Phoneserver (`192.168.1.116`) живёт в `lan`, не в `srv`, но **мониторит** homelab через Uptime Kuma и Beszel — его падение не роняет Proxmox, но слепнет наблюдаемость.

---

## Типичные сценарии «всё упало»

### 1. Сломан firewall / zone `srv`

**Симптомы:** с ПК (`192.168.1.x`) не открываются `https://192.168.50.9:8006`, `https://192.168.50.34`, `http://192.168.50.51:8123`; ping до `.50.x` не проходит.

**Частые причины:** случайно удалили forwarding `lan→srv`; перенесли `lan2` в другую zone; включили `reject` на input srv; добавили `srv→awg*` forwarding «для теста».

**Не делать:** массовый `uci commit firewall` без бэкапа и без `check_stack` до/после.

### 2. Каскадный рестарт VPN-стека

**Симптомы:** интернет на `lan` пропадает или «полумёртвый»; через 1–2 минуты частично возвращается; `srv` может отвалиться из-за зависшего dnsmasq/DHCP.

**Причина:** ручной рестарт `pbr` / `podkop` / `zapret` / `sing-box` **не в том порядке** или несколько раз подряд. На `wan`/`awg*` flap hotplug [`99-vpn-stack`](../../scripts/openwrt/99-vpn-stack) ждёт 10 с и рестартует: `sing-box → podkop → zapret → pbr`.

**Правило:** один компонент — один рестарт; подождать 30–60 с; прогнать health-check.

### 3. DHCP / DNS на `srv`

**Симптомы:** после reboot Proxmox или ВМ получают wrong IP или не получают lease; сервисы «есть», но с ПК не резолвятся домены.

**Проверка:** на роутере `cat /tmp/dhcp.leases | grep 192.168.50`.

### 4. zapret без bypass для srv

**Симптомы:** HTTPS к `.50.x` обрывается, curl висит, Nextcloud/Proxmox «то работает, то нет»; особенно после правок `custom.bypass_devices.sh`.

**Восстановление:** залить актуальный [`custom.bypass_devices.sh`](../../scripts/openwrt/custom.bypass_devices.sh) и `/etc/init.d/zapret restart`.

### 5. Физика / link down на `lan2`

**Симптомы:** полная изоляция `srv`; `lan` может работать.

**Проверка:** кабель Proxmox ↔ X3000T порт `lan2`; `ip -br link show lan2` на роутере.

---

## Протокол безопасных изменений на роутере

Перед **любой** правкой pbr, podkop, zapret, firewall, DHCP, DNS:

1. **Baseline:** с ПК `python start.py check_stack` (или `python scripts/openwrt/check_stack.py`). Сохранить вывод — эталон «до».
2. **Один шаг:** одно изменение (один `uci set`, один upload, один restart одного сервиса).
3. **Проверка srv отдельно:** с ПК:
   ```powershell
   curl -k -sS -o NUL -w "%{http_code}" https://192.168.50.9:8006/
   curl -k -sS -o NUL -w "%{http_code}" https://192.168.50.34/
   curl -sS -o NUL -w "%{http_code}" http://192.168.50.51:8123/
   ```
   Ожидается HTTP-код **не** `000`.
4. **Повторный health-check:** `check_stack` — все группы `vm-services` и `zapret-bypass` зелёные.
5. **Откат:** если `vm-services` красные — **сначала** откатить последнее изменение firewall/DHCP, **не** крутить podkop/pbr наугад.

### Порядок рестартов (если без hotplug)

Только если нужно вручную, **строго так**:

```sh
/etc/init.d/sing-box restart
sleep 5
/etc/init.d/podkop restart
sleep 5
/etc/init.d/zapret restart
/etc/init.d/pbr restart
```

Не рестартовать `network` / `firewall` на роутере без крайней необходимости — это роняет и `lan`, и `srv`, и все туннели одновременно.

### Что не трогать без явной цели

| Действие | Риск |
|----------|------|
| `srv→awg1/awg2/workvpn` forwarding | VM-трафик уходит в туннели; изоляция ломается |
| Отключить zapret bypass `192.168.50.0/24` | nfqws ломает HTTPS на srv |
| Менять IP/маску `srv` без правки Proxmox | Proxmox offline до ручного fix |
| `podkop` / `sing-box` disable «чтобы проверить WAN» | Ломается DNS для всего `lan` |
| Массовый `uci revert` без понимания | Можно откатить и рабочие резервации DHCP |

---

## После перезагрузки роутера (checklist)

Выполнять с ПК в LAN, по порядку:

| # | Действие | OK если |
|---|----------|---------|
| 1 | Ping `192.168.1.1` | ответ |
| 2 | `python start.py check_stack` | 0 failed; особенно `srv-zone-up`, `srv-vms-leased`, `vm-isolation-from-tunnels` |
| 3 | Proxmox UI `https://192.168.50.9:8006/` | страница логина |
| 4 | Nextcloud `https://cloud-pundef.mooo.com/` или `https://192.168.50.34/` | 2xx/3xx |
| 5 | HA `http://192.168.50.51:8123/` | UI |
| 6 | Static apps `https://apps-pundef.mooo.com/beszel/` | 2xx |
| 7 | Uptime Kuma `http://192.168.1.116:3001/` | UI (мониторы могут краснеть 1–2 мин — норма после cold start) |

Hotplug [`99-vpn-stack`](../../scripts/openwrt/99-vpn-stack) на `ifup wan|awg1|awg2` сам перезапускает стек через ~10 с. Если `check_stack` сразу после reboot показывает FAIL на `podkop`/`pbr` — **подождать 60 с и повторить**, не чинить вслепую.

На Proxmox после длительного outage ВМ могут быть stopped — это уже уровень гипервизора: `qm list`, `pct list`, autostart policies.

---

## Аварийный доступ (когда «всё мертво»)

| Узел | Как добраться | Заметки |
|------|---------------|---------|
| OpenWrt LuCI | `http://192.168.1.1/` с ПК в `lan` | SSH: `python scripts/openwrt/openwrt_exec.py "..."` |
| Proxmox | монитор+клавиатура к N150 **или** `192.168.50.9` если `srv` жив | gateway `.50.1` = роутер |
| Nextcloud VM | Proxmox → VM 101 console | если сеть srv мертва — только local console |
| phoneserver | USB `172.16.42.1` через WSL + `usbipd` | см. [`scripts/phoneserver/README.md`](../../scripts/phoneserver/README.md) |

Если недоступен только `srv`, но `192.168.1.1` жив — проблема почти наверняка в firewall/DHCP/`lan2`, а не в Proxmox.

---

## Быстрое восстановление по симптомам

### `srv` не pingуется с `lan`

1. На роутере: `ifstatus srv`, `ip -br a show lan2`
2. LuCI → Network → Interfaces → `srv` → Save & Apply **не** нажимать без бэкапа; сначала сравнить с [`router-openwrt-x3000t.md`](router-openwrt-x3000t.md)
3. LuCI → Firewall → проверить zone `srv`, forwarding `lan→srv`, `srv→wan`

### `srv` pingуется, HTTPS к `.50.x` — нет

1. `check_stack` → `zapret-bypass-srv-*`, `vm-isolation-from-tunnels`
2. Перезалить `custom.bypass_devices.sh`, `zapret restart`
3. Проверить нет ли новых `accept_to_awg*` в `forward_srv`

### Интернет на `lan` есть, Proxmox нет

1. Кабель / `lan2`
2. DHCP leases
3. Firewall (не DNS и не podkop — они `lan`, не `srv`)

### После правок pbr/podkop «упало всё»

1. Подождать 60 с (hotplug)
2. `check_stack`
3. Если не помогло — ручной рестарт по порядку (см. выше)
4. В крайнем случае — reboot роутера **только** когда записан последний рабочий `uci export` / есть доступ к физическому LuCI

---

## Мониторинг и профилактика

| Инструмент | Назначение |
|------------|------------|
| [`check_stack.py`](../../scripts/openwrt/check_stack.py) | Полный стек + `vm-services` + phoneserver lease |
| Uptime Kuma на phoneserver | Внешние/HTTPS пробы homelab |
| Beszel | Метрики хостов и agents |
| [`podkop-subnets-watchdog.sh`](../../scripts/openwrt/podkop-subnets-watchdog.sh) | Cron: пустой `podkop_subnets` → list_update |

**Рекомендация:** перед и после каждой сессии правок на роутере — `check_stack`. При плановом reboot роутера — checklist выше.

---

## Сделано (история)

| Дата | Что |
|------|-----|
| 2026-05-28 | Первый runbook: критический путь, протокол изменений, post-reboot checklist, сценарии recovery |
