# kb-remote-ui

Локальный дашборд для `kb-remote` / `kb-dev` — следит за Mac→WSL remote-сессиями, которые поднимаются по скиллу `kupibilet-remote-setup`.

Показывает в одном окне:

- SSH-доступность удалёнки (`kupi-remote`)
- состояние autossh launchd-агента (pid, running/stopped)
- состояние Mutagen-демона
- для каждой attached-папки:
  - basename, stack (`kupibilet` / `new-kupibilet`), worktree-флаг
  - git-ветку, последний коммит, кол-во dirty-файлов
  - Mutagen-сессию (Watching / Scanning / Conflicts / Disconnected)
  - **deps-state на mirror** (`installed` / `missing` / `installing` / `unknown`) — проверяется наличие `node_modules` через одну ssh-команду по всем папкам. `Start dev` блокируется (с явным title-tooltip) если deps `missing` или install уже крутится — чтобы агенту/пользователю было сразу видно, почему `kb-dev` бы упал, без копания в логах
  - проброшенный порт (и слушает ли его Mac через autossh)
  - dev-tmux-сессию на удалёнке (running / stopped)
- last-refresh таймштамп, прогресс-бар поллинга

И кнопки действий:

- **Restart** — `kb-remote restart-tunnel`
- **Start dev (variant) ▾ / Stop dev** — `kb-dev --bg <path> [--variant V]` / `kb-dev --stop <path>`. Для new-kupibilet можно выбрать `kupibilet` (default), `sales`, `seo-landings`, `help`, `blog`, `price-map`, `storybook`. Для legacy kupibilet — `kupibilet.ru` (default) или `kupicom.com`. Выбор последнего variant пишется в `state.json` как `last_variant` и предзаполняется при следующем рендере.
- **Refresh sync** — `kb-remote refresh <path>`
- **Install deps** — `kb-remote install-deps <path>`. Поднимает tmux-сессию `${label}-install` на удалёнке и гоняет в ней yarn/pnpm install. Кнопка автоматически появляется в footer карточки если deps `missing` (красная, с подсказкой в health-row) или `unknown`. Пока install крутится, кнопка показывает `Installing…` (busy spinner) и `Start dev` остаётся заблокирован.
- **Detach** — `kb-remote detach <path> [--purge-mirror]`. Модалка-confirm с чекбоксом «Also delete mirror on WSL (irreversible)» — по умолчанию выключен. Корректно вызывает `mutagen sync terminate`, освобождает порт и перезагружает autossh launchd-агент.
- **+ Attach** (в шапке) — `kb-remote attach <path>`. Попап с двумя секциями:
  - **Suggested in ~/Documents** — авто-список папок, чей basename матчит naming-convention (`kupibilet.ru` / `new-kupibilet.ru` / `<repo>-<branch>`) и которые ещё не attached. Под каждой строкой подсказан порт, который будет выдан (из дефолтного pool: `8443` / `8453-8493` для kupibilet, `3000` / `3010-3050` для new-kupibilet — алгоритм совпадает с `allocate_port` в `kb-remote`).
  - **Custom path** — text input + live preview (debounced fetch к `/api/attach-preview?path=…`). Кнопка Attach разблокируется только если preview валидный. На fail показывается stderr из `kb-remote attach`.
- **Open &lt;host&gt;:&lt;port&gt;** — открыть проброшенный dev-сервер в браузере. Для `new-kupibilet` рендерится **две** кнопки — `kupibilet.local` и `kupicom.local`, потому что один и тот же next-dev процесс отдаёт оба whitelabel'а в зависимости от Host-header. Для legacy `kupibilet` — одна `Open :NNNN` (localhost). Все кнопки disabled (зачёркнуты) если dev лежит **или** autossh не форвардит порт. Хосты должны быть прописаны в `/etc/hosts` → `127.0.0.1`.

Когда autossh tunnel падает, наверху списка появляется глобальный warning-баннер с прямой кнопкой Restart. Каждая карточка имеет цветной health-row (LIVE / TUNNEL DOWN / SYNC CONFLICT / IDLE / OFFLINE) и левую цветную полосу.

## Архитектура

```
┌────────────────────┐    HTTP    ┌──────────────────────────┐
│ browser (any)      │ ─────────► │ Mac daemon  :4747        │
│ public/index.html  │            │ server.js (zero deps)    │
└────────────────────┘            └──────────┬───────────────┘
                                              │ shells out
                                              ▼
                          ┌─────────────────────────────────────┐
                          │ ~/.config/kb-remote/state.json      │
                          │ mutagen sync list                   │
                          │ launchctl print …                   │
                          │ git -C <path> branch/log/status     │
                          │ ssh kupi-remote tmux list-sessions  │
                          └─────────────────────────────────────┘
```

Все источники данных живут на Mac, поэтому сервер обязан быть на Mac. Фронт — чистая статика; его можно деплоить откуда угодно и переключать backend через query-параметр (см. ниже).

