# ONLYOFFICE на одной VM с Nextcloud — пошагово

Контекст из предыдущего чата: VM в Proxmox с Nextcloud (рекомендуется **6 GiB RAM**, 2–4 vCPU). Порт 80 занят Nextcloud, ONLYOFFICE поднимаем на порту **9980**, слушаем только localhost.

**Сделано:** шаги 1–9, интеграция по HTTPS, превью только для картинок и видео (офисные — иконки).

---

## Сделано (история)

Пункты, которые уже выполнены. Оставлены для истории; в текущем плане не повторять.

| Когда      | Что сделано |
| ---------- | ----------- |
| 2026-03-15 | **Шаги 1–5:** обновление системы, Docker (Debian), каталоги ONLYOFFICE, JWT, запуск контейнера на 127.0.0.1:9980. |
| 2026-03-15 | **Шаги 6–9:** проверка контейнера, включение приложения ONLYOFFICE в Nextcloud, настройка адреса и JWT, проверка открытия файлов. |
| 2026-03-15 | **Интеграция по HTTPS:** Apache — прокси `/onlyoffice-docs/` (HTTP + WebSocket) и `/cache/files/` на Document Server; `RequestHeader set X-Forwarded-Proto "https"`; в Nextcloud — overwrite.cli.url, overwriteprotocol, storageUrl (occ), адрес ONLYOFFICE `https://домен/onlyoffice-docs`, внутренние адреса (127.0.0.1:9980 и https-домен). Открытие и редактирование .docx/.xlsx работает. |
| 2026-03-15 | **Превью:** отключена опция «Использовать ONLYOFFICE для создания превью документа» в настройках ONLYOFFICE; в `/var/www/nextcloud/config/config.php` задан `enabledPreviewProviders` (PNG, JPEG, GIF, BMP, SVG, HEIC, TXT, Movie, MP4, MOV). Для офисных файлов — иконки, для изображений и видео — превью. |

---

## Шаг 1. Подключиться к VM и обновить систему — ✅ сделано

```bash
sudo apt update && sudo apt upgrade -y
```

---

## Шаг 2. Установить Docker (если ещё не стоит) — ✅ сделано

Проверка:

```bash
docker --version
```

Если Docker нет — установка. **Важно:** для **Debian** — репозиторий `debian`, для **Ubuntu** — `ubuntu`. Иначе будет ошибка «Release file does not exist».

**Debian** (в т.ч. TurnKey на базе Debian):

```bash
sudo apt install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo systemctl enable docker && sudo systemctl start docker
```

**Ubuntu:**

```bash
sudo apt install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo systemctl enable docker && sudo systemctl start docker
```

---

## Шаг 3. Каталоги для данных ONLYOFFICE — ✅ сделано

```bash
sudo mkdir -p /app/onlyoffice/DocumentServer/{data,logs,lib,db}
sudo chown -R 104:107 /app/onlyoffice/DocumentServer/
```

---

## Шаг 4. JWT-секрет — ✅ сделано

Один и тот же ключ потом прописать в Nextcloud:

```bash
openssl rand -hex 32
```

Сохрани вывод — это `JWT_SECRET`.

---

## Шаг 5. Запуск ONLYOFFICE Document Server — ✅ сделано

Подставь свой `JWT_SECRET` вместо `ТВОЙ_JWT_SECRET`:

```bash
sudo docker run -i -t -d \
  --restart=always \
  -p 127.0.0.1:9980:80 \
  -e JWT_SECRET="ТВОЙ_JWT_SECRET" \
  -v /app/onlyoffice/DocumentServer/logs:/var/log/onlyoffice \
  -v /app/onlyoffice/DocumentServer/data:/var/www/onlyoffice/Data \
  -v /app/onlyoffice/DocumentServer/lib:/var/lib/onlyoffice \
  -v /app/onlyoffice/DocumentServer/db:/var/lib/postgresql \
  --name onlyoffice-documentserver \
  onlyoffice/documentserver
```

Если Nextcloud на **HTTPS с самоподписанным сертификатом**, добавь переменную:

```bash
-e USE_UNAUTHORIZED_STORAGE=true \
```

(в той же команде `docker run`).

---

## Шаг 6. Проверка контейнера — ✅ сделано

```bash
sudo docker ps
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9980/healthcheck
```

Ожидается `200`.

---

## Шаг 7. Приложение ONLYOFFICE в Nextcloud — ✅ сделано

1. Вход под админом → **Приложения** (Apps).
2. Поиск **ONLYOFFICE** → категория «Офис и текст» → **Включить**.

---

## Шаг 8. Настройка в Nextcloud — ✅ сделано

**Настройки** → **Администрирование** → **ONLYOFFICE**:

- **Адрес документального сервера:** `http://127.0.0.1:9980`
- **Секретный ключ (JWT):** тот же `JWT_SECRET`, что в контейнере.

Сохранить.

---

## Шаг 9. Проверка — ✅ сделано

Создать или открыть .docx / .xlsx в Nextcloud → «Редактировать» — должен открыться редактор ONLYOFFICE.

---

## Apache: прокси HTTPS и кэш (пример)

Внутри блока `<VirtualHost *:443>` для домена Nextcloud (комментарии в конфиге — на английском, см. правило):

```apache
    RequestHeader set X-Forwarded-Proto "https"

    # ONLYOFFICE Document Server (HTTP + WebSocket)
    ProxyPreserveHost On
    ProxyPass /onlyoffice-docs/ http://127.0.0.1:9980/ upgrade=websocket
    ProxyPassReverse /onlyoffice-docs/ http://127.0.0.1:9980/

    # Editor cache (Editor.bin); client requests /cache/files/ on Nextcloud domain
    ProxyPass /cache/files/ http://127.0.0.1:9980/cache/files/
    ProxyPassReverse /cache/files/ http://127.0.0.1:9980/cache/files/
```

