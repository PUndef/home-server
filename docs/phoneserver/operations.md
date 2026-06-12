# Phoneserver — повседневная эксплуатация

> **Статус:** living reference  
> **Связано:** [pmos-setup.md](pmos-setup.md), [scripts/phoneserver/README.md](../../scripts/phoneserver/README.md)

Phoneserver — узел в сегменте `lan` (`192.168.1.227`, eth через USB-Ethernet хаб), не в `srv`. Его падение **не роняет** Proxmox, но отключает Beszel agent и Home Assistant.

---

## Быстрые проверки

```bash
# SSH по LAN (из WSL — ключ ~/.ssh/phoneserver_nopass):
ssh -i ~/.ssh/phoneserver_nopass pmos@192.168.1.227

# Сводка (PHONE_IP из hosts.yaml по умолчанию):
./scripts/phoneserver/status.sh

# Health homelab с роутера (включая lease phoneserver):
python start.py check_stack
```

---

## После reboot телефона

1. Подождать ~30 с (dhcpcd на eth0).
2. `ping 192.168.1.227` с ПК.
3. Если нет ответа — проверить кабель хаб → Mercusys; USB fallback: `usbipd attach`, `./wsl-usbnet-up.sh`, `PHONE_IP=172.16.42.1`.
4. Beszel agent: `./scripts/phoneserver/fix-beszel-agent-lan.sh` если в UI offline.

---

## Смена IP / новый телефон

Инвентарь: [scripts/phoneserver/hosts.yaml](../../scripts/phoneserver/hosts.yaml). Для другого codename — новая секция в yaml + `PHONE_HOST=<id>` или установка через [install/](../../scripts/phoneserver/install/README.md).

После смены IP на OpenWrt: [reserve-phoneserver-dhcp.sh](../../scripts/openwrt/reserve-phoneserver-dhcp.sh) и обновить zapret bypass IP в [custom.bypass_devices.sh](../../scripts/openwrt/custom.bypass_devices.sh) + `check_stack` → `zapret-bypass-phoneserver-*`.

---

## Критичность для homelab

| Сервис на phoneserver | Если упал |
| --------------------- | --------- |
| Uptime Kuma | **снят** — Kuma на `192.168.50.35` |
| Beszel agent | Пропадают метрики телефона в Beszel UI |
| Home Assistant | Голос / автоматизации на phoneserver недоступны |

Полный runbook по отказоустойчивости **роутера и srv**: [router-resilience.md](../network/router-resilience.md).
