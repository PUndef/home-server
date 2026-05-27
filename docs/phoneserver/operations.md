# Phoneserver — повседневная эксплуатация

> **Статус:** living reference  
> **Связано:** [pmos-setup.md](pmos-setup.md), [scripts/phoneserver/README.md](../../scripts/phoneserver/README.md)

Phoneserver — узел в сегменте `lan` (`192.168.1.116`), не в `srv`. Его падение **не роняет** Proxmox, но отключает Uptime Kuma и часть мониторинга.

---

## Быстрые проверки

```bash
# SSH по Wi-Fi:
ssh -i ~/.ssh/phoneserver_nopass pmos@192.168.1.116

# Сводка (PHONE_IP из hosts.yaml по умолчанию):
./scripts/phoneserver/status.sh

# Health homelab с роутера (включая lease phoneserver):
python start.py check_stack
```

---

## После reboot телефона

1. Подождать ~1–2 мин (OpenRC `phoneserver-wifi`).
2. `ping 192.168.1.116` с ПК.
3. Если нет ответа — USB fallback: `usbipd attach`, `./wsl-usbnet-up.sh`, `PHONE_IP=172.16.42.1 ./wifi-reconnect.sh`.
4. Kuma: `http://192.168.1.116:3001/` — мониторы могут краснеть до поднятия Wi-Fi/DNS.

---

## Смена IP / новый телефон

Инвентарь: [scripts/phoneserver/hosts.yaml](../../scripts/phoneserver/hosts.yaml). Для другого codename — новая секция в yaml + `PHONE_HOST=<id>` или установка через [install/](../../scripts/phoneserver/install/README.md).

После смены IP на OpenWrt: [reserve-phoneserver-dhcp.sh](../../scripts/openwrt/reserve-phoneserver-dhcp.sh) и обновить zapret bypass IP в [custom.bypass_devices.sh](../../scripts/openwrt/custom.bypass_devices.sh) + `check_stack` → `zapret-bypass-phoneserver-*`.

---

## Критичность для homelab


| Сервис на phoneserver | Если упал                                                |
| --------------------- | -------------------------------------------------------- |
| Uptime Kuma           | Нет внешних HTTP-probe; Proxmox/Nextcloud могут работать |
| Beszel agent          | Пропадают метрики телефона в Beszel UI                   |
| Wi-Fi                 | Нет SSH/Kuma; инфра на `srv` не затронута                |


Полный runbook по отказоустойчивости **роутера и srv**: [router-resilience.md](../network/router-resilience.md).
