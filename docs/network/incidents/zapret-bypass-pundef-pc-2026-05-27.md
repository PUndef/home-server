# pundef-pc: zapret bypass + Cursor Remote SSH (192.168.1.133)

> **Статус:** incident (snapshot)  
> **Дата:** 2026-05-27

**Контекст:** Cursor Remote SSH с Mac (`paul-mac`, `192.168.1.198`) на Win-ПК (`pundef-pc`, `192.168.1.133`) через WSL2 в mirrored networking mode. WSL шерит namespace с Win, тот же IP `192.168.1.133`.

**Статус (2026-05-27):** ✅ zapret bypass, ✅ pbr `pundef-pc kpb via workvpn`, ✅ corp GitLab из WSL, ✅ Cloudflare CDN (nodesource), ✅ SSH `:22` на LAN IP. На Mac-стороне — установка Node 22 / pnpm / git config + ключ в WSL `authorized_keys`.

**Симптом (исходный):** `curl https://deb.nodesource.com/setup_22.x` в WSL висит 272+ сек — DNS резолвит Cloudflare CDN (`172.66.150.169`, `104.20.45.190`), TCP-handshake на 443 не проходит. Гипотеза: `zapret`/`nfqws` ломает первые пакеты TLS-handshake к Cloudflare при выходе через WAN.

**Решение (zapret):** per-device bypass для `192.168.1.133` (тот же паттерн, что для `phoneserver` `.227` и srv-сегмента `192.168.50.0/24`).

**Решение (corp):** pbr-policy `pundef-pc kpb via workvpn` на роутере (настроено с Mac-стороны) — WSL ходит в `*.kpb.lt` через `vpn-workvpn`, DNS `gitlab.kpb.lt` → `10.0.17.5`.

**Remote SSH:** Mac подключается к `<wsl-user>@192.168.1.133` (не `localhost`). WSL: `sshd` active, слушает `0.0.0.0:22`. `.wslconfig`: `networkingMode=mirrored`, `hostAddressLoopback=true`.

См. также: [router-openwrt-x3000t.md](../router-openwrt-x3000t.md) («Per-device bypass», «Корпоративные ресурсы», таблица pbr), исходник [custom.bypass_devices.sh](../../../scripts/openwrt/custom.bypass_devices.sh).

---

## Сделано (история)

Пункты, которые уже выполнены. Оставлены для истории; в текущем плане не повторять.


| Когда      | Что сделано                                                                                                                                     |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-05-27 | **DHCP-резервация** — `pundef-pc` MAC `9C:6B:00:8B:3F:18` → `192.168.1.133` (infinite) на роутере.                                              |
| 2026-05-27 | **pbr workvpn** — политика `pundef-pc kpb via workvpn` для `192.168.1.133` (на роутере, с Mac-стороны).                                         |
| 2026-05-27 | **Проверка corp + SSH** — из WSL: `gitlab.kpb.lt` → `10.0.17.5`, HTTPS 302; `deb.nodesource.com` HTTP 200; `sshd` на `:22`, TCP с LAN OK.       |
| 2026-05-27 | **Runtime bypass** — `nft insert` postnat/prenat для `192.168.1.133` (комментарии `zapret-bypass-pundef-pc` / `-pre`).                          |
| 2026-05-27 | **Permanent bypass** — правила добавлены в `scripts/openwrt/custom.bypass_devices.sh`, залиты на роутер `/opt/zapret/custom.bypass_devices.sh`. |
| 2026-05-27 | **Проверка после `zapret restart`** — правила `zapret-ct-bypass-133` / `-pre` на месте через `INIT_FW_POST_UP_HOOK`.                            |
| 2026-05-27 | **Smoke-test** — `Test-NetConnection deb.nodesource.com -Port 443` с Win: `TcpTestSucceeded = True` до и после restart.                         |


---

## Паттерн bypass в скрипте


| Устройство/сеть               | postnat                         | prenat                       | nft comment                     |
| ----------------------------- | ------------------------------- | ---------------------------- | ------------------------------- |
| `192.168.1.227` (phoneserver) | `ct original ip saddr … return` | `ct reply ip daddr … return` | `zapret-ct-bypass-227` / `-pre` |
| `192.168.1.133` (pundef-pc)   | то же                           | то же                        | `zapret-ct-bypass-133` / `-pre` |
| `192.168.50.0/24` (srv)       | то же с `/24`                   | то же с `/24`                | `zapret-ct-bypass-srv` / `-pre` |


