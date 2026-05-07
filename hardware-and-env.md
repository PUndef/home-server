# Железо и окружение home-server

> Заполни этот файл под свою сборку. Он используется как контекст для ответов по серверу (ресурсы, миграции, настройки). Обновляй по мере изменений.

---

## Хост (Proxmox)


| Параметр           | Значение                                                                               |
| ------------------ | -------------------------------------------------------------------------------------- |
| **Имя хоста**      | pundef                                                                                 |
| **CPU**            | Intel N150, 4 ядра / 4 потока (1 thread per core)                                      |
| **RAM**            | 15 ГБ всего; под ВМ отдано ~12 ГБ (100: 6 ГБ, 101: 6 ГБ), доступно ~2.8 ГБ             |
| **Диски**          | Один диск 476.9 ГБ (sda), LVM: root 96 ГБ (ext4), thin pool pve-data для ВМ; swap 8 ГБ |
| **Версия Proxmox** | 9.1.1 (kernel 6.17.2-1-pve)                                                            |
| **Сеть**           | vmbr0 — 192.168.50.9/24; nic0 (UP), wlp2s0 (DOWN)                                      |


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


| Параметр                 | Значение                                                                                                                                                                            |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Домашняя подсеть (ASUS)  | 192.168.50.0/24 — Proxmox, ВМ, uplink OpenWrt-роутера                                                                                                                               |
| LAN за OpenWrt (Xiaomi)  | 192.168.1.0/24 — основной ПК подключён сюда                                                                                                                                         |
| Хост (Proxmox)           | 192.168.50.9/24 (статично), на сегменте ASUS                                                                                                                                        |
| Важные ВМ (статичные IP) | nextcloud-vm: 192.168.50.34; haos17.0: 192.168.50.51                                                                                                                                |
| Основной ПК пользователя | Windows 11; **за роутером Xiaomi/OpenWrt** (LAN `192.168.1.0/24`). Ранее был в LAN ASUS с адресом **192.168.50.61** — при необходимости обнови актуальный IP в DHCP/статике OpenWrt |
| Рабочий MacBook          | `paul-mac`, DHCP reservation `192.168.1.198`; для корпоративных ресурсов применяется policy `workvpn` на OpenWrt                                                                    |


**Топология:** провайдер → **ASUS RT-AX55** (`192.168.50.0/24`) → порт WAN **Xiaomi X3000T** (OpenWrt; пример WAN `192.168.50.20`) → LAN OpenWrt → ПК. Проброс портов и «белый» IP по-прежнему на стороне **ASUS**; VPN / pbr / zapret настроены на **OpenWrt**. Детали: `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`.

---

## Роутер / проброс портов

*Какие порты проброшены на какой внутренний IP (и порт). Нужно для советов по доступу извне, HTTPS, безопасности.*

**Upstream (NAT к провайдеру, проброс портов):** ASUS RT-AX55 — таблица ниже без изменений; цели в сегменте `192.168.50.0/24` (ВМ и ранее ПК на ASUS) доступны с WAN ASUS напрямую.

**Второй роутер (OpenWrt):** Xiaomi **X3000T**, OpenWrt **24.10.6**; LuCI с LAN: [http://192.168.1.1/](http://192.168.1.1/) или [http://openwrt.lan/cgi-bin/luci/](http://openwrt.lan/cgi-bin/luci/); два туннеля **AmneziaWG** — `awg1` (Fin) и `awg2` (Neth NL), **podkop** + **sing-box**, **pbr** (политики для AI/Spotify/workvpn), **zapret**, **OpenConnect** `vpn-workvpn` для corp — см. `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`. В репозитории: `[scripts/openwrt/](scripts/openwrt/)` (SSH-helper `openwrt_exec.py`, загрузчик файлов `upload.py`, health-check `check_stack.py`, watchdog для `podkop_subnets`, исходник hotplug `99-vpn-stack`).


| Внешний порт | Внутренний IP:порт | Протокол | Сервис / примечание                                                                                                               |
| ------------ | ------------------ | -------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 80           | 192.168.50.34:80   | TCP      | VM Nextcloud (HTTP)                                                                                                               |
| 443          | 192.168.50.34:443  | TCP      | VM Nextcloud (HTTPS)                                                                                                              |
| 6881–6889    | 192.168.50.61      | TCP      | BitTorrent — **цель была ПК на ASUS**; ПК теперь за OpenWrt: при необходимости проброс на актуальный IP ПК или отключение правила |


> Если торрент-клиент только на ПК за Xiaomi, правило ASUS `6881–6889 → 192.168.50.61` может быть **неактуально**, пока не настроен двойной проброс (ASUS → OpenWrt → ПК) или пока торрент не перенесён на хост в `192.168.50.x`.

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

- **Два роутера:** ASUS остаётся шлюзом к провайдеру и местом проброса портов; Xiaomi/OpenWrt — слой для LAN ПК (podkop/sing-box, pbr с политиками AI→`awg1`, Spotify→`awg2`, corp→`vpn-workvpn`, zapret). Подробно: `[router-openwrt-x3000t.md](router-openwrt-x3000t.md)`.
- **Корпоративный VPN на OpenWrt:** для `paul-mac` (`192.168.1.198`) включён split-routing через `workvpn` для зоны `kpb.lt` (домены + подсеть `10.0.160.0/22`) и принудительный DNS redirect этого клиента на роутерный `dnsmasq`.
- **DNS:** централизованного DNS-фильтра на Proxmox нет; при необходимости — фильтрация на роутере или клиентские средства.
- Один физический диск: все ВМ на LVM thin в одном пуле — при апгрейде/бэкапах учитывать отсутствие отдельного хранилища.
- На хосте 4 ядра; nextcloud-vm занимает 4 vCPU — при пиковой нагрузке возможна конкуренция с haos17.0 (2 vCPU). При желании можно ограничить nextcloud-vm до 2–3 vCPU и смотреть по нагрузке.
- haos17.0: по Proxmox память ~81% (≈4.9 ГБ из 6 ГБ) — при добавлении интеграций/надстроек следить за RAM.

