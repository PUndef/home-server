# Nextcloud — настройка и обслуживание

Инструкция по предупреждениям из панели **Настройки → Администрирование → Обзор** («Проверка безопасности и параметров»).  
Делай **по одному шагу**, после каждого — блок **Проверить**: убедись, что ничего не сломалось, затем переходи к следующему.

---

## План работ

1. **Сначала бэкапы** — поставить бэкапы на поток (регулярные, с возможностью отката), см. раздел [Бэкапы Nextcloud](#бэкапы-nextcloud) и **Шаг 0** в текущих шагах.
2. **Затем остальные настройки** — Cron, логи, OPcache, почта, 2FA и т.д. Так при любом сбое можно будет откатиться к сохранённому состоянию.

---

## Как пользоваться

1. Выбери один пункт из раздела **Текущие шаги** (по приоритету или по списку). **Первым делом — Шаг 0 (бэкапы).**
2. Выполни только **Сделать** для этого шага.
3. Выполни **Проверить** — убедись, что Nextcloud и сайт работают.
4. Если всё ок — отметь пункт выполненным и перенеси в **Сделано (история)** (или просто отметь галочкой в таблице).
5. Переходи к следующему шагу.

---

## Сделано (история)

Пункты, которые уже выполнены. Оставлены для истории; в текущем плане не повторять.


| Когда      | Что сделано                                                                                                                                               |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| —          | **Удаление PHP 8.2** — `apt purge 'php8.2-*'`, autoremove. Веб Nextcloud работает на **PHP 8.3** (php8.3-fpm); CLI может быть 8.4.                        |
| 2026-03-15 | **Первый ручной бэкап** — app, data, дамп MySQL; пароль БД в `/root/.nextcloud-mysql-backup.cnf`.                                                         |
| 2026-03-15 | **Скрипт бэкапа + cron** — `/usr/local/bin/nextcloud-backup.sh` (tar.gz + gzip), воскресенье 3:00, ротация 3 набора, лог `/var/log/nextcloud-backup.log`. |
| —          | **Cron (фоновые задачи)** — в Nextcloud выбран Cron, в crontab www-data: `occ cron:run` каждые 5 мин; предупреждение в Обзоре исчезло.                    |
| —          | **Ошибки в журнале** — основная масса была из-за отсутствия Imagick; лог очищен (`truncate -s 0` файла лога).                                             |
| —          | **PHP модуль Imagick** — установлен `php8.3-imagick`, перезапущен php8.3-fpm; предупреждение в Обзоре и ошибки theming исчезли.                           |
| —          | **Модуль PHP OPcache** — `opcache.interned_strings_buffer=16` в конфиге PHP 8.3 FPM, перезапущен php8.3-fpm; предупреждение в Обзоре исчезло.             |
| —          | **Сервис AppAPI (Ex-Apps)** — пропущено: не настраивали; Ex-Apps в основном AI, прожорливые. При необходимости — позже.                               |
| —          | **Second factor (2FA)** — пропущено: принудительная 2FA не включена, по желанию.                                                                      |
| —          | **Тестовое письмо (почта)** — пропущено: SMTP не настраивали, пока не нужно.                                                                           |
| —          | **ID сервера конфигурации** — пропущено: один сервер, server_id не нужен.                                                                              |


Детали по удалению PHP 8.2 — в разделе [Справка: удаление старого PHP 8.2](#справка-удаление-старого-php-82-после-перехода-на-84) внизу документа.

---

## Бэкапы Nextcloud — ✅ сделано

По [официальной документации](https://docs.nextcloud.com/server/stable/admin_manual/maintenance/backup.html) и best practices нужно сохранять **четыре вещи**: каталог **config**, каталог **data**, каталог **themes** (если менялся) и **базу данных**. Восстановление возможно только при наличии **и БД, и data** вместе.

**Мало места на диске (например 50 ГБ):** в скрипте (Шаг 0.2) — **сжатие** (tar.gz + gzip) и **раз в неделю, хранить 3 набора** (~3 недели). Ручной бэкап (Шаг 0.1) можно делать без сжатия; автоматический — со сжатием.

### Best practices (кратко)

- Перед бэкапом включать **режим обслуживания** (`maintenance:mode --on`), чтобы не было изменений во время копирования.
- Каталоги — через **rsync -Aavx** (сохраняются атрибуты, симлинки, консистентность).
- БД — дамп с **--single-transaction** (MySQL/MariaDB), чтобы не ломать консистентность.
- Бэкапы делать **регулярно** (cron) и хранить с **ротацией** (например, последние 7 дней или 4 недельных).
- Периодически **проверять восстановление** (тест на копии или после переноса).

Ниже — пошагово: первый ручной бэкап, затем автоматизация.

---

### Шаг 0.1 — Первый ручной бэкап (каталоги + БД) — ✅ сделано

Подставь свои пути и параметры БД. Ниже для установки с **отдельным каталогом данных**: приложение `/var/www/nextcloud`, данные `/var/www/nextcloud-data`; каталог бэкапов — `/backup/nextcloud`. Для БД: тип и параметры из `config/config.php`.

**Сделать:**

1. Создать каталог для бэкапов и включить режим обслуживания:

```bash
sudo mkdir -p /backup/nextcloud
sudo chown www-data:www-data /backup/nextcloud
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
```

1. Бэкап каталогов: приложение (config, код, themes) и отдельный каталог данных.

Если `datadirectory` в `config.php` указывает на `/var/www/nextcloud-data`, бэкапь оба каталога:

```bash
BACKUP_ROOT="/backup/nextcloud"
DATE=$(date +%Y%m%d_%H%M%S)
sudo mkdir -p "$BACKUP_ROOT/app_${DATE}" "$BACKUP_ROOT/data_${DATE}"
sudo rsync -Aavx /var/www/nextcloud/ "$BACKUP_ROOT/app_${DATE}/"
sudo rsync -Aavx /var/www/nextcloud-data/ "$BACKUP_ROOT/data_${DATE}/"
```

Проверить, куда указывает `datadirectory`:  
`sudo grep datadirectory /var/www/nextcloud/config/config.php`  
Если там путь вне `/var/www/nextcloud` — бэкапь оба каталога (app + data), как выше. Если данные внутри nextcloud — один rsync каталога nextcloud.

1. Бэкап базы данных.

**MySQL/MariaDB** (логин/пароль/БД — из `config/config.php`):

```bash
# Если используется utf8mb4 (эмодзи в именах файлов):
sudo mysqldump --single-transaction --default-character-set=utf8mb4 -h localhost -u nextcloud -p nextcloud > "/backup/nextcloud/nextcloud-sqlbkp_$(date +%Y%m%d_%H%M%S).bak"
# Без utf8mb4:
# sudo mysqldump --single-transaction -h localhost -u nextcloud -p nextcloud > "/backup/nextcloud/nextcloud-sqlbkp_$(date +%Y%m%d_%H%M%S).bak"
```

**PostgreSQL:**

```bash
sudo -u postgres PGPASSWORD="пароль" pg_dump nextcloud -h localhost -U nextcloud -f "/backup/nextcloud/nextcloud-sqlbkp_$(date +%Y%m%d_%H%M%S).bak"
```

**SQLite** (файл обычно в `data/owncloud.db`):

```bash
sqlite3 /var/www/nextcloud/data/owncloud.db .dump | sudo tee "/backup/nextcloud/nextcloud-sqlbkp_$(date +%Y%m%d_%H%M%S).bak" > /dev/null
```

1. Выключить режим обслуживания:

```bash
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
```

**Проверить:**

- `ls -la /backup/nextcloud/` — есть каталоги `app_`* и `data_*` (или один `nextcloud-dirbkp_*`, если данные внутри nextcloud) и файл `nextcloud-sqlbkp_*.bak`.
- Nextcloud открывается в браузере, логин работает (`maintenance:mode --off` снял блокировку).

---

### Шаг 0.2 — Скрипт и расписание (поставить на поток) — ✅ сделано

Один скрипт: включает maintenance, бэкапит с **сжатием** (мало места на диске), выключает maintenance, ротирует старые бэкапы. Запуск по cron (например, раз в ночь).

**Экономия места:** каталоги в **tar.gz**, дамп БД в **.bak.gz**. Бэкап по расписанию **раз в неделю** (например, воскресенье 3:00), хранить **последние 3 набора** (~3 недели истории). Так и место экономим, и откат есть. Если нужны частые точки — ставь cron каждый день и уменьши число хранимых (например, 3 дня).

**Сделать:**

1. Создать скрипт (пути и параметры БД замени на свои). Пример для MySQL/MariaDB:

```bash
sudo nano /usr/local/bin/nextcloud-backup.sh
```

Перед скриптом создай файл с паролем БД (только root читает), чтобы не хранить пароль в скрипте:

```bash
sudo bash -c 'cat > /root/.nextcloud-mysql-backup.cnf << EOF
[client]
user=nextcloud
password=ПАРОЛЬ_ИЗ_config.php
host=localhost
EOF'
sudo chmod 600 /root/.nextcloud-mysql-backup.cnf
```

Содержимое скрипта (сжатие: tar.gz + gzip для БД; ротация 3 дня для экономии места):

```bash
#!/bin/bash
set -e
NC_PATH="/var/www/nextcloud"
NC_DATA="/var/www/nextcloud-data"
BACKUP_ROOT="/backup/nextcloud"
MYSQL_CNF="/root/.nextcloud-mysql-backup.cnf"
DATE=$(date +%Y%m%d_%H%M%S)
APP_BKP="${BACKUP_ROOT}/app_${DATE}.tar.gz"
DATA_BKP="${BACKUP_ROOT}/data_${DATE}.tar.gz"
SQL_BKP="${BACKUP_ROOT}/nextcloud-sqlbkp_${DATE}.bak.gz"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== Nextcloud backup start ==="

log "Enabling maintenance mode..."
sudo -u www-data php "$NC_PATH/occ" maintenance:mode --on
log "Maintenance on."

log "Backing up app (tar.gz)..."
tar czf "$APP_BKP" -C /var/www nextcloud
log "App backup done: $(du -h "$APP_BKP" | cut -f1)"

log "Backing up data (tar.gz)..."
tar czf "$DATA_BKP" -C /var/www nextcloud-data
log "Data backup done: $(du -h "$DATA_BKP" | cut -f1)"

log "Dumping database (gzip)..."
mysqldump --defaults-extra-file="$MYSQL_CNF" --single-transaction --default-character-set=utf8mb4 nextcloud | gzip > "$SQL_BKP"
log "Database dump done: $(du -h "$SQL_BKP" | cut -f1)"

log "Disabling maintenance mode..."
sudo -u www-data php "$NC_PATH/occ" maintenance:mode --off
log "Maintenance off."

log "Rotating old backups (keep last ~3 weeks)..."
find "$BACKUP_ROOT" -maxdepth 1 -name 'app_*.tar.gz' -type f -mtime +21 -delete
find "$BACKUP_ROOT" -maxdepth 1 -name 'data_*.tar.gz' -type f -mtime +21 -delete
find "$BACKUP_ROOT" -maxdepth 1 -name 'nextcloud-sqlbkp_*.bak.gz' -type f -mtime +21 -delete
log "Rotation done."

log "=== Nextcloud backup finished ==="
```

Сделать скрипт исполняемым и при необходимости ограничить доступ (пароль БД не светить):

```bash
sudo chmod +x /usr/local/bin/nextcloud-backup.sh
```

1. Добавить в cron **раз в неделю** (воскресенье 3:00):

```bash
sudo crontab -e
```

Строка:

```
0 3 * * 0 /usr/local/bin/nextcloud-backup.sh >> /var/log/nextcloud-backup.log 2>&1
```

(Формат: минута час день_месяца месяц день_недели; `0` = воскресенье.) Если нужен ежедневный бэкап — замени `0 3 * * 0` на `0 3 * * *` и в скрипте поменяй ротацию на `-mtime +3` (хранить 3 дня).

При использовании PostgreSQL или SQLite замени в скрипте блок дампа на соответствующие команды из Шага 0.1.

**Проверить:**

- Запустить скрипт вручную: `sudo /usr/local/bin/nextcloud-backup.sh`.
- В `/backup/nextcloud/` должны появиться `app_*.tar.gz`, `data_*.tar.gz` и `nextcloud-sqlbkp_*.bak.gz`; Nextcloud снова доступен после скрипта.
- Через день проверить лог: `cat /var/log/nextcloud-backup.log` (при необходимости: `sudo touch /var/log/nextcloud-backup.log`).

---

### Справка: восстановление из бэкапа

1. Остановить веб-сервер / PHP-FPM при необходимости или включить `maintenance:mode --on`.
2. **Восстановить каталоги** (подставь нужную дату из имени бэкапа).
  - **Если бэкап в виде tar.gz** (как делает скрипт со сжатием):
    - Приложение: `cd /var/www && sudo tar xzf /backup/nextcloud/app_YYYYMMDD_HHMMSS.tar.gz`
    - Данные: `cd /var/www && sudo tar xzf /backup/nextcloud/data_YYYYMMDD_HHMMSS.tar.gz`
  - **Если бэкап в виде каталогов** (ручной rsync):  
    - Приложение: `rsync -Aax /backup/nextcloud/app_YYYYMMDD_HHMMSS/ /var/www/nextcloud/`  
    - Данные: `rsync -Aax /backup/nextcloud/data_YYYYMMDD_HHMMSS/ /var/www/nextcloud-data/`
3. **БД:** удалить и заново создать базу, затем импорт (см. [официальный Restore](https://docs.nextcloud.com/server/stable/admin_manual/maintenance/restore.html)):
  - MySQL: `DROP DATABASE nextcloud;` затем `CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;`
  - **Если дамп сжат (.bak.gz):** `zcat /backup/nextcloud/nextcloud-sqlbkp_YYYYMMDD.bak.gz | mysql -h localhost -u nextcloud -p nextcloud`
  - Если дамп без сжатия (.bak): `mysql -h localhost -u nextcloud -p nextcloud < nextcloud-sqlbkp_YYYYMMDD.bak`
4. Права: `sudo chown -R www-data:www-data /var/www/nextcloud /var/www/nextcloud-data`
5. Выключить режим обслуживания: `occ maintenance:mode --off`
6. Если бэкап старый и клиенты новее — после восстановления:
  `sudo -u www-data php occ maintenance:data-fingerprint`  
   (чтобы клиенты могли подтянуть недостающие файлы).

---

## Проверка безопасности и параметров (панель админа)

В **Настройки → Администрирование → Обзор** Nextcloud показывает блок «Проверка безопасности и параметры»: предупреждения о конфигурации, журнале, PHP, почте и т.д. Ниже — соответствие между тем, что видно в панели, и шагами в этом документе (что сделать и где искать инструкцию).


| Что показывается в панели               | Куда смотреть в документе                                        | Статус |
| --------------------------------------- | ---------------------------------------------------------------- | ------ |
| Ошибки в журнале (N записей)            | [Шаг 2. Ошибки в журнале](#шаг-2-ошибки-в-журнале)               | ✅      |
| Модуль PHP OPcache (буфер строк выше 8) | [Шаг 3. Модуль PHP OPcache](#шаг-3-модуль-php-opcache)           | ✅      |
| Сервис развертывания AppAPI (Ex-Apps)   | [Шаг 4. Сервис AppAPI](#шаг-4-сервис-appapi-ex-apps)             | пропущено |
| Second factor (2FA не принудительная)   | [Шаг 5. Second factor (2FA)](#шаг-5-second-factor-2fa)           | пропущено |
| Тестовое письмо (почта не настроена)    | [Шаг 6. Тестовое письмо](#шаг-6-тестовое-письмо-почта)           | пропущено |
| ID сервера конфигурации                 | [Шаг 7. ID сервера конфигурации](#шаг-7-id-сервера-конфигурации) | пропущено |
| PHP модуль Imagick (favicon)            | [Шаг 8. PHP модуль Imagick](#шаг-8-php-модуль-imagick)           | ✅      |


Если в обзоре ещё есть «Последний запуск Cron» — см. [Шаг 1. Cron](#шаг-1-cron-фоновые-задачи).  
По мере исправления отмечай (✅) в колонке «Статус» или в [краткой шпаргалке](#краткая-шпаргалка-по-предупреждениям).

---

## Текущие шаги

Каждый пункт — один шаг. После выполнения обязательно пройти **Проверить**. Сначала — [Шаг 0 (бэкапы)](#шаг-0-бэкапы-поставить-на-поток--сделано), затем пункты из [проверки безопасности и параметров](#проверка-безопасности-и-параметров-панель-админа) выше.

---

### Шаг 0. Бэкапы (поставить на поток) — ✅ сделано

**Цель:** иметь регулярные бэкапы (config, data, themes, БД), чтобы перед остальными настройками можно было спокойно откатиться при сбое.

**Сделано:** ручной бэкап (Шаг 0.1), скрипт со сжатием + cron по воскресеньям 3:00, ротация 3 набора. См. [Сделано (история)](#сделано-история).

**Проверить (уже пройдено):** в `/backup/nextcloud/` есть `app_*.tar.gz`, `data_*.tar.gz`, `nextcloud-sqlbkp_*.bak.gz`; скрипт отрабатывает; в cron запись есть (`sudo crontab -l`).

---

### Шаг 1. Cron (фоновые задачи) — ✅ сделано

**Симптом:** «Последняя фоновая задача была выполнена в X часов назад. Check the background job settings.»

**Сделано:** выбран Cron в Nextcloud, в crontab добавлен `occ cron:run` каждые 5 мин. Предупреждение в Обзоре не показывается.

**Сделать (если понадобится на другом сервере):**

- В Nextcloud: **Настройки → Основные** → блок «Фоновая задача» → выбрать **Cron** (не AJAX).
- На сервере настроить cron (путь к Nextcloud замени на свой):

```bash
sudo -u www-data crontab -e
```

Добавить строку:

```
*/5 * * * * php -f /var/www/nextcloud/occ cron:run
```

Либо через root: `sudo crontab -e` и строка:

```
*/5 * * * * www-data php -f /var/www/nextcloud/occ cron:run
```

**Проверить:**

- Подождать до 5 минут, обновить **Настройки → Обзор** — «Последний запуск Cron» должен показывать недавнее время (например, «несколько секунд назад»).
- Убедиться, что сайт открывается, логин работает.

---

### Шаг 2. Ошибки в журнале — ✅ сделано

**Симптом:** «N записей об ошибках в журнале».

**Сделано:** основная масса ошибок была из-за отсутствия Imagick (theming); установлен php8.3-imagick. Лог очищен (`truncate -s 0` файла лога), плашка в Обзоре исчезла.

**Сделать (если понадобится снова):**

- **Настройки → Администрирование → Логирование** — просмотреть ошибки, устранить повторяющиеся (пути, права, модули).
- При необходимости включить логи в `config/config.php`:

```php
'log_type' => 'file',
'logfile' => '/var/www/nextcloud/data/nextcloud.log',
'loglevel' => 2,
```

**Проверить:**

- Страница Nextcloud открывается, нет новых критичных ошибок в логах после изменений.
- Если правил `config.php` — перезагрузка страницы и проверка, что логи пишутся.

---

### Шаг 3. Модуль PHP OPcache — ✅ сделано

**Симптом:** «Буфер встроенных строк OPcache почти заполнен… opcache.interned_strings_buffer выше, чем 8».

**Сделано:** в конфиге PHP 8.3 FPM задано `opcache.interned_strings_buffer=16`, перезапущен php8.3-fpm.

**Сделать (если понадобится на другом сервере):**

Найти конфиг opcache (для веб используется PHP 8.3):

```bash
php --ini
grep -r opcache /etc/php/8.3/
```

Создать/отредактировать файл, например `/etc/php/8.3/fpm/conf.d/10-opcache.ini`:

```ini
opcache.enable=1
opcache.interned_strings_buffer=16
opcache.memory_consumption=256
opcache.max_accelerated_files=20000
opcache.revalidate_freq=60
```

Перезапуск PHP-FPM (8.3):

```bash
sudo systemctl restart php8.3-fpm
```

**Проверить:**

- `sudo systemctl status php8.3-fpm` — сервис в состоянии `active (running)`.
- Открыть Nextcloud в браузере — страница загружается.
- **Настройки → Обзор** — предупреждение по OPcache должно исчезнуть (или обновить страницу через минуту).

---

### Шаг 4. Сервис AppAPI (Ex-Apps) — пропущено

**Симптом:** «Служба развертывания AppAPI по умолчанию не установлена».

**Сделано:** пропущено. Ex-Apps в основном AI, требовательны к ресурсам; при необходимости настроить позже (HaRP или Docker Socket Proxy).

**Сделать (если понадобится позже):**

Нужно только если планируешь ставить приложения через Ex-Apps. В **Настройки → Администрирование** найти раздел AppAPI / Ex-Apps и зарегистрировать службу развертывания по инструкции Nextcloud. Если Ex-Apps не используешь — шаг можно пропустить.

**Проверить:**

- Если ничего не настраивал — просто убедиться, что остальные функции работают.
- Если настраивал — проверить, что установка Ex-Apps (если есть) работает.

---

### Шаг 5. Second factor (2FA) — пропущено

**Симптом:** «Second factor providers are available but two-factor authentication is not enforced.»

**Сделано:** пропущено; принудительная 2FA не включена.

**Сделать (если понадобится позже):**

Решение по политике: **Настройки → Безопасность** — включить принудительную 2FA для нужных групп (например, для админов) или осознанно оставить необязательной.

**Проверить:**

- Вход под учёткой с 2FA и без — в зависимости от выбранной политики всё должно работать как задумано.

---

### Шаг 6. Тестовое письмо (почта) — пропущено

**Симптом:** «Параметры сервера электронной почты ещё не заданы или не проверены.»

**Сделано:** пропущено; SMTP не настраивали.

**Сделать (если понадобится позже):**

**Настройки → Основные** — указать SMTP (хост, порт, пользователь, пароль), нажать «Отправить сообщение». Если почта не нужна — шаг пропустить.

**Проверить:**

- При настройке: тестовое письмо пришло, в интерфейсе нет ошибки.
- Сайт и логин работают как прежде.

---

### Шаг 7. ID сервера конфигурации — пропущено

**Симптом:** «Server identifier isn’t configured.»

**Сделано:** пропущено; один сервер, server_id не нужен.

**Сделать (если понадобится при нескольких серверах):**

Нужно в основном при нескольких PHP-серверах. На одной VM по желанию добавить в `config/config.php`:

```php
'server_id' => 'nc-vm-01',
```

Любая уникальная строка.

**Проверить:**

- Nextcloud открывается, в **Обзор** предупреждение про server_id исчезает (или остаётся, если не добавлял — не критично).

---

### Шаг 8. PHP модуль Imagick — ✅ сделано

**Симптом:** «Для создания значка favicon… необходим модуль imagic».

**Сделано:** установлен `php8.3-imagick`, перезапущен php8.3-fpm; предупреждение в Обзоре исчезло.

**Сделать (если понадобится на другом сервере):**

```bash
sudo apt update
sudo apt install -y php8.3-imagick
sudo systemctl restart php8.3-fpm
```

**Проверить:**

- `php8.3 -m | grep -i imagick` — выводит `imagick`.
- `sudo systemctl status php8.3-fpm` — `active (running)`.
- Открыть Nextcloud — страница загружается; в **Обзор** предупреждение про Imagick исчезнет.

---

## Краткая шпаргалка по предупреждениям


| Предупреждение / Задача | Действие                                                                  | Статус |
| ----------------------- | ------------------------------------------------------------------------- | ------ |
| **Бэкапы**              | Ручной бэкап + скрипт + cron (воскресенье 3:00), сжатие, ротация 3 набора | ✅      |
| Cron                    | Настроить cron для `occ cron:run` каждые 5 мин                            | ✅      |
| Ошибки в журнале        | Разобрать логи, исправить причины; при необходимости очистить лог         | ✅      |
| OPcache                 | `opcache.interned_strings_buffer` = 16+, перезапуск PHP-FPM               | ✅      |
| AppAPI / Ex-Apps        | Настроить только при использовании Ex-Apps (пропущено: AI прожорливые)    | пропущено |
| 2FA                     | Включить принудительную 2FA по желанию (пропущено)                        | пропущено |
| Тестовое письмо         | Настроить SMTP и отправить тест (пропущено)                               | пропущено |
| Server ID               | Добавить `server_id` в config при нескольких серверах (пропущено: один)   | пропущено |
| Imagick                 | Установить `php8.3-imagick`, перезапустить php8.3-fpm                     | ✅      |


По мере выполнения отмечай (✅) в колонке «Статус».

---

## Справка: требования к PHP

- **Nextcloud 34+** официально требует **PHP 8.4** (8.2 не поддерживается). В данном экземпляре веб работает на **PHP 8.3** (php8.3-fpm) — оставлено по выбору.
- Проверка: в браузере **Настройки → Обзор** (версия PHP для веб); в консоли `php -v` (CLI) и `php8.3 -v` (версия FPM).

---

## Справка: удаление старого PHP 8.2

*(Уже выполнено — см. «Сделано (история)». Ниже — для справки.)*

1. Убедиться, что веб на нужной версии (8.3): Nextcloud в браузере → Обзор, `systemctl status php8.3-fpm`.
2. Удалить пакеты: `sudo apt purge 'php8.2-*'` (или перечислить пакеты из `dpkg -l | grep php8.2`).
3. Почистить: `sudo apt autoremove -y && sudo apt autoclean`.
4. Проверить: `dpkg -l | grep php8.2` — пусто; Nextcloud в браузере работает.

---

## Версии и обновления

- Перед обновлением до Nextcloud 34 — перейти на PHP 8.4.
- Перед крупным обновлением: сделать полный бэкап по разделу [Бэкапы Nextcloud](#бэкапы-nextcloud) (config, data, themes, БД).

---

*См. также: [onlyoffice-nextcloud-setup.md](onlyoffice-nextcloud-setup.md) — интеграция ONLYOFFICE с Nextcloud.*