# phoneserver — postmarketOS на Redmi Note 9 Pro

Второй физический узел домашней инфраструктуры — Xiaomi Redmi Note 9 Pro Global (codename **`joyeuse`**, SoC SM7125 / Snapdragon 720G), переделанный под headless-сервер на postmarketOS. Изначальная мотивация — UPS «из коробки» (батарея 5020 mAh), 8-ядерный ARM, 6 ГБ RAM и 128 ГБ UFS, потребление 2–5 Вт в idle.

Рабочие скрипты для повседневной эксплуатации и переустановки — [`scripts/phoneserver/`](scripts/phoneserver/README.md).

---

## Состояние

| Параметр | Значение |
|---|---|
| Хост | Xiaomi Redmi Note 9 Pro Global, codename `joyeuse`, 6/128 ГБ |
| SoC | Qualcomm SM7125 (Snapdragon 720G), 8 ядер aarch64 |
| Ядро | Mainline Linux **6.14.7-sm7125** |
| ОС | postmarketOS Edge, **без UI** (`ui=none`), без `systemd` (OpenRC) |
| Корень | `/dev/sda18` (userdata), ext4, **103 GiB** свободно |
| Boot partition | `/dev/disk/by-partlabel/boot` (Android `boot`, 128 MiB) — наш Android-style boot.img |
| `cache` partition | 384 MiB, не используется в нашей схеме |
| Hostname | `phoneserver` |
| Пользователь | `pmos` (sudo NOPASSWD пока не настроен; пароль `changemenow`) |
| SSH-ключ от WSL | `~/.ssh/phoneserver_nopass` (ed25519, без passphrase) |
| Сеть | USB-CDC `usb0` 172.16.42.1/16 ← связь со стороны WSL Ubuntu 24.04 на основном ПК |
| Swap | 8.2 GiB zram |
| Время | сбрасывается при reboot (нет RTC battery) — TODO: NTP в default runlevel |

---

## Сделано в эту итерацию

1. **Mi Unlock** на стоковой MIUI (бутлоадер разблокирован, `userdata` зачищен, FBE-ключи в TEE уничтожены).
2. **WSL Ubuntu 24.04** на основном ПК, поверх:
   - `pmbootstrap` 3.10.1 через `pipx` (apt-версия 2.1.0 устарела — несовместима с актуальным `pmaports`)
   - `usbipd-win` для проброса USB в WSL
   - `mkbootimg-osm0sis` (через `pmbootstrap chroot` — Ubuntu-пакет `mkbootimg` сломан из-за отсутствующего `gki` модуля)
3. **`pmaports` main**, shallow-clone (полный clone из `gitlab.postmarketos.org` слишком медленный из локальной сети — 470 KB/s).
4. **`pmbootstrap init`** автоматизирован через `expect`-скрипт (см. [`scripts/phoneserver/pmbootstrap-init.exp`](scripts/phoneserver/pmbootstrap-init.exp)): UI=none, hostname=phoneserver, locale=C.UTF-8, без SSH-ключей хоста.
5. **Зеркало pmOS** — `https://distrohub.kyiv.ua/postmarketos/` (дефолтный `mirror.postmarketos.org` отдавал ~3 KB/s, остальные мирроры работали стабильно).
6. **Локальная пересборка пакета** `device-xiaomi-miatoll` (testing-категория, бинарей на зеркалах нет).
7. **Патч `pmbootstrap`** (см. [`patch-pmbootstrap-bootsize.sh`](scripts/phoneserver/patch-pmbootstrap-bootsize.sh)) — снимает hardcoded sanity-check `boot_size >= 512 MiB`. У joyeuse раздел `cache` всего 384 MiB.
8. **Кастомный Android boot.img** (см. [`build-bootimg.sh`](scripts/phoneserver/build-bootimg.sh)):
   - распакован kernel из EFI-zboot wrapper (PE/COFF + gzip-payload) — [`extract-kernel-from-zboot.py`](scripts/phoneserver/extract-kernel-from-zboot.py)
   - в boot.img уложены **оба** joyeuse DTB (huaxing + tianma), bootloader сам выбирает по compatible
   - header v2, стандартные offsets SM7125, cmdline `console=null no_console_suspend earlycon ignore_loglevel PMOS_NO_OUTPUT_REDIRECT`
9. **Прошивка**: `fastboot erase dtbo` (чтобы Xiaomi-overlay не ломал DTB) → `fastboot flash boot <наш .img>` → `fastboot flash userdata <pmOS rootfs>`. Самозагрузка работает.
10. **SSH** — ключ от WSL положен, password disabled не настроен.
11. **`resize2fs`** довёл root до полных 103 GiB (pmbootstrap делает ~650 MiB по умолчанию).
12. **Internet sharing** через WSL (`MASQUERADE` на eth0) — для `apk update` пока нет Wi-Fi.

---

## Архитектурные решения, не очевидные из pmaports

