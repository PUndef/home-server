# Relics Helper

Статический помощник для поиска выгодных миссий под фарм ресурса, релика или мода по [официальному списку PC Drops](https://warframe-web-assets.nyc3.cdn.digitaloceanspaces.com/uploads/cms/hnfvc0o3jnfvc873njb03enrf56.html).

Стек и деплой — как у `requiem-helper` (Vite + React, `base: "./"`, Caddy path `/relics/`).

## Локальная разработка

```powershell
cd relics-helper
npm ci
npm run dev
```

В dev запросы идут через прокси `/drops-source` → CDN (см. `vite.config.ts`).

## Сборка

```powershell
npm run sync-drops   # опционально: копия HTML в public/drops.html (fallback ~4 МБ)
npm run build
```

При открытии сайта данные загружаются с CDN; при ошибке CORS — из `drops.html` или `localStorage`.

## Деплой на static-sites LXC

Маршрут уже описан в `static-sites/Caddyfile`:

- URL: `http://192.168.50.35/relics/` или `https://apps-pundef.mooo.com/relics/`
- Корень на LXC: `/srv/static-sites/relics`

```bash
mkdir -p /srv/static-sites/relics
```

```powershell
.\relics-helper\scripts\deploy.ps1
```

## Обновление данных

Кнопка «Обновить данные» или перезагрузка страницы тянет свежий HTML с CDN. После патча Warframe список DE обновится сам.

## Рейтинг

`(шанс % / 100) × количество ÷ оценочные минуты` — эвристика по типу миссии и ротации A/B/C. Настройка весов: `src/lib/mission-speed.ts`.