Формат: idempotent `grep -q comment \|\| nft insert …`, shell-комментарий с описанием устройства, короткий nft comment. Host — один IP, subnet — CIDR `/24`. На роутере порядок в `postnat`: `srv` → `.133` → `.116` (порядок не критичен — все до WAN-правил zapret).

> Legacy: Android `.157`, phoneserver wlan `.116` — только в истории; phoneserver сейчас eth `.227`.

---

## Diff `custom.bypass_devices.sh`

```diff
+# pundef-pc (Win + WSL mirrored): Cloudflare CDN TLS handshake bypass. See zapret-bypass-pundef-pc-2026-05-27.
+nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-133 || \
+    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.133 return comment zapret-ct-bypass-133
+nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-133-pre || \
+    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.133 return comment zapret-ct-bypass-133-pre
```

---

## Output runtime nft insert

```
=== postnat top ===
table inet zapret {
	chain postnat {
		ct original ip saddr 192.168.1.133 return comment "zapret-bypass-pundef-pc"
		ct original ip saddr 192.168.50.0/24 return comment "zapret-ct-bypass-srv"
		ct original ip saddr 192.168.1.116 return comment "zapret-ct-bypass-116"
		...
=== prenat top ===
table inet zapret {
	chain prenat {
		...
		ct reply ip daddr 192.168.1.133 return comment "zapret-bypass-pundef-pc-pre"
		ct reply ip daddr 192.168.50.0/24 return comment "zapret-ct-bypass-srv-pre"
		ct reply ip daddr 192.168.1.116 return comment "zapret-ct-bypass-116-pre"
```

---

## Test-NetConnection `deb.nodesource.com:443`


| Когда                  | RemoteAddress    | TcpTestSucceeded |
| ---------------------- | ---------------- | ---------------- |
| До runtime bypass      | `104.20.45.190`  | **True**         |
| После `zapret restart` | `172.66.150.169` | **True**         |


Команда (PowerShell, без admin):

```powershell
Test-NetConnection -ComputerName deb.nodesource.com -Port 443 -WarningAction SilentlyContinue |
  Select-Object ComputerName, RemoteAddress, TcpTestSucceeded |
  Format-Table -AutoSize
```

---

## nft после `zapret restart`

```
=== postnat for 192.168.1.133 ===
		ct original ip saddr 192.168.1.133 return comment "zapret-ct-bypass-133"
=== prenat for 192.168.1.133 ===
		ct reply ip daddr 192.168.1.133 return comment "zapret-ct-bypass-133-pre"
```

Permanent bypass через `INIT_FW_POST_UP_HOOK` работает — правила пережили restart.

---

## Команды для повторного применения

Runtime (срочно, без restart):

```powershell
py -3 d:\repositories\home-server\scripts\openwrt\openwrt_exec.py "nft insert rule inet zapret postnat ct original ip saddr 192.168.1.133 return comment 'zapret-bypass-pundef-pc' && nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.133 return comment 'zapret-bypass-pundef-pc-pre'"
```

Upload permanent script:

```powershell
py -3 d:\repositories\home-server\scripts\openwrt\upload.py `
  d:\repositories\home-server\scripts\openwrt\custom.bypass_devices.sh `
  /opt/zapret/custom.bypass_devices.sh --chmod 755
```

Проверка после restart:

```powershell
py -3 d:\repositories\home-server\scripts\openwrt\openwrt_exec.py "/etc/init.d/zapret restart && sleep 2 && nft list chain inet zapret postnat | grep 192.168.1.133 && nft list chain inet zapret prenat | grep 192.168.1.133"
```

---

## Проверки (актуальные)

### Corp из WSL

```bash
getent hosts gitlab.kpb.lt          # 10.0.17.5
curl -I https://gitlab.kpb.lt       # HTTP 302 → /users/sign_in
ip route get 10.0.17.5              # via 192.168.1.1 src 192.168.1.133
```

### Cloudflare CDN (Node 22)

```bash
curl -I https://deb.nodesource.com/setup_22.x   # HTTP 200
```

### Remote SSH (с Mac или Win в LAN)

```powershell
Test-NetConnection 192.168.1.133 -Port 22     # TcpTestSucceeded = True
```

```bash
ssh <wsl-user>@192.168.1.133                   # ключ Mac в WSL ~/.ssh/authorized_keys
```

---

## Следующий шаг (Mac / WSL)

Установка Node 22 / pnpm / git config в WSL с Mac-стороны. После reboot роутера подождать 3–5 мин (стек `pbr`/`workvpn`/`zapret` сходится не мгновенно).