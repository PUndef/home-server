# WF Twitch Drops

Расписание Twitch-дропов Warframe: RSS форума Livestreams → `events.json` → SPA.

## Локально

```powershell
cd static-sites\wf-twitch
npm ci
npm run sync-events   # подтянуть RSS с forums.warframe.com
npm run dev
```

## Деплой

```powershell
.\static-sites\wf-twitch\scripts\deploy.ps1
```

Перед первым деплоем на LXC: блок в `static-sites/Caddyfile`, DNS `wftwitch.home` → `192.168.50.35`, `apply-caddyfile.ps1`.

## Источник данных

- RSS: `https://forums.warframe.com/forum/113-livestreams.xml/`
- Парсер: `scripts/sync-events.mjs` (запускается при деплое)
- Время на сайте: **Asia/Krasnoyarsk**

## URL

| Среда | URL |
|-------|-----|
| LAN | `http://wftwitch.home/` |
| Path | `https://apps-pundef.mooo.com/wf-twitch/` |
