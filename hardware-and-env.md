# Железо и окружение home-server

> Заполни этот файл под свою сборку. Он используется как контекст для ответов по серверу (ресурсы, миграции, настройки). Обновляй по мере изменений.

---

## Хост (Proxmox)


| Параметр           | Значение                                                                                                                                  |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| **Имя хоста**      | pundef                                                                                                                                    |
| **CPU**            | Intel N150, 4 ядра / 4 потока (1 thread per core)                                                                                         |
| **RAM**            | 15 ГБ всего; под ВМ отдано ~12 ГБ (100: 6 ГБ, 101: 6 ГБ), доступно ~2.8 ГБ                                                                |
| **Диски**          | Один диск 476.9 ГБ (sda), LVM: root 96 ГБ (ext4), thin pool pve-data для ВМ; swap 8 ГБ                                                    |
| **Версия Proxmox** | 9.1.1 (kernel 6.17.2-1-pve)                                                                                                               |
| **Сеть**           | vmbr0 — 192.168.50.9/24 (статика, gateway 192.168.50.1 — теперь это `srv` X3000T); nic0 (UP) подключён в LAN2 X3000T (срв-сегмент)        |
| **DNS хоста**      | `/etc/resolv.conf` правится руками: `1.1.1.1`, `8.8.8.8` (намеренно в обход dnsmasq роутера, чтобы apt/certbot не зависели от sing-box).  |


---

## Виртуальные машины / LXC


| Имя          | ОС / тип                 | Назначение             | vCPU | RAM  | Диск                    | Сеть / примечания    |
| ------------ | ------------------------ | ---------------------- | ---- | ---- | ----------------------- | -------------------- |
| haos17.0     | VM (Home Assistant OS)   | Home Assistant         | 2    | 6 ГБ | 64 ГБ (virtio, discard) | vmbr0, 192.168.50.51 |
| nextcloud-vm | VM, Debian 12 (Bookworm) | Nextcloud + ONLYOFFICE | 4    | 6 ГБ | 50 ГБ (virtio, discard) | vmbr0, 192.168.50.34 |


LXC-контейнеров нет. Ранее был отдельный LXC под DNS-фильтрацию — снят и удалён в Proxmox; в **ASUS** в DHCP на старый адрес DNS не указывается.

---

## Сервисы (где что крутится)


| Сервис                     | Где запущен (ВМ/LXC)       | Версия / примечания                                                                       |
| -------------------------- | -------------------------- | ----------------------------------------------------------------------------------------- |
| Nextcloud                  | nextcloud-vm (101)         | 33.0.0; PHP 8.3.30, OPcache                                                               |
| ONLYOFFICE Document Server | nextcloud-vm (101), Docker | образ `onlyoffice/documentserver`, контейнер onlyoffice-documentserver, 127.0.0.1:9980→80 |
| Home Assistant             | haos17.0 (100)             | HA OS 17.0                                                                                |
| MariaDB                    | nextcloud-vm (101)         | 10.11.14                                                                                  |


**Бэкапы Nextcloud (nextcloud-vm):** раз в неделю по cron, воскресенье 3:00. Скрипт `/usr/local/bin/nextcloud-backup.sh`, лог `/var/log/nextcloud-backup.log`. Сжатие (tar.gz + gzip). Папка: `/backup/nextcloud`. Ротация: `-mtime +21` — хранятся бэкапы за последние ~3 недели (~3 набора: app_*.tar.gz, data_*.tar.gz, nextcloud-sqlbkp_*.bak.gz).

**HTTPS Nextcloud:** **Let's Encrypt**. Домен cloud-pundef.mooo.com; сертификат в `/etc/letsencrypt/live/cloud-pundef.mooo.com/` (fullchain.pem, privkey.pem). Срок действия — ~3 месяца. Автопродление: certbot.timer (systemd), запуск дважды в день. В Nextcloud: overwriteprotocol https, overwrite.cli.url [https://cloud-pundef.mooo.com](https://cloud-pundef.mooo.com).

---

## Сеть


| Параметр                 | Значение                                                                                                                                          |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Серверный сегмент `srv`  | 192.168.50.0/24 — Proxmox + ВМ. Шлюз `192.168.50.1` (порт `lan2` X3000T). DHCP с upstream DNS `8.8.8.8 / 1.1.1.1` (мимо подкопа).                 |
| Клиентский сегмент `lan` | 192.168.1.0/24 — ПК, Mac, телефоны. Шлюз `192.168.1.1` (порты `lan3 lan4` X3000T + WiFi). pbr / podkop / zapret / awg1 / awg2 / workvpn — здесь.  |
| Хост Proxmox             | 192.168.50.9/24 (статика), gateway `192.168.50.1` = X3000T. DNS: `1.1.1.1`, `8.8.8.8`.                                                            |
| ВМ (DHCP-резервация)     | nextcloud-vm `192.168.50.34` (MAC `02:CC:61:7E:E7:7B`), haos17 `192.168.50.51` (MAC `02:DF:3B:CA:E9:AC`). leasetime `infinite`.                   |
| Основной ПК пользователя | Windows 11; за X3000T в `lan`.                                                                                                                    |
| Рабочий MacBook          | `paul-mac`, DHCP reservation `192.168.1.198`; для корпоративных ресурсов применяется policy `workvpn` на OpenWrt.                                 |


