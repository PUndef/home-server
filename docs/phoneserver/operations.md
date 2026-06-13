# Phoneserver — повседневная эксплуатация

> **Статус:** living reference  
> **Последняя проверка:** 2026-06-12  
> **Связано:** [pmos-setup.md](pmos-setup.md), [voice-assistant.md](voice-assistant.md), [scripts/phoneserver/README.md](../../scripts/phoneserver/README.md)

Phoneserver — **dual-homed**: основной uplink **eth0** в srv (`192.168.50.127`), **wlan0** в lan (`192.168.1.227`) для Voice PE и Groq PBR. Падение телефона **не роняет** Proxmox, но отключает HA, Beszel agent и голосовой ассистент.

---

## Быстрые проверки

```bash
# SSH — eth (через Proxmox jump, если с ПК нет маршрута в 50.x):
ssh -i ~/.ssh/proxmox_pundef_nopass root@192.168.50.9
sshpass -p 1234 ssh user@192.168.50.127

# SSH — wlan (из lan, ключ):
ssh -i ~/.ssh/phoneserver_nopass user@192.168.1.227

# Сводка (PHONE_IP из hosts.yaml, по умолчанию srv .127):
./scripts/phoneserver/status.sh

# Health homelab с роутера:
python start.py check_stack
```

**Проверить сервисы на телефоне:**

```bash
curl -s -o /dev/null -w 'HA=%{http_code}\n' http://127.0.0.1:8123/
systemctl is-active docker beszel-agent phoneserver-disable-usb-gadget
cat /sys/class/power_supply/battery/status
```

---

## После reboot телефона

1. Подождать ~30–60 с (systemd, NM, docker).
2. `ping 192.168.50.127` с Proxmox или `ping 192.168.1.227` с lan.
3. Если **eth0 нет** — переткнуть USB-C хаб (host mode + PD); проверить `systemctl status phoneserver-disable-usb-gadget`.
4. USB fallback: `usbipd attach`, `./wsl-usbnet-up.sh`, `PHONE_IP=172.16.42.1 PHONE_DEFAULT=usb ./status.sh`.
5. Beszel offline в UI — перерегистрация fingerprint/token в hub DB или `./scripts/phoneserver/beszel-agent-install-systemd.sh`.

---

## Какой IP когда использовать

| Задача | IP | Почему |
| ------ | -- | ------ |
| HA в браузере, Kuma, Beszel | `192.168.50.127:8123` | srv eth, стабильный путь с homelab |
| HA `internal_url`, Voice PE | `192.168.1.227:8123` | Voice PE только в lan |
| SSH с Proxmox / srv | `user@192.168.50.127` | jump уже в srv |
| SSH с WSL на lan | `user@192.168.1.227` | прямой wlan |
| Groq/Yandex egress (pbr) | src `192.168.1.227` + `192.168.50.127` | `enable-phoneserver-ai-pbr.sh` |

---

## Смена IP / новый телефон

Инвентарь: [scripts/phoneserver/hosts.yaml](../../scripts/phoneserver/hosts.yaml).

После смены IP на OpenWrt:

- [reserve-phoneserver-dhcp.sh](../../scripts/openwrt/reserve-phoneserver-dhcp.sh) — srv + wlan MAC
- [custom.bypass_devices.sh](../../scripts/openwrt/custom.bypass_devices.sh) — zapret bypass для wlan IP
- [enable-phoneserver-ai-pbr.sh](../../scripts/openwrt/enable-phoneserver-ai-pbr.sh) — оба src IP
- Kuma: `scripts/phoneserver/kuma-monitors.json` + seed
- Beszel UI: Host в настройках системы

Переустановка с нуля: [migrate-v2512/README.md](../../scripts/phoneserver/migrate-v2512/README.md).

---

## Критичность для homelab

| Сервис на phoneserver | Если упал |
| --------------------- | --------- |
| Uptime Kuma | **не здесь** — Kuma на `192.168.50.35` |
| Beszel agent | Пропадают метрики телефона в Beszel UI |
| Home Assistant | Голос / автоматизации недоступны |
| Voice PE | Работает локально, но без HA — бесполезен |

Runbook роутера и srv: [router-resilience.md](../network/router-resilience.md).
