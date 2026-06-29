# Единый контур OpenWrt overrides

> **Статус:** manifest-first apply  
> **Последняя проверка:** 2026-06-30

Этот документ описывает пользовательский слой поверх OpenWrt X3000T: `pundef-pc`, Discord/Destiny, `workvpn` clients, per-device zapret bypass, cron/hotplug и live drift checks. Dynamic lists `podkop`/`sing-box` и внутренние списки `zapret` не переносятся в manifest и остаются владельцами своих данных.

Source of truth для кастомных правил:

```text
config/openwrt/overrides.json
```

## Workflow

1. Изменить `config/openwrt/overrides.json`.
2. Сгенерировать/проверить embedded blocks:

```powershell
py -3 scripts/openwrt/generate_overrides.py --write
py -3 scripts/openwrt/generate_overrides.py --check
```

3. Проверить live drift без изменений на роутере:

```powershell
py -3 scripts/openwrt/validate_overrides.py
py -3 scripts/openwrt/apply_overrides.py --check-only
```

4. Только после отдельного ACT применить:

```powershell
py -3 scripts/openwrt/apply_overrides.py --mode normal
py -3 scripts/openwrt/apply_overrides.py --mode login
py -3 scripts/openwrt/apply_overrides.py --mode login --full
```

Единственная точка apply: `apply_overrides.py`. `apply_pundef_pc_routes.py` и `destiny_login_mode.py` — deprecated wrappers.

## Inventory Источников Состояния

| Источник | Runtime путь | Чем владеет | Restart side effects |
| --- | --- | --- | --- |
| `scripts/openwrt/apply_overrides.py` | — (PC-side) | validate → upload → apply normal/login | делегирует в shell scripts ниже |
| `scripts/openwrt/apply-pundef-pc-routes.sh` | `/opt/apply-pundef-pc-routes.sh` | pbr/DNS policies для `pundef-pc`: Steam/Nexus/RU-local/Discord/Destiny/srv default/Warframe | `dnsmasq restart`, `pbr restart` |
| `scripts/openwrt/custom.bypass_devices.sh` | `/opt/zapret/custom.bypass_devices.sh` | per-device zapret bypass, `DESTINY_NETS`, Steam SDR UDP | hook apply без service restart |
| `scripts/openwrt/destiny-login-mode.sh` | `/opt/destiny-login-mode.sh` | temporary login mode из `destiny_modes` в manifest | `pbr restart`; flag `/etc/destiny-login-mode` |
| `scripts/openwrt/destiny-normal-mode.sh` | `/opt/destiny-normal-mode.sh` | снимает login flag → canonical apply | через apply |
| `scripts/openwrt/99-vpn-stack` | `/etc/hotplug.d/iface/99-vpn-stack` | hotplug restore | stack restarts on ifup |
| `scripts/openwrt/pundef-pc-routes-watchdog.sh` | cron | drift check → apply | через apply |

## Generated Blocks

Manifest генерирует blocks в:

- `scripts/openwrt/apply-pundef-pc-routes.sh` — baseline + Discord/Destiny domain lists
- `scripts/openwrt/custom.bypass_devices.sh` — `DESTINY_NETS`, Steam SDR bypass constants
- `scripts/openwrt/destiny-login-mode.sh` — login flag path, policy name templates, client IPs
- `scripts/openwrt/check_gaming_pc_routes.py` — expected policies, DNS hosts, zapret nets

Правило для агентов: не менять generated blocks руками. Сначала manifest → `generate_overrides.py --write --check` → ACT через `apply_overrides.py`.

## Read-Only Проверки

`validate_overrides.py` проверяет:

- локальные scripts содержат значения из manifest (baseline + Discord/Destiny + zapret);
- live router: Discord/Destiny policies, baseline Steam/Nexus, destiny login/normal state;
- stuck login flag / missing `pundef-pc steam via wan`;
- repo vs `/opt` sha256 для apply/zapret/login/normal scripts;
- workvpn, Discord nftset, zapret invariants, cron watchdogs.

## Restart Политика

- `apply_overrides.py` отказывает apply без `--force-live-session`, если на `.208` активен Discord/Destiny UDP.
- `pbr restart` только когда менялись pbr/DNS sections.
- zapret hook apply предпочтительнее `zapret restart` для точечных nft rules.

## См. Также

- [`gaming-pc-routes.md`](gaming-pc-routes.md)
- [`router-openwrt-x3000t.md`](router-openwrt-x3000t.md)
- [`router-resilience.md`](router-resilience.md)
