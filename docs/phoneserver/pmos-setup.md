# phoneserver — postmarketOS на Redmi Note 9 Pro

Второй физический узел домашней инфраструктуры — Xiaomi Redmi Note 9 Pro Global (codename **joyeuse**, SoC SM7125 / Snapdragon 720G), headless-сервер на postmarketOS. Мотивация: встроенный UPS (батарея 5020 mAh), 8 ядер ARM, 6 ГБ RAM, 128 ГБ UFS, 2–5 Вт в idle.

Рабочие скрипты — [scripts/phoneserver/](../../scripts/phoneserver/README.md).  
Голосовой ассистент — [voice-assistant.md](voice-assistant.md).  
Повседневная эксплуатация — [operations.md](operations.md).  
Переустановка / миграция v25.12 — [migrate-v2512/README.md](../../scripts/phoneserver/migrate-v2512/README.md).

> **Последняя проверка:** 2026-06-12 (живой узел `192.168.50.127`)

---

## Текущее состояние


| Параметр | Значение |
| -------- | -------- |
| Хост | Xiaomi Redmi Note 9 Pro Global, codename `joyeuse`, 6/128 ГБ |
| Панель | **Huaxing** (DTB `sm7125-xiaomi-joyeuse-huaxing-pd`) |
| SoC | Qualcomm SM7125 (Snapdragon 720G), 8 ядер aarch64 |
| Ядро | Mainline Linux **6.14.7-sm7125** (asidko / pmaports `v25.12`) |
| ОС | postmarketOS **v25.12**, Phosh в образе (headless в эксплуатации), **systemd** |
| Схема загрузки | **fastboot-bootpart**: kernel+initramfs в partition **`cache`**, U-Boot в **`boot`** (не Android boot.img) |
| Корень | `userdata`, ext4, ~103 GiB |
| Hostname | `phoneserver` |
| Пользователь SSH | `user` (образ asidko v25.12), **NOPASSWD sudo** |
| SSH-ключ | `~/.ssh/phoneserver_nopass` (WSL/ПК); jump с Proxmox: `root@192.168.50.9` → `user@192.168.50.127` |
| **eth0** (USB-C хаб → srv) | **`192.168.50.127/24`**, MAC `dc:04:5a:58:5a:93` (permanent в NetworkManager), DHCP-резерв на роутере |
| **wlan0** (2.4 GHz) | **`192.168.1.227/24` static** (Voice PE / HA `internal_url`, Groq PBR), MAC `22:84:8d:3d:5d:8e` |
| USB gadget | `usb0` `172.16.42.1/16` — резерв при прямом USB к ПК; отключается unit `phoneserver-disable-usb-gadget` для host mode хаба |
| DNS | `1.1.1.1, 8.8.8.8` (в обход dnsmasq / sing-box) |
| Swap | zram ~8 GiB |
| Время | `chronyd` (RTC battery отсутствует) |
| Зарядка | asidko **pm6150-charger v0.6.2**: `qcom_qg` + `joyeuse_battery_shim` + `pm6150_chgr_minimal`; PD dual role через PD-DTB |
| Лимит батареи | `term_capacity=80`, `term_hysteresis=5` (24/7 на хабе, против вздутия) |
| Home Assistant | Docker, `http://192.168.50.127:8123/` (основной UI), `internal_url` → wlan `.227` |
| Beszel agent | systemd, hub `192.168.50.35`, мониторинг по eth `.127` |
| Uptime Kuma | **не на телефоне** — LXC `192.168.50.35:3001` |

### Доступ с ПК

Прямой маршрут ПК (`192.168.1.x`) → `192.168.50.x` **не всегда есть**. Надёжные пути:

```bash
# Через Proxmox (jump):
ssh -i ~/.ssh/proxmox_pundef_nopass root@192.168.50.9
sshpass -p 1234 ssh user@192.168.50.127

# wlan (если виден из lan):
ssh -i ~/.ssh/phoneserver_nopass user@192.168.1.227
```

---

## Сделано (история)

Пункты, которые уже выполнены. Оставлены для истории; в текущем плане не повторять.

| Когда | Что сделано |
| ----- | ----------- |
| 2026-03…05 | Первая установка pmOS на **v25.06** / **6.12.1-sm7125**, kernel sub-package `joyeuse_tianma`, OpenRC, пользователь `pmos`, Android boot.img в partition `boot` |
| 2026-05 | Eth через хаб в srv `.127`; HA Container; Voice PE; Groq/Yandex; Kuma перенесён на LXC `.35` |
| 2026-06-12 | **Миграция на v25.12 / 6.14.7-sm7125** (asidko prebuilt + fastboot-bootpart), панель Huaxing, PD зарядка с хаба, HA restore, Beszel, лимит зарядки 80% |

---

## Архитектурные решения


