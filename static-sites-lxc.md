# Static-sites LXC — хостинг маленьких фронтов

Инструкция для отдельного лёгкого LXC `static-sites`, который отдаёт собранную статику через Caddy. Первый целевой сайт — `requiem-helper`, но схема рассчитана на несколько маленьких сайтов.

Делай по одному шагу. После каждого шага выполни блок **Проверить** и только потом переходи дальше.

---

## Схема

```text
Windows / Git repo
  -> npm run build (Vite, base: "./", относительные пути)
  -> requiem-helper/scripts/deploy.ps1 (tar + scp + remote untar)
  -> static-sites LXC:/srv/static-sites/requiem
  -> Caddy на :80, path-based: /requiem/* -> /srv/static-sites/requiem
       <- локально:  http://requiem.home/      (split-horizon DNS на OpenWrt)
                    или http://192.168.50.35/requiem/
       <- снаружи:   https://apps-pundef.mooo.com/requiem/
                    Internet -> router DNAT 443 -> nextcloud-vm Apache
                    Apache vhost ServerName apps-pundef.mooo.com
                      -> ProxyPass / http://192.168.50.35/
```

Фактические параметры:


| Параметр           | Значение                                                                  |
| ------------------ | ------------------------------------------------------------------------- |
| VMID               | `102`                                                                     |
| Контейнер          | `static-sites`                                                            |
| Тип                | Debian 13 LXC, unprivileged                                               |
| Template           | `local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst`                    |
| Storage            | `local-lvm:8`                                                             |
| Сеть               | `vmbr0`, `srv` (`192.168.50.0/24`), `192.168.50.35/24`, gw `192.168.50.1` |
| Web server         | Caddy v2 (из `dl.cloudsmith.io/public/caddy/stable`)                      |
| Локальный hostname | `requiem.home`                                                            |
| Внешний hostname   | `apps-pundef.mooo.com` (FreeDNS, A → белый IP)                            |
| Внешний URL        | `https://apps-pundef.mooo.com/requiem/`                                   |
| Edge HTTPS         | Apache на `nextcloud-vm` (`192.168.50.34`), LE на `apps-pundef.mooo.com`  |
| Корень сайта       | `/srv/static-sites/requiem`                                               |
| Deploy user        | `deploy` (uid 1000), ключ `~/.ssh/proxmox_pundef_nopass`                  |
| Deploy команда     | `requiem-helper/scripts/deploy.ps1`                                       |


---

## Текущие шаги

Все шаги ниже отмечены ✅ — это то, что реально сделано в инфраструктуре. Команды оставлены, чтобы можно было воспроизвести при пересборке.

### Шаг 1. Создать LXC `static-sites` — ✅ сделано

**Сделать:**

1. На Proxmox убедиться, что нужный Debian template есть, и при необходимости скачать:

```bash
pveam update
pveam list local | grep debian
# при необходимости:
# pveam download local debian-13-standard_13.1-2_amd64.tar.zst
```

1. Положить нужный public key (например `cursor-agent@home-server-repo`) в файл `/tmp/static-sites/keys.pub` на Proxmox-хосте, чтобы скормить его LXC при создании:

```bash
mkdir -p /tmp/static-sites
cat /root/.ssh/authorized_keys > /tmp/static-sites/keys.pub
```

1. Создать LXC:

```bash
pct create 102 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname static-sites \
  --cores 1 \
  --memory 512 \
  --swap 256 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.50.35/24,gw=192.168.50.1 \
  --nameserver 192.168.50.1 \
  --unprivileged 1 \
  --features nesting=1 \
  --onboot 1 \
  --ssh-public-keys /tmp/static-sites/keys.pub \
  --start 1
```

**Проверить:**

```bash
pct status 102
pct exec 102 -- ip -4 addr show eth0
pct exec 102 -- ping -c 2 -W 1 1.1.1.1
```

Ожидаемо: `status: running`, `eth0` имеет `192.168.50.35/24`, ping наружу работает.

---

