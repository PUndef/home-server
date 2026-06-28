# Маршрутизация игрового ПК (pundef-pc)

> **Статус:** living reference  
> **Последняя проверка:** 2026-06-14

Единая схема для `pundef-pc` — eth lan `192.168.1.133`, Wi‑Fi `192.168.1.208`, **eth srv (Mercusys → lan2) `192.168.50.133`**.  
**Catch-all `0.0.0.0/0` на lan запрещён** — ломает podkop fake-IP (Discord и др.). На **srv** catch-all через awg2 **разрешён** только для `192.168.50.133`: там DNS `8.8.8.8`, fake-IP podkop нет.

---

## Топология (Mercusys / dual-homed)

```text
X3000T lan3/lan4 + WiFi ──► 192.168.1.133 (eth lan) / .208 (wlan)
                              podkop, pbr per-app, workvpn, zapret per-IP

Mercusys switch ──► X3000T lan2 (srv) ──► 192.168.50.133 (eth srv)
                              Proxmox .9, phoneserver .127, ВМ .34/.35, …
                              DNS 8.8.8.8 (без sing-box); pbr src .50.133 → awg2
```

**Физика:** игровой ПК, Proxmox и phoneserver eth висят на одном **Mercusys-коммутаторе** в порту `lan2` (zone `srv`). Wi‑Fi и отдельный eth в `lan` — опционально, для corp (`workvpn`) и когда нужен podkop без catch-all.

**Важно:** с `srv` **нельзя** SSH/LuCI на роутер (fw4 reject на `lan2`) — deploy только с `lan` (`192.168.1.1`) или Wi‑Fi `192.168.1.x`.

---

## Таблица маршрутов


