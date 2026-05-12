# Xiaomi X3000T (OpenWrt 24.10) — актуальная схема

Справочник по **текущей** домашней конфигурации. Ключи AmneziaWG, пароли и токены в репозиторий не копировать.

**LuCI** с LAN (`192.168.1.0/24`):

- [http://192.168.1.1/](http://192.168.1.1/)
- [http://openwrt.lan/cgi-bin/luci/](http://openwrt.lan/cgi-bin/luci/)

---

## Топология

Провайдер → **WAN Xiaomi/OpenWrt** (DHCP, белый IP `5.189.245.251`) → две firewall zone на X3000T:

- `lan` `192.168.1.0/24` — клиенты (ПК, Mac, телефоны), порты `lan3 lan4` X3000T + WiFi. Здесь работает вся машинерия: pbr / podkop / sing-box / zapret / awg1 / awg2 / workvpn.
- `srv` `192.168.50.0/24` — Proxmox + ВМ, отдельный физический порт `lan2` X3000T. Forwarding только `srv→wan` и `lan→srv`. **Никаких** туннелей и DPI: zapret bypass-нут по `ct original ip saddr 192.168.50.0/24 return`.

Проброс портов, белый IP, DDNS, NAT — теперь на OpenWrt (был ASUS RT-AX55 до 2026-05-10; ASUS снят). История миграции: `[migration-asus-to-openwrt.md](migration-asus-to-openwrt.md)`. Общий контекст дома: `[hardware-and-env.md](hardware-and-env.md)`.

---

## Прошивка


| Параметр   | Значение                                                              |
| ---------- | --------------------------------------------------------------------- |
| Устройство | Xiaomi X3000T                                                         |
| Система    | **OpenWrt 24.10.6** (`r29141-81be8a8869`), LuCI ветка `openwrt-24.10` |


---

## Цель маршрутизации (как сейчас)

```text
Обычный трафик              → WAN → ASUS → провайдер
Автообход блокировок        → podkop + sing-box (tproxy, fakeip, community lists)
AI / Cursor домены          → pbr policy «AI Tools via awg1 (global)» → awg1 (Fin)
Mangalib (geo/RU блокировки)→ pbr policy «Mangalib via awg1» → awg1 (Fin)
Spotify (NL-аккаунт)        → pbr policy «Spotify via awg2 (Neth NL)» → awg2 (Neth)
Корпоративные домены        → pbr policy «paul-mac kpb via workvpn» → vpn-workvpn
DPI                         → zapret / nfqws на WAN-потоках (mark не пересекается с pbr)
Default route               → всегда WAN, не в туннели
```

### Кто за что отвечает

- **dnsmasq** — корневой резолвер LAN (`192.168.1.1:53`). Имеет per-domain upstream:
  - `*.spotify.com`, `*.scdn.co`, `*.spotifycdn.com/.net`, `pscdn.co` → `8.8.8.8` (мимо подкопа), чтобы получать **реальные** IP, а не fake-IP.
  - `*.kpb.lt` → `10.0.160.1` (внутренний DNS workvpn).
  - всё остальное → `127.0.0.42` (DNS-инбаунд `sing-box` подкопа: rule_set + fake-IP).
- **pbr** — выбор маршрута по `dst_addr` (через `nftset`-сеты) и/или `src_addr`. Раздаёт mark, ставит `ip rule` в свои таблицы.
- **podkop / sing-box** — основной автообход. Перехватывает трафик в community-листы и `198.18.0.0/15` через `tproxy → 127.0.0.1:1602` и выпускает наружу через `bind_interface=awg1`.
- **AmneziaWG `awg1`** — туннель в Fin VPS (`89.44.76.52`).
- **AmneziaWG `awg2`** — туннель в Neth VPS (`45.154.35.222`, NL/Amsterdam). Используется только под Spotify-policy.
- **OpenConnect `vpn-workvpn`** — корпоративный VPN, поднимается с парой `username/password`, маршрут только для `paul-mac` (DHCP-резервация `26:C5:4C:20:C5:AD → 192.168.1.198`) и `*.kpb.lt`.
- **zapret / nfqws** — модификация первых пакетов TCP/UDP уже выбранных WAN-потоков; маршрут не выбирает.

---

## Древовидная схема: путь пакета

Дерево читается сверху вниз: пакет приходит с LAN, проходит DNS-стадию (резолв) и стадию решения о маршруте, и в конце уходит через один из выходов.

```mermaid
graph TD
  L[LAN client 192.168.1.x]

  L --> DNS{DNS query на 192.168.1.1}
  DNS -->|*.spotify.com\n*.scdn.co\n*.spotifycdn.com\n*.spotifycdn.net\npscdn.co| DNS_DIR[dnsmasq → 8.8.8.8\nреальные IP]
  DNS -->|*.kpb.lt| DNS_WORK[dnsmasq → 10.0.160.1\ninternal corp DNS]
  DNS -->|community lists\ntelegram, google_ai,\ngoogle_play, russia_inside| DNS_PD[dnsmasq → sing-box\nfake-IP 198.18.0.x]
  DNS -->|остальное| DNS_FW[dnsmasq → sing-box → upstream]

  L --> PKT[TCP/UDP пакет с dst IP]

  PKT --> MARK{mangle prerouting:\nкто первым ставит mark?}

  MARK -->|dst в pbr_awg2 set\n_real Spotify IPs_| MK_AWG2[mark 0x00040000]
  MARK -->|dst в pbr_awg1 set\n_AI/Cursor + Mangalib IPs_| MK_AWG1[mark 0x00020000]
  MARK -->|src=192.168.1.198 +\ndst=*.kpb.lt / 10.0.160.0/22| MK_WORK[mark 0x00030000]
  MARK -->|dst в podkop_subnets\nили 198.18.0.0/15| MK_PD[mark 0x00100000]
  MARK -->|без правил| MK_NONE[нет mark]

  MK_AWG2 --> R_AWG2[ip rule 29997\ntable pbr_awg2\ndefault via 10.8.1.2 dev awg2]
  MK_AWG1 --> R_AWG1[ip rule 29999\ntable pbr_awg1\ndefault via 10.8.1.10 dev awg1]
  MK_WORK --> R_WORK[ip rule 29998\ntable pbr_workvpn\ndefault dev vpn-workvpn]
  MK_PD --> R_PD[ip rule 105\ntable podkop\ntproxy → 127.0.0.1:1602]
  MK_NONE --> R_MAIN[ip rule 32766\ntable main\ndefault via 192.168.50.1 dev wan]

  R_AWG2 --> NAT_AWG2[zone awg2: masq=1, mtu_fix=1]
  R_AWG1 --> NAT_AWG1[zone awg1: masq=1, mtu_fix=1]
  R_WORK --> NAT_WORK[zone wan включает workvpn: masq=1]
  R_PD --> SB[sing-box outbound\n_main-out_ → bind_interface=awg1]
  SB --> NAT_AWG1
  R_MAIN --> NAT_WAN[zone wan: masq=1, mtu_fix=1]

  NAT_AWG2 --> OUT_AWG2[awg2 → Neth NL\n45.154.35.222]
  NAT_AWG1 --> OUT_AWG1[awg1 → Fin\n89.44.76.52]
  NAT_WORK --> OUT_WORK[vpn-workvpn → corp]
  NAT_WAN --> ZAP{zapret postnat?\noifname @wanif\n+ first 1-9 packets}
  ZAP -->|да| ZQ[queue → nfqws\nDPI mod]
  ZAP -->|нет| OUT_WAN[wan → ASUS → провайдер]
  ZQ --> OUT_WAN
```



Ключевые свойства схемы:

- **Default всегда `wan`.** Сами VPN-туннели поднимаются с `defaultroute=0`, чтобы не ломать остальной интернет.
- `**pbr` и `podkop` смотрят на разные mark-биты** (`0x00ff0000` против `0x0f000000`), не пересекаются.
- `**zapret` появляется ТОЛЬКО на WAN-ветке** (`oifname @wanif`); для пакетов в `awg1`/`awg2`/`workvpn` он не работает.
- **DNS-обход подкопа для Spotify-доменов** обязателен: иначе клиент получает fake-IP `198.18.0.x`, который перехватывает `podkop` → выйдет через `awg1`, а не `awg2`.

---

## Текущие правила маршрутизации


| Priority | Условие                               | Таблица       | Что значит                                       |
| -------- | ------------------------------------- | ------------- | ------------------------------------------------ |
| `105`    | `fwmark 0x100000/0x100000`            | `podkop`      | подкоп tproxy / sing-box (главный обход)         |
| `29997`  | `fwmark 0x40000/0xff0000`             | `pbr_awg2`    | pbr-policy «Spotify via awg2 (Neth NL)»          |
| `29998`  | `fwmark 0x30000/0xff0000`             | `pbr_workvpn` | pbr-policy «paul-mac kpb via workvpn»            |
| `29999`  | `fwmark 0x20000/0xff0000`             | `pbr_awg1`    | pbr-policy «AI Tools via awg1 (global)»          |
| `29998`  | `lookup main suppress_prefixlength 1` | `main`        | local/специфичные маршруты, default подавлен     |
| `30000`  | `fwmark 0x10000/0xff0000`             | `pbr_wan`     | pbr-uplink, явно вернуть в WAN при необходимости |
| `32766`  | без mark                              | `main`        | default через `wan`                              |


Содержимое таблиц:

```sh
ip route
# default via 192.168.50.1 dev wan
# 89.44.76.52 via 192.168.50.1 dev wan         # Fin endpoint
# 45.154.35.222 via 192.168.50.1 dev wan       # Neth endpoint
# 140.82.112.0/20 dev awg1 scope link          # github API через awg1 (для community lists)
# 185.199.108.0/22 dev awg1 scope link         # github raw

ip route show table pbr_awg1   # default via 10.8.1.10 dev awg1
ip route show table pbr_awg2   # default via 10.8.1.2  dev awg2
ip route show table pbr_workvpn # default dev vpn-workvpn
```

Endpoints VPN-серверов (`89.44.76.52`, `45.154.35.222`) обязательно остаются доступны через `wan`, чтобы туннель не пытался завернуться сам в себя.

---

## Сценарии (по доменам)

### Обычный сайт

1. dnsmasq → sing-box (т.к. нет per-domain upstream и нет community match).
2. sing-box возвращает реальный IP.
3. mark не ставится → `lookup main` → `default dev wan`.
4. На выходе `zapret postnat` может модифицировать первые пакеты для DPI-обхода.

### Сайт из community list (Telegram, Google Play, и т.п.)

1. dnsmasq → sing-box; sing-box матчит rule_set → возвращает fake-IP `198.18.0.x`.
2. Пакет с `dst=198.18.0.x` ловится в `PodkopTable mangle` → mark `0x00100000`.
3. `ip rule 105` → `table podkop` → tproxy на `127.0.0.1:1602`.
4. sing-box разрешает fake-IP в реальный, отправляет через `main-out` (bind `awg1`).
5. Выход через `awg1 → Fin`.

### AI / Cursor (`api.openai.com`, `chatgpt.com`, `claude.ai`, ...)

1. dnsmasq → sing-box → реальный IP (домены не в community lists).
2. Параллельно `dnsmasq nftset` hook добавляет IP в `pbr_awg1_4_dst_ip_cfg056ff5`.
3. `pbr_prerouting` сматчил `dst @set` → mark `0x00020000`.
4. `ip rule 29999` → `table pbr_awg1` → `default via 10.8.1.10 dev awg1` → Fin.

### Spotify (NL-аккаунт)

1. dnsmasq имеет per-domain server `=/spotify.com/8.8.8.8` (и для CDN). Запрос идёт **мимо** подкопа, возвращается реальный IP.
2. `dnsmasq nftset` hook добавляет IP в `pbr_awg2_4_dst_ip_cfg076ff5`. Покрыты CNAME-таргеты `dual-gslb.spotify.com`, `single-gslb.spotify.com`, `cdn-gslb.spotify.com`, `edge-web.dual-gslb.spotify.com`.
3. `pbr_prerouting` сматчил `dst @set` → mark `0x00040000`.
4. `ip rule 29997` → `table pbr_awg2` → `default via 10.8.1.2 dev awg2` → Neth NL.

### Корпоративные ресурсы `*.kpb.lt` для `paul-mac`

1. dnsmasq имеет per-domain server `=/kpb.lt/10.0.160.1` → DNS уходит в туннель `vpn-workvpn`.
2. `pbr_prerouting` сматчил `src=192.168.1.198 + dst @kpb_set | 10.0.160.0/22` → mark `0x00030000`.
3. `ip rule 29998` → `table pbr_workvpn` → `vpn-workvpn`.

---

## Где именно вмешивается `zapret`

`zapret` живёт в `table inet zapret`, реагирует только на WAN-ветку (`oifname @wanif = wan`):

```sh
chain postnat {
    ct original ip saddr 192.168.1.157 return            # bypass для Redmi-Note-9-Pro
    oifname @wanif udp ... queue flags bypass to 200
    oifname @wanif tcp dport ... ct original packets 1-9 ... queue flags bypass to 200
}

chain prenat {
    ct reply ip daddr 192.168.1.157 return
    iifname @wanif tcp sport ... ct reply packets 1-3 ... queue flags bypass to 200
}
```

Что важно:

- для `awg1`/`awg2`/`workvpn` zapret не срабатывает (другой выходной интерфейс);
- работает только на первых пакетах TCP/UDP конкретных портов;
- для конкретного устройства можно сделать **per-device bypass** (см. ниже).

### Per-device bypass для zapret

Сейчас bypass включён для `192.168.1.157` (`Redmi-Note-9-Pro`, реальный device-MAC `18:87:40:44:CD:51` после отключения Wi-Fi MAC randomization на телефоне; IP закреплён DHCP-резервацией). Стабильность:

- hook `INIT_FW_POST_UP_HOOK=/opt/zapret/custom.bypass_devices.sh` в `/opt/zapret/config`;
- скрипт `/opt/zapret/custom.bypass_devices.sh` (исходник: `[scripts/openwrt/custom.bypass_devices.sh](scripts/openwrt/custom.bypass_devices.sh)`) после каждого `zapret restart` досыпает правила `ct original/reply ... return`.

Если телефон когда-то снова окажется на другом IP (например, опять включится MAC randomization), DHCP даст ему адрес из общего пула, и старый bypass на `.157` не сработает. В этом случае надо либо вернуть пин по реальному MAC в `dhcp.@host`, либо обновить скрипт.

Добавить ещё устройство (пример `192.168.1.240`):

```sh
nft insert rule inet zapret postnat ct original ip saddr 192.168.1.240 return comment "zapret-ct-bypass-240"
nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.240 return comment "zapret-ct-bypass-240-pre"
```

---

## Mark-и (диапазоны не должны пересекаться)


| Компонент          | Mark / ct mark             | Где используется                                   | Зачем                                    |
| ------------------ | -------------------------- | -------------------------------------------------- | ---------------------------------------- |
| `pbr` (awg1)       | `0x00020000/0xff0000`      | `ip rule 29999`, table `pbr_awg1`                  | AI / Cursor → awg1 (Fin)                 |
| `pbr` (workvpn)    | `0x00030000/0xff0000`      | `ip rule 29998`, table `pbr_workvpn`               | corp `*.kpb.lt` для paul-mac             |
| `pbr` (awg2)       | `0x00040000/0xff0000`      | `ip rule 29997`, table `pbr_awg2`                  | Spotify → awg2 (Neth NL)                 |
| `pbr` (uplink)     | `0x00010000/0xff0000`      | `ip rule 30000`, table `pbr_wan`                   | принудительный return в WAN              |
| `podkop`           | `0x00100000`               | `PodkopTable mangle/proxy`, `ip rule priority 105` | tproxy в sing-box                        |
| `zapret` / `nfqws` | `0x20000000`, `0x40000000` | `table inet zapret`, conntrack                     | пометить nfqws-обработку, не зацикливать |


---

## Интерфейсы и адреса


| Интерфейс     | Роль                | Параметры                                                                                              |
| ------------- | ------------------- | ------------------------------------------------------------------------------------------------------ |
| `wan`         | Uplink к провайдеру | `5.189.245.251/26` (DHCP), шлюз `5.189.245.193`. Белый IP, DDNS `cloud-pundef.mooo.com`.               |
| `br-lan`      | LAN (клиенты)       | `192.168.1.1/24`, ports `lan3 lan4` + WiFi, DHCP `192.168.1.100-249`.                                  |
| `srv` (lan2)  | Серверный сегмент   | `192.168.50.1/24`, отдельный физический порт `lan2`, DHCP `192.168.50.100-199`, DNS `8.8.8.8/1.1.1.1`. |
| `awg1`        | AmneziaWG → Fin     | `10.8.1.10/32`, endpoint `89.44.76.52:45007`, `defaultroute=0`                                         |
| `awg2`        | AmneziaWG → Neth NL | `10.8.1.2/32`, endpoint `45.154.35.222:40698`, `defaultroute=0`                                        |
| `vpn-workvpn` | OpenConnect → corp  | `10.0.161.32/32`, hostname `oc-lux.kpb.lol`                                                            |


### Серверный сегмент `srv` (отдельная firewall zone)

`srv` физически — это порт `lan2` X3000T, исключённый из `br-lan`. К нему подключён Proxmox-хост (через `vmbr0 → nic0 → lan2`). За хостом на этом сегменте живут ВМ `nextcloud-vm` и `haos17`.

Ключевые свойства:

- **DHCP-резервации `infinite`** под MAC ВМ:
  - `nextcloud-vm` MAC `02:CC:61:7E:E7:7B` → `192.168.50.34`;
  - `haos17` MAC `02:DF:3B:CA:E9:AC` → `192.168.50.51`.
- **DNS для srv** выдаётся не через роутерный dnsmasq, а напрямую: `dhcp.srv.dhcp_option='6,8.8.8.8,1.1.1.1'`. Это намеренно — иначе Nextcloud резолвил бы community-домены через sing-box и получал fake-IP `198.18.x`.
- **Firewall zone `srv`**: `input REJECT, output ACCEPT, forward REJECT`, плюс rule `Allow-DHCP-DNS-srv` (53/67/68 udp). Forwarding только `srv→wan` и `lan→srv`. **НЕТ** `srv→awg1/awg2/workvpn` — ВМ всегда идут чистым WAN.
- **Hairpin**: `dnsmasq.@dnsmasq[0].address='/cloud-pundef.mooo.com/192.168.50.34'` — клиенты `lan` резолвят домен сразу в локальный IP, без NAT loopback.
- **Port-forwards** `wan: 80 → srv:192.168.50.34:80` и `wan: 443 → srv:192.168.50.34:443` (DNAT с `wan` в `srv`).
- **zapret bypass для srv**: в `[scripts/openwrt/custom.bypass_devices.sh](scripts/openwrt/custom.bypass_devices.sh)` добавлены `ct original ip saddr 192.168.50.0/24 return` (postnat) и зеркальное правило в `prenat`. Источник применяется автоматически через `INIT_FW_POST_UP_HOOK=/opt/zapret/custom.bypass_devices.sh` в `/opt/zapret/config`.


Проверки:

```sh
ip -br a
ip route
ip rule
ifstatus awg1
ifstatus awg2
ifstatus workvpn
awg show awg1
awg show awg2
```

---

## pbr (актуальная конфигурация)

Версия **pbr 1.2.2-r14**. Включён, `supported_interface = awg1 awg2 workvpn`, uplink — `wan`. Приоритеты `ip rule` см. выше.

Активные политики:


| #   | Имя                          | Интерфейс | src             | dest_addr (кратко)                                                                                                                                                                                                                                                             |
| --- | ---------------------------- | --------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0   | `AI Tools via awg1 (global)` | `awg1`    | —               | домены Cursor, OpenAI, Anthropic, Claude, Groq, Google Generative API                                                                                                                                                                                                          |
| 1   | `paul-mac kpb via workvpn`   | `workvpn` | `192.168.1.198` | `kpb.lt`, `*.kpb.lt`, `gitlab.kpb.lt`, `10.0.160.0/22`                                                                                                                                                                                                                         |
| 2   | `Spotify via awg2 (Neth NL)` | `awg2`    | —               | `spotify.com`, `www.spotify.com`, `open.spotify.com`, `accounts.spotify.com`, `ap.spotify.com`, `scdn.co`, `spotifycdn.com`, `spotifycdn.net`, плюс CNAME-таргеты `dual-gslb.spotify.com`, `single-gslb.spotify.com`, `cdn-gslb.spotify.com`, `edge-web.dual-gslb.spotify.com` |
| 3   | `Mangalib via awg1`          | `awg1`    | —               | `mangalib.me`, `lib.social`, `ranobelib.me`, `imglib.org` — резерв под точечные RU-блокировки тайтлов и API; делит mark `0x00020000` и таблицу `pbr_awg1` с AI-policy                                                                                                          |


Полный список:

```sh
uci show pbr | grep -E '@policy'
nft list chain inet fw4 pbr_prerouting
```

После любых правок:

```sh
uci commit pbr
/etc/init.d/pbr restart
```

---

## DNS bypass для Spotify (важно)

Без этого Spotify попадает в community list `russia_inside` подкопа, dnsmasq возвращает fake-IP `198.18.0.x`, и трафик ушёл бы через `awg1` независимо от pbr-policy.

В `/etc/config/dhcp` (`dhcp.@dnsmasq[0].server`) добавлены прямые upstream'ы:

```sh
uci show dhcp.@dnsmasq[0].server
# 127.0.0.42                       # default → sing-box (подкоп DNS)
# /kpb.lt/10.0.160.1               # corporate DNS
# /spotify.com/8.8.8.8             # bypass podkop для Spotify
# /scdn.co/8.8.8.8
# /spotifycdn.com/8.8.8.8
# /spotifycdn.net/8.8.8.8
# /pscdn.co/8.8.8.8
```

dnsmasq матчит самый специфичный домен, поэтому `*.spotify.com` уходит на `8.8.8.8` напрямую, минуя sing-box.

После изменения списка:

```sh
uci commit dhcp
/etc/init.d/dnsmasq restart
# затем перезапуск pbr, чтобы перерезолвить и заполнить nft set:
/etc/init.d/pbr restart
```

Проверка резолва:

```sh
nslookup ap.spotify.com 192.168.1.1   # должен быть НЕ 198.18.0.x
nft list set inet fw4 pbr_awg2_4_dst_ip_cfg076ff5
```

---

## Firewall zones

Каждый VPN-туннель должен иметь собственную zone с `masq=1` и `forwarding lan→<zone>`, иначе LAN-клиенты не попадут в туннель (нет NAT, либо `forward=REJECT`).

Текущие зоны:

```sh
uci show firewall | grep -E 'zone|forwarding'
```


| Zone   | Networks                 | input  | output | forward | masq | forwarding from `lan` |
| ------ | ------------------------ | ------ | ------ | ------- | ---- | --------------------- |
| `lan`  | `lan`                    | ACCEPT | ACCEPT | ACCEPT  | —    | —                     |
| `wan`  | `wan`, `wan6`, `workvpn` | REJECT | ACCEPT | REJECT  | 1    | да (стандарт)         |
| `awg1` | `awg1`                   | REJECT | ACCEPT | REJECT  | 1    | `awg1-lan`            |
| `awg2` | `awg2`                   | REJECT | ACCEPT | REJECT  | 1    | `awg2-lan`            |


`workvpn` намеренно сидит в zone `wan` — этого достаточно для NAT/forward в туннель, отдельная zone не нужна.

---

## podkop и sing-box

- **podkop** управляет конфигом **sing-box**, списками community-подсетей и nft-таблицей `inet PodkopTable` (mangle + tproxy на `127.0.0.1:1602`).
- В `uci`: `podkop.main.connection_type='vpn'`, `podkop.main.interface='awg1'` (это значит sing-box outbound `main-out` имеет `bind_interface=awg1`), `community_lists='telegram google_ai google_play russia_inside'`.
- **Spotify-домены не должны попадать в подкоп** (см. секцию выше про DNS bypass), иначе pbr-policy `awg2` будет проигнорирована.

Проверки:

```sh
/usr/bin/podkop get_status
/usr/bin/podkop check_nft_rules
nft list set inet PodkopTable podkop_subnets
/etc/init.d/sing-box status
```

---

## Стабильность после перезагрузки / обрыва питания

### Маршруты к GitHub для обновления community-списков

С `raw.githubusercontent.com` по WAN иногда таймаут; для **загрузки листов** статически прописаны через `awg1`:

- `185.199.108.0/22`
- `140.82.112.0/20`

### Hotplug

Файл: `/etc/hotplug.d/iface/99-vpn-stack` (исполняемый, исходник `[scripts/openwrt/99-vpn-stack](scripts/openwrt/99-vpn-stack)`).

На `ifup` для `wan`, `awg1` или `awg2`:

1. перепрописать github-маршруты через `awg1`;
2. пауза 10s;
3. перезапустить `sing-box → podkop → zapret → pbr` в этом порядке.

Заливка/обновление с ПК:

```powershell
python d:\repositories\home-server\scripts\openwrt\upload.py `
  d:\repositories\home-server\scripts\openwrt\99-vpn-stack `
  /etc/hotplug.d/iface/99-vpn-stack --chmod 755
```

---

## zapret

`zapret` — это слой DPI-обхода на WAN-потоках, не VPN и не policy routing:

- `pbr` выбирает маршрут через `fwmark` и собственные таблицы;
- `podkop` перехватывает в `tproxy → sing-box`;
- `zapret` модифицирует первые пакеты уже выбранных WAN-потоков (`oifname @wanif`).

```sh
/etc/init.d/zapret status
nft list table inet zapret
```

Если конкретное приложение ломается — добавлять **bypass по conntrack IP клиента** (см. «Per-device bypass» выше), а не выключать pbr / подкоп.

---

## Скрипты в этом репозитории

Путь в проекте: `[scripts/openwrt/](scripts/openwrt/)`.


| Файл                                                                                                 | Назначение                                                                                                                                                                          |
| ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[scripts/openwrt/openwrt_exec.py](scripts/openwrt/openwrt_exec.py)`                                 | Выполнить одну команду на роутере по SSH с ключом без passphrase (`OPENWRT_HOST`, `OPENWRT_USER`, `OPENWRT_KEY`).                                                                   |
| `[scripts/openwrt/upload.py](scripts/openwrt/upload.py)`                                             | Залить локальный файл на роутер по SSH (без SFTP — через `base64 -d`). Используется для обновления `99-vpn-stack` и других конфигов.                                                |
| `[scripts/openwrt/check_stack.py](scripts/openwrt/check_stack.py)`                                   | Health-check всего стека (`pbr`/`podkop`/`sing-box`/`zapret` + `awg1`/`awg2`/`workvpn` + DNS bypass + AI/Spotify/gitlab активные пробы).                                            |
| `[scripts/openwrt/trace_traffic.py](scripts/openwrt/trace_traffic.py)`                               | Трассировка пути конкретного домена/IP через pbr/podkop/zapret.                                                                                                                     |
| `[scripts/openwrt/podkop-subnets-watchdog.sh](scripts/openwrt/podkop-subnets-watchdog.sh)`           | Если `podkop_subnets` пуст — запустить `podkop list_update`. Cron: `*/15 * * * *`.                                                                                                  |
| `[scripts/openwrt/99-vpn-stack](scripts/openwrt/99-vpn-stack)`                                       | Исходник hotplug-скрипта `/etc/hotplug.d/iface/99-vpn-stack`.                                                                                                                       |
| `[scripts/openwrt/custom.bypass_devices.sh](scripts/openwrt/custom.bypass_devices.sh)`               | Источник `/opt/zapret/custom.bypass_devices.sh`: per-IP bypass для `192.168.1.157` (Redmi-Note-9-Pro, MAC `18:87:40:44:CD:51`) и per-subnet bypass для серверного сегмента `192.168.50.0/24`. |
| `[scripts/openwrt/migration-activate-srv.sh](scripts/openwrt/migration-activate-srv.sh)`             | Активатор миграции "ASUS off, OpenWrt main" (см. `[migration-asus-to-openwrt.md](migration-asus-to-openwrt.md)`). Поднимает `srv`, перезапускает стек, пере-привинчивает маршруты.  |


Пример с ПК (PowerShell, дефолтный ключ `C:\Users\PUndef-PC\.ssh\openwrt_ax300t_nopass`):

```powershell
python d:\repositories\home-server\scripts\openwrt\openwrt_exec.py "uci show pbr | head"
python d:\repositories\home-server\scripts\openwrt\check_stack.py
```

---

## Быстрый health-check

```sh
ip route
ip rule | grep -E 'pbr|fwmark'
ifstatus awg1; ifstatus awg2; ifstatus workvpn
/etc/init.d/pbr status
/etc/init.d/sing-box status
/etc/init.d/zapret status
/usr/bin/podkop check_nft_rules
nft list set inet PodkopTable podkop_subnets
nft list set inet fw4 pbr_awg2_4_dst_ip_cfg076ff5     # должны быть реальные Spotify IP
```

---

## Диагностика с ПК

```powershell
nslookup spotify.com           # ожидаемо: 35.186.224.x / 45.155.204.x (НЕ 198.18.0.x)
nslookup api.openai.com        # ожидаемо: реальный IP
tracert example.com            # после 192.168.1.1 — 192.168.50.1 (ASUS, WAN-ветка)
```

На роутере для конкретного клиента (подставь IP):

```sh
opkg install tcpdump-mini
tcpdump -ni br-lan host 192.168.1.xxx and 'tcp port 443 or udp port 443 or port 53'
```

---

## Rollback

### Spotify-policy → обратно на awg1

```sh
uci set pbr.@policy[2].interface='awg1'
uci set pbr.@policy[2].name='Spotify via awg1 (global)'
uci commit pbr && /etc/init.d/pbr restart
```

### Полностью убрать `awg2` и Spotify-DNS-bypass

```sh
cp /etc/config/network.bak.awg2  /etc/config/network
cp /etc/config/pbr.bak.awg2      /etc/config/pbr
cp /etc/config/dhcp.bak.spotify  /etc/config/dhcp
cp /etc/config/firewall.bak.awg2 /etc/config/firewall
/etc/init.d/network reload
/etc/init.d/firewall reload
/etc/init.d/dnsmasq restart
/etc/init.d/pbr restart
```

### Откат hotplug + github-маршрутов

```sh
rm -f /etc/hotplug.d/iface/99-vpn-stack
ip route del 185.199.108.0/22 dev awg1 2>/dev/null
ip route del 140.82.112.0/20 dev awg1 2>/dev/null
/etc/init.d/podkop restart
/etc/init.d/sing-box restart
/etc/init.d/zapret restart
/etc/init.d/pbr restart
```

Удаление cron-строки watchdog с роутера — вручную отредактировать `/etc/crontabs/root` и `service cron restart`.

---

## Примечание про модели в Cursor

Маршрутизация Cursor/AI через `awg1` настроена политикой выше; если часть моделей (например, Anthropic) не отображается, это может быть **ограничение аккаунта/региона/плана**, а не отсутствие URL в списке. Список `dest_addr` при необходимости дополняется по `tcpdump` / логам клиента.