### Шаг 2. Установить Caddy и системные пакеты — ✅ сделано

**Сделать:**

```bash
pct exec 102 -- bash -lc '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl gnupg debian-keyring debian-archive-keyring \
  apt-transport-https rsync ca-certificates openssh-server sudo
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
  > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -qq
apt-get install -y -qq caddy
'
```

**Проверить:**

```bash
pct exec 102 -- caddy version
pct exec 102 -- systemctl is-active caddy
```

Ожидаемо: версия `v2.x.x`, статус `active`.

---

### Шаг 3. Настроить Caddy и каталог сайта — ✅ сделано

**Сделать:**

Записать `/etc/caddy/Caddyfile`. Удобнее всего собрать локальный файл и залить через `pct push`:

```caddy
{
	auto_https off
}

# Локальный hostname — отдаёт сайт сразу с корня.
http://requiem.home {
	root * /srv/static-sites/requiem
	try_files {path} /index.html
	encode zstd gzip
	file_server
}

# Path-based edge: реквест приходит либо напрямую по IP, либо
# проксируется от Nextcloud Apache как https://apps-pundef.mooo.com/requiem/.
# Каждый новый сайт = новый handle_path /<name>/* блок.
http://apps-pundef.mooo.com, http://192.168.50.35, http://localhost {
	redir /requiem /requiem/ 301

	handle_path /requiem/* {
		root * /srv/static-sites/requiem
		try_files {path} /index.html
		encode zstd gzip
		file_server
	}

	handle / {
		redir /requiem/ 302
	}

	handle {
		respond "404 - unknown app" 404
	}
}
```

```bash
pct push 102 ./Caddyfile /etc/caddy/Caddyfile
pct exec 102 -- bash -lc '
set -e
mkdir -p /srv/static-sites/requiem
caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile
systemctl reload caddy
'
```

> `auto_https off` важен: иначе Caddy попытается выпустить TLS-сертификат для `requiem.home`, что без внешнего DNS невозможно. Локально работаем только по `http://`.

**Проверить:**

```bash
pct exec 102 -- curl -fsS -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1/
pct exec 102 -- curl -fsS -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: requiem.home' http://127.0.0.1/
```

Ожидаемо: `HTTP 200` (default Caddy welcome или index сайта).

---

### Шаг 4. Создать deploy-пользователя — ✅ сделано

**Сделать:**

```bash
pct push 102 /tmp/static-sites/keys.pub /tmp/deploy-keys.pub
pct exec 102 -- bash -lc '
set -e
id deploy >/dev/null 2>&1 || adduser --disabled-password --gecos "" deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
install -m 600 -o deploy -g deploy /tmp/deploy-keys.pub /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /srv/static-sites
'
```

**Проверить:**

С Windows:

```powershell
ssh -i "$env:USERPROFILE\.ssh\proxmox_pundef_nopass" `
    deploy@192.168.50.35 "whoami && test -w /srv/static-sites/requiem && echo writable"
```

Ожидаемо: `deploy` и `writable`.

---

### Шаг 5. Настроить локальный DNS на OpenWrt — ✅ сделано

**Сделать:**

```sh
ssh root@192.168.1.1 "
uci add_list dhcp.@dnsmasq[0].address='/requiem.home/192.168.50.35'
uci commit dhcp
/etc/init.d/dnsmasq restart
"
```

**Проверить:**

С клиента в `lan`:

```powershell
Resolve-DnsName requiem.home -Server 192.168.1.1
```

С OpenWrt:

```sh
nslookup requiem.home 127.0.0.1
```

Ожидаемо: оба ответа возвращают `192.168.50.35`.

---

### Шаг 6. Задеплоить `requiem-helper` — ✅ сделано

**Сделать:**

Из корня репозитория на Windows:

```powershell
.\requiem-helper\scripts\deploy.ps1
```

Скрипт делает: `npm ci && npm run build` в `requiem-helper/`, пакует `dist` в `tar.gz`, копирует его на LXC по `scp`, распаковывает в `/srv/static-sites/requiem` и проверяет `http://requiem.home`.