| Трафик               | Домены / IP                                                             | Куда                          | Механизм                         | DNS                   | Автовосстановление                                                                                                                                                  |
| -------------------- | ----------------------------------------------------------------------- | ----------------------------- | -------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Steam** (загрузки) | `steampowered.com`, CDN, `steamstatic.com`                              | **WAN**                       | pbr `pundef-pc steam via wan`    | реальные IP (nftset)  | `apply-pundef-pc-routes.sh`                                                                                                                                         |
| **Nexus Mods**       | `nexusmods.com`                                                         | **WAN**                       | pbr `pundef-pc nexus via wan`    | реальные IP           | то же                                                                                                                                                               |
| **RU local (2GIS)**  | `2gis.ru`, `dublgis.ru`                                                 | **WAN**                       | pbr `pundef-pc ru-local via wan` | bypass → `8.8.8.8`    | иначе srv catch-all уводит в awg2                                                                                                                                   |
| **Destiny / Bungie** | `bungie.net`, `steamserver.net`, `deadorbit.net`, `gravityshavings.net` | **awg2** (NL)                 | pbr `pundef-pc destiny via awg2` | bypass → `8.8.8.8`    | TAPIR — гео-блок на **авторизации** ([обход](https://github.com/Flowseal/zapret-discord-youtube/discussions/6033)); `steamserver.net` уходит в awg2, не в Steam WAN |
| **Warframe**         | `warframe.com`, `digitalextremes.com`                                   | **awg2**                      | pbr global `Warframe via awg2`   | подкоп / реальные     | то же                                                                                                                                                               |
| **Discord**          | `discord.com`, `discord.gg`, …                                          | **awg2** (через реальные IP)  | dns bypass + default path        | bypass → `8.8.8.8`    | то же                                                                                                                                                               |
| **Corp**             | `*.kpb.lt`, `10.0.160.0/22`                                             | **workvpn**                   | pbr `pundef-pc kpb via workvpn`  | `10.0.160.1`          | `pbr-workvpn-watchdog.sh`                                                                                                                                           |
| **Всё остальное (lan)** | любые                                                                | **podkop → awg2** или **WAN** | без pbr catch-all                | fake-IP `198.18.x` OK | podkop / sing-box                                                                                                                                                   |
| **Всё остальное (srv / Mercusys)** | любые не попавшие в Steam/Nexus/Destiny above              | **awg2**                      | pbr `pundef-pc srv default via awg2` | реальные IP (`8.8.8.8`) | `apply-pundef-pc-routes.sh`                                                                                                                                      |


### Приоритет pbr (lan: `.133` / `.208`)

```text
1. pundef-pc nexus via wan      (если dst Nexus)
2. pundef-pc steam via wan      (если dst Steam)
3. pundef-pc ru-local via wan   (2GIS и др. RU-сервисы)
4. pundef-pc kpb via workvpn    (corp — только lan .133)
5. pundef-pc destiny via awg2   (Bungie)
6. Warframe via awg2            (глобально, все клиенты)
7. — НЕТ catch-all на lan —
8. podkop / default WAN
```

### Приоритет pbr (srv / Mercusys: `192.168.50.133`)

```text
1. pundef-pc nexus via wan
2. pundef-pc steam via wan
3. pundef-pc ru-local via wan   (2GIS — иначе попадает в catch-all)
4. pundef-pc destiny via awg2
5. pundef-pc srv default via awg2   (0.0.0.0/0 — YouTube, Discord, прочее)
```

Corp `workvpn` и per-IP zapret bypass (`.133`) действуют только когда источник **lan** `192.168.1.133` / `.208`. С eth srv corp GitLab не маршрутизируется — для WSL/Cursor Remote SSH используй lan или Wi‑Fi.

---

## Известные риски (без catch-all)


| Риск                           | Что может сломаться                                  | Обход                                                                                                  |
| ------------------------------ | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **UDP на случайные IP**        | Warframe in-game chat/relay; Destiny matchmaking P2P | Явные домены покрывают API/лаунчер; UDP вне списка идёт через podkop/WAN — **может не работать из RU** |
| **TAPIR Destiny**              | Гео-блок Bungie на входе (СНГ)                       | Домены выше → awg2; если остаётся — патч/аккаунт (CAT)                                                 |
| **steamserver.net через awg2** | Часть Steam-трафика может идти медленнее туннелем    | Осознанный tradeoff ради Destiny login                                                                 |
| **pbr wildcard `*.domain`**    | В логах `ERROR: Unknown entry`                       | Обычно nftset всё равно заполняется; при поломке — убрать `*.` из dest_addr                            |
| **Битые политики `Untitled`**  | pbr restart с ошибками                               | `apply-pundef-pc-routes.sh` удаляет пустые                                                             |
| **Перезагрузка роутера**       | Политики слетают, если только в RAM                  | hotplug + cron watchdog                                                                                |
| **PC на srv без pbr**          | YouTube/Discord таймаут (голый RU WAN)               | `apply_pundef_pc_routes.py`; eth должен быть `.50.133`, не случайный `.50.x`                          |
| **RU-сайты через VPN на srv**  | 2GIS и др. уходят в awg2 из-за srv catch-all         | политика `pundef-pc ru-local via wan`; `apply_pundef_pc_routes.py`                                    |
| **Deploy с srv**               | SSH/LuCI на `192.168.1.1` недоступны                 | Подключиться к домашнему Wi‑Fi или lan-кабелю X3000T, затем deploy                                     |
| **Corp с Mercusys**            | `*.kpb.lt` не идёт в workvpn                         | Переключиться на lan `.133` / Wi‑Fi `.208`                                                             |


---

## Destiny: режим логина (TAPIR)

Steam-auth на входе должен идти через туннель (не RU WAN). После входа в игру — вернуть Steam на WAN.

```powershell
# Перед запуском Destiny (закрой Steam, потом снова открой):
py -3 scripts/openwrt/destiny_login_mode.py login

# Если TAPIR остаётся — полный туннель только на время входа (как VPN на весь ПК):
py -3 scripts/openwrt/destiny_login_mode.py login --full

# Другой egress (тест): --tunnel awg1
py -3 scripts/openwrt/destiny_login_mode.py login --full --tunnel awg1

# После того как оказался В МИРЕ (башня / корабль / патруль), НЕ на экране персонажей:
py -3 scripts/openwrt/destiny_login_mode.py normal
# Скрипт «висит» ~30–60 с (pbr restart) — не запускать во время загрузки.

# Статус:
py -3 scripts/openwrt/destiny_login_mode.py status
```

Пока активен login mode, файл `/etc/destiny-login-mode` на роутере — watchdog и `apply-pundef-pc-routes` **не откатывают** Steam на WAN.

## Один скрипт — один источник правды

```powershell
# Применить / починить всё (normal mode):
py -3 scripts/openwrt/apply_pundef_pc_routes.py --install-cron

# Проверить:
py -3 scripts/openwrt/check_gaming_pc_routes.py
```

### Автовосстановление после reboot / flap


| Триггер                                       | Действие                                                     |
| --------------------------------------------- | ------------------------------------------------------------ |
| hotplug `99-vpn-stack` на `wan`/`awg1`/`awg2` | после `pbr restart` → `/opt/apply-pundef-pc-routes.sh`       |
| cron каждые 15 мин                            | `pundef-pc-routes-watchdog.sh` → `--check-only` или re-apply |
| Ручной откат                                  | `py -3 scripts/openwrt/apply_pundef_pc_routes.py`            |


---

## Что НЕ делать

- **Не** добавлять постоянный `pundef-pc games via awg2` с `0.0.0.0/0` на **lan** — ломает Discord и podkop. На **srv** (Mercusys) catch-all только как `pundef-pc srv default via awg2` для `192.168.50.133`.
- **Не** чинить каждый сервис отдельным скриптом без обновления `apply-pundef-pc-routes.sh`.
- **Не** использовать `switch_steam_route.py awg2` — режим удалён; Steam всегда WAN, Destiny — отдельная политика.
- **Не** считать, что eth в `srv` «само» получит VPN — без pbr src `.50.133` трафик идёт в WAN.

---

## Файлы


| Файл                                                                                 | Назначение                                |
| ------------------------------------------------------------------------------------ | ----------------------------------------- |
| `[apply-pundef-pc-routes.sh](../../scripts/openwrt/apply-pundef-pc-routes.sh)`       | Каноническое состояние на роутере `/opt/` |
| `[apply_pundef_pc_routes.py](../../scripts/openwrt/apply_pundef_pc_routes.py)`       | Deploy + apply с ПК                       |
| `[check_gaming_pc_routes.py](../../scripts/openwrt/check_gaming_pc_routes.py)`       | Smoke-test                                |
| `[reserve-pundef-pc-dhcp.sh](../../scripts/openwrt/reserve-pundef-pc-dhcp.sh)`       | DHCP lan `.133` + srv `.133` (Mercusys); Wi‑Fi `.208` — отдельный MAC при необходимости |
| `[pundef-pc-routes-watchdog.sh](../../scripts/openwrt/pundef-pc-routes-watchdog.sh)` | Cron self-heal на роутере                                                               |


## Сделано (история)

Пункты, которые уже выполнены. Оставлены для истории; в текущем плане не повторять.

| Когда      | Что сделано |
| ---------- | ----------- |
| 2026-06-14 | **Mercusys / srv:** pbr `pundef-pc srv default via awg2` для `192.168.50.133`; DHCP `pundef-pc-srv`; deploy через `apply_pundef_pc_routes.py --install-cron`. YouTube/Discord по eth srv — HTTP 200. |
| 2026-06-12 | Канон без lan catch-all: Steam/Nexus WAN, Destiny/Discord awg2, watchdog + hotplug. |

См. также: `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`, `[router-resilience.md](router-resilience.md)`.