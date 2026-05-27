# WF Farm Helper

Статический помощник для поиска выгодных миссий под фарм ресурса, релика или мода по [официальному списку PC Drops](https://warframe-web-assets.nyc3.cdn.digitaloceanspaces.com/uploads/cms/hnfvc0o3jnfvc873njb03enrf56.html).

Стек — Vite + React + shadcn (`base: "./"`). Общая схема — [`../README.md`](../README.md).

## Локальная разработка

```powershell
cd static-sites\wf-farm
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
.\static-sites\wf-farm\scripts\deploy.ps1
```

- URL: `http://wffarm.home/` · `http://192.168.50.35/wf-farm/` · `https://apps-pundef.mooo.com/wf-farm/`
- На LXC: `/srv/static-sites/wf-farm`

## Обновление данных

Кнопка «Обновить» или перезагрузка страницы тянет свежий HTML с CDN.
