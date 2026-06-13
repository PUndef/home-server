# Миграция phoneserver → postmarketOS v25.12

Headless-сборка с ядром **6.14.7-sm7125** и схемой загрузки **fastboot-bootpart** (kernel в `cache`, U-Boot в `boot`). Зарядка и PD — **asidko pm6150-charger v0.6.2**.

**HA восстанавливается только после успешного smoke-test.**

## Фазы

| # | Действие | Где |
|---|----------|-----|
| 0 | Бэкап HA на Proxmox | уже: `/root/backups/phoneserver-pre-v2512/` |
| 1 | Сборка образов | Proxmox (WSL сейчас без сети) |
| 2 | Fastboot flash | ПК/Proxmox + USB к телефону |
| 3 | `post-flash-setup.sh` | с ПК по Wi‑Fi |
| 4 | `install-asidko-charger-v062.sh` | на телефоне → **reboot** |
| 5 | `smoke-test-post-flash.sh` | на телефоне — **gate для HA** |
| 6 | `restore-ha.sh` | только если smoke-test = PASS |

## Сборка (Proxmox)

```bash
# на Proxmox как root
bash /root/pmos-build/proxmox-start-build.sh
tail -f /root/pmos-build/build.log
```

Артефакты:

- `~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-boot.img` → **`cache`**
- `.../xiaomi-miatoll-root.img` → **`userdata`**
- `/root/pmos-artifacts/u-boot-sm7125.img` → **`boot`**

## Прошивка (fastboot)

Телефон: Vol-Down + Power → `fastboot devices`.

```bash
ARTIFACT_DIR=/root/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs \
  bash migrate-v2512/flash-fastboot.sh
```

**Не прошивать boot.img в partition `boot`** — только U-Boot.

## После первой загрузки

```bash
PHONE_IP=192.168.1.227 bash migrate-v2512/post-flash-setup.sh
scp migrate-v2512/install-asidko-charger-v062.sh pmos@$PHONE_IP:/tmp/
ssh pmos@$PHONE_IP sudo sh /tmp/install-asidko-charger-v062.sh
# reboot, подключить хаб (LAN + питание)
ssh pmos@$PHONE_IP sudo sh smoke-test-post-flash.sh
```

## Restore HA

```bash
PHONE_IP=192.168.1.227 bash migrate-v2512/restore-ha.sh
```