| Вопрос | Ответ |
| ------ | ----- |
| Почему v25.12, а не v25.06? | На v25.12 + asidko **6.14.7** работают **одновременно** USB host (eth хаба), PD-зарядка и стабильный WLAN. v25.06 / 6.12.1 не давала зарядку с хаба без ломания eth. |
| Почему `cache` = kernel, `boot` = U-Boot? | Схема pmaports **fastboot-bootpart** для v25.12. **Никогда** не прошивать pmOS `boot.img` в partition `boot` — только U-Boot. |
| Huaxing vs Tianma | Два варианта дисплея RN9 Pro. У нас **Huaxing** — PD-DTB `…-huaxing-pd.dtb`; скрипты автоопределяют по `/sys/firmware/devicetree/base/model`. |
| Зачем wlan `.227` при eth `.127`? | Voice PE (`192.168.1.171`) в lan не видит srv `192.168.50.x`. HA `internal_url` — только wlan. Браузер/Kuma/Beszel — eth `.127`. |
| Зачем `phoneserver-disable-usb-gadget`? | pmOS initramfs поднимает USB gadget на `usb0` → занимает UDC → хаб не видит host. Unit освобождает dwc3 до сети. |
| Лимит 80% | Параметр `term_capacity` в `pm6150_chgr_minimal`, не sysfs `charge_control_*` (на joyeuse его нет). |
| `dtbo erase` | На старой v25.06-схеме — убрать Xiaomi overlay DTB. На v25.12 fastboot-bootpart — по инструкции asidko. |

---

## Зарядка и батарея

Файл `/etc/modprobe.d/pm6150-charger.conf`:

```
options pm6150_chgr_minimal icl_ma=2000 fcc_ma=2000 temp_hot_dc=999 term_capacity=80 term_hysteresis=5
```

| Параметр | Назначение |
| -------- | ---------- |
| `icl_ma` | Входной ток с хаба (макс ~2 A) |
| `fcc_ma` | Ток быстрой зарядки в батарею |
| `temp_hot_dc=999` | Отключить ложный JEITA «перегрев» |
| `term_capacity=80` | Остановить зарядку на 80% |
| `term_hysteresis=5` | Возобновить при ~75% |

**Проверить:**

```bash
cat /sys/class/power_supply/battery/{capacity,status}
cat /sys/module/pm6150_chgr_minimal/parameters/term_capacity
cat /sys/class/typec/port0/power_role   # ожидается dual при PD-хабе
```

Установка/обновление модулей: `scripts/phoneserver/migrate-v2512/install-asidko-charger-v062.sh`.

---

## Сеть после reboot

1. Unit `phoneserver-disable-usb-gadget` отключает gadget.
2. **Перетык хаба** (или reboot) часто нужен, чтобы xhci/host поднялся — классическая особенность joyeuse + Type-C.
3. eth0: NM autoconnect, permanent MAC `dc:04:5a:58:5a:93`.
4. wlan0: static `192.168.1.227` в профиле NM `DECO_HOME`.

**Проверить:** `ping 192.168.50.127` с Proxmox; `curl -s -o /dev/null -w '%{http_code}\n' http://192.168.50.127:8123/` → `200`.

---

## Текущие TODO


| Приоритет | Задача | Комментарий |
| --------- | ------ | ----------- |
| средний | Отключить Phosh / полный headless | UI не нужен для сервера |
| низкий | SSH только по ключу | `PasswordAuthentication no` в `sshd_config` |
| низкий | Сменить пароль `user` | Сейчас дефолт образа; sudo NOPASSWD, но пароль для recovery |
| низкий | DHCP-резерв wlan MAC | Фактический MAC `22:84:8d:3d:5d:8e` (static IP в NM уже держит `.227`) |
| низкий | Beszel battery % | Опционально `beszel-battery-status-fix.sh` если qcom_qg `status=Unknown` |
| низкий | Обновить legacy-скрипты `pmos@` → `user@` | Часть оркестраторов ещё с старым логином; см. `hosts.yaml` `ssh_user` |

---

## Файлы и пути

| Что | Где |
| --- | --- |
| Инвентарь IP/SSH | `scripts/phoneserver/hosts.yaml` |
| Миграция v25.12 | `scripts/phoneserver/migrate-v2512/` |
| USB gadget disable | `scripts/phoneserver/disable-usb-gadget.{sh,service}` → `/usr/local/sbin/` |
| HA compose | `/opt/homeassistant/compose.yaml` |
| nftables HA | `/etc/nftables.d/52_homeassistant.nft` (tcp/8123 wlan+eth) |
| Модули зарядки | `/lib/modules/6.14.7-sm7125/extra/` |
| PD DTB | `/boot/dtbs/qcom/sm7125-xiaomi-joyeuse-huaxing-pd.dtb`, `deviceinfo_dtb` в `/etc/deviceinfo` |
| Бэкап HA (pre-migration) | Proxmox `/root/backups/phoneserver-pre-v2512/` |

### Legacy: v25.06 / 6.12.1

Старая схема (Android boot.img в `boot`, OpenRC, `pmos`, `joyeuse_tianma`) — [install/README.md](../../scripts/phoneserver/install/README.md), [install-pm6150-charger.sh](../../scripts/phoneserver/install-pm6150-charger.sh). **Не использовать** для текущего узла.

---

## Аппаратное состояние (6.14.7-sm7125, v25.12)

**Работает:**

- CPU, RAM, UFS
- **USB-Ethernet** (eth0 через PD-хаб) — основной uplink srv
- **USB-C PD** зарядка + host одновременно (asidko + PD-DTB)
- WLAN ath10k_snoc
- Bluetooth (QCA WCN3990)
- DSP / modem (без SIM не используется)
- Docker, chronyd, Beszel agent

**Не используется / ограничения:**

- Дисплей (Phosh есть, для headless не нужен)
- Камеры, тач, аудио на телефоне
- RTC — нет батарейки; время через NTP
- `/sys/.../charge_control_*` — нет; лимит только через `pm6150_chgr_minimal`
