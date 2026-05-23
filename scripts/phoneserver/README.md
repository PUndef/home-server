# `phoneserver` — postmarketOS на Redmi Note 9 Pro

Скрипты для установки и сопровождения второго узла домашней инфраструктуры — Xiaomi Redmi Note 9 Pro Global (codename `joyeuse`, SoC SM7125), переделанного под headless-сервер на postmarketOS.

Подробная история установки и текущий статус железа: [`../../phoneserver-pmos-setup.md`](../../phoneserver-pmos-setup.md).

Целевая конфигурация — pmaports **`v25.06`** stable, `device-xiaomi-miatoll-kernel-joyeuse_tianma`, Linux 6.12.1, классический Android boot.img в стандартный `boot` partition. Возня с edge-схемой (кастомный boot.img из EFI zboot, патчи pmbootstrap и т.п.) теперь не нужна — оставлена как fallback в [`diag/`](diag/).

---

## Когда что запускать

Все скрипты гоняются из **WSL Ubuntu 24.04** на основном Windows-ПК. Подразумевается, что:

- `pmbootstrap` 3.x установлен в WSL и инициализирован
- public-ключ для phoneserver лежит в `~/.ssh/phoneserver_nopass{,.pub}` (создаётся через `setup-ssh-key.sh`)
- IP телефона по USB-сети — `172.16.42.1`, по Wi-Fi — `192.168.1.116` (или DHCP-резерв на OpenWrt)
- USB-устройство при необходимости проброшено в WSL через `usbipd attach --wsl --busid <id>` (из PowerShell **от админа**)
- по умолчанию все скрипты идут на `${PHONE_IP:-172.16.42.1}` (по USB); для Wi-Fi/LAN — `PHONE_IP=192.168.1.116 ./script.sh`

### При обычной работе

| Скрипт | Когда запускать |
|---|---|
| `wsl-usbnet-up.sh` | После переподключения USB / нового `usbipd attach` — поднимает USB-cdc интерфейс в WSL, ставит ему `172.16.42.2/24`, проверяет ssh до телефона. Не нужно если phoneserver уже доступен по Wi-Fi / LAN. |
| `wsl-share-internet.sh` | Когда телефону нужен интернет через WSL (например, до подключения Wi-Fi). Делает MASQUERADE из WSL в интернет, прописывает default route + 1.1.1.1 DNS на телефоне. |
| `status.sh` | Снять текущую сводку с телефона (kernel, uptime, диск, сервисы, сеть). |

### При первичной установке (по порядку)

| Шаг | Скрипт | Что делает |
|---|---|---|
| 1 | `pmbootstrap-init.exp` | Прогон `pmbootstrap init` non-interactively с правильными ответами для joyeuse (UI=none, hostname=phoneserver, kernel=joyeuse_tianma). |
| 2 | вручную: `cd ~/.local/var/pmbootstrap/cache_git/pmaports && git checkout v25.06` | Переключить pmaports на stable канал — на `main` (edge) у `xiaomi-miatoll` сейчас регрессии (см. setup-doc). |
| 3 | вручную: `pmbootstrap config kernel joyeuse_tianma; pmbootstrap config boot_size 128` | Подогнать конфиг под joyeuse. |
| 4 | `pmbootstrap install --no-fde --password changemenow --split --add device-xiaomi-miatoll-kernel-joyeuse_tianma` | Сборка boot.img (~18 MB sparse, 128 MiB partition) и rootfs.img (570 MB → растягиваем потом). |
| 5 | `fastboot erase dtbo; pmbootstrap flasher flash_kernel; sudo fastboot flash userdata ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-root.img; fastboot reboot` | Прошить и перезагрузить. `dtbo erase` обязателен — иначе Xiaomi overlay ломает наш DTB. |
| 6 | `setup-ssh-key.sh` | Сгенерировать `~/.ssh/phoneserver_nopass`, положить в `pmos@phoneserver:~/.ssh/authorized_keys`. |
| 7 | `wsl-share-internet.sh` | Дать phone интернет через WSL, пока Wi-Fi не настроен. |
| 8 | `enable-passwordless-doas.sh` | Pmos v25.06 ставит `doas+doas-sudo-shim`, наш `sudo -S` не работает. Скрипт ставит настоящий sudo, удаляет shim, кладёт `/etc/sudoers.d/pmos-nopasswd`. После этого все остальные `sudo $cmd` через ssh-key работают без password. |
| 9 | `resize-root.sh` | Расширить ext4 на `/dev/sda18` до 103 GiB. На v25.06 pmOS делает это сам при первом mount, скрипт скорее no-op. |
| 10 | `wifi-scan.sh` | Сканирует Wi-Fi-сети, чтобы убедиться что wlan0 поднимается и radio работает. |
| 11 | `wifi-connect.sh` | Подключить wlan0 к WPA2-сети: `WIFI_SSID=... WIFI_PSK=... ./wifi-connect.sh`. Кладёт `/etc/wpa_supplicant/wpa_supplicant.conf`, стартует wpa_supplicant + dhcpcd, делает их persistent. |
| 12 | `post-wifi-setup.sh` | После того как Wi-Fi заработал: dhcpcd в default runlevel, chrony NTP, фиксированный `/etc/resolv.conf` (1.1.1.1). |
| 13 | `pin-dns-and-ntp.sh` | Запретить dhcpcd перезаписывать resolv.conf (`nohook resolv.conf` в `dhcpcd.conf`) — иначе при renew возвращается 192.168.1.1 (dnsmasq на OpenWrt с fake-IP от sing-box). |
| 14 | `fix-routes.sh` | Убрать stale default через USB-net когда phone уже работает по Wi-Fi — иначе трафик уходит в WSL даже когда тот не делает MASQUERADE. |
| 15 | `fix-dns-and-apk.sh` | На случай если apk завис из-за подкопа / fake-IP — переставляет DNS и поднимает базовые tools (`curl`). |