## Запуск

Требует Node ≥ 20.

### Всегда-доступный режим (рекомендуется)

Регистрирует LaunchAgent `com.kupibilet.kb-remote-ui`, который поднимается
при логине, переживает crash'и (KeepAlive=true) и держит сервер на
`127.0.0.1:4747`.

```bash
./bin/kb-remote-ui-service install   # bootstrap в launchd, сразу стартует
./bin/kb-remote-ui-service status    # pid + state + port
./bin/kb-remote-ui-service restart   # kickstart -k
./bin/kb-remote-ui-service stop      # bootout, plist на диске остаётся
./bin/kb-remote-ui-service uninstall # bootout + удалить plist
./bin/kb-remote-ui-service logs      # tail -F stdout+stderr
```

После `install` дашборд доступен **всегда** на `http://127.0.0.1:4747`,
без ручного `node server.js`.

- **Plist:** `~/Library/LaunchAgents/com.kupibilet.kb-remote-ui.plist`
  (рендерится из `launchd/com.kupibilet.kb-remote-ui.plist.template` при каждом
  `install` — пути к `node` и `server.js` подставляются абсолютные).
- **Логи:** `~/Library/Logs/kb-remote-ui/server.log` и `server.err.log`
  (не удаляются при `uninstall`).
- **node** ищется через `command -v node` (т.е. NVM-версия, активная в shell),
  путь резолвится через `realpath` чтобы launchd жёстко зафиксировал ту же
  установку.

### Разовый запуск (для разработки самого UI)

```bash
cd ~/Documents/kb-remote-ui
npm start                   # node server.js → http://127.0.0.1:4747
# или
./bin/kb-remote-ui          # тонкий launcher
```

> **Внимание:** не запускай разовый `node server.js` одновременно с
> launchd-инстансом — порт 4747 будет занят и второй упадёт с EADDRINUSE.
> Перед dev-итерациями делай `./bin/kb-remote-ui-service stop`.

### Проверка

```bash
curl -s http://127.0.0.1:4747/api/health
curl -s http://127.0.0.1:4747/api/snapshot | jq .ssh,.tunnel,.folders[0]
```

## Конфиг (env)

| Переменная        | Default                                  | Описание                                                          |
| ----------------- | ---------------------------------------- | ----------------------------------------------------------------- |
| `PORT`            | `4747`                                   | HTTP-порт                                                         |
| `HOST`            | `127.0.0.1`                              | Bind-адрес. `0.0.0.0` чтобы открыть для Tailscale / LAN           |
| `KB_REMOTE_HOST`  | `kupi-remote`                            | SSH-алиас (как в `kb-remote`)                                     |
| `KB_STATE_FILE`   | `$XDG_CONFIG_HOME/kb-remote/state.json`  | Альтернативный путь к state-файлу                                 |
| `KB_MUTAGEN_BIN`  | автодетект (`~/.local/bin/mutagen`, etc) | Путь к бинарю Mutagen                                             |
| `POLL_INTERVAL`   | `5000`                                   | Период фонового опроса в мс                                       |

## HTTP API

```
GET  /api/health                   # liveness ping
GET  /api/snapshot[?force=1]       # полный снимок (см. ниже)
GET  /api/attach-candidates        # сканирует ~/Documents, возвращает unattached папки c suggestedPort
GET  /api/attach-preview?path=…    # validate path + предсказывает порт без вызова kb-remote
POST /api/actions/tunnel-restart   # exec kb-remote restart-tunnel
POST /api/actions/dev-start        # body {path, variant?}: exec kb-dev --bg <path> [--variant V]
POST /api/actions/dev-stop         # body {path}:           exec kb-dev --stop <path>
POST /api/actions/set-variant      # body {path, variant}:  persist last_variant in state.json (no exec)
POST /api/actions/mutagen-refresh  # body {path}:           exec kb-remote refresh <path>
POST /api/actions/install-deps     # body {path}:           exec kb-remote install-deps <path>     (tmux session)
POST /api/actions/attach           # body {path}:           exec kb-remote attach <path>           (mutexed)
POST /api/actions/detach           # body {path, purgeMirror?: bool}: exec kb-remote detach <path> [--purge-mirror] (mutexed)
```

`GET /api/snapshot` (сокращённо):

