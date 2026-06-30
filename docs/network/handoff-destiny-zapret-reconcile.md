# Handoff: Destiny cabbage + reconcile zapret bypass

> **Для:** другой модели / оператора с **paul-mac**  
> **Репо:** `home-server`  
> **Роутер:** OpenWrt X3000T `192.168.1.1`  
> **Игра:** Destiny 2 на **pundef-pc** Wi‑Fi `192.168.1.208` (не paul-mac)

---

## 1. Суть проблемы

Destiny 2: **cabbage / weasel / anteater**; в данже не спавнятся враги, ивенты не регятся → disconnect / телепорт на спавн.

**Доказано логом** (`logs/destiny-net-watch/`): activity **TCP `:7500`** на **`172.97.56.x`** идёт на WAN через **zapret**, bypass не срабатывает.

**В manifest уже есть** `172.97.56.0/24` в `zapret_bypass.destiny_activity.dst`.

**Почему ломается несмотря на manifest:**

| Слой | Задумка | Факт |
|------|---------|------|
| Manifest | desired state | OK |
| `/opt/custom.bypass_devices.sh` | генерится из manifest | OK после upload |
| **nft runtime** | = manifest после apply | **НЕТ** — patch-mode hook, дубли, stale rules |
| validate | runtime = manifest | substring «есть /24» → ложный OK |
| watcher | observability | был сломан; потом stale manifest в long-running PID |

Hook был **`grep comment → skip insert`**, а не **`delete by comment → insert`**. При смене `DESTINY_NETS` старые nft-правила оставались.

---

## 2. Что мы делаем (цель ACT)

**Не «ещё один IP».** **Reconcile:** каждый `apply` с одним manifest → **идентичный nft runtime**, без хвостов.

- IP в manifest **не менять** (`172.97.56.0/24` уже там)
- Починить hook + validate + watcher
- Post-check **всей** сети, не только Destiny

---

## 3. Инварианты — НЕ ЛОМАТЬ

- **Discord voice** `104.29.154.185:19315` — **НЕ** добавлять `104.29.154.0/24` в Destiny bypass
- Destiny zapret bypass **только** для src `192.168.1.133` и `192.168.1.208`
- **paul-mac** `192.168.1.198` — workvpn only (`paul-mac kpb via workvpn`), **не** в `destiny_activity.src`
- **Не** `pbr restart` / `zapret restart` / `network reload` без крайней нужды
- **Не** catch-all `0.0.0.0/0` на lan для pundef-pc
- validate FAIL → **стоп + rollback**, не «играй и посмотрим»

Протокол: `.cursor/rules/router-network-change-protocol.mdc`  
Docs: `docs/network/gaming-pc-routes.md`, `docs/network/openwrt-overrides.md`

---

## 4. Работа с paul-mac

| | |
|---|---|
| Машина | paul-mac `192.168.1.198` |
| SSH роутер | `192.168.1.1` (lan/Wi‑Fi; **не** с srv Mercusys) |
| SSH key | `~/.ssh/openwrt_ax300t_nopass` |
| Apply/watcher | запускаются **с Mac**, смотрят на игровой ПК |

**Watcher client IP** (Destiny на pundef-pc):

```bash
export DESTINY_CLIENT_IP=192.168.1.208
py -3 scripts/openwrt/watch_destiny_sessions.py --client-ip 192.168.1.208 --interval 5
```

Если Destiny с **paul-mac** — bypass для `.198` **нет** в manifest; нужен отдельный ACT (вне scope).

---

## 5. Ключевые файлы

| Файл | Роль |
|------|------|
| `config/openwrt/overrides.json` | Source of truth |
| `scripts/openwrt/generate_overrides.py` | generate / `--check` |
| `scripts/openwrt/custom.bypass_devices.sh` | zapret hook → `/opt/zapret/` |
| `scripts/openwrt/apply_overrides.py` | validate → upload → apply → verify |
| `scripts/openwrt/validate_overrides.py` | drift + enforcement |
| `scripts/openwrt/check_gaming_pc_routes.py` | smoke Destiny/Discord/Steam |
| `scripts/openwrt/watch_destiny_sessions.py` | nf_conntrack ALERT log |
| `scripts/openwrt/analyze_destiny_log.py` | разбор после отвала |

**DESTINY_NETS в manifest (актуально):**

```text
57.129.90.115/32
172.97.56.0/24
155.133.0.0/16
162.254.0.0/16
205.196.0.0/16
205.209.0.0/16
```