---

## Короткая шпаргалка

```bash
# Подключиться по Wi-Fi (когда phoneserver в LAN):
ssh -i ~/.ssh/phoneserver_nopass pmos@192.168.1.116

# Подключиться по USB (резерв; когда USB проброшен в WSL):
ssh -i ~/.ssh/phoneserver_nopass pmos@172.16.42.1

# Снять статус:
PHONE_IP=192.168.1.116 ./status.sh

# Если phone сменил IP / переустановили pmOS:
PHONE_IP=192.168.1.116 ./setup-ssh-key.sh
```

---

## Известные особенности

- **Wi-Fi работает только на pmaports `v25.06`.** На `main` (edge) — `ath10k_snoc` не делает firmware download, и заодно сломалась EFI/systemd-boot схема загрузки. Не возвращаться на edge без необходимости.
- **`/etc/resolv.conf`** на phone должен указывать на **public DNS** (1.1.1.1 / 8.8.8.8), а не на dnsmasq роутера. Иначе срабатывает sing-box-подкоп для некоторых доменов и часть apk/curl-запросов зависает.
- **doas vs sudo.** v25.06 по умолчанию `doas`. Запускай `enable-passwordless-doas.sh` сразу после первой установки, иначе остальные скрипты будут падать на `sudo -S`.
- **Зарядка** работает только от полноценного USB-C PD-источника. ПК через USB-A или короткий «попытался зарядить» от PC USB-C — не работает, Type-C port уходит в `source` role (Linux mainline driver `qcom,pmic-typec` пока без write-callback для role-switch).
- **RTC battery отсутствует** — после reboot часы откатываются в 1975 год. `chrony` синхронизирует за секунды после поднятия сети.

---

## Edge-only скрипты (как fallback)

Эти артефакты остались с первой попытки на `main` (edge). Не нужны при штатной установке на `v25.06`, но **могут пригодиться** если pmaports опять перейдут на ту же схему или для отладки нестандартного устройства:

| Скрипт | Зачем |
|---|---|
| `build-bootimg.sh` | Собирает Android boot.img из артефактов pmOS вручную через `mkbootimg-osm0sis` в `pmbootstrap chroot`. На v25.06 pmbootstrap сам это делает. |
| `extract-kernel-from-zboot.py` | Распаковывает Linux Image из EFI zboot wrapper (PE/COFF + gzip-payload). Edge-`vmlinuz` был в таком формате; на v25.06 уже обычный Image. |
| `flash-bootimg-via-ssh.sh` | Заливает свежий boot.img на phone и пишет dd в `/dev/disk/by-partlabel/boot`. Работает на любой версии, но проще использовать `pmbootstrap flasher flash_kernel`. |
| `patch-pmbootstrap-bootsize.sh` | Снимает hardcoded sanity-check `boot_size >= 512 MiB` в `pmbootstrap 3.10.1`. На v25.06 не нужен (boot_size 128 не вызывает проверку). |