**Топология:** провайдер → **WAN Xiaomi X3000T** (OpenWrt 24.10.6, DHCP, белый IP `5.189.245.251`) → две зоны:
- `lan` `192.168.1.0/24` — клиентский трафик, поверх него вся VPN/DPI-машинерия (pbr / podkop / sing-box / zapret / awg1 / awg2 / workvpn);
- `srv` `192.168.50.0/24` — Proxmox + ВМ, **изолированно** от туннелей и DPI: forwarding только `srv→wan` и `lan→srv`, без `srv→awg1/awg2/workvpn`. zapret отдельно `bypass`-нут для подсети `192.168.50.0/24` через `[scripts/openwrt/custom.bypass_devices.sh](scripts/openwrt/custom.bypass_devices.sh)`.

ASUS RT-AX55 выведен из эксплуатации (выключен, не нужен). История миграции: `[migration-asus-to-openwrt.md](migration-asus-to-openwrt.md)`.

Детали роутера: `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`.

---

## Роутер / проброс портов

*Какие порты проброшены на какой внутренний IP (и порт). Нужно для советов по доступу извне, HTTPS, безопасности.*

**Uplink и NAT** теперь на OpenWrt X3000T (был ASUS до 2026-05-10). Белый IP `5.189.245.251` приходит провайдером по DHCP прямо на WAN X3000T. Обновление DDNS `cloud-pundef.mooo.com` (FreeDNS) — `ddns-scripts` на роутере, lookup через `8.8.8.8`, IP-source = HTTP-чек `https://checkip.amazonaws.com/`.