Forbidden: `104.29.154.0/24`

---

## 6. ACT — пошагово

### 6.1 Hook reconcile (`custom.bypass_devices.sh`)

Для managed rules `*-destiny-ip`, `*-steam-sdr`:

1. `delete_nft_by_comment` (handle через `sed 's/.*# handle \([0-9]*\).*/\1/p'`)
2. `nft insert` с актуальным `$DESTINY_NETS`

**Убрать** `grep -q comment || insert` там, где меняется содержимое set.

Static bypass (227, 133-tcp, 214, srv) — не ломать.

### 6.2 Generate + full apply

```bash
cd /path/to/home-server

py -3 scripts/openwrt/generate_overrides.py --write
py -3 scripts/openwrt/generate_overrides.py --check
py -3 scripts/openwrt/validate_overrides.py          # read-only до apply
py -3 scripts/openwrt/apply_overrides.py --mode normal   # ПОЛНЫЙ pipeline, не ручной scp
```

**Не** partial upload hook без full apply.

### 6.3 Validate — усилить (`validate_overrides.py`)

- `zapret-ct-bypass-208-destiny-ip` / `133-destiny-ip`: **ровно 1** в postnat и prenat
- nft set **содержит** `172.97.56.0/24`
- forbidden `104.29.154.0/24` **отсутствует** в destiny bypass
- workvpn policies (paul-mac `.198`, pundef-pc `.133`, xiaomi `.214`) — OK

### 6.4 Watcher

В `watch_destiny_sessions.py`:

- reload manifest **каждый tick**
- `bypass_version` в log tick
- preflight: 0 entries → exit 2
- source: `/proc/net/nf_conntrack` (не `conntrack` CLI)

```bash
py -3 scripts/openwrt/watch_destiny_sessions.py --once --no-lock --client-ip 192.168.1.208
# фон:
py -3 scripts/openwrt/watch_destiny_sessions.py --client-ip 192.168.1.208 --interval 5
```

Логи: `logs/destiny-net-watch/` (`YYYY-MM-DD.jsonl`, `alerts.jsonl`).

### 6.5 Post-checks (обязательно)

```bash
py -3 scripts/openwrt/validate_overrides.py
py -3 scripts/openwrt/check_gaming_pc_routes.py
py -3 scripts/openwrt/watch_destiny_sessions.py --once --no-lock --client-ip 192.168.1.208
py -3 scripts/openwrt/analyze_destiny_log.py
```

**Критерии успеха:**

- Два подряд `apply_overrides.py --mode normal` → **одинаковый** nft для destiny comments
- `--once`: **0 ALERT** на `172.97.56.x:7500`
- validate + check_gaming_pc_routes: **OK** (Discord, workvpn, Steam, srv)

**Rollback:**

```bash
git restore config/openwrt/overrides.json scripts/openwrt/custom.bypass_devices.sh
py -3 scripts/openwrt/generate_overrides.py --write
py -3 scripts/openwrt/apply_overrides.py --mode normal
```

---

## 7. Если cabbage после reconcile

1. `py -3 scripts/openwrt/analyze_destiny_log.py` — новый IP/порт в ALERT
2. Если `:7500` **вне** `172.97.56.0/24` → расширить manifest (`172.97.0.0/16`), generate, apply, validate
3. TCP 7500 port bypass на any IP — **только** если лог покажет `:7500` на разных /16; риск шире

---

## 8. Чего НЕ делать

- Ручной `nft insert` / partial upload
- Добавлять `/32` по одному без reconcile
- `104.29.154.0/24` в Destiny bypass
- `pbr restart` / `zapret restart` «на всякий случай»
- validate OK только по substring
- Менять workvpn / podkop / srv «заодно»

---

## 9. Ожидание пользователя

```text
manifest → apply → runtime ИДЕНТИЧЕН следующему apply
```

Destiny stable. Discord, workvpn (paul-mac), phoneserver, srv — **не сломаны**. Лог — доказательство, не шум.

---

## 10. История (контекст)

- Watcher изначально использовал `conntrack -L` — **нет на роутере**; починено на `/proc/net/nf_conntrack`
- ALERT: `172.97.56.47:7500` → `/32` → anteater на `172.97.56.127:7500` → `/24` в manifest, runtime не reconcile
- Симптомы «мёртвый данж» = TCP :7500 через zapret до disconnect
