# Миграция: OpenWrt X3000T становится основным роутером (ASUS RT-AX55 выключен)

Контекст: `[hardware-and-env.md](hardware-and-env.md)`, `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`.

Целевая топология после миграции:

```
провайдер → WAN OpenWrt X3000T (DHCP, белый IP) → две зоны:
                              ├── lan  192.168.1.0/24  — клиенты (ПК, Mac, телефоны), pbr/podkop/zapret/awg1/awg2/workvpn
                              └── srv  192.168.50.0/24 — Proxmox + ВМ, без туннелей и DPI
```

Один LAN-порт `lan2` X3000T выделен под серверный сегмент `srv` (untagged, без VLAN — отдельный физический интерфейс).

---

## Что уже сделано (подготовительная фаза, без простоя)

- Snapshot OpenWrt: `D:\repositories\home-server\backups\owrt-pre-mainrouter-2026-05-10.tar.gz`.
- Установлен `ddns-scripts` + `luci-app-ddns`, настроен сервис `cloud_pundef` с Direct URL FreeDNS, `ip_source=web` (`https://checkip.amazonaws.com/`). DDNS уже корректно резолвит белый IP `5.189.245.251`.
- В `/etc/config/network` создан `interface srv` (`device='lan2'`, `192.168.50.1/24`, `disabled=1`). Порт `lan2` исключён из `br-lan`.
- DHCP-сервер `dhcp.srv` (`100..199`, leasetime 12h, `dhcp_option='6,8.8.8.8,1.1.1.1'`) — серверы получают upstream DNS, минуя `dnsmasq` роутера.
- Firewall: zone `srv` (input REJECT, output ACCEPT, forward REJECT), rule `Allow-DHCP-DNS-srv`, forwarding `lan→srv` и `srv→wan`. Туннели `awg1/awg2/workvpn` для `srv` намеренно НЕ открыты.
- Split-horizon DNS: `dnsmasq.@dnsmasq[0].address='/cloud-pundef.mooo.com/192.168.50.34'` — клиенты резолвят домен напрямую в локальный IP Nextcloud, без NAT loopback.
- Port-forwards `wan: 80 → srv:192.168.50.34:80` и `wan: 443 → srv:192.168.50.34:443`.
- zapret bypass: в `/opt/zapret/custom.bypass_devices.sh` добавлен `ct original ip saddr 192.168.50.0/24 return` (и зеркальное правило в `prenat`). Источник в репо: `[scripts/openwrt/custom.bypass_devices.sh](scripts/openwrt/custom.bypass_devices.sh)`.
- Скрипт-активатор `migration-activate-srv.sh` уже на роутере в `/root/`. Источник: `[scripts/openwrt/migration-activate-srv.sh](scripts/openwrt/migration-activate-srv.sh)`.
- DNS на хосте Proxmox (`pundef`, статика, `/etc/resolv.conf` правился руками 8 февраля) переключён с `192.168.50.1` на `1.1.1.1` + `8.8.8.8`. Резолв проверен (`deb.debian.org`, `cloud-pundef.mooo.com`).
- Static-leases в `dhcp` на OpenWrt:
  - `nextcloud-vm` (MAC `02:CC:61:7E:E7:7B`) → `192.168.50.34`, `infinite`.
  - `haos17` (MAC `02:DF:3B:CA:E9:AC`) → `192.168.50.51`, `infinite`.
  Это критично: у обеих ВМ в Proxmox `iface inet dhcp`, фиксированные IP сейчас обеспечивает резервация в ASUS. Когда ASUS отключим, без этих записей dnsmasq на OpenWrt выдал бы им случайные IP из `192.168.50.100..199`, и сломались бы port-forward, `trusted_domains` Nextcloud и т.д.

Подготовительные изменения **обратимы** и не влияют на рабочий трафик: `srv` отключён, `lan2` без линка.

---

## День X — switch-over

### Шаг 1. До перетыкания кабелей