---

## Показывать иконки типов файлов вместо превью

Если в списке файлов .docx/.xlsx выглядят как размытые прямоугольники — это **превью** (миниатюры), а не сломанные иконки. Чтобы для офисных показывались иконки, а для картинок и видео оставались превью — см. вариант 2 ниже.

**Вариант 1: отключить все превью** — везде будут иконки (и для картинок тоже).

В `config/config.php` в массив `$CONFIG` добавить:

```php
  'enable_previews' => false,
```

**Вариант 2: превью только для картинок и видео** — для docx/xlsx/pdf иконки, для изображений и видео — превью. Два действия: (1) отключить превью в приложении ONLYOFFICE (оно регистрирует свой провайдер для офисных файлов); (2) в конфиге разрешить превью и явно задать только нужные провайдеры.

1. **Настройки ONLYOFFICE:** Настройки → Администрирование → ONLYOFFICE → в блоке «Дополнительные настройки» или в разделе приложения найти опцию вроде «Генерировать превью для документов» / «Preview» и **выключить** её. Сохранить.

2. **Конфиг Nextcloud** — файл **`/var/www/nextcloud/config/config.php`**. Убедиться, что нет `'enable_previews' => false` (удалить или закомментировать). Добавить или оставить только список провайдеров для изображений и видео:

```php
  'enabledPreviewProviders' => [
    'OC\Preview\PNG',
    'OC\Preview\JPEG',
    'OC\Preview\GIF',
    'OC\Preview\BMP',
    'OC\Preview\SVG',
    'OC\Preview\HEIC',
    'OC\Preview\TXT',
    'OC\Preview\Movie',
    'OC\Preview\MP4',
    'OC\Preview\MOV',
  ],
```

Для видео превью нужен ffmpeg на сервере. Сохранить, перезапустить PHP-FPM. Удалить старые превью (опционально):

```bash
sudo -u www-data php /var/www/nextcloud/occ preview:cleanup
```

Обновить страницу «Файлы» (Ctrl+F5). Документация: [Previews configuration](https://docs.nextcloud.com/server/stable/admin_manual/configuration_files/previews_configuration.html).

---

## sidebar-tab.css отдаётся как HTML

Ошибка в консоли: `Refused to apply style from '.../apps/files_versions/css/sidebar-tab.css' because its MIME type ('text/html')`. По этому URL приходит HTML (логин или 404), а не CSS. Путь относится к встроенной части Nextcloud (вкладка «Версии» в боковой панели файлов), отдельного приложения «История версий» в списке приложений может не быть.

**Проверить по шагам:**

1. **Файл на диске** — есть ли он вообще:
   ```bash
   ls -la /var/www/nextcloud/apps/files_versions/css/sidebar-tab.css
   ```
   Каталог `files_versions` входит в ядро Nextcloud (или в «Файлы»), отдельным приложением в списке он может не значиться. **Если каталога `css` и файла нет** — в новых версиях этот CSS убрали (миграция на Vue), но фронт или кэш всё ещё запрашивает старый URL. Создать пустой файл, чтобы запрос возвращал CSS, а не 404/HTML:
   ```bash
   sudo mkdir -p /var/www/nextcloud/apps/files_versions/css
   echo '/* placeholder: sidebar-tab.css removed in Vue migration */' | sudo tee /var/www/nextcloud/apps/files_versions/css/sidebar-tab.css
   sudo chown www-data:www-data /var/www/nextcloud/apps/files_versions/css/sidebar-tab.css
   ```
   После этого обновить страницу (Ctrl+F5). Ошибка в консоли должна пропасть.

2. **.htaccess и маршрутизация** — запросы к `/apps/...` должны уходить в `index.php`. Обновить .htaccess:
   ```bash
   sudo -u www-data php /var/www/nextcloud/occ maintenance:update-htaccess
   ```
   В конфиге Apache для Nextcloud должно быть `AllowOverride All` в `<Directory>`, чтобы .htaccess применялся.

3. **Открыть URL в браузере** — в новой вкладке открыть `https://cloud-pundef.mooo.com/apps/files_versions/css/sidebar-tab.css`. Если видишь страницу входа или «Not found» — запрос не доходит до раздачи статики приложения (редирект на логин или 404). Тогда проверить `overwrite.cli.url` и `overwriteprotocol` в config.php; при необходимости задать `default_language` и сбросить кэш: `occ maintenance:repair` и жёсткое обновление страницы (Ctrl+F5).

4. **Версия Nextcloud** — в старых версиях бывали баги с путями к CSS приложений; обновление до актуальной ветки иногда снимает проблему.

---

## Шпаргалка


| Что               | Значение                                                     |
| ----------------- | ------------------------------------------------------------ |
| Порт ONLYOFFICE   | 9980 (только localhost)                                      |
| URL для Nextcloud | `http://127.0.0.1:9980`                                      |
| JWT               | Один ключ в контейнере и в настройках ONLYOFFICE в Nextcloud |
| Данные контейнера | `/app/onlyoffice/DocumentServer/`                            |


---

## Ресурсы (из предыдущего чата)

- **Только Nextcloud:** 2 GiB RAM достаточно для лёгкой нагрузки.
- **Nextcloud + ONLYOFFICE на одной VM:** минимум **4 GiB**, комфортно **6 GiB** RAM.
- ONLYOFFICE Community — бесплатно, до 20 одновременных подключений.

