# WF Farm Helper

Статический помощник для поиска выгодных миссий под фарм ресурса, релика или мода по [официальному списку PC Drops](https://warframe-web-assets.nyc3.cdn.digitaloceanspaces.com/uploads/cms/hnfvc0o3jnfvc873njb03enrf56.html).

Стек и деплой — как у `requiem-helper` (Vite + React, `base: "./"`, Caddy path `/wf-farm/`).

## Локальная разработка

```powershell
cd wf-farm-helper
npm ci
npm run dev
```

В dev запросы идут через прокси `/drops-source` → CDN (см. `vite.config.ts`).

## Сборка

```powershell
npm run sync-drops   # опционально: копия HTML в public/drops.html (fallback ~4 МБ)
npm run build
```

## Деплой

```powershell
.\wf-farm-helper\scripts\deploy.ps1
```

- URL: `http://192.168.50.35/wf-farm/` или `https://apps-pundef.mooo.com/wf-farm/`
- Корень на LXC: `/srv/static-sites/wf-farm`
- Caddy: `scripts/static-sites/apply-caddyfile.ps1` после правок `static-sites/Caddyfile`

## Обновление данных

Кнопка «Обновить» или перезагрузка страницы тянет свежий HTML с CDN.
