# Requiem Helper

Небольшой статический помощник для подбора Requiem-порядка у Kuva Lich / Sister of Parvos.

Стек — Vite + React + shadcn (`base: "./"`). Общая схема — [`../README.md`](../README.md).

## Локальная разработка

```powershell
cd static-sites\requiem
npm ci
npm run dev
```

Production-сборка:

```powershell
npm run build
```

## Деплой

```powershell
.\static-sites\requiem\scripts\deploy.ps1
```

- URL: `http://requiem.home/` · `http://192.168.50.35/requiem/` · `https://apps-pundef.mooo.com/requiem/`
- На LXC: `/srv/static-sites/requiem`

## Как пользоваться

1. Смотри верхний блок `Маршрут убийства лича`: он показывает, что уже сделано, что делать сейчас и что будет следующим.
2. Пока не открыт ни один Requiem, фарми миссии лича и добивай thralls через Mercy.
3. Если сам лич пришёл до первого открытого Requiem, не делай Mercy: положи его 3 раза, чтобы он ушёл без сброса rage.
4. Когда открылся первый Requiem, отметь его в интерфейсе и укажи, есть ли `Oull`.
5. Первый осмысленный порядок обычно такой: `первый мод / Oull / любой`.
6. После первой проверки снова фарми thralls, пока не откроется второй Requiem.
7. После stab добавь попытку и укажи результат каждого проверенного слота:
   - `верный / белый` — слот прошёл.
   - `неверный / красный` — слот не прошёл.
   - `не проверялся` — игра не дошла до этого слота.
8. После этого helper предложит следующий порядок.

Массовые сбросы и удаление попыток спрашивают подтверждение.

## Favicon

`scripts/make-favicon.py` собирает `favicon.ico` и `apple-touch-icon.png` из `Oull.webp`.