```jsonc
{
  "generatedAt": "2026-06-24T17:00:12.345Z",
  "elapsedMs": 412,
  "config": { "sshHost": "kupi-remote", "stateFile": "...", "plistLabel": "com.kupibilet.kb-remote" },
  "ssh":            { "ok": true,  "code": 0,  "error": null },
  "tunnel":         { "loaded": true, "state": "running", "pid": 64321 },
  "mutagenDaemon":  { "ok": true, "raw": "Daemon: Running" },
  "folders": [
    {
      "path": "/Users/work/Documents/new-kupibilet.ru",
      "mirror_path": "/home/paul/Documents/new-kupibilet.ru",
      "label": "kb-new-kupibilet-ru",
      "stack": "new-kupibilet",
      "is_worktree": false,
      "port": 3000,
      "git": { "ok": true, "branch": "main", "commit": { "hash": "abc1234", "ago": "2 hours ago", "subject": "..." }, "dirty": 0 },
      "mutagen": { "status": "Watching for changes", "conflicts": false, "alphaConn": "Connected", "betaConn": "Connected" },
      "listening": true,
      "devRunning": true,
      "devSession": "kb-new-kupibilet-ru-dev",
      "devActive": true,
      "devPortListening": true,
      "installRunning": false,
      "installSession": "kb-new-kupibilet-ru-install",
      "installActive": false,
      "deps": { "state": "ok", "mirrorPath": "/home/paul/Documents/new-kupibilet.ru" },
      "devReady": true,
      "devBlockedReason": null
    }
  ]
}
```

Семантика per-folder state-полей (важна для интерпретации «Live»/«Installing» в UI). Три **независимых** сигнала:

- `listening` — Mac-сторона слышит autossh tunnel на 127.0.0.1:port (`lsof -i :port`). Туннель жив независимо от того, что происходит на WSL.
- `devRunning` / `installRunning` — на WSL существует tmux-сессия `<label>-dev` / `<label>-install`. Сама по себе сессия ничего не гарантирует: после выхода из `next dev`/`pnpm install` остаётся `exec bash -i` хвост или `sleep 600`, и сессия живёт пустой.
- `devActive` / `installActive` — `<session>Running && pane_current_command — реальная работа` (НЕ `sleep`, НЕ `bash`, НЕ shell), через `tmux list-sessions -F '#{session_name}|#{pane_current_command}'` + `isActiveWorkCommand()`. Это сигнал «pane сейчас занят `next`/`node`/`pnpm`/etc», а не «сессия осталась пустой после exit'а».
- `devPortListening` — `ss -lntH` на WSL показывает LISTEN на `*:port` или `:::port`. Реальный сигнал «кто-то на удалёнке слушает HTTP на этом порту».

`devActive` и `devPortListening` могут расходиться: например `devActive=false` (pane в `bash` после exit'а) + `devPortListening=true` (zombie-процесс держит порт, или порт занял другой процесс). Это «session zombie», UI рисует `dev exited` с action=`stop-dev`.

- `installRunning` — остался для back-compat; UI его не использует.
- `devReady` — зависит от `installActive` (нельзя стартовать dev пока **реально** ставятся deps), а не от `installRunning`.


POST-actions валидируют `body.path` против state-файла и шеллят бинарь с argv (без shell-строки) — путь из state не может уйти в инъекцию. `/api/actions/attach` — единственное исключение: путь ещё не в state, поэтому он отдельно проверяется на (а) существование как директория, (б) расположение под `$HOME`, (в) basename, матчащий kb-remote naming convention, (г) отсутствие в state. `attach` и `detach` сериализуются между собой через in-memory promise-queue — два concurrent запроса не вызывают параллельные `launchctl kickstart -k` на одном автоssh-агенте.

## Безопасность

- По умолчанию демон слушает **только `127.0.0.1:4747`**, никакого auth-токена нет.
- Если ставишь `HOST=0.0.0.0` (например, чтобы открыть из Tailscale), помни: любой, кто доберётся до порта, сможет дёргать `kb-dev --stop` и `kb-remote refresh` на твоей машине. Закрывай файрволом / Tailscale ACL.
- CORS — `*` (намеренно, чтобы фронт можно было хостить отдельно).

## Деплой фронта отдельно (опционально)

Папка `public/` — самодостаточная статика. Любой статик-хостинг (PUndef/home-server static-sites, GitHub Pages, локальный nginx) сработает. Один раз указываешь backend:

```
https://kb.dashboard.local/?api=http://100.x.x.x:4747
```

Параметр `?api=` сохраняется в `localStorage` и подмешивается ко всем последующим `fetch`-ам. Чтобы сбросить:

```
https://kb.dashboard.local/?api=
```

## Связанные файлы

- `~/.local/bin/kb-remote` — оркестратор (Mutagen + autossh), source of truth для state-файла.
- `~/.local/bin/kb-dev` — стартер dev-сервера в tmux на удалёнке.
- `~/.config/kb-remote/state.json` — список attached-папок (формат: `{entries: [...]}`).
- `~/Library/LaunchAgents/com.kupibilet.kb-remote.plist` — autossh launchd-агент.
- `~/Library/LaunchAgents/com.kupibilet.kb-remote-ui.plist` — этот дашборд (генерируется из `launchd/*.template`).
- `~/Library/Logs/kb-remote-ui/{server.log,server.err.log}` — логи launchd-инстанса.
- `~/.cursor/skills/kupibilet-remote-setup/SKILL.md` — описание изначального флоу.