Полезные флаги:

```powershell
# уже собрано, только заливка
.\requiem-helper\scripts\deploy.ps1 -SkipBuild

# другой ключ / хост / урл проверки
.\requiem-helper\scripts\deploy.ps1 `
  -HostName 192.168.50.35 `
  -User deploy `
  -KeyPath "$env:USERPROFILE\.ssh\proxmox_pundef_nopass" `
  -RemotePath /srv/static-sites/requiem `
  -Url http://requiem.home
```

**Проверить:**

```powershell
(Invoke-WebRequest http://requiem.home/        -UseBasicParsing -TimeoutSec 5).StatusCode
(Invoke-WebRequest http://192.168.50.35/       -UseBasicParsing -TimeoutSec 5).StatusCode
```

Ожидаемо: оба — `200`, сайт открывается в браузере и через `http://requiem.home`, и по IP.

---

## Внешний HTTPS-доступ — ✅ сделано (через Nextcloud Apache)

Внешний `80/443` уже проброшен на `nextcloud-vm` (`192.168.50.34`), поэтому новый сайт втащен в этот же edge: один общий hostname `apps-pundef.mooo.com`, в Apache добавлен **один** vhost-reverse-proxy на Caddy LXC, а path-роутинг для каждого сайта живёт уже внутри Caddy (`/requiem/`*, потом `/foo/*` и т.д.). Nextcloud `cloud-pundef.mooo.com` не трогается.

> Vite build должен идти с `base: "./"`, чтобы один и тот же `dist` работал и с корня (`http://requiem.home/`), и под префиксом (`https://apps-pundef.mooo.com/requiem/`). См. `requiem-helper/vite.config.ts`.

### Шаг 7. FreeDNS hostname для всех сайтов — ✅ сделано

1. На [https://freedns.afraid.org](https://freedns.afraid.org) завести subdomain:
  - Type `A`, Subdomain `apps-pundef`, Domain `mooo.com (public)`, Destination — белый IP роутера.
  - Сохранить с капчей.
2. На странице субдомена скопировать **Dynamic update URL** (`https://freedns.afraid.org/dynamic/update.php?...`).

**Проверить:**

```powershell
Resolve-DnsName apps-pundef.mooo.com -Type A -Server 8.8.8.8
```

Ожидаемо: возвращается белый IP. Иногда первая публикация в зону afraid занимает несколько минут.

### Шаг 8. DDNS для нового hostname на OpenWrt — ✅ сделано

```sh
ssh root@192.168.1.1 "
uci set ddns.apps_pundef=service
uci set ddns.apps_pundef.enabled='1'
uci set ddns.apps_pundef.update_url='<URL из FreeDNS>'
uci set ddns.apps_pundef.lookup_host='apps-pundef.mooo.com'
uci set ddns.apps_pundef.domain='apps-pundef.mooo.com'
uci set ddns.apps_pundef.use_ipv6='0'
uci set ddns.apps_pundef.use_https='1'
uci set ddns.apps_pundef.cacert='IGNORE'
uci set ddns.apps_pundef.ip_source='web'
uci set ddns.apps_pundef.ip_url='https://checkip.amazonaws.com/'
uci set ddns.apps_pundef.interface='wan'
uci set ddns.apps_pundef.check_interval='10'
uci set ddns.apps_pundef.check_unit='minutes'
uci set ddns.apps_pundef.force_interval='72'
uci set ddns.apps_pundef.force_unit='hours'
uci set ddns.apps_pundef.dns_server='8.8.8.8'
uci commit ddns
/etc/init.d/ddns reload
"
```

### Шаг 9. Apache vhost stage1 + Let's Encrypt — ✅ сделано

Сначала ставится минимальный `:80`-vhost (`ServerName apps-pundef.mooo.com`), который проксирует на Caddy и оставляет локально `/.well-known/acme-challenge/` для certbot webroot.

```apache
<VirtualHost *:80>
    ServerName apps-pundef.mooo.com
    DocumentRoot /var/www/html
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass /.well-known/acme-challenge/ !
    ProxyPass        / http://192.168.50.35/
    ProxyPassReverse / http://192.168.50.35/
    ErrorLog ${APACHE_LOG_DIR}/apps-pundef-error.log
    CustomLog ${APACHE_LOG_DIR}/apps-pundef-access.log combined
</VirtualHost>
```

На Nextcloud VM:

```bash
a2ensite apps-pundef.conf
apache2ctl configtest && systemctl reload apache2
certbot certonly --webroot -w /var/www/html -d apps-pundef.mooo.com \
  --non-interactive --agree-tos --register-unsafely-without-email
```

LE-аккаунт уже зарегистрирован без email (как и у `cloud-pundef`). Сертификат лежит в `/etc/letsencrypt/live/apps-pundef.mooo.com/` и продлевается тем же `certbot.timer`.

### Шаг 10. Apache vhost stage2 (полная HTTPS-конфигурация) — ✅ сделано

```apache
<VirtualHost *:80>
    ServerName apps-pundef.mooo.com
    DocumentRoot /var/www/html
    Alias /.well-known/acme-challenge/ /var/www/html/.well-known/acme-challenge/
    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>

<VirtualHost *:443>
    ServerName apps-pundef.mooo.com
    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/apps-pundef.mooo.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/apps-pundef.mooo.com/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf
    Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"

    ProxyPreserveHost On
    ProxyRequests Off
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Host "apps-pundef.mooo.com"

    ProxyPass        / http://192.168.50.35/
    ProxyPassReverse / http://192.168.50.35/
</VirtualHost>
```

`apache2ctl configtest && systemctl reload apache2`.

**Проверить:**

```text
https://apps-pundef.mooo.com/         -> 302 на /requiem/
https://apps-pundef.mooo.com/requiem/ -> 200, отдаёт SPA
```

### Шаг 11. Split-horizon DNS для нового hostname (важно) — ✅ сделано

Без этого шага из домашнего LAN сайт открываться **не будет**: `uhttpd` LuCI на OpenWrt слушает `0.0.0.0:80` и `0.0.0.0:443` и съедает hairpin-запросы на белый IP до того, как сработает DNAT, отдавая `<h1>Forbidden</h1> Rejected request from RFC1918 IP to public server address`. Это поведение `uhttpd -R` (RFC1918-фильтр), не Apache.

Решение — split-horizon: для LAN-клиентов резолвить `apps-pundef.mooo.com` напрямую на IP Nextcloud VM, чтобы пакет не уходил на роутер. Так уже сделано для `cloud-pundef.mooo.com`:

```sh
ssh root@192.168.1.1 "
uci add_list dhcp.@dnsmasq[0].address='/apps-pundef.mooo.com/192.168.50.34'
uci commit dhcp
/etc/init.d/dnsmasq restart
"
```

**Проверить:**

```powershell
ipconfig /flushdns
Resolve-DnsName apps-pundef.mooo.com -Server 192.168.1.1
curl.exe -sS -o nul -w "HTTP %{http_code} cert=%{ssl_verify_result}`n" https://apps-pundef.mooo.com/requiem/
```

Ожидаемо: DNS из LAN отдаёт `192.168.50.34`, HTTPS возвращает `HTTP 200 cert=0` (cert валиден).

#### Подводный камень: Secure DNS (DoH) в браузере

После split-horizon `curl` уже работает (он берёт DNS из ОС), но **браузер** может всё равно показывать `Forbidden / Rejected request from RFC1918 IP to public server address`. Так происходит, если в Chrome/Edge включён **Secure DNS (DoH)** — браузер игнорирует роутерный dnsmasq и идёт напрямую в Google/Cloudflare, получая публичный IP, и опять упирается в hairpin.

Способ проверить и починить:

1. Сравнить системный резолв с резолвом браузера:
  ```powershell
   Resolve-DnsName apps-pundef.mooo.com         # должен быть 192.168.50.34
   Resolve-DnsName apps-pundef.mooo.com -Server 8.8.8.8   # будет 5.189.245.251
  ```
   Если в браузере не работает, а в `curl` работает — это именно DoH.
2. В Chrome: `chrome://settings/security` → выключить **Use secure DNS** (или поставить "With your current service provider"). В Edge — `edge://settings/privacy`.
3. Сбросить HSTS/host cache для домена: `chrome://net-internals/#hsts` → ввести `apps-pundef.mooo.com` в **Delete domain security policies**; затем `chrome://net-internals/#dns` → **Clear host cache**.

### Как добавить новый сайт потом

1. Положить статикy в `/srv/static-sites/<name>/` (через тот же deploy-pattern или вручную через `deploy@192.168.50.35`).
2. В `/etc/caddy/Caddyfile` в общий vhost-блок (`apps-pundef.mooo.com, 192.168.50.35, localhost`) добавить:
  ```caddy
   redir /<name> /<name>/ 301
   handle_path /<name>/* {
       root * /srv/static-sites/<name>
       try_files {path} /index.html
       encode zstd gzip
       file_server
   }
  ```
3. `pct exec 102 -- systemctl reload caddy`.
4. Сайт сразу доступен по `https://apps-pundef.mooo.com/<name>/`. Apache / DDNS / cert трогать не надо.

---

## Сделано (история)

Пункты, которые уже выполнены. Оставлены для истории; в текущем плане не повторять.


| Когда      | Что сделано                                                                                                                                                  |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 2026-05-23 | Создан LXC `static-sites` (VMID 102) на Debian 13, IP `192.168.50.35`, `vmbr0`/`srv`.                                                                        |
| 2026-05-23 | Установлен Caddy v2.11.3 из cloudsmith, настроен `auto_https off` + один vhost для `requiem.home`/IP/`localhost`.                                            |
| 2026-05-23 | Создан пользователь `deploy` с ключом `cursor-agent@home-server-repo`, дан write на `/srv/static-sites`.                                                     |
| 2026-05-23 | На OpenWrt добавлена split-horizon запись `/requiem.home/192.168.50.35` в `dnsmasq`.                                                                         |
| 2026-05-23 | Задеплоен `requiem-helper`, проверено `http://requiem.home` и `http://192.168.50.35` → `HTTP 200`.                                                           |
| 2026-05-23 | Vite `base: "./"` + `import.meta.env.BASE_URL` для иконок — один build работает и с корня, и из-под префикса.                                                |
| 2026-05-23 | Caddy переведён на path-based edge: `/requiem/*` → сайт, `/` → 302 на `/requiem/`.                                                                           |
| 2026-05-23 | На FreeDNS заведён `apps-pundef.mooo.com`, на OpenWrt добавлен второй DDNS-сервис `apps_pundef`.                                                             |
| 2026-05-23 | На Nextcloud Apache добавлен vhost `apps-pundef.mooo.com` (:80 + :443), LE-cert через certbot webroot.                                                       |
| 2026-05-23 | Внешний `https://apps-pundef.mooo.com/requiem/` проверен через внешний клиент — отдаёт HTML SPA, cert валиден.                                               |
| 2026-05-23 | Фикс `crypto.randomUUID` → fallback через `crypto.getRandomValues`, чтобы работало по `http://` (не secure context).                                         |
| 2026-05-23 | Split-horizon на OpenWrt: `/apps-pundef.mooo.com/192.168.50.34` — обход hairpin/uhttpd RFC1918-фильтра из LAN.                                               |
| 2026-05-23 | Зафиксировано: в браузере для split-horizon нужно отключить Secure DNS (DoH), иначе он обходит роутерный dnsmasq.                                            |
| 2026-05-23 | Favicon: `requiem-helper/scripts/make-favicon.py` собирает `favicon.ico` (16/32/48/64) и `apple-touch-icon.png` из `Oull.webp` (белый знак на индиго круге). |