Желательно делать в окно низкой нагрузки (никто не работает на Nextcloud/HA, бэкапы не идут).

1. Записать текущий MAC WAN ASUS на бумажку — на случай, если провайдер привязал тебя к нему. Команда на ASUS / в его LuCI / на наклейке.
2. **DNS уже подготовлен** (см. чек-лист выше). Конкретно:
  - Хост Proxmox `pundef` (статика `192.168.50.9`) — `/etc/resolv.conf` уже переписан на `1.1.1.1` + `8.8.8.8`. Файл правился руками, ничем не управляется (systemd-resolved неактивен, resolvconf не установлен).
  - VM 101 `nextcloud-vm` — `iface eth0 inet dhcp`, после переезда в `srv` получит DNS из `dhcp_option='6,8.8.8.8,1.1.1.1'` нашего dhcp.srv.
  - VM 100 `haos17.0` — Supervisor connection NetworkManager, eth0 на DHCP. То же самое, DNS придёт от OpenWrt.
3. На Nextcloud-vm проверить, что `certbot` следующий запуск не ближе чем через несколько часов:
  ```sh
   qm guest exec 101 -- systemctl list-timers certbot.timer
  ```
   Сейчас `Sun 2026-05-10 10:30:55 UTC` — это значит ближайший запуск через ~8 минут после фактической миграции, **специально подгадай так, чтобы switch-over закончился ДО этого момента**, либо подвинь таймер: `qm guest exec 101 -- systemctl stop certbot.timer` и потом `... start certbot.timer` после успешного switch-over.

### Шаг 2. Физическая перекоммутация (1–3 минуты)

1. Выключить ASUS (питание). DDNS на ASUS перестанет обновляться — это уже не страшно, на OpenWrt он работает.
2. Кабель **провайдера** (был в WAN ASUS) → в **WAN** X3000T.
3. Кабель **Proxmox-хоста** (был в LAN ASUS) → в **LAN2** X3000T (это серверный порт `lan2`, который мы готовили под `srv`).
4. Все остальные кабели LAN3/LAN4 X3000T и WiFi — НЕ трогать.

### Шаг 3. Активация серверного сегмента (на роутере)

Открыть SSH в OpenWrt (`192.168.1.1`) и запустить:

```sh
sh /root/migration-activate-srv.sh
```

Скрипт:

1. Убедится, что `WAN` получил реальный белый IP (не `192.168.50.x`).
2. Снимет `disabled=1` с `srv`, поднимет интерфейс на `lan2`.
3. Перезапустит firewall, ddns, sing-box → podkop → zapret → pbr (в правильном порядке), пере-привинтит маршруты GitHub через `awg1`.
4. Покажет статус.

При фейле на шаге 1 (`WAN still in 192.168.50.0/24 or empty`) — кабель провайдера не подцепился или провайдер требует MAC-clone. Решение:

```sh
# клонировать MAC ASUS, если у провайдера привязка:
uci set network.wan.macaddr='AA:BB:CC:DD:EE:FF'   # старый MAC ASUS WAN
uci commit network && /etc/init.d/network restart
ifup wan
```

### Шаг 4. Проверки с ПК (LAN, `192.168.1.x`)

```powershell
nslookup cloud-pundef.mooo.com 192.168.1.1   # → 192.168.50.34 (split-horizon)
nslookup api.openai.com         192.168.1.1   # реальный IP, маршрут через awg1
nslookup ap.spotify.com         192.168.1.1   # реальный IP, не 198.18.x.x
tracert 8.8.8.8                                # после 192.168.1.1 → провайдерский шлюз
python d:\repositories\home-server\scripts\openwrt\check_stack.py
```

В браузере: `https://cloud-pundef.mooo.com/` — ОК, валидный сертификат.

### Шаг 5. Проверки снаружи (с телефона по 4G)