| Вопрос | Что выяснили |
|---|---|
| Почему не `fastboot-bootpart` (новая дефолтная схема pmaports для miatoll)? | Bootloader Xiaomi на joyeuse **не умеет** грузить EFI/systemd-boot из `cache` partition. `lk2nd` для SM7125 не существует (только msm89xx). Поэтому собираем классический Android boot.img в Android `boot` partition. |
| Почему оба DTB в одном boot.img? | У Redmi Note 9 Pro два варианта дисплея — Huaxing и Tianma. Какой именно у этого экземпляра — не знаем. Concat в multi-DTB blob в Android boot.img стандартен; bootloader выбирает по `qcom,board-id` match. |
| Почему `dtbo erase`? | На стоке `dtbo` partition содержит Android-overlay, который накладывается на главный DTB до передачи в kernel. Этот overlay рассчитан на vendor-ROM и ломает наш DTB. |
| Почему `vmlinuz` нельзя пихать в Android boot.img как есть? | pmOS `vmlinuz` собран как **EFI zboot wrapper** (PE/COFF c gzip-сжатым ARM64 Image внутри). Android bootloader его не распакует. Извлекаем raw Image через `extract-kernel-from-zboot.py`. |
| Почему `cfg80211` не подхватывает `regulatory.db`? | `cfg80211` **вкомпилирован** в kernel (builtin), `request_firmware` вызывается **до** монтирования rootfs, retry'я нет. Файл `regulatory.db` (из `wireless-regdb`) лежит в rootfs, но загружается слишком поздно. Решение — `regdb` в initramfs через `/etc/mkinitfs/files.d/`. |
| Почему `pmbootstrap install --no-fde`? | Headless-сервер, монитор/клавиатура не подключены, FDE-пароль вводить негде. |
| Почему `build_pkgs_on_install = True`? | Пакет `device-xiaomi-miatoll` в категории **testing**, бинарей на зеркалах нет. |

---

## Текущие проблемы / TODO

| Приоритет | Задача | Комментарий |
|---|---|---|
| **высокий** | **Charge limit** | Постоянная зарядка 100% убьёт батарею. Точное API зависит от драйвера; начать с `/sys/class/power_supply/battery/charge_control_limit`. Либо железный таймер на розетке. |
| ~~высокий~~ ✅ | **NTP при boot** | Готово: `chrony` + `chrony-openrc` в default runlevel. После reboot системные часы синхронизируются за секунды. См. `[scripts/phoneserver/harden-basics.sh](scripts/phoneserver/harden-basics.sh)`. |
| **средний** | **Wi-Fi** (`ath10k_snoc` / WCN3990) | Нужно либо: (1) включить `regulatory.db` в initramfs через `/etc/mkinitfs/files.d/`, либо (2) разобраться с qcom_remoteproc + QMI bring-up на SM7125. Альтернатива — USB-Ethernet адаптер. |
| **средний** | **Интеграция в `srv`-сегмент** | После появления Wi-Fi/Ethernet — DHCP-резервация на OpenWrt X3000T на `192.168.50.60` (по аналогии с `nextcloud-vm` / `haos17.0` в [`hardware-and-env.md`](hardware-and-env.md)). DNS дать `1.1.1.1 / 8.8.8.8` через `dhcp_option='6,...'`. |
| ~~низкий~~ ✅ | Отключить парольный SSH | Готово через `harden-basics.sh`: `PasswordAuthentication no` и `ChallengeResponseAuthentication no` в `/etc/ssh/sshd_config`, ключ-only login. |
| ~~низкий~~ ✅ | Поменять пароль `pmos` с `changemenow` | Готово через `harden-basics.sh`. Новый пароль — у владельца устройства, не в репо. Скрипты используют env-переменную `SUDO_PASS` (или `OLD_PASS`/`NEW_PASS` в `harden-basics.sh`). |
| низкий | Расширить `scripts/openwrt/check_stack.py` | Добавить пробу `phoneserver` ping + ssh (по аналогии с `vm-services`). |
| низкий | Запись в [`hardware-and-env.md`](hardware-and-env.md) | Когда телефон получит постоянный IP в `srv`-сегменте. |

---

## Файлы и пути

- **Образы pmOS** на стороне WSL:
  - boot.img: `~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-boot.img` (512 MiB EFI ESP с systemd-boot — **не используется** на joyeuse, остаётся для совместимости с pmaports flow)
  - root.img: `~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-root.img`
- **Наш кастомный Android boot.img**: `~/.local/var/pmbootstrap/chroot_native/home/pmos/pmos-joyeuse-test.img`
- **pmbootstrap config**: `~/.config/pmbootstrap_v3.cfg` (TOML/INI-формат v3)
- **pmaports**: `~/.local/var/pmbootstrap/cache_git/pmaports` (branch `main`, shallow)
- **SSH ключ** (на WSL): `~/.ssh/phoneserver_nopass{,.pub}` — выделенный, без passphrase, по образцу `~/.ssh/proxmox_pundef_nopass` для Proxmox

---

## Аппаратное состояние портов joyeuse в pmOS 6.14.7-sm7125

Что точно работает:
- CPU (8 ядер), RAM, UFS storage
- USB-CDC NCM (USB-сеть)
- Bluetooth (QCA WCN3990) — `hci0` поднимается, firmware `qca/crbtfw32.tlv` + `crnv32u.bin` загружается
- DSP (`adsp.mbn`, `cdsp.mbn`) — для сенсоров (`hexagonrpcd-adsp-sensorspd` стартует)

Что не проверяли / не нужно для сервера:
- Дисплей (виден консолью, но перевёрнут — нормально для портретного устройства)
- Камеры
- Аудио (динамик/микрофон)
- Модем (cellular)

Что не работает:
- Wi-Fi (`ath10k_snoc` загружен, но не активирует чип — см. TODO выше)
- RTC (нет hardware battery, time сбрасывается при power-off)
