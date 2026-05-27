# Warframe Hub

Разводящая страница с карточками для локальных Warframe-инструментов.

Стек — Vite + React + shadcn (`base: "./"`). Общая схема — [`../README.md`](../README.md).

## Локальная разработка

```powershell
cd static-sites\warframe
npm ci
npm run dev
```

## Деплой

```powershell
.\static-sites\warframe\scripts\deploy.ps1
```

- URL: `http://warframe.home/` · `http://192.168.50.35/warframe/` · `https://apps-pundef.mooo.com/warframe/`
- На LXC: `/srv/static-sites/warframe`
