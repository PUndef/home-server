# `phoneserver` — postmarketOS на Redmi Note 9 Pro

Скрипты для установки и сопровождения второго узла домашней инфраструктуры — Xiaomi Redmi Note 9 Pro Global (codename `joyeuse`, SoC SM7125), переделанного под headless-сервер на postmarketOS.

Подробная история установки и текущий статус железа: [`../../phoneserver-pmos-setup.md`](../../phoneserver-pmos-setup.md).

---

## Когда что запускать

Все скрипты гоняются из **WSL Ubuntu** на основном Windows-ПК. По умолчанию подразумевается, что:

- `pmbootstrap` 3.x установлен в WSL и инициализирован
- public-ключ для phoneserver лежит в `~/.ssh/phoneserver_nopass{,.pub}` (создаётся через `setup-ssh-key.sh`)
- IP телефона по USB-сети — `172.16.42.1`, IP WSL-стороны — `172.16.42.2`
- USB-устройство уже проброшено в WSL через `usbipd attach --wsl --busid <id>` (запускается из PowerShell **от админа** на Windows-стороне)

### При обычной работе (телефон уже установлен)

| Скрипт | Когда запускать |
|---|---|
| `wsl-usbnet-up.sh` | После каждой перезагрузки телефона / переподключения USB — поднимает USB-cdc интерфейс в WSL, ставит ему `172.16.42.2/24`, проверяет ssh до телефона. |
| `wsl-share-internet.sh` | Когда телефону временно нужен интернет (например, для `apk update`) и Wi-Fi/Ethernet на нём ещё не настроены. Делает NAT из WSL в интернет, прописывает default route на телефоне. |
| `status.sh` | Снять текущую сводку с телефона (kernel, uptime, диск, сервисы, сеть). |

### При перепрошивке/обновлении boot.img

| Скрипт | Что делает |
|---|---|
| `extract-kernel-from-zboot.py` | Извлекает чистый ARM64 `Image` из pmOS `vmlinuz` (EFI zboot wrapper c gzip-payload'ом внутри). Нужно, потому что Android bootloader Xiaomi не умеет грузить EFI напрямую. |
| `build-bootimg.sh` | Собирает Android-style `boot.img` (header v2) из `Image` + initramfs + объединённого joyeuse DTB (tianma + huaxing), для прямой прошивки в `boot` partition. Запускается **внутри `pmbootstrap chroot`** на native chroot — там лежит рабочий `mkbootimg-osm0sis`. |
| `flash-bootimg-via-ssh.sh` | Заливает свежий `boot.img` на телефон по SSH и пишет `dd` в `/dev/disk/by-partlabel/boot`. Не требует возврата в fastboot. |

### При первичной установке / переустановке

| Скрипт | Когда |
|---|---|
| `pmbootstrap-init.exp` | Прогон `pmbootstrap init` non-interactively с правильными ответами для joyeuse. Использует `expect`. Заменяет 20+ интерактивных вопросов. |
| `patch-pmbootstrap-bootsize.sh` | Снимает hardcoded sanity-check `boot_size >= 512` MiB в `pmbootstrap 3.10.1` — у joyeuse Android `boot` partition всего 128 MiB, а раздел `cache` (на который мы **не** прошиваем) — 384 MiB. Без патча `pmbootstrap install` падает. |
| `setup-ssh-key.sh` | Генерирует выделенный ed25519-ключ `~/.ssh/phoneserver_nopass`, копирует на телефон. После этого пароль `changemenow` больше не нужен. |
| `resize-root.sh` | Расширяет ext4 на `/dev/sda18` до полного размера userdata-партиции (~103 GiB). pmbootstrap по умолчанию делает root ~650 MiB. |

---

## Совсем коротко: цепочка установки с нуля

```bash
# 1) Один раз: подготовка WSL
sudo apt install -y pipx git android-tools-fastboot android-tools-adb usbutils \
                    kpartx expect sshpass iptables mkbootimg python3
pipx install 'git+https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git'

# 2) Один раз: pmaports (shallow, чтобы быстро)
git clone --depth 1 -b main https://gitlab.postmarketos.org/postmarketOS/pmaports.git \
    ~/.local/var/pmbootstrap/cache_git/pmaports

# 3) Один раз: pmbootstrap init
./pmbootstrap-init.exp

# 4) Один раз: патч проверки boot_size
./patch-pmbootstrap-bootsize.sh

# 5) Сборка образов pmOS (cache target). Здесь --add не нужен для joyeuse.
pmbootstrap config boot_size 256
pmbootstrap install --password changemenow --split

# 6) Собрать собственный Android boot.img из артефактов pmOS
./build-bootimg.sh    # требует уже работающего pmbootstrap chroot

# 7) Записать на телефон (через fastboot, телефон в bootloader-mode):
fastboot erase dtbo
fastboot flash boot /home/$USER/.local/var/pmbootstrap/chroot_native/home/pmos/pmos-joyeuse-test.img
fastboot flash userdata /home/$USER/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-root.img
fastboot reboot

# 8) Когда телефон загрузился — на стороне WSL:
./wsl-usbnet-up.sh
./setup-ssh-key.sh
./resize-root.sh
./wsl-share-internet.sh

# Дальше apk на телефоне работает: можно ставить wpa_supplicant, htop, tmux, ...
```

---

## Известные проблемы

- **Wi-Fi (`ath10k_snoc`, чип WCN3990) не поднимается** на mainline kernel 6.14.7-sm7125 в нашей конфигурации. `regulatory.db` не подхватывается потому что `cfg80211` вкомпилирован в kernel (builtin), и `request_firmware` не повторяется после монтирования rootfs. Альтернативы: `regdb` в initramfs (через `/etc/mkinitfs/files.d/`) и/или USB-Ethernet адаптер. См. подробности в [phoneserver-pmos-setup.md](../../phoneserver-pmos-setup.md).
- **RTC battery отсутствует** — после reboot системные часы откатываются в 1975 год. Нужно настроить `chrony`/`openntpd` в default runlevel. Сейчас сделано вручную через `share-internet`.
- **Charge limit** не настроен. Постоянная зарядка 100% убьёт батарею за полгода. Нужен либо kernel-параметр через `/sys/class/power_supply/battery/`, либо железный таймер на розетке.
- **Один порт USB-C** — он же зарядка, он же связь с WSL. Для долгосрочной эксплуатации нужен PD-хаб с passthrough питанием.

---

## Тонкости joyeuse, на которые мы наступили

- pmaports под `xiaomi-miatoll` рассчитан скорее на `curtana` (Redmi Note 9S): `deviceinfo_flash_method="fastboot-bootpart"` хочет прошивать boot в `cache` partition как FAT32 EFI ESP с systemd-boot. На joyeuse Xiaomi-bootloader **не умеет** грузить EFI напрямую, и `lk2nd` для SM7125 не существует. Поэтому собрали свой Android boot.img и прошили в обычный `boot` partition.
- Раздел `cache` на joyeuse только 384 MiB, а pmbootstrap по умолчанию делает 512 MiB boot.img + жёстко это проверяет. Отсюда `patch-pmbootstrap-bootsize.sh`.
- В свежей `device-xiaomi-miatoll` (testing) пакет нет sub-package'ей `*-kernel-joyeuse/curtana`. Достаточно стандартного `device-xiaomi-miatoll` + `linux-postmarketos-qcom-sm7125`, а DTB выбирается systemd-boot'ом (либо нашим объединённым DTB в Android boot.img).
- В boot.img пихается **конкатенация обоих DTB** (huaxing + tianma) — bootloader сам выбирает правильный по compatible. Какой именно дисплей у этого экземпляра — не знаем, и проверять не нужно.
- `dtbo` partition на joyeuse применяется bootloader'ом как overlay поверх основного DTB и ломает наш DTB. Перед прошивкой обязательно `fastboot erase dtbo`.
- pmOS `vmlinuz` — это **EFI zboot wrapper** (PE/COFF с gzip-сжатым ARM64 Image внутри), Android-bootloader его так загрузить не может. См. `extract-kernel-from-zboot.py`.
- Mainline `cfg80211` — **builtin**, не модуль. Любые манипуляции с `wireless-regdb` требуют перезагрузки (либо включения в initramfs).
