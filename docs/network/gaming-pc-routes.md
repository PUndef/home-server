# Маршрутизация игрового ПК (pundef-pc)

> **Статус:** living reference  
> **Последняя проверка:** 2026-06-12

Единая схема для `pundef-pc` — eth `192.168.1.133`, Wi‑Fi `192.168.1.208` (dual-NIC).  
**Catch-all `0.0.0.0/0` запрещён** — он ломает podkop fake-IP (Discord и др.).

---

## Таблица маршрутов


| Трафик               | Домены / IP                                                             | Куда                          | Механизм                         | DNS                   | Автовосстановление                                                                                                                                                  |
| -------------------- | ----------------------------------------------------------------------- | ----------------------------- | -------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Steam** (загрузки) | `steampowered.com`, CDN, `steamstatic.com`                              | **WAN**                       | pbr `pundef-pc steam via wan`    | реальные IP (nftset)  | `apply-pundef-pc-routes.sh`                                                                                                                                         |
| **Nexus Mods**       | `nexusmods.com`                                                         | **WAN**                       | pbr `pundef-pc nexus via wan`    | реальные IP           | то же                                                                                                                                                               |
| **Destiny / Bungie** | `bungie.net`, `steamserver.net`, `deadorbit.net`, `gravityshavings.net` | **awg2** (NL)                 | pbr `pundef-pc destiny via awg2` | bypass → `8.8.8.8`    | TAPIR — гео-блок на **авторизации** ([обход](https://github.com/Flowseal/zapret-discord-youtube/discussions/6033)); `steamserver.net` уходит в awg2, не в Steam WAN |
| **Warframe**         | `warframe.com`, `digitalextremes.com`                                   | **awg2**                      | pbr global `Warframe via awg2`   | подкоп / реальные     | то же                                                                                                                                                               |
| **Discord**          | `discord.com`, `discord.gg`, …                                          | **awg2** (через реальные IP)  | dns bypass + default path        | bypass → `8.8.8.8`    | то же                                                                                                                                                               |
| **Corp**             | `*.kpb.lt`, `10.0.160.0/22`                                             | **workvpn**                   | pbr `pundef-pc kpb via workvpn`  | `10.0.160.1`          | `pbr-workvpn-watchdog.sh`                                                                                                                                           |
| **Всё остальное**    | любые                                                                   | **podkop → awg2** или **WAN** | без pbr catch-all                | fake-IP `198.18.x` OK | podkop / sing-box                                                                                                                                                   |


### Приоритет pbr (сверху вниз, для `.133` / `.208`)

```text
1. pundef-pc nexus via wan      (если dst Nexus)
2. pundef-pc steam via wan    (если dst Steam)
3. pundef-pc kpb via workvpn  (corp — выше игр)
4. pundef-pc destiny via awg2 (Bungie)
5. Warframe via awg2          (глобально, все клиенты)
6. — НЕТ catch-all —
7. podkop / default WAN
```

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

- **Не** добавлять постоянный `pundef-pc games via awg2` с `0.0.0.0/0` — ломает Discord и podkop. Временный catch-all только через `login --full` + `normal` после входа.
- **Не** чинить каждый сервис отдельным скриптом без обновления `apply-pundef-pc-routes.sh`.
- **Не** использовать `switch_steam_route.py awg2` — режим удалён; Steam всегда WAN, Destiny — отдельная политика.

---

## Файлы


| Файл                                                                                 | Назначение                                |
| ------------------------------------------------------------------------------------ | ----------------------------------------- |
| `[apply-pundef-pc-routes.sh](../../scripts/openwrt/apply-pundef-pc-routes.sh)`       | Каноническое состояние на роутере `/opt/` |
| `[apply_pundef_pc_routes.py](../../scripts/openwrt/apply_pundef_pc_routes.py)`       | Deploy + apply с ПК                       |
| `[check_gaming_pc_routes.py](../../scripts/openwrt/check_gaming_pc_routes.py)`       | Smoke-test                                |
| `[pundef-pc-routes-watchdog.sh](../../scripts/openwrt/pundef-pc-routes-watchdog.sh)` | Cron self-heal                            |


См. также: `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`, `[router-resilience.md](router-resilience.md)`.