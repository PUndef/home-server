# phoneserver — postmarketOS на Redmi Note 9 Pro

Второй физический узел домашней инфраструктуры — Xiaomi Redmi Note 9 Pro Global (codename `**joyeuse**`, SoC SM7125 / Snapdragon 720G), переделанный под headless-сервер на postmarketOS. Изначальная мотивация — UPS «из коробки» (батарея 5020 mAh), 8-ядерный ARM, 6 ГБ RAM и 128 ГБ UFS, потребление 2–5 Вт в idle.

Рабочие скрипты для повседневной эксплуатации и переустановки — [scripts/phoneserver/](../../scripts/phoneserver/README.md).  
Голосовой ассистент (Voice PE + HA) — [voice-assistant.md](voice-assistant.md).

---

## Состояние


| Параметр          | Значение                                                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Хост              | Xiaomi Redmi Note 9 Pro Global, codename `joyeuse`, 6/128 ГБ                                                             |
| SoC               | Qualcomm SM7125 (Snapdragon 720G), 8 ядер aarch64                                                                        |
| Ядро              | Mainline Linux **6.12.1-sm7125** (pmaports канал `v25.06`, kernel sub-package `joyeuse_tianma`)                          |
| ОС                | postmarketOS **v25.06 stable**, `ui=none`, OpenRC (без systemd)                                                          |
| Корень            | `/dev/sda18` (userdata), ext4, **103 GiB** свободно                                                                      |
| Boot partition    | `/dev/disk/by-partlabel/boot` (Android `boot`, 128 MiB) — pmbootstrap-сгенерированный Android boot.img (~18 MB sparse)   |
| `cache` partition | 384 MiB, не используется в этой схеме                                                                                    |
| Hostname          | `phoneserver`                                                                                                            |
| Пользователь      | `pmos`, **NOPASSWD sudo** через `/etc/sudoers.d/pmos-nopasswd` (доступ только по SSH-ключу)                              |
| SSH-ключ от WSL   | `~/.ssh/phoneserver_nopass` (ed25519, без passphrase)                                                                    |
| LAN (eth0)        | USB-C хаб с RJ45 → Mercusys → OpenWrt `lan`; DHCP `**192.168.1.227**`, MAC `dc:04:5a:58:5a:93`                           |
| USB-сеть          | `usb0` 172.16.42.1/16 — резервный канал при прямом USB к ПК (usbipd)                                                     |
| DNS               | `1.1.1.1, 8.8.8.8` (в обход dnsmasq роутера / sing-box, через `/etc/resolv.conf` + `nohook resolv.conf` в `dhcpcd.conf`) |
| Swap              | 8.2 GiB zram                                                                                                             |
| Время             | синхронизируется `chrony` при загрузке (RTC battery в устройстве физически отсутствует)                                  |


---

## Сделано

### Установка (edge → v25.06)

1. **Mi Unlock** на стоковой MIUI (бутлоадер разблокирован, `userdata` зачищен, FBE-ключи в TEE уничтожены).
2. **WSL Ubuntu 24.04** на основном ПК + `pmbootstrap` 3.10.1 (apt-версия 2.1.0 устарела), `usbipd-win` для проброса USB.
3. **Первая попытка на pmaports `main` (edge)**: Linux 6.14.7, новая EFI-bootpart схема. Завелось через кастомный Android boot.img из артефактов pmOS (kernel из EFI zboot wrapper, объединённый joyeuse DTB, `dtbo erase`). Но **Wi-Fi не запустился** (`ath10k_snoc` не делал firmware download на этой ветке), а Type-C застрял в `source` role (зарядка от ПК не работала).
4. **Переход на pmaports `v25.06` stable** — там для `xiaomi-miatoll` ещё актуальна классическая схема с отдельными kernel-пакетами `device-xiaomi-miatoll-kernel-joyeuse_tianma`, `flash_method="fastboot"`, нормальным Android boot.img, и **рабочим WLAN** на ath10k_snoc. Это и есть текущее рабочее состояние.
5. **Прошивка v25.06**: `fastboot erase dtbo` (чтобы Xiaomi-overlay не ломал DTB) → `fastboot flash boot xiaomi-miatoll-boot.img` (18 MB sparse в 128 MiB boot) → `fastboot flash userdata xiaomi-miatoll-root.img` (570 MB → 103 GB после resize). Самозагрузка работает.