- `https://cloud-pundef.mooo.com/` — открывается.
- `curl -I http://cloud-pundef.mooo.com/.well-known/acme-challenge/test` — 80-й порт доходит до Nextcloud (нужно для autorenew Let's Encrypt).

### Шаг 6. Проверки из ВМ

Через консоль Proxmox / HA OS:

```sh
# на nextcloud-vm
ip route          # default via 192.168.50.1 dev ens18
ping -c2 1.1.1.1
curl -s ifconfig.me   # должен вернуть твой белый IP, НЕ 89.44.76.52 (Fin) и НЕ 45.154.35.222 (Neth)
traceroute -n 1.1.1.1 # после 192.168.50.1 → провайдер, без awg1/awg2
```

Если `ifconfig.me` отдаёт `89.44.76.x` или `45.x` — что-то из ВМ ушло в туннель. Проверить, какой DNS у ВМ (см. Шаг 1.2) и список `pbr policies` (`uci show pbr | grep -E '@policy'`).

### Шаг 7. Косметика

```sh
# на роутере
logread | grep -iE 'ddns|wan' | tail -30   # последняя запись DDNS — успешный update новым IP
ip route                                    # default via <провайдерский шлюз> dev wan
```

Если белый IP сменился — FreeDNS получит апдейт уже при первом тике updater'а, или сразу через `ifup`-hotplug. Подождать 5–10 минут и проверить:

```sh
nslookup cloud-pundef.mooo.com 1.1.1.1
```

Должен ответить новым внешним IP.

### Шаг 8. Документация

Обновить:

- `[hardware-and-env.md](hardware-and-env.md)` — топология "провайдер → X3000T", таблица port-forward теперь на OpenWrt, удалить упоминание ASUS как шлюза, обновить заметку про правило `6881–6889 → 192.168.50.61` (правило не нужно).
- `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)` — секция WAN: DHCP к провайдеру (вместо `192.168.50.20/24` за ASUS); добавить раздел про `srv` (`192.168.50.0/24`, отдельный физический LAN-порт `lan2`, отдельная firewall zone, изоляция от pbr/podkop/zapret); раздел про port-forward; раздел про DDNS; обновить hairpin-секцию (split-horizon DNS вместо упоминания, что hairpin делает ASUS).

---

## План отката (на случай если что-то пошло не так)

Если в течение 30 минут после Шага 3 что-то критично сломалось:

1. Подать питание на ASUS, дождаться загрузки (~1 минута).
2. Кабель провайдера обратно в WAN ASUS.
3. Кабель Proxmox обратно в LAN ASUS.
4. На OpenWrt:
  ```sh
   uci set network.srv.disabled='1'
   uci commit network && ifdown srv
   /etc/init.d/firewall restart
  ```
5. WAN OpenWrt получит обратно `192.168.50.20` от ASUS DHCP.
6. Старая схема "провайдер → ASUS → OpenWrt" восстановлена.
7. Снять снимок чем были не довольны, разобраться, повторить.

Сделанные подготовительные правки (DDNS, port-forwards, split-horizon DNS, zapret bypass для srv) на старой схеме безвредны: DDNS обновляет на тот же белый IP, port-forwards не получают трафик (на WAN-IP `192.168.50.20` извне никто не стучится), split-horizon делает то же что было раньше через NAT loopback, zapret bypass холостой (нет трафика с saddr 192.168.50.x на wan).

---

## Чек-лист "после миграции — прибраться"

- Удалить `migration-asus-to-openwrt.md` или оставить как историю (рекомендую оставить).
- Удалить `/root/migration-activate-srv.sh` с роутера, если не нужен.
- В `dhcp` на OpenWrt опционально завести static-leases для `pundef` (Proxmox) / `nextcloud-vm` / `haos17.0` по их MAC, если внутри ВМ переключали DNS/IP.
- Подумать о mDNS/Avahi между `lan` и `srv` (если хочется заходить на `nextcloud-vm.local` с ПК) — `avahi-daemon` + `enable-reflector`.
- Через неделю — проверить, что autorenew Let's Encrypt сработал на Nextcloud (`certbot certificates`).

