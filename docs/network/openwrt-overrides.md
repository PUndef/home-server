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
```

`--mode login` — deprecated rollback only (baseline steam_auth заменяет daily login workflow).

Единственная точка apply: `apply_overrides.py`. `apply_pundef_pc_routes.py` и `destiny_login_mode.py` — deprecated wrappers.

## Inventory Источников Состояния

| Источник | Runtime путь | Чем владеет | Restart side effects |
| --- | --- | --- | --- |
| `scripts/openwrt/apply_overrides.py` | — (PC-side) | validate → upload → apply baseline | делегирует в shell scripts ниже |
| `scripts/openwrt/apply-pundef-pc-routes.sh` | `/opt/apply-pundef-pc-routes.sh` | pbr/DNS: steam_auth (awg2) + steam_cdn (wan), Discord/Destiny/srv/Warframe | `dnsmasq restart`, `pbr restart` |
| `scripts/openwrt/custom.bypass_devices.sh` | `/opt/zapret/custom.bypass_devices.sh` | per-device zapret bypass, `DESTINY_NETS`, Steam SDR UDP | hook apply без service restart |
| `scripts/openwrt/destiny-login-mode.sh` | `/opt/destiny-login-mode.sh` | **deprecated** rollback login mode | `pbr restart`; flag `/etc/destiny-login-mode` |
| `scripts/openwrt/routing_status.py` | — (PC/LXC) | JSON snapshot для dashboard | read-only SSH |
| `scripts/openwrt/collect-routing-status.sh` | `/opt/collect-routing-status.sh` (optional) | cron → `status.json` + `history.jsonl` | none |
| `scripts/openwrt/destiny-normal-mode.sh` | `/opt/destiny-normal-mode.sh` | снимает login flag → canonical apply | через apply |
| `scripts/openwrt/99-vpn-stack` | `/etc/hotplug.d/iface/99-vpn-stack` | hotplug restore | stack restarts on ifup |
| `scripts/openwrt/pundef-pc-routes-watchdog.sh` | cron | drift check → apply | через apply |

## Generated Blocks

Manifest генерирует blocks в:

- `scripts/openwrt/apply-pundef-pc-routes.sh` — baseline + Discord/Destiny domain lists
- `scripts/openwrt/custom.bypass_devices.sh` — `DESTINY_NETS`, Steam SDR bypass constants
- `scripts/openwrt/destiny-login-mode.sh` — login flag path, policy name templates, client IPs
- `scripts/openwrt/check_gaming_pc_routes.py` — expected policies, DNS hosts, zapret nets, steam auth/CDN route tests
- `scripts/openwrt/routing_status.py` — same expectations as JSON for dashboard

Правило для агентов: не менять generated blocks руками. Сначала manifest → `generate_overrides.py --write --check` → ACT через `apply_overrides.py`.

## Observability

Dashboard: `http://network.home/` или `https://apps-pundef.mooo.com/network-routing/`

Cron на **gaming PC** (LXC srv не имеет SSH к роутеру):

```powershell
.\scripts\openwrt\publish-routing-status.ps1 -InstallTask
```

Пишет `/srv/static-sites/network-routing/status.json` + `history.jsonl` на LXC каждые 3 мин.

`destiny_modes` в manifest — **deprecated** (legacy rollback doc). Baseline `steam_auth` + static IP заменяет login flag workflow.

## Read-Only Проверки

`validate_overrides.py` проверяет:

- локальные scripts содержат значения из manifest (baseline steam_auth/steam_cdn + Discord/Destiny + zapret);
- live router: Discord/Destiny policies, split Steam baseline, auth IP → awg2, CDN → wan;
- legacy login flag / `pundef-pc steam via wan` / `(destiny login)` policies absent;
- repo vs `/opt` sha256 для apply/zapret/login/normal scripts;
- workvpn, Discord nftset, zapret invariants, cron watchdogs.

## Restart Политика

- `apply_overrides.py` отказывает apply без `--force-live-session`, если на `.208` активен Discord/Destiny UDP.
- `pbr restart` только когда менялись pbr/DNS sections.
- zapret hook apply предпочтительнее `zapret restart` для точечных nft rules.

## Legacy scripts (deprecated)

Не использовать как primary deploy path. Все gaming-pc routing changes — через manifest + `apply_overrides.py`.

| Script | Superseded by |
| --- | --- |
| `apply_pundef_pc_routes.py` | `apply_overrides.py --mode normal` |
| `destiny_login_mode.py` | `apply_overrides.py --mode login\|normal` |
| `switch_steam_route.py` / `switch-steam-route.sh` | `apply_overrides.py --mode normal` |
| `enable-steam-wan.sh` / `rollback-steam-wan.sh` | manifest `pbr_baseline.steam_cdn` + apply |
| `enable_steam_wan_safe.py` | `apply_overrides.py --mode normal` |
| `check_steam_route.py` | `check_gaming_pc_routes.py` |
| `enable-discord-gaming-pc.sh` | manifest `pbr_overrides.discord` |
| `enable-nexus-wan.sh` | manifest `pbr_baseline.nexus` |
| `enable-warframe-awg2.sh` | manifest `pbr_baseline.warframe` |
| `expand-pundef-pc-pbr.sh` | `apply-pundef-pc-routes.sh` (generated) |
| `lib-ddg-wan-only.sh` | manifest `pbr_baseline.lib_ddg` |

**Green check = Destiny login path OK** после split baseline: `check_gaming_pc_routes.py` и dashboard проверяют auth IP `199.165.136.100` → awg2 и CDN → wan.

## См. Также

- [`gaming-pc-routes.md`](gaming-pc-routes.md)
- [`router-openwrt-x3000t.md`](router-openwrt-x3000t.md)
- [`router-resilience.md`](router-resilience.md)