### Базовая настройка (v25.06)

1. **SSH-ключ от WSL** положен в `pmos@phoneserver:~/.ssh/authorized_keys`.
2. **Реальный sudo вместо doas-sudo-shim** + `/etc/sudoers.d/pmos-nopasswd` (см. [`enable-passwordless-doas.sh`](../../scripts/phoneserver/install/enable-passwordless-doas.sh)). По умолчанию в pmOS v25.06 стоит `doas + doas-sudo-shim`, в котором нет `sudo -S` — это ломает скрипты с `echo $pass | sudo -S`. Замена на настоящий `sudo` + NOPASSWD убирает проблему.
3. `**resize2fs /dev/sda18`** — root до 103 GiB.
4. **LAN (eth0)**: USB-Ethernet хаб, `dhcpcd` на eth0, IP `192.168.1.227`. DHCP-резервация: `scripts/openwrt/reserve-phoneserver-dhcp.sh`.
5. **DNS pinned**: `/etc/resolv.conf` → `1.1.1.1, 8.8.8.8`; `nohook resolv.conf` в `/etc/dhcpcd.conf` чтобы dhcpcd при ренью не возвращал dnsmasq роутера (с sing-box подкопом).
6. `**chrony`** + `chrony-openrc` в default runlevel — время синхронизируется при загрузке.
7. **Internet sharing через WSL** (`MASQUERADE`) нужен только при первичной установке до появления eth в LAN. В штатной эксплуатации phoneserver в сети через хаб.

### Архитектурные решения, не очевидные из pmaports


| Вопрос                                                   | Что выяснили                                                                                                                                                                                                                                                                                                            |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Почему именно channel `v25.06`, а не `edge`?             | На `edge` (pmaports `main`) сейчас идёт переход на схему `fastboot-bootpart` с EFI ESP в `cache` партиции и systemd-boot. На `joyeuse` это **не работает**: bootloader Xiaomi не умеет грузить EFI/systemd-boot, `lk2nd` для SM7125 не существует, а заодно отвалился WLAN. На `v25.06` всё это в стабильном состоянии. |
| Почему `kernel = joyeuse_tianma`, а не просто `joyeuse`? | У RN9 Pro два варианта дисплея (Huaxing и Tianma). У нас Tianma — pmbootstrap выбирает соответствующий DTB через kernel sub-package. Подтверждаем через сканирование Wi-Fi: BSSID, на котором ассоциация COMPLETED, успешно подцепляется именно с этим DTB.                                                             |
| Почему `dtbo erase`?                                     | На стоке `dtbo` partition содержит Android-overlay, который накладывается на главный DTB до передачи в kernel. Этот overlay рассчитан на vendor-ROM и ломает наш DTB.                                                                                                                                                   |
| Почему replace `doas-sudo-shim` на настоящий `sudo`?     | pmOS v25.06 по умолчанию переключился на `doas`, а `doas-sudo-shim` не поддерживает `sudo -S` (password из stdin). Все наши скрипты с `echo "$PASS" | sudo -S ...` ломаются. NOPASSWD-sudo решает это для headless-узла.                                                                                                |
| Почему `nohook resolv.conf` в dhcpcd.conf?               | Иначе при renew dhcpcd перезаписывает `/etc/resolv.conf` на `192.168.1.1` (dnsmasq на OpenWrt), а тот может вернуть fake-IP от sing-box для определённых доменов → подключения к Cloudflare/Alpine mirrors зависают. Чистый public DNS обходит подкоп.                                                                  |


---

## Текущие проблемы / TODO


