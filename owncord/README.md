# OwnCord (homelab)

Self-hosted чат [Restezzz/OwnCord](https://github.com/Restezzz/OwnCord) на LXC 103, HTTPS edge на nextcloud-vm (101), DNS на OpenWrt.

| Параметр | Значение |
|----------|----------|
| LXC | 103, `192.168.50.36` |
| URL | `https://owncord-pundef.mooo.com` |
| Backend | `/opt/owncord`, `systemctl status owncord` |

Полный runbook: **[setup.md](setup.md)**.

## Структура

```text
owncord/
├── README.md              # этот файл
├── setup.md               # деплой, TLS, TURN, патчи, проверки
├── apache/
│   └── owncord-pundef.conf   # vhost на VM 101 (источник правды)
└── scripts/
    ├── proxmox/           # Proxmox host + LXC 103
    │   ├── install.sh
    │   ├── edge-setup.sh
    │   ├── le-cert.sh
    │   ├── restore-selfsigned.sh
    │   ├── turn-install.sh
    │   ├── patch-voice-media.sh
    │   ├── patch-screen-fs-audio.sh
    │   └── qm-guest.sh
    └── openwrt/           # split-horizon DNS, DDNS, TURN DNAT
        ├── enable-dns.sh
        ├── disable-dns.sh
        ├── enable-ddns.sh
        └── enable-turn.sh
```

Общие helpers Proxmox (`upload.py`, `proxmox_exec.py`, `apply-vm-file.sh`) остаются в [`scripts/proxmox/`](../scripts/proxmox/).

## Быстрые команды

```powershell
python scripts/proxmox/check_vms.py
python start.py check_stack
curl.exe -fsS https://owncord-pundef.mooo.com/api/health
```

Деплой — см. [setup.md](setup.md).