**Роутер:** Xiaomi **X3000T**, OpenWrt **24.10.6**; LuCI с LAN: [http://192.168.1.1/](http://192.168.1.1/) или [http://openwrt.lan/cgi-bin/luci/](http://openwrt.lan/cgi-bin/luci/); два туннеля **AmneziaWG** — `awg1` (Fin) и `awg2` (Neth NL), **podkop** + **sing-box**, **pbr** (политики для AI/Spotify/workvpn), **zapret**, **OpenConnect** `vpn-workvpn` для corp — см. `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`. В репозитории: `[scripts/openwrt/](scripts/openwrt/)` (SSH-helper `openwrt_exec.py`, загрузчик файлов `upload.py`, health-check `check_stack.py` — 40 проб включая `vm-services` секцию, watchdog для `podkop_subnets`, исходник hotplug `99-vpn-stack`, источник zapret-bypass `custom.bypass_devices.sh`, активатор миграции `migration-activate-srv.sh`).

**Helper для Proxmox/ВМ:** `[scripts/proxmox/](scripts/proxmox/)` — `proxmox_exec.py` (одна команда на хосте по SSH, по образцу `openwrt_exec.py`) и `upload.py` (заливка файлов без SFTP). Аутентификация: ключ `%USERPROFILE%/.ssh/proxmox_pundef_nopass` (без passphrase, ed25519), public part в `~/.ssh/authorized_keys` пользователя `root@pundef`. Через эти helpers удобно ходить и в гостей: `proxmox_exec.py "qm guest exec 101 -- curl -s ifconfig.me"`.


| Внешний порт | Внутренний IP:порт | Протокол | Сервис / примечание                                                              |
| ------------ | ------------------ | -------- | -------------------------------------------------------------------------------- |
| 80           | 192.168.50.34:80   | TCP      | VM Nextcloud (HTTP, ACME http-01 для Let's Encrypt). DNAT `wan→srv` на X3000T.   |
| 443          | 192.168.50.34:443  | TCP      | VM Nextcloud (HTTPS). DNAT `wan→srv` на X3000T.                                  |


> Hairpin-доступа извне-петлёй внутри LAN **нет** — клиенты резолвят `cloud-pundef.mooo.com` сразу в локальный IP благодаря split-horizon DNS (`dnsmasq.@dnsmasq[0].address='/cloud-pundef.mooo.com/192.168.50.34'`), и идут через `lan→srv` напрямую, без NAT loopback.

> Старое правило ASUS `6881–6889 → 192.168.50.61` (BitTorrent) **снято** при миграции, на OpenWrt не переносилось: целевого ПК на этом адресе давно нет.

---

## Внешний (белый) IP


| Параметр                       | Значение                                                      |
| ------------------------------ | ------------------------------------------------------------- |
| Тип                            | статичный (куплен)                                            |
| Текущий белый IP (если знаешь) | 5.189.245.251                                                 |
| Домен(ы) на этот хост          | cloud-pundef.mooo.com → Nextcloud / домашний сервер (FreeDNS) |


---

## Другие VPS / серверы

*Серверы не на этом Proxmox: облачные VPS, VPN и т.д. — чтобы понимать, где что крутится и как связано.*


| Где / имя                       | IP или хост   | Назначение                       | Роль на роутере                                       |
| ------------------------------- | ------------- | -------------------------------- | ----------------------------------------------------- |
| fin-sweet-home-vps.mooo.com     | 89.44.76.52   | Amnezia-WG (Finland)             | `awg1`: AI/Cursor pbr-policy + основной outbound подкопа |
| sweet-home-vps.mooo.com (Neth)  | 45.154.35.222 | Amnezia-WG (Netherlands / Amsterdam) | `awg2`: pbr-policy «Spotify via awg2 (Neth NL)»     |


**Детали fin-sweet-home-vps:** Ubuntu 24.04 LTS, 1 vCPU (Intel Broadwell), 1.9 ГБ RAM, диск 15 ГБ, eth0 89.44.76.52/24. **3x-ui полностью удалён.** Вместо него — **Amnezia-WG**: сервер WireGuard развёрнут с приложения Amnezia на Windows, создано несколько клиентских профилей.

**Детали sweet-home-vps (Neth):** Ubuntu 22.04.5 LTS, hostname `customer55224`, 1 vCPU (Intel Xeon E5-2699A v4), 957 МБ RAM, диск 15 ГБ, ens3 `45.154.35.222/24`. **Очищен 2026-05-07** от лишнего:

- удалены `x-ui` (3x-ui) и весь стек `hysteria` / Blitz Panel (`hysteria-server`, `hysteria-auth`, `hysteria-caddy`, `hysteria-scheduler`, `hysteria-webpanel`);
- удалены каталоги `/etc/x-ui`, `/usr/local/x-ui`, `/etc/hysteria`, `/var/lib/hysteria`;
- освободилось ≈210 МБ RAM (было `free 80MiB → available 419MiB`, стало `free 297MiB → available 525MiB`) и ≈10% диска (было 69% → 59%).

Сейчас на VPS работает только AmneziaWG-сервер, развёрнут с Windows-клиента Amnezia. Для управления через клиент Amnezia создан отдельный сервисный пользователь `amnadmin` с `NOPASSWD sudo` (нужно для неинтерактивных `sudo`-команд установщика). Клиентский профиль роутера: address `10.8.1.2/32`, peer endpoint `45.154.35.222:40698`. Подключён на роутере как `awg2` (см. `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`).

---

## Заметки

- **Один роутер:** OpenWrt X3000T теперь основной — uplink к провайдеру, NAT, проброс портов, DDNS, плюс вся VPN/DPI-машинерия (pbr с политиками AI→`awg1`, Spotify→`awg2`, corp→`vpn-workvpn`, podkop/sing-box, zapret). ASUS RT-AX55 выведен из эксплуатации 2026-05-10. Подробно: `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`. История миграции: `[migration-asus-to-openwrt.md](migration-asus-to-openwrt.md)`.
- **Изоляция серверного сегмента:** `srv` (`192.168.50.0/24`) и `lan` (`192.168.1.0/24`) — две независимые firewall zone на X3000T. ВМ намеренно не имеют forwarding в `awg1/awg2/workvpn` и закрыты от zapret через `ct original ip saddr 192.168.50.0/24 return` (`[scripts/openwrt/custom.bypass_devices.sh](scripts/openwrt/custom.bypass_devices.sh)`). DNS у ВМ — `8.8.8.8 / 1.1.1.1` (через `dhcp_option='6,...'`), мимо dnsmasq роутера; иначе Nextcloud получал бы fake-IP `198.18.x` от sing-box.
- **Корпоративный VPN на OpenWrt:** для `paul-mac` (`192.168.1.198`) включён split-routing через `workvpn` для зоны `kpb.lt` (домены + подсеть `10.0.160.0/22`) и принудительный DNS redirect этого клиента на роутерный `dnsmasq`.
- **DNS:** централизованного DNS-фильтра на Proxmox нет; при необходимости — фильтрация на роутере или клиентские средства. Хост Proxmox смотрит на `1.1.1.1 / 8.8.8.8` напрямую (см. `/etc/resolv.conf`), не через роутерный dnsmasq.
- Один физический диск: все ВМ на LVM thin в одном пуле — при апгрейде/бэкапах учитывать отсутствие отдельного хранилища.
- На хосте 4 ядра; nextcloud-vm занимает 4 vCPU — при пиковой нагрузке возможна конкуренция с haos17.0 (2 vCPU). При желании можно ограничить nextcloud-vm до 2–3 vCPU и смотреть по нагрузке.
- haos17.0: по Proxmox память ~81% (≈4.9 ГБ из 6 ГБ) — при добавлении интеграций/надстроек следить за RAM.

