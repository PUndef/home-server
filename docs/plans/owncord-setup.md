# OwnCord — план развёртывания в home-server

> **Статус:** plan (blocked — upstream alpha, только Windows server)

Self-hosted Discord-подобный чат: текст, DM, голос/видео (LiveKit), **десктоп-клиент** (Tauri). Репозиторий: [J3vb/OwnCord](https://github.com/J3vb/OwnCord).

> **Статус на 2026-05:** проект в **ранней alpha**. Официальный сервер — **Windows** (`chatserver.exe`). Запуск на Linux/macOS пока **не работает** ([#88](https://github.com/J3vb/OwnCord/issues/88), [#95](https://github.com/J3vb/OwnCord/issues/95)). Docker-образа нет. Автор предупреждает, что безопасность и production-readiness ещё в работе ([#89](https://github.com/J3vb/OwnCord/issues/89)).

---

## phoneserver (телефон) — не тот хост, куда смотрел план ниже

Если цель — **поднять OwnCord на Redmi / postmarketOS** (`192.168.1.116`, aarch64, `ui=none`):

| Роль | На телефоне сейчас |
|------|---------------------|
| **Сервер** (`chatserver`) | ❌ Только Windows `.exe`; Linux x86_64/arm64 сервер не стартует upstream; готового бинаря под **aarch64** нет |
| **Клиент** (Tauri) | ❌ В Releases только **Windows installer**; под pmOS нужна самостоятельная сборка `aarch64-unknown-linux-gnu` (тяжёло, webkit/gtk) |
| **Admin в браузере** | ⚠️ Теоретически `https://<сервер>:8443/admin` с другого ПК; на самом телефоне без UI/браузера неудобно |

**Почему в `owncord-setup.md` изначально Proxmox/LXC:** в репозитории phoneserver описан как **headless-узел** (SSH, Beszel agent), а OwnCord в документации — **сервер чата** для десктоп-клиентов; логичное место в homelab — ВМ/LXC в `srv`, не телефон.

**Что реально на телефоне сегодня:** подключаться к OwnCord **нельзя** штатно; хостить чат на телефоне — **нельзя**. Варианты: (1) сервер на Windows/ПК/LXC, клиент OwnCord на Windows/Mac; (2) когда появится Linux-сервер — всё равно лучше **не** на phoneserver (батарея, NAT, alpha, LiveKit); (3) для «чата с телефона» позже — другой стек (Matrix, etc.) или ждать mobile/Linux-сборки OwnCord.

Подробнее про phoneserver: [pmos-setup.md](../phoneserver/pmos-setup.md).

---

## Куда логично встроить в нашу схему (Proxmox / Windows)

```
Интернет / LAN
    -> OpenWrt X3000T (DNAT, DDNS)
    -> nextcloud-vm Apache :443 (apps-pundef.mooo.com)
    -> static-sites LXC 102 (192.168.50.35) Caddy :80
           /requiem/*  -> статика
           /beszel/*   -> Beszel hub
           /owncord/*  -> ❌ не подходит (см. ниже)
```

| Вариант | Где | Комментарий |
|---------|-----|-------------|
| **Рекомендуемый (когда будет Linux)** | Отдельный LXC в `srv` или тот же `static-sites` | Go + SQLite, мало RAM; по аналогии с Beszel Hub |
| **Сейчас (Windows)** | ПК Windows 24/7 или Windows VM на Proxmox | Единственный официально рабочий сервер |
| **Не сюда** | phoneserver (pmOS arm64) | Нет Windows-бинаря, клиент — desktop x64 |

**Path vs subdomain.** Beszel и requiem живут под `https://apps-pundef.mooo.com/<path>/`. OwnCord **рассчитан на корень хоста** (`https://host:8443`), клиент подключается как `domain:8443`. Для внешнего доступа лучше **отдельный поддомен**, например `owncord-pundef.mooo.com` → reverse proxy на backend, а не `/owncord/` на общем vhost (если только не проверим subpath отдельно после появления Linux-сборки).

---

## Что понадобится

### Минимум (только текст + файлы)

| Компонент | Порт | Протокол |
|-----------|------|----------|
| OwnCord HTTPS API + WebSocket | `8443` (default) | TCP |

### С голосом / видео (LiveKit)

| Компонент | Порт | Протокол |
|-----------|------|----------|
| LiveKit signaling | `7880`, `7881` | TCP |
| WebRTC media | `50000–60000` | **UDP** |

Для доступа **из интернета** с голосом нужен проброс UDP-диапазона на OpenWrt — тяжелее, чем Beszel/Nextcloud. Для **только LAN** (`192.168.50.0/24` + `192.168.1.0/24`) достаточно внутреннего IP и без hairpin.

### Клиенты

Пользователи ставят **десктоп OwnCord** (Windows installer из Releases), в настройках сервера указывают адрес (`192.168.50.x:8443` или `owncord-pundef.mooo.com:443` через proxy) и **invite code** из admin-панели (`/admin`).

---

## Вариант A — Windows (работает сейчас)

**Цель.** Поднять сервер на машине, где уже есть Windows, без ожидания Linux-порта.

### Шаг 1. Скачать и первый запуск

**Сделать**

1. С [GitHub Releases](https://github.com/J3vb/OwnCord/releases) скачать `chatserver.exe`.
2. Положить в каталог, например `C:\OwnCord\`.
3. Запустить `chatserver.exe` — создадутся `config.yaml` и `data/` (SQLite, TLS, uploads).
4. Открыть `https://localhost:8443/admin`, создать Owner, сгенерировать invite.

**Проверить**

- `https://localhost:8443/api/v1/info` отвечает.
- Клиент OwnCord с LAN подключается по `192.168.x.x:8443`.

### Шаг 2. Доступ из `srv` / `lan`

**Сделать**

1. В `config.yaml` при необходимости: `server.port`, `tls.mode` (`self_signed` / `acme` / `manual`).
2. Windows Firewall — разрешить входящий TCP `8443` (и порты LiveKit, если нужен голос).
3. Если сервер на ПК в `lan` (`192.168.1.x`) — клиенты в `srv` ходят напрямую по IP (маршрут `srv→lan` на X3000T есть).

**Проверить**

- С Proxmox или LXC: `curl -k https://<win-ip>:8443/api/v1/info`.

### Шаг 3. Доступ из интернета (опционально)

**Сделать**

1. FreeDNS: запись `owncord-pundef.mooo.com` → белый IP (как у cloud/apps).
2. OpenWrt DNAT: `443` или `8443` → `<win-ip>:8443` (или TLS на Apache → proxy, см. вариант B когда будет Linux).
3. Для голоса — проброс `7880`, `7881`, UDP `50000–60000` (осознанно: широкий UDP-диапазон).

**Проверить**

- С мобильного интернета клиент подключается к публичному адресу.

### Шаг 4. Сервис (опционально)

NSSM или Task Scheduler — autostart `chatserver.exe` (см. upstream `docs/deployment.md`).

---

## Вариант B — Linux LXC в `srv` (целевой, когда заработает сервер)

Повторяем паттерн Beszel: бинарь + systemd в LXC, снаружи Caddy/Apache, GitHub tarball через pre-stage если `srv` не достаёт github.

### Шаг 1. Выбор хоста — ⬜ не сделано

**Симптом/цель.** Решить, куда класть процесс.

**Сделать**

| Вариант | Плюс | Минус |
|---------|------|-------|
| **Новый LXC `owncord`** (512–1024 МБ RAM) | Изоляция, свой бэкап `data/` | Ещё один контейнер |
| **static-sites LXC 102** | Уже есть Caddy, опыт с `/beszel/` | RAM 1 ГБ уже занят hub + Caddy + agent |

**Проверить**

- `free -m` на выбранном хосте — запас ≥ 256 МБ под idle.

### Шаг 2. Сборка / установка сервера — ⬜ заблокировано (нет Linux)

**Сделать** (когда upstream починит #88)

1. Склонировать [J3vb/OwnCord](https://github.com/J3vb/OwnCord), `cd Server && go build -o chatserver`.
2. Или скачать linux-amd64 из Releases, если появится.
3. Пользователь `owncord`, `/opt/owncord/`, `data/` на volume.
4. systemd unit, `127.0.0.1:8443`, `tls.mode: off` или `manual` (TLS на Caddy).

Пример env (из upstream `server-configuration.md`):

```yaml
server:
  port: 8443
  trusted_proxies: ["127.0.0.1/32", "192.168.50.0/24"]
  allowed_origins: ["https://owncord-pundef.mooo.com"]
tls:
  mode: off   # TLS terminates at Caddy/Apache
```

**Проверить**

- `curl http://127.0.0.1:8443/api/v1/info` внутри LXC.

### Шаг 3. Caddy + Apache (subdomain) — ⬜ не сделано

**Сделать**

1. DNS: `owncord-pundef.mooo.com` → split-horizon на Apache/LXC (как `apps-pundef`).
2. На `nextcloud-vm`: отдельный vhost `443` → `ProxyPass / http://192.168.50.xx:8443/` + **WebSocket upgrade** (как в [`nextcloud-vm/apache/apps-pundef.conf`](nextcloud-vm/apache/apps-pundef.conf) для Beszel).
3. Либо отдельный `listen 8443` на Caddy с `reverse_proxy` и `read_timeout` для WS.

**Проверить**

- `curl -fsS https://owncord-pundef.mooo.com/api/v1/info`
- Admin: `https://owncord-pundef.mooo.com/admin` (доступ только из `admin_allowed_cidrs` — по умолчанию private nets).

### Шаг 4. LiveKit (опционально) — ⬜ не сделано

**Сделать**

1. Отдельный бинарь `livekit-server`, ключи в `config.yaml` (`voice.livekit_*`).
2. Проброс портов на OpenWrt или только LAN.

**Проверить**

- Голосовой канал в клиенте поднимается без ICE failed.

### Шаг 5. Клиенты и invite — ⬜ не сделано

**Сделать**

1. Admin → invite codes.
2. Друзья: installer OwnCord, server = `owncord-pundef.mooo.com` (порт 443 если proxy, иначе `:8443`).

**Проверить**

- Регистрация по invite, сообщения в канале, DM.

---

## Сравнение с тем, что уже есть

| | Beszel | OwnCord |
|---|--------|---------|
| Назначение | Мониторинг | Чат / голос |
| UI | Браузер | **Desktop app** |
| Сервер OS | Linux ✅ | Windows ✅, Linux ⏳ |
| Path на apps-pundef | `/beszel/` ✅ | Скорее **subdomain** |
| WebRTC / UDP | Нет | Да (LiveKit) |

---

## Рекомендация

1. **Сейчас**, если нужен OwnCord немедленно — **вариант A (Windows)** на постоянно включённом ПК в `lan`, доступ по локальному IP; в интернет — только если осознанно пробрасываешь порты.
2. **Для homelab на Proxmox/LXC** — **подождать Linux-сервер** (следить за #88 / Releases) и тогда делать **вариант B** по чеклисту выше; скрипт установки можно набросать по образцу [`scripts/proxmox/beszel-hub-install.sh`](scripts/proxmox/beszel-hub-install.sh).
3. **Голос из интернета** — отложить; начать с текста в LAN.
4. **Alpha / security** — не светить в интернет с чувствительными данными до стабилизации upstream.

---

## Сделано (история)

| Когда | Что сделано |
|-------|-------------|
| 2026-05-24 | Документ создан: обзор OwnCord, блокер Linux, схема для `srv`, варианты Windows vs LXC, порты LiveKit. |

---

## Ссылки

- [Quick Start](https://github.com/J3vb/OwnCord/blob/main/docs/quick-start.md)
- [Deployment (Windows)](https://github.com/J3vb/OwnCord/blob/main/docs/deployment.md)
- [Server configuration](https://github.com/J3vb/OwnCord/blob/main/docs/server-configuration.md)
- [Beszel setup (паттерн LXC + Caddy)](../proxmox/beszel-monitoring-setup.md)
- [static-sites LXC](../proxmox/static-sites-lxc.md)