| Приоритет   | Задача                                                            | Комментарий                                                                                                                                                                                                                                                                                                           |
| ----------- | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **высокий** | **Зарядка от USB-PD-хаба**                                        | Ждём приезд USB-C хаба с PD passthrough + RJ45. Пока используется wall-PD-зарядка отдельно от USB-связи с ПК; от ПК через USB-A фоном **не** заряжается (Type-C порт уходит в `source` role). Через хаб одновременно: PD-passthrough зарядка + Ethernet в `srv`-сегмент.                                              |
| средний     | **Интеграция в `srv`-сегмент**                                    | Сейчас phoneserver в `lan` (`192.168.1.227`) — pbr/zapret/awg на клиентском сегменте. Опционально: хаб в `lan2` X3000T → IP в `192.168.50.0/24`. DHCP-резервация: MAC `dc:04:5a:58:5a:93`. |
| низкий      | **Charge limit при питании через хаб**                            | Когда подключим хаб с PD passthrough — постоянная зарядка станет реальной 24/7. Тогда либо kernel-параметр `/sys/class/power_supply/battery/charge_control_*` (если драйвер поддержит), либо железный таймер на розетке.                                                                                              |
| низкий      | **Отключить парольный SSH**                                       | Сейчас SSH работает по ключу. Стоит явно поставить `PasswordAuthentication no` в `/etc/ssh/sshd_config` после того как пароль будет сменён с `changemenow`.                                                                                                                                                           |
| низкий      | **Поменять пароль `pmos`** с `changemenow`                        | После v25.06-переустановки пароль снова дефолтный. SSH-логин — только по ключу, но sudo-пароль (на случай восстановления) поменять стоит.                                                                                                                                                                             |
| низкий      | Расширить `scripts/openwrt/check_stack.py`                        | Добавить пробу `phoneserver` ping + ssh (по аналогии с `vm-services`).                                                                                                                                                                                                                                                |
| низкий      | Запись в [hardware-and-env.md](../overview/hardware-and-env.md) | Обновить когда телефон получит постоянный IP в `srv`-сегменте.                                                                                                                                                                                                                                                        |


---

## Файлы и пути

- **Образы pmOS** на стороне WSL:
  - boot.img: `~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-boot.img` (128 MiB ext2 c kernel + initramfs + DTB; pmbootstrap делает Android boot.img автоматически)
  - root.img: `~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-root.img` (570 MiB; растягивается до 103 GiB после `resize2fs` на устройстве)
- **pmbootstrap config**: `~/.config/pmbootstrap_v3.cfg` (TOML/INI-формат v3)
- **pmaports**: `~/.local/var/pmbootstrap/cache_git/pmaports`, branch `**v25.06`**, shallow-clone
- **SSH ключ** (на WSL): `~/.ssh/phoneserver_nopass{,.pub}` — выделенный, без passphrase, по образцу `~/.ssh/proxmox_pundef_nopass` для Proxmox

---

## Аппаратное состояние портов joyeuse в pmOS 6.12.1-sm7125 (v25.06)

Работает:

- CPU (8 ядер), RAM, UFS storage
- **USB-Ethernet** (eth0 через хаб) — основной uplink в `lan`
- Bluetooth (QCA WCN3990) — `hci0` поднимается, firmware `qca/crbtfw32.tlv` + `crnv32u.bin` загружается
- USB-CDC NCM (USB-сеть к WSL как резерв)
- DSP (`adsp.mbn`, `cdsp.mbn`) — для сенсоров (`hexagonrpcd-adsp-sensorspd` стартует)
- Modem (cellular, `rmnet_ipa0` интерфейс) — без SIM не пробовали, но `qcom_q6v5_pas` грузит modem.mbn

Не работает / не пользуется:

- **Зарядка от USB-A через ПК** — Type-C порт стартует в `source` role и не переходит в `sink` без полноценной PD-negotiation. От wall PD-зарядки работает нормально.
- **RTC** — hardware battery отсутствует, время сбрасывается при power-off → `chrony` синхронизирует при загрузке.
- Дисплей (виден консолью, но перевёрнут — нормально для портретного устройства, для headless не важно)
- Камеры, аудио, тач — не нужны для сервера

