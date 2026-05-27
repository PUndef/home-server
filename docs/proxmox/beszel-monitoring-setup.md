# Beszel — мониторинг всей инфраструктуры

> **Статус:** completed setup  
> **Последняя проверка:** 2026-05-28

Лёгкий «единый дашборд» по всем узлам: Proxmox-host, ВМ/LXC, phoneserver, VPS. Hub живёт в существующем LXC `static-sites` (102), наружу прокидывается через тот же Caddy + Apache по path-based схеме (`https://apps-pundef.mooo.com/beszel/`). Опенсорс, без облака — [henrygd/beszel](https://github.com/henrygd/beszel).

Делай по одному шагу. После каждого выполни блок **Проверить** и подтверди, прежде чем переходить дальше.

---

## Схема

```text
                                       Internet
                                          |
                                          v
                            X3000T (DNAT 80/443 -> 192.168.50.34)
                                          |
                                          v
                       nextcloud-vm (101) Apache vhost
                       apps-pundef.mooo.com
                          |  ProxyPass /  ->  http://192.168.50.35/
                          v
                   static-sites LXC (102), 192.168.50.35
                   +----------------------------------------+
                   |  Caddy :80                             |
                   |    /requiem/* -> /srv/static-sites/... |
                   |    /beszel/*  -> 127.0.0.1:8090 (NEW)  |
                   |                                        |
                   |  beszel hub on 127.0.0.1:8090 (NEW)    |
                   |  beszel-agent  on :45876               |
                   +----------------------------------------+
                                  ^ ^ ^ ^ ^ ^
                                  |  SSH-pull metrics
   +------------+-----------+-----+-----+-------+--------------+
   |            |           |           |       |              |
 pundef    nextcloud-vm   static-      phone-   fin-VPS    sweet-VPS
 (Proxmox)  (101, Debian) sites self  server   (Ubuntu)   (Ubuntu)
            +Docker meta              (pmOS,
                                       OpenRC)
```

Ключевые свойства:

- **Hub** — это веб-морда + хранилище (PocketBase + SQLite). Не SSH-сервер; он сам **подключается** к агентам.
- **Agent** — на каждом наблюдаемом узле, слушает порт `45876` только в LAN, авторизация по public-key Hub.
- **Edge без новых cert/DDNS:** переиспользуем уже работающий `apps-pundef.mooo.com` + LE-cert на `nextcloud-vm`.

---

## Параметры

| Параметр | Значение |
| -------- | -------- |
| Hub LXC | `static-sites` (VMID 102), `192.168.50.35` |
| Hub URL внутри LAN | `http://requiem.home/beszel/` или `http://192.168.50.35/beszel/` |
| Hub URL снаружи | `https://apps-pundef.mooo.com/beszel/` |
| Hub listen | `127.0.0.1:8090` (только локально, Caddy проксирует) |
| Agent listen | `0.0.0.0:45876/tcp` на каждом узле |
| Установка Hub | нативный binary + systemd unit (без Docker) |
| Установка Agent | нативный binary + systemd unit (на phoneserver — OpenRC) |
| Данные Hub | `/opt/beszel/` (бинарь) + `/var/lib/beszel/` (SQLite) |

**Узлы под наблюдением** (стартовый набор; имя в Beszel UI — слева):

| Имя в Beszel UI | Хост (`uname -n`) | IP / адрес | Init |
| --------------- | ----------------- | ---------- | ---- |
| `Proxmox` | `pundef` (Proxmox host) | `192.168.50.9` | systemd |
| `nextcloud-vm` | `nextcloud-vm` (VM 101) | `192.168.50.34` | systemd |
| `static-sites` | `static-sites` (LXC 102, self-monitor) | `127.0.0.1` | systemd |
| `phoneserver` | `phoneserver` (Redmi/pmOS) | `192.168.1.116` (Wi-Fi/LAN) | OpenRC |
| `fin-sweet-home-vps` | `fin-sweet-home-vps` | `89.44.76.52` | systemd |
| `sweet-home-vps` | `customer55224` (hostname) | `45.154.35.222` | systemd |

**Не подключаем на старте:**

- `haos17.0` (HA OS) — нет нативного способа поставить агент; проксмоксовский host всё равно даст метрики ВМ.
- OpenWrt X3000T — отдельный квест с procd-init и местом на rootfs; рассмотрим позже.

---

## План шагов

| Шаг | Что делаем | Статус |
| --- | ---------- | ------ |
| 1 | Поднять RAM LXC `static-sites` до 1 ГБ | ✅ |
| 2 | Установить Beszel Hub в LXC 102 (binary + systemd) | ✅ |
| 3 | Включить Hub в Caddy (path-based `/beszel/`) и проверить локально | ✅ |
| 4 | Прокинуть наружу через Apache на nextcloud-vm и проверить HTTPS | ✅ |
| 4b | Апгрейдить Apache vhost `apps-pundef.mooo.com` для WebSocket (`mod_proxy_wstunnel`) | ✅ |
| 5 | Создать в Hub admin-пользователя и забрать `KEY` (хаб public-key) | ✅ |
| 6 | Установить агент на сам LXC 102 (self-monitor) | ✅ |
| 7 | Установить агент на Proxmox host (`pundef`, имя в UI: `Proxmox`) | ✅ |
| 8 | Установить агент на `nextcloud-vm` (с docker-метриками) | ✅ |
| 9 | Установить агент на `phoneserver` (OpenRC init) | ✅ |
| 10a | SSH-ключ для VPS + helpers в `scripts/vps/` | ✅ |
| 10b | Установить агенты на оба VPS | ✅ |

> Детали Шагов 5-10 будут расписаны по мере выполнения, чтобы не уходить далеко вперёд от реальных проверок.

---

## Шаг 1. Поднять RAM LXC `static-sites` до 1 ГБ — ✅ сделано

**Цель.** Сейчас в LXC 102 — `512 МБ RAM + 256 МБ swap`. После добавления Beszel Hub + локального агента + Caddy под нагрузкой это станет впритык. Поднимаем RAM до 1024 МБ (swap оставляем 256), это обеспечит спокойный запас и место под SQLite WAL.

Запас на хосте есть: по [`hardware-and-env.md`](../overview/hardware-and-env.md) свободно ~2 ГБ, забираем из них 512 МБ.

**Сделать.**

С Windows через helper `scripts/proxmox/proxmox_exec.py` (одна команда на хосте по SSH):

```powershell
python scripts/proxmox/proxmox_exec.py "pct set 102 --memory 1024"
```

> Важно: использовать **полное имя** опции `--memory`, не короткое `-m`. PVE отвергает `-m` как неоднозначное (конфликт с `mp0..mp255`), отдавая `Option m is ambiguous (memory, mp0, mp1, ...)`.

Команда применяется **на лету**, перезагрузка LXC не требуется (cgroup memory.max обновляется сразу).

**Проверить.**

1. Конфиг LXC изменился:

```powershell
python scripts/proxmox/proxmox_exec.py "pct config 102 | grep -E '^(memory|swap):'"
```

Ожидаемо:

```text
memory: 1024
swap: 256
```

2. Внутри LXC видны новые лимиты:

```powershell
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- free -m"
```

Ожидаемо: в строке `Mem:` колонка `total` ≈ `1000` (не `~500`, как было).

3. Caddy и сайт `requiem` остались живы (мы ничего не рестартовали, но проверим явно):

```powershell
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- systemctl is-active caddy"
curl.exe -fsS -o NUL -w "HTTP %{http_code}`n" http://192.168.50.35/requiem/
```

Ожидаемо: `active`, `HTTP 200`.

---

---

## Шаг 2. Установить Beszel Hub в LXC 102 — ✅ сделано

**Цель.** Поставить hub как нативный systemd-сервис без Docker (LXC unprivileged + nesting=1 принципиально позволяет, но Docker для hub'а — лишняя прослойка). Бинарь — Go, статически слинкованный, ~12 МБ; данные — SQLite (PocketBase) в `/opt/beszel/pb_data/`.

**Установочный скрипт.** Логика зафиксирована в [`scripts/proxmox/beszel-hub-install.sh`](scripts/proxmox/beszel-hub-install.sh):

- создаёт системного юзера `beszel` (без shell, без home);
- кладёт каталоги `/opt/beszel/` и `/opt/beszel/pb_data/` под этим юзером;
- если в `/tmp/beszel_linux_amd64.tar.gz` есть pre-staged tarball — берёт его, иначе качает с GitHub;
- ставит бинарь в `/opt/beszel/beszel`;
- генерирует unit `/etc/systemd/system/beszel.service` с `User=beszel`, `WorkingDirectory=/opt/beszel`, `Environment="APP_URL=…"`, `ExecStart=… serve --http "127.0.0.1:8090"`, лёгким hardening (`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=full`, `ProtectHome`, `ReadWritePaths=/opt/beszel`);
- `systemctl enable --now beszel`, ждёт до 15 секунд порт `:8090`.

Скрипт идемпотентен: повторный запуск обновит бинарь, не сломав данные.

> **Важный обходной путь: github недоступен из `srv`-сегмента.**
> Из LXC 102 (`192.168.50.35`) DNS-резолв github идёт через роутерный dnsmasq → подкоп → fake-IP уходит в pbr policy `awg1` (AI/Cursor). Из `srv` форвард в `awg1` намеренно закрыт (см. [`hardware-and-env.md`](../overview/hardware-and-env.md) → «Изоляция серверного сегмента»). Симптом: `curl -v https://github.com` падает за 2 мс с `Connection refused`. Чинить роутер или заводить отдельный bypass для `srv→github` не стали — вместо этого скрипт умеет работать в режиме «tarball уже подложен в `/tmp/`».

**Сделать.**

1. Локально на Windows скачать tarball Beszel Hub (там, где github работает):

```powershell
$tmp = Join-Path $env:TEMP "beszel_linux_amd64.tar.gz"
curl.exe -fsSL -o $tmp "https://github.com/henrygd/beszel/releases/download/v0.18.7/beszel_linux_amd64.tar.gz"
```

2. Залить tarball и установочный скрипт на Proxmox-хост, потом в LXC 102:

```powershell
$tmp = Join-Path $env:TEMP "beszel_linux_amd64.tar.gz"
python scripts/proxmox/upload.py $tmp /tmp/beszel_linux_amd64.tar.gz
python scripts/proxmox/upload.py scripts/proxmox/beszel-hub-install.sh /tmp/beszel-hub-install.sh --chmod 755

python scripts/proxmox/proxmox_exec.py "pct push 102 /tmp/beszel_linux_amd64.tar.gz /tmp/beszel_linux_amd64.tar.gz"
python scripts/proxmox/proxmox_exec.py "pct push 102 /tmp/beszel-hub-install.sh /tmp/beszel-hub-install.sh --perms 0755"
```

3. Запустить установщик внутри LXC 102:

```powershell
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- bash /tmp/beszel-hub-install.sh"
```

Ожидаемый вывод:

```text
[beszel-hub-install] starting installation (v0.18.7)
[beszel-hub-install] APP_URL=https://apps-pundef.mooo.com/beszel
[beszel-hub-install] using pre-staged tarball: /tmp/beszel_linux_amd64.tar.gz
[beszel-hub-install] installed binary at /opt/beszel/beszel
[beszel-hub-install] beszel listening on 127.0.0.1:8090 (after Ns)
```

**Проверить.**

```powershell
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- systemctl is-active beszel"
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- ss -ltn"
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- curl -fsS http://127.0.0.1:8090/api/health"
```

Ожидаемо: `active`, в `ss -ltn` есть строка `127.0.0.1:8090`, `/api/health` отдаёт `{"message":"API is healthy.","code":200,"data":{}}`.

После проверки можно почистить staging-файлы:

```powershell
python scripts/proxmox/proxmox_exec.py "rm -f /tmp/beszel_linux_amd64.tar.gz /tmp/beszel-hub-install.sh"
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- rm -f /tmp/beszel_linux_amd64.tar.gz /tmp/beszel-hub-install.sh"
```

---

## Шаг 3. Включить Hub в Caddy (`/beszel/*`) и проверить локально — ✅ сделано

**Цель.** Дать Beszel UI выйти из LXC через тот же Caddy, рядом с `requiem`, под path-префиксом `/beszel/`. Hub поддерживает subpath нативно: путь-часть из `APP_URL` автоматически становится `BASE_PATH` для фронта (виден внутри `index.html` как `globalThis.BESZEL.BASE_PATH`), и SPA правильно генерирует ссылки на `/beszel/assets/*`, `/beszel/static/*`, `/beszel/api/*`.

**Caddyfile.** Конфигурация теперь живёт в репозитории — [`static-sites/Caddyfile`](../../static-sites/Caddyfile) (раньше существовала только инлайном внутри `static-sites-lxc.md`). К общему vhost-блоку добавлены:

- `request_body { max_size 10MB }` — запас под будущие POST-запросы хаба/агентов;
- `redir /beszel /beszel/ 301` — нормализация URL без trailing slash;
- `handle_path /beszel/* { reverse_proxy 127.0.0.1:8090 { transport http { read_timeout 360s } } }` — strip префикса + длинный read_timeout под WebSocket UI и SSH к агентам.

**Сделать.**

```powershell
python scripts/proxmox/upload.py static-sites/Caddyfile /tmp/Caddyfile
python scripts/proxmox/proxmox_exec.py "pct push 102 /tmp/Caddyfile /etc/caddy/Caddyfile"
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile"
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- systemctl reload caddy"
```

**Проверить.**

С Windows из LAN:

```powershell
curl.exe -fsS -o NUL -w "/beszel/                                  HTTP %{http_code}, %{size_download}b`n" http://192.168.50.35/beszel/
curl.exe -fsS -o NUL -w "/beszel/api/health                        HTTP %{http_code}, %{size_download}b`n" http://192.168.50.35/beszel/api/health
curl.exe -fsS -o NUL -w "/beszel/static/icon.svg                   HTTP %{http_code}, %{size_download}b`n" http://192.168.50.35/beszel/static/icon.svg
curl.exe -fsS -o NUL -w "/beszel/assets/index-Dq5BcLwo.js         HTTP %{http_code}, %{size_download}b`n" http://192.168.50.35/beszel/assets/index-Dq5BcLwo.js
curl.exe -fsS -o NUL -w "/requiem/ (regression check)              HTTP %{http_code}, %{size_download}b`n" http://192.168.50.35/requiem/
```

Ожидаемо: все `HTTP 200` и ненулевой `size_download`. В частности у `/beszel/` — ровно `1307b` (HTML с `BASE_PATH: "/beszel/"`), у `/beszel/assets/index-….js` — около 470-500 КБ.

> **Важно про hostname.** `vhost`-блок в Caddyfile навешан на `apps-pundef.mooo.com, 192.168.50.35, localhost`. При запросе с `Host: 127.0.0.1` Caddy не находит совпадение, попадает на default-реакцию и возвращает `200 OK / Content-Length: 0` (пустое тело). Это сбивает с толку при отладке. **Тестировать только через `localhost`, `192.168.50.35` или `apps-pundef.mooo.com`** — не через `127.0.0.1`.

---

## Шаг 4. Внешний HTTPS через Apache на nextcloud-vm — ✅ сделано (наследовано)

**Цель.** Доступ снаружи как `https://apps-pundef.mooo.com/beszel/`.

**Что было сделано.** Ничего нового — задача автоматически решена существующей конфигурацией из `static-sites-lxc.md` (Шаги 8-11). Apache vhost на `nextcloud-vm` (`192.168.50.34`) уже:

- слушает `:443` для `apps-pundef.mooo.com`;
- использует Let's Encrypt cert (`/etc/letsencrypt/live/apps-pundef.mooo.com/`), автопродление через тот же `certbot.timer`;
- проксирует **всё** (`ProxyPass / http://192.168.50.35/`) на Caddy в LXC 102;
- внутри Caddy `/beszel/*` уже обрабатывается (Шаг 3).

DDNS, FreeDNS-запись, split-horizon (`/apps-pundef.mooo.com/192.168.50.34` в dnsmasq на OpenWrt) — всё унаследовано.

**Проверить.**

```powershell
curl.exe -sS -o NUL -w "https://apps-pundef.mooo.com/beszel/                  HTTP %{http_code}, %{size_download}b, cert_verify=%{ssl_verify_result}`n" https://apps-pundef.mooo.com/beszel/
curl.exe -sS -o NUL -w "https://apps-pundef.mooo.com/beszel/api/health        HTTP %{http_code}, %{size_download}b`n" https://apps-pundef.mooo.com/beszel/api/health
curl.exe -sS -o NUL -w "https://apps-pundef.mooo.com/beszel/assets/index.js   HTTP %{http_code}, %{size_download}b`n" https://apps-pundef.mooo.com/beszel/assets/index-Dq5BcLwo.js
curl.exe -sS -o NUL -w "https://apps-pundef.mooo.com/requiem/ (regression)    HTTP %{http_code}, %{size_download}b`n" https://apps-pundef.mooo.com/requiem/
```

Ожидаемо: все `HTTP 200`, `cert_verify=0` на корне, requiem не сломан.

> **WebSocket из LAN.** Apache vhost для `apps-pundef.mooo.com` собран без явного WS-rewrite (это обычный `ProxyPass /`). Mod_proxy_http в Apache 2.4.47+ умеет проксировать WebSocket внутри обычного HTTP-канала через `Upgrade`-механику, но если Beszel-агенты при использовании universal-token или UI realtime-обновления начнут отваливаться извне — посмотреть в ту сторону. Локально (по `http://192.168.50.35/beszel/`) WS работает напрямую через Caddy без вопросов.

---

## Шаг 4b. Apache vhost: WebSocket-апгрейд — ✅ сделано

**Цель.** Beszel-агенты держат WS-канал к хабу для heartbeat/realtime; UI Beszel — тоже WS для live-обновлений. Базовый Apache `ProxyPass / http://192.168.50.35/` корректно проксирует HTTP, но не апгрейдит `Connection: Upgrade` → агент ловил `WebSocket connection failed err="unexpected status code: 400"`.

**Что добавлено.** Новая версия vhost-а зафиксирована в репозитории — [`nextcloud-vm/apache/apps-pundef.conf`](nextcloud-vm/apache/apps-pundef.conf). К `:443`-блоку добавлен RewriteRule, который перехватывает upgrade-запросы и проксирует их как `ws://`:

```apache
RewriteEngine On
RewriteCond %{HTTP:Connection} Upgrade [NC]
RewriteCond %{HTTP:Upgrade} websocket [NC]
RewriteRule ^/(.*) "ws://192.168.50.35/$1" [P,L]
```

Обычный HTTP-трафик идёт через `ProxyPass / http://192.168.50.35/` ниже.

**Helper.** Файлы в гостевые ВМ заливаем без SSH через QEMU guest agent. Helper [`scripts/proxmox/apply-vm-file.sh`](scripts/proxmox/apply-vm-file.sh): берёт локальный файл с Proxmox-хоста, base64-кодирует, через `qm guest exec --timeout 30 -- bash -c "printf '%s' '<b64>' | base64 -d > <path>"` пишет в гостевой fs, опционально выполняет post-cmd.

**Сделать.**

```powershell
python scripts/proxmox/upload.py scripts/proxmox/apply-vm-file.sh /tmp/apply-vm-file.sh --chmod 755
python scripts/proxmox/upload.py nextcloud-vm/apache/apps-pundef.conf /tmp/apps-pundef.conf

# backup существующего конфига внутри VM
python scripts/proxmox/proxmox_exec.py "qm guest exec 101 --timeout 5 -- bash -lc 'cp -a /etc/apache2/sites-available/apps-pundef.conf /etc/apache2/sites-available/apps-pundef.conf.bak.$(date +%Y%m%d)'"

# применить новый vhost + включить модули + configtest
python scripts/proxmox/proxmox_exec.py "/tmp/apply-vm-file.sh 101 /tmp/apps-pundef.conf /etc/apache2/sites-available/apps-pundef.conf 'a2enmod -q proxy_wstunnel rewrite headers; apache2ctl configtest'"

# reload (configtest должен был отдать Syntax OK, иначе не reloadить)
python scripts/proxmox/proxmox_exec.py "qm guest exec 101 --timeout 15 -- systemctl reload apache2"
```

**Проверить.**

```powershell
curl.exe -sS -o NUL -w "https      HTTP %{http_code}, %{size_download}b`n" https://apps-pundef.mooo.com/beszel/
curl.exe -sS -o NUL -w "regression HTTP %{http_code}, %{size_download}b`n" https://apps-pundef.mooo.com/requiem/

# WS upgrade probe (Apache теперь должен пропускать Connection: Upgrade)
curl.exe -sS -o NUL -w "WS via apache HTTP %{http_code}`n" `
    -H "Connection: Upgrade" -H "Upgrade: websocket" `
    -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" `
    --max-time 5 https://apps-pundef.mooo.com/beszel/
```

> Простой curl-WS-проб может вернуть `200` (Beszel hub отдаёт HTML для unknown WS-endpoint), а не каноничные `101 Switching Protocols`. Это **не** диагностика — реальная диагностика делается по логам агента (см. Шаг 6, `journalctl -u beszel-agent`): пропали ли `WebSocket connection failed` варнинги.

---

## Шаг 5. Создать в Hub admin + per-system токены — ✅ сделано

**Цель.** Зарегистрировать первого пользователя в Beszel (он автоматически становится superuser) и понять модель аутентификации агентов в **0.18.x**: гибрид WS + SSH.

- **`KEY`** — public SSH-key хаба, генерируется один раз при первом запуске hub'а. Один на весь хаб, не меняется. Видится в `Add System` диалоге как `Public Key`.
- **`TOKEN`** — UUID, отдельный для каждой системы. Создаётся автоматически когда оператор делает `+ Add System` в UI (поля: Name, Host, Port). Используется агентом при первичной WS-регистрации к хабу.
- **`HUB_URL`** — полный URL хаба, включая subpath. У нас: `https://apps-pundef.mooo.com/beszel`.

Агент с этими тремя env-переменными:

1. подключается к `HUB_URL` по WS, авторизуется по `TOKEN`, регистрируется как «такая-то система»;
2. слушает `:45876` для входящих SSH-соединений от хаба, авторизованных public-key'ом `KEY`;
3. метрики хаб тянет по SSH (pull-модель), heartbeat и команды UI идут по WS.

**Сделать.**

1. Открыть [https://apps-pundef.mooo.com/beszel/](https://apps-pundef.mooo.com/beszel/), пройти setup-wizard: email + пароль для superuser.
2. На главной кликнуть `+ Add System`. Заполнить поля для **первой** системы (LXC 102 self-monitor):
   - Name: `static-sites`
   - Host: `127.0.0.1`
   - Port: `45876`
3. После сохранения откроется модалка с готовой `docker run …` командой. Скопировать оттуда `KEY=…`, `TOKEN=…`, `HUB_URL=…` — это всё что нужно для нативной (не-Docker) установки агента, которую мы делаем дальше в Шаге 6.

**Settings → Tokens & Fingerprints** в UI — это место, где видны все per-system tokens для всех уже-добавленных систем. Universal token (toggle сверху) — оставить **выключенным**, идём по per-system модели.

**Проверить.**

- Логин в UI работает.
- В UI на главной появилась запись `static-sites` (пока offline, т.к. агент ещё не запущен — это нормально, агента ставим в Шаге 6).
- В скопированной `docker run`-команде есть все три env-переменных.

---

## Шаг 6. Агент в LXC 102 (self-monitor) — ✅ сделано

**Цель.** Поставить нативный (не-Docker) Beszel-агент в LXC 102, чтобы хаб видел сам себя как «систему».

**Установочный скрипт.** Универсальный для всех Linux-узлов с systemd: [`scripts/proxmox/beszel-agent-install.sh`](scripts/proxmox/beszel-agent-install.sh).

- читает `/tmp/beszel-agent.env` (если есть) или env-окружение для `KEY` / `TOKEN` / `HUB_URL` / `LISTEN`;
- создаёт системного пользователя `beszel-agent`;
- кладёт бинарь в `/opt/beszel-agent/beszel-agent`, данные — `/var/lib/beszel-agent/`;
- пишет env-файл `/etc/default/beszel-agent` (mode `0640`, owner `root:beszel-agent`) — TOKEN секрет, права жёсткие;
- генерирует unit `/etc/systemd/system/beszel-agent.service` с `EnvironmentFile=/etc/default/beszel-agent`, `ExecStart=/opt/beszel-agent/beszel-agent`, лёгким hardening;
- `systemctl enable --now beszel-agent`, ждёт открытия порта (по умолчанию `:45876`);
- **после успеха удаляет** `/tmp/beszel-agent.env` (там TOKEN секрет, не должен валяться).

Скрипт идемпотентен: повторный запуск обновляет бинарь и env-файл.

**Tarball агента.** Из тех же github-релизов; для современных Debian/Ubuntu/PVE-систем берём `_glibc`-вариант (он чаще обновляется и решает проблемы с DNS-резолвом):

```text
beszel-agent_linux_amd64_glibc.tar.gz   - amd64, glibc-системы (Debian, Ubuntu, PVE)
beszel-agent_linux_amd64.tar.gz         - amd64, статический pure-Go (musl и т.п.)
beszel-agent_linux_arm64.tar.gz         - arm64, для phoneserver (Шаг 9)
```

Качаем локально на Windows (github из `srv` всё ещё блокирован, см. Шаг 2).

**Сделать.**

1. Скачать tarball локально:

```powershell
$tmp = Join-Path $env:TEMP "beszel-agent_linux_amd64_glibc.tar.gz"
curl.exe -fsSL -o $tmp "https://github.com/henrygd/beszel/releases/download/v0.18.7/beszel-agent_linux_amd64_glibc.tar.gz"
```

2. Подготовить env-файл с секретами **в `%TEMP%`, не в репо**:

```powershell
$envContent = @"
KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9I03DG8DciIm5AklgrMF1GMQoIlYibQxKWbzzdFv3W"
TOKEN=<token-из-Add-System-для-static-sites>
HUB_URL=https://apps-pundef.mooo.com/beszel
LISTEN=45876
"@
$envFile = Join-Path $env:TEMP "beszel-agent.env"
[System.IO.File]::WriteAllText($envFile, $envContent.Replace("`r`n","`n"))
```

3. Залить tarball, install-скрипт и env-файл на Proxmox-host, потом в LXC 102:

```powershell
$tar = Join-Path $env:TEMP "beszel-agent_linux_amd64_glibc.tar.gz"
$envFile = Join-Path $env:TEMP "beszel-agent.env"

python scripts/proxmox/upload.py $tar /tmp/beszel-agent_linux_amd64_glibc.tar.gz
python scripts/proxmox/upload.py scripts/proxmox/beszel-agent-install.sh /tmp/beszel-agent-install.sh --chmod 755
python scripts/proxmox/upload.py $envFile /tmp/beszel-agent.env --chmod 600

python scripts/proxmox/proxmox_exec.py "pct push 102 /tmp/beszel-agent_linux_amd64_glibc.tar.gz /tmp/beszel-agent_linux_amd64_glibc.tar.gz"
python scripts/proxmox/proxmox_exec.py "pct push 102 /tmp/beszel-agent-install.sh /tmp/beszel-agent-install.sh --perms 0755"
python scripts/proxmox/proxmox_exec.py "pct push 102 /tmp/beszel-agent.env /tmp/beszel-agent.env --perms 0600"
```

4. Запустить установщик:

```powershell
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- bash /tmp/beszel-agent-install.sh"
```

Ожидаемый вывод:

```text
[beszel-agent-install] starting
[beszel-agent-install] HUB_URL=https://apps-pundef.mooo.com/beszel
[beszel-agent-install] LISTEN=45876
[beszel-agent-install] tarball=/tmp/beszel-agent_linux_amd64_glibc.tar.gz
[beszel-agent-install] created system user 'beszel-agent'
[beszel-agent-install] installed binary at /opt/beszel-agent/beszel-agent
[beszel-agent-install] beszel-agent listening on :45876 (after Ns)
```

5. Зачистить временные файлы (на хосте + локально + на LXC оставшиеся):

```powershell
python scripts/proxmox/proxmox_exec.py "rm -f /tmp/beszel-agent_linux_amd64_glibc.tar.gz /tmp/beszel-agent-install.sh /tmp/beszel-agent.env"
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- rm -f /tmp/beszel-agent_linux_amd64_glibc.tar.gz /tmp/beszel-agent-install.sh"
Remove-Item (Join-Path $env:TEMP "beszel-agent.env") -Force
```

> `/tmp/beszel-agent.env` внутри LXC 102 удаляется самим установщиком после успеха. Шаг 5 здесь — на случай, если установка прервалась раньше.

**Проверить.**

```powershell
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- systemctl is-active beszel-agent"
python scripts/proxmox/proxmox_exec.py "pct exec 102 -- journalctl -u beszel-agent --no-pager -n 30"
```

Признак успеха в логах:

```text
INFO Data directory path=/var/lib/beszel-agent
INFO Detected disk name=...
INFO Detected network interface name=eth0 ...
INFO Starting SSH server addr=:45876 network=tcp
INFO SSH connected addr=127.0.0.1:NNNNN
INFO SSH connection established
```

В UI Beszel система `static-sites` переходит в `online`, появляются текущие значения CPU / RAM / Disk / Network.

> **Что делать с `WARN WebSocket connection failed err="unexpected status code: 400"`** — на момент Шага 6 они появлялись, но **исчезли** после Шага 4b (Apache WS-fix). Если у тебя они всё-таки висят, проверь:
> - модули apache: `qm guest exec 101 -- bash -lc 'apache2ctl -M' | grep -E proxy_wstunnel|rewrite|headers`
> - что был сделан reload (`systemctl reload apache2`).
>
> WS-канал нужен в первую очередь для realtime-обновлений UI и для command-channel (например, при переустановке агента из UI). Метрики собираются по SSH; если SSH работает, значения в UI обновляются при F5 даже без WS.

---

## Шаг 7. Агент на Proxmox host (`pundef`, в UI: `Proxmox`) — ✅ сделано

Установка идентична Шагу 6, **только без `pct push`** — устанавливаемся прямо на хост:

| Параметр | Значение |
| --- | --- |
| `+ Add System` в UI | Name: `Proxmox`, Host: `192.168.50.9`, Port: `45876` |
| Скачать tarball | тот же `beszel-agent_linux_amd64_glibc.tar.gz` v0.18.7 |
| Залить tarball | `upload.py … /tmp/beszel-agent_linux_amd64_glibc.tar.gz` (и всё) |
| Залить env-файл | `upload.py … /tmp/beszel-agent.env --chmod 600` |
| Запустить установщик | `proxmox_exec.py "bash /tmp/beszel-agent-install.sh"` |
| Зачистить | `proxmox_exec.py "rm -f /tmp/beszel-agent*"` + `Remove-Item %TEMP%\beszel-agent.env` |

**Открытие про WS-режим.** На host'е (где Apache WS-fix уже работал к моменту запуска) агент сразу пошёл в WS, и **не открыл** SSH-listener `:45876`. В Beszel 0.18+ это штатное поведение: успешный WS — тогда hub→agent весь трафик через тот же tunnel, listening socket не нужен. SSH-режим включается только как fallback, если WS недоступен. **Install-script обновлён** — теперь ждёт **либо** `WebSocket connected` в логах, **либо** `:LISTEN` сокет (что прилетит первым).

**SMART-метрики физического диска.** Beszel пытается читать SMART через `smartctl`. На свежем PVE-host'е могут быть две причины фейла:

1. `smartmontools` не установлен → `smartctl failed err="exit status 2"`.
   ```powershell
   python scripts/proxmox/proxmox_exec.py "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq smartmontools"
   ```
2. Юзер `beszel-agent` не имеет доступа к `/dev/sda` (он `root:disk` `0660`). Лечится добавлением в группу `disk`. **Установщик теперь делает это автоматически** (`usermod -aG disk beszel-agent`), но на уже-установленных агентах (как наш host) — руками + restart:
   ```powershell
   python scripts/proxmox/proxmox_exec.py "usermod -aG disk beszel-agent && systemctl restart beszel-agent"
   ```

После обоих фиксов на нашем host'е логи показывают `INFO no valid SMART data found device=/dev/sda` — это **уже не ошибка прав/пакета**, а особенность конкретного SSD под N150 (не отдаёт SMART через SATA-канал). Не критично, остальные метрики идут.

**Проверить.**

```powershell
python scripts/proxmox/proxmox_exec.py "systemctl is-active beszel-agent"
python scripts/proxmox/proxmox_exec.py "journalctl -u beszel-agent --no-pager -n 20"
```

Признак успеха: `WebSocket connected host=apps-pundef.mooo.com` в логах, в UI Beszel система `Proxmox` online, видны CPU / RAM / LVM-volumes / vmbr0 / nic0 / tap*-интерфейсы (PVE отдаёт всю сетевую обвязку, включая VM-tap'ы).

---

## Шаг 8. Агент в `nextcloud-vm` (VM 101) — ✅ сделано

**Особенность.** Доступ в гостевую ВМ — только через QEMU guest agent (`qm guest exec`), прямого SSH-ключа нет. Это даёт два вызова, которых не было в Шагах 6/7:

- **`qm guest exec` имеет лимит на размер аргументов** (~2 МБ через QGA RPC). Tarball агента ~3.9 МБ, base64 ~5.2 МБ — через `apply-vm-file.sh` (он base64-кодирует и пихает аргументом) **не пройдёт**. Решение: временный HTTP-сервер на Proxmox-хосте, ВМ скачивает тарбол через curl. Маленькие файлы (install-script, env-файл с TOKEN) — по-прежнему через `apply-vm-file.sh`.
- **Запуск долгоживущих фоновых процессов через `proxmox_exec.py`** (paramiko ssh) с `nohup ... &` зависает: paramiko не отпускает session пока stdout/stderr остаются открыты у дочернего процесса. Решение — `systemd-run --unit=beszel-temp-http …`: создаёт transient unit, ssh возвращается мгновенно. После использования — `systemctl stop beszel-temp-http` (или `pkill`), unit пропадает.

**Сделать.**

1. `+ Add System` в UI: Name `nextcloud-vm`, Host `192.168.50.34`, Port `45876`. Скопировать TOKEN.

2. Подготовить env-файл локально (как в Шаге 6) и залить tarball/install-script/env-файл на Proxmox-host:

```powershell
# (env-файл создаётся в %TEMP%, как в Шаге 6, c новым TOKEN)
$tar = Join-Path $env:TEMP "beszel-agent_linux_amd64_glibc.tar.gz"
$envFile = Join-Path $env:TEMP "beszel-agent.env"

python scripts/proxmox/upload.py $tar /tmp/beszel-agent_linux_amd64_glibc.tar.gz
python scripts/proxmox/upload.py scripts/proxmox/beszel-agent-install.sh /tmp/beszel-agent-install.sh --chmod 755
python scripts/proxmox/upload.py $envFile /tmp/beszel-agent.env --chmod 600
```

3. Поднять временный HTTP-сервер на хосте, скачать tarball в ВМ:

```powershell
# Один раз перед всеми VM-агентами:
python scripts/proxmox/proxmox_exec.py "systemctl stop beszel-temp-http 2>/dev/null; systemctl reset-failed beszel-temp-http 2>/dev/null; systemd-run --unit=beszel-temp-http --description='temp http for beszel agent install' /usr/bin/python3 -m http.server 8888 --bind 192.168.50.9 --directory /tmp/"

# Скачать тарбол внутрь VM 101:
python scripts/proxmox/proxmox_exec.py "qm guest exec 101 --timeout 30 -- bash -lc 'curl -fsSL -o /tmp/beszel-agent_linux_amd64_glibc.tar.gz http://192.168.50.9:8888/beszel-agent_linux_amd64_glibc.tar.gz && wc -c /tmp/beszel-agent_linux_amd64_glibc.tar.gz'"
```

4. Залить установщик и env-файл в ВМ через QGA (через `apply-vm-file.sh`):

```powershell
python scripts/proxmox/proxmox_exec.py "/tmp/apply-vm-file.sh 101 /tmp/beszel-agent-install.sh /tmp/beszel-agent-install.sh 'chmod 755 /tmp/beszel-agent-install.sh'"
python scripts/proxmox/proxmox_exec.py "/tmp/apply-vm-file.sh 101 /tmp/beszel-agent.env /tmp/beszel-agent.env 'chmod 600 /tmp/beszel-agent.env'"
```

5. Запустить установщик внутри ВМ:

```powershell
python scripts/proxmox/proxmox_exec.py "qm guest exec 101 --timeout 60 -- bash /tmp/beszel-agent-install.sh"
```

Ожидаемо: `[beszel-agent-install] beszel-agent connected via WebSocket (after Ns)`.

6. Прибраться (выключить http-сервер, удалить /tmp/* на хосте и в ВМ, удалить локальный env-файл):

```powershell
python scripts/proxmox/proxmox_exec.py "systemctl stop beszel-temp-http 2>/dev/null; pkill -f 'http.server 8888' 2>/dev/null; rm -f /tmp/beszel-agent* /tmp/http.log"
python scripts/proxmox/proxmox_exec.py "qm guest exec 101 --timeout 5 -- bash -lc 'rm -f /tmp/beszel-agent.env /tmp/beszel-agent_linux_amd64_glibc.tar.gz /tmp/beszel-agent-install.sh'"
Remove-Item (Join-Path $env:TEMP "beszel-agent.env") -Force
```

**Docker-метрики.** На `nextcloud-vm` крутится Docker (контейнер `onlyoffice-documentserver`). Чтобы Beszel видел контейнеры и их CPU/RAM, нужен доступ к `/var/run/docker.sock` (`root:docker 0660`). Установщик теперь автоматически добавляет `beszel-agent` в группу `docker`, если она существует — для уже-установленных агентов это можно сделать руками:

```powershell
python scripts/proxmox/proxmox_exec.py "qm guest exec 101 --timeout 10 -- bash -lc 'usermod -aG docker beszel-agent && systemctl restart beszel-agent'"
```

После рестарта в UI Beszel в карточке `nextcloud-vm` появится секция Docker с `onlyoffice-documentserver`.

**Проверить.**

```powershell
python scripts/proxmox/proxmox_exec.py "qm guest exec 101 --timeout 5 -- bash -lc 'systemctl is-active beszel-agent; journalctl -u beszel-agent --no-pager -n 10'"
```

Признаки успеха: `active`, `WebSocket connected host=apps-pundef.mooo.com`, в UI система `nextcloud-vm` online, видна docker-секция.

---

## Шаг 9. Агент на `phoneserver` (OpenRC) — ✅ сделано

**Цель.** Нативный `beszel-agent` на postmarketOS (arm64), без HAOS и без Docker.

**От оператора (один раз в UI).**

1. [https://apps-pundef.mooo.com/beszel/](https://apps-pundef.mooo.com/beszel/) → `+ Add System`:
   - Name: `phoneserver`
   - Host: `192.168.1.116` (или актуальный IP; USB: `172.16.42.1`)
   - Port: `45876`
2. Из модалки `docker run …` скопировать **только `TOKEN=`** (UUID). `KEY` и `HUB_URL` уже зашиты в установщик).

**Предусловия на телефоне.**

- SSH по ключу: `pmos@192.168.1.116` (ключ в WSL `~/.ssh/phoneserver_nopass` или Windows `%USERPROFILE%\.ssh\phoneserver_nopass`).
- Телефон видит hub по LAN: `curl -fsS -m 5 http://192.168.50.35/beszel/` → HTTP 200 (маршрут `lan→srv` на X3000T).

**Установка (Windows или WSL, из корня репо).**

```powershell
# WSL (рекомендуется — ключ ~/.ssh/phoneserver_nopass):
wsl bash scripts/phoneserver/install-beszel-agent.sh "<uuid-из-ui>"

# PowerShell (если ключ в %USERPROFILE%\.ssh\ или WSL):
.\scripts\phoneserver\install-beszel-agent.ps1 -Token "<uuid-из-ui>"
```

Скрипты: [`install-beszel-agent.ps1`](scripts/phoneserver/install-beszel-agent.ps1) (оркестратор), [`beszel-agent-install.sh`](scripts/phoneserver/beszel-agent-install.sh) (OpenRC на телефоне). Tarball: `beszel-agent_linux_arm64.tar.gz` v0.18.7. **`HUB_URL` по умолчанию внутренний** `http://192.168.50.35/beszel` (без hairpin через публичный домен).

**Проверить.**

- UI: система `phoneserver` **online**.
- На телефоне: `sudo tail -20 /var/log/beszel-agent.log` → `WebSocket connected`.
- `sudo rc-service beszel-agent status` → started.

**Батарея в UI.** Beszel 0.18.x **не показывает %**, если в sysfs `status=Unknown` (так отдаёт `qcom_qg` на joyeuse). Обход: [`scripts/phoneserver/beszel-battery-status-fix.sh`](scripts/phoneserver/beszel-battery-status-fix.sh) — bind-mount `Charging`/`Discharging` по `tcpm-source …/online` перед стартом агента. Установка: `wsl bash scripts/phoneserver/install-beszel-battery-fix.sh`. Проверка: `cat /sys/class/power_supply/qcom_qg/status` → не `Unknown`.

---

## Шаг 10a. SSH-ключ для VPS — ⬜ не сделано

**Цель.** С Windows нужен passwordless SSH на оба VPS, чтобы заливать установщик через helpers `scripts/vps/vps_exec.py` и `scripts/vps/vps_upload.py` (по образцу Proxmox).

**Параметры.**

| VPS | Host | SSH user | Beszel UI name | TOKEN (per-system) |
| --- | ---- | -------- | -------------- | ------------------ |
| Fin | `89.44.76.52` | `root` | `fin-sweet-home-vps` | `<TOKEN из Add System>` |
| Neth | `45.154.35.222` | `pundef` (sudo с паролем) | `sweet-home-vps` | `<TOKEN из Add System>` |

Ключ: `%USERPROFILE%\.ssh\vps_nopass` (ed25519, без passphrase). Public part — положить в `~/.ssh/authorized_keys` на **обоих** VPS.

**Сделать.**

1. Если ключа ещё нет — сгенерировать на Windows:

```powershell
ssh-keygen -t ed25519 -N '""' -C "vps@windows" -f "$env:USERPROFILE\.ssh\vps_nopass"
Get-Content "$env:USERPROFILE\.ssh\vps_nopass.pub"
```

2. Авторизовать ключ на каждом VPS (один раз — через консоль хостера или интерактивный SSH; Fin: `root`, Neth: `pundef`):

```powershell
# Fin (root)
type $env:USERPROFILE\.ssh\vps_nopass.pub | ssh root@89.44.76.52 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Neth (pundef)
type $env:USERPROFILE\.ssh\vps_nopass.pub | ssh pundef@45.154.35.222 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

3. Проверить passwordless-доступ:

```powershell
$py = Join-Path $env:LOCALAPPDATA "Python\bin\python.exe"
$env:VPS_HOST='89.44.76.52'; $env:VPS_USER='root'
& $py scripts/vps/vps_exec.py hostname

$env:VPS_HOST='45.154.35.222'; $env:VPS_USER='pundef'
& $py scripts/vps/vps_exec.py hostname
```

**Проверить.**

Ожидаемо: `fin-sweet-home-vps` и `customer55224` (или актуальный hostname Neth-VPS) без запроса пароля.

> **Почему отдельный ключ.** Proxmox-ключ (`proxmox_pundef_nopass`) на VPS не авторизован — это намеренно: VPS смотрят в интернет, ключ home-server держим отдельно.

---

## Шаг 10b. Агенты на оба VPS — ⬜ не сделано

**Цель.** Поставить Beszel Agent на Fin и Neth VPS. Агент **сам** подключается к хабу по WebSocket (`HUB_URL=https://apps-pundef.mooo.com/beszel`) — inbound `:45876` с интернета не нужен. Tarball качается **на VPS** с GitHub (в отличие от `srv`-сегмента, тут github доступен).

**Предусловие.** В UI Hub уже созданы системы `fin-sweet-home-vps` и `sweet-home-vps` с per-system TOKEN (см. таблицу в Шаге 10a). Шаг 10a выполнен (SSH-ключ работает).

**Оркестратор.** [`scripts/vps/install-beszel-agent.ps1`](scripts/vps/install-beszel-agent.ps1) — заливает env + установщики, на VPS вызывает [`scripts/vps/beszel-agent-install-vps.sh`](scripts/vps/beszel-agent-install-vps.sh) (wrapper: curl tarball + общий [`scripts/proxmox/beszel-agent-install.sh`](scripts/proxmox/beszel-agent-install.sh)).

**Сделать.**

Из корня репо, после Шага 10a:

```powershell
$env:BESZEL_FIN_TOKEN = "<TOKEN-fin-sweet-home-vps>"
$env:BESZEL_NETH_TOKEN = "<TOKEN-sweet-home-vps>"
.\scripts\vps\install-beszel-agent.ps1 -Target all
```

Или по одному:

```powershell
.\scripts\vps\install-beszel-agent.ps1 -Target fin
.\scripts\vps\install-beszel-agent.ps1 -Target neth
```

Ожидаемый вывод на каждом VPS:

```text
[beszel-agent-install-vps] downloading v0.18.7 tarball
[beszel-agent-install] starting
[beszel-agent-install] beszel-agent connected via WebSocket (after Ns)
```

**Проверить.**

```powershell
$py = Join-Path $env:LOCALAPPDATA "Python\bin\python.exe"

$env:VPS_HOST='89.44.76.52'; $env:VPS_USER='root'
& $py scripts/vps/vps_exec.py "systemctl is-active beszel-agent; journalctl -u beszel-agent --no-pager -n 10"

$env:VPS_HOST='45.154.35.222'; $env:VPS_USER='pundef'
& $py scripts/vps/vps_exec.py "systemctl is-active beszel-agent; journalctl -u beszel-agent --no-pager -n 10"
```

В UI [https://apps-pundef.mooo.com/beszel/](https://apps-pundef.mooo.com/beszel/) обе системы (`fin-sweet-home-vps`, `sweet-home-vps`) переходят в **online**, видны CPU / RAM / Disk / Network.

> **Neth и RAM.** На Neth-VPS ~957 МБ RAM — Beszel Agent лёгкий (~10–20 МБ), но следить за `available` в UI; AmneziaWG уже занимает часть памяти.

---

## Сделано (история)

Пункты, которые уже выполнены. Оставлены для истории; в текущем плане не повторять.

| Когда | Что сделано |
| ----- | ----------- |
| 2026-05-24 | **Шаг 1: RAM LXC 102 → 1024 МБ.** `pct set 102 --memory 1024` применён на лету. `pct config 102` показывает `memory: 1024`, внутри LXC `free -m` → `total=1024, free=724`, `caddy active`, `http://192.168.50.35/requiem/` → `HTTP 200`. Зафиксирован нюанс: `-m` неоднозначен в `pct set`, нужно полное `--memory`. |
| 2026-05-24 | **Шаг 2: Beszel Hub v0.18.7 установлен в LXC 102.** Добавлен `scripts/proxmox/beszel-hub-install.sh` — идемпотентный установщик; пользователь `beszel`, `/opt/beszel/`, systemd unit с `Environment="APP_URL=https://apps-pundef.mooo.com/beszel"`. Hub слушает `127.0.0.1:8090`, `systemctl is-active beszel`=active, `/api/health`=`{"message":"API is healthy.","code":200,"data":{}}`. Зафиксирован обходной путь: tarball pre-staged в `/tmp/`, потому что github из `srv`-сегмента уходит в pbr→awg1 и connection refused. |
| 2026-05-24 | **Шаг 3: Caddy — path-based `/beszel/*`.** Caddyfile вынесен в репозиторий (`static-sites/Caddyfile`), добавлен `handle_path /beszel/*` с `reverse_proxy 127.0.0.1:8090` и `read_timeout 360s`. `caddy validate` ОК, reload без рестарта. Локальные пробы: `/beszel/`=200/1307b, `/beszel/api/health`=200/51b, `/beszel/static/icon.svg`=200/1138b, `/beszel/assets/index-Dq5BcLwo.js`=200/484389b. `BASE_PATH: "/beszel/"` присутствует в HTML. Зафиксирован нюанс: тестировать через `localhost`/`192.168.50.35`, не через `127.0.0.1` (нет в списке vhost). |
| 2026-05-24 | **Шаг 4: внешний HTTPS — наследован.** `https://apps-pundef.mooo.com/beszel/` работает «из коробки» через существующий Apache vhost на nextcloud-vm (proxy `/` → `http://192.168.50.35/`). Все 4 пробы (`/beszel/`, `/beszel/api/health`, `/beszel/assets/…`, regression `/requiem/`) — HTTP 200, cert валиден. Дополнительной настройки Apache, DDNS, certbot не потребовалось. |
| 2026-05-24 | **Шаг 4b: Apache vhost — WebSocket-апгрейд.** Vhost вынесен в репозиторий как `nextcloud-vm/apache/apps-pundef.conf`, добавлен `RewriteRule` для `Connection: Upgrade` → `ws://192.168.50.35/`. Включены модули `proxy_wstunnel`, `rewrite`, `headers` (`a2enmod -q`). Backup существующего конфига: `/etc/apache2/sites-available/apps-pundef.conf.bak.20260524`. Helper `scripts/proxmox/apply-vm-file.sh` — заливает файлы в гостевые ВМ через QEMU guest agent (без SSH-ключа). |
| 2026-05-24 | **Шаг 5: admin создан, модель аутентификации — гибрид WS+SSH.** В UI Hub зарегистрирован первый пользователь (он же superuser). Зафиксирована схема per-system: `KEY` (хаб public-key, один на всех), `TOKEN` (UUID на систему, выдаётся при `+ Add System`), `HUB_URL`. Universal token — выключен, идём по per-system. |
| 2026-05-24 | **Шаг 6: агент в LXC 102 (self-monitor) запущен.** Добавлен `scripts/proxmox/beszel-agent-install.sh` — универсальный установщик агента под systemd (читает `/tmp/beszel-agent.env`, создаёт `beszel-agent` user, ставит бинарь в `/opt/beszel-agent/`, генерит unit с `EnvironmentFile=/etc/default/beszel-agent` mode 0640, после успеха удаляет staging env-файл). Бинарь — `beszel-agent_linux_amd64_glibc.tar.gz` v0.18.7, pre-staged через Windows %TEMP% → upload.py → host → pct push (github из srv-сегмента всё ещё блокирован). В UI система `static-sites` online, в логах `SSH connection established`. После Шага 4b WS-варнинги пропали. Зафиксирован нюанс: per-system token и хаб public-key — оба нужны (TOKEN для регистрации по WS, KEY для SSH-канала с метриками). |
| 2026-05-24 | **Шаг 7: агент на Proxmox host `pundef` запущен (WS-режим).** Тот же установщик, env-файл с TOKEN для системы `Proxmox` (host=192.168.50.9, port=45876) залит через `upload.py`, агент стартанул и сразу `INFO WebSocket connected host=apps-pundef.mooo.com`. **Открытие**: в Beszel 0.18+ при успешном WS-канале агент **не открывает SSH-listener** — hub→agent трафик идёт по обратному WS-tunnel'ю. Install-script обновлён: ждёт либо `WebSocket connected` в logs, либо `:LISTEN` socket; иначе fail. Поставлен `smartmontools` (для SMART-метрик SSD), юзер `beszel-agent` добавлен в группу `disk` (чтобы smartctl читал `/dev/sda` без root). Конкретный SSD под N150 не отдаёт SMART (`no valid SMART data found device=/dev/sda`) — это фича диска, не баг. github из host тоже блокирован pbr-policy на роутере — pre-stage tarball через Windows как для LXC. Display name в UI Beszel — `Proxmox` (hostname остаётся `pundef`). |
| 2026-05-24 | **Шаг 8: агент в `nextcloud-vm` (101) запущен.** Прямого SSH к гостю нет, всё через `qm guest exec`. Маленькие файлы (install.sh, env-файл) — через `apply-vm-file.sh` (base64). Tarball (3.9 МБ) — через временный HTTP-сервер на хосте: `systemd-run --unit=beszel-temp-http -- python3 -m http.server 8888 --bind 192.168.50.9 --directory /tmp/` (transient unit, чтобы paramiko ssh не зависал на nohup). После загрузки в `/tmp/` ВМ — `bash /tmp/beszel-agent-install.sh` через QGA, агент стартанул, `WebSocket connected`. Зачистка: `systemctl stop beszel-temp-http`, `rm /tmp/beszel-agent*` на host и в ВМ. Дополнительно: `usermod -aG docker beszel-agent` + restart — теперь Beszel видит `onlyoffice-documentserver` контейнер и его метрики. Install-script теперь автоматом добавляет в группы `disk` и `docker` если они существуют. |
| 2026-05-24 | **Шаг 10: VPS helpers + агенты на оба VPS.** Добавлены `scripts/vps/vps_exec.py`, `vps_upload.py`, `beszel-agent-install-vps.sh`, `install-beszel-agent.ps1`; SSH-ключ `%USERPROFILE%\.ssh\vps_nopass`. Fin (`89.44.76.52`, root): агент v0.18.7, `WebSocket connected`. Neth (`45.154.35.222`, **`pundef`** — не `amnadmin`; ключ в `~pundef/.ssh/authorized_keys`, sudo с паролем): файлы залиты с Windows, установка `sudo bash /tmp/beszel-agent-install-vps.sh` вручную в консоли; `systemctl is-active beszel-agent`=active, PID running. |

