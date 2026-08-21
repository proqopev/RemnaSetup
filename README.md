# RemnaSetup

<div align="center">

[English](README.en.md) | [Русский](README.md)

![RemnaSetup](https://img.shields.io/badge/RemnaSetup-2.5-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-orange)

Скрипт для установки и управления инфраструктурой **Remnawave** и **Remnanode**

📖 **[Полный гайд по деплою нод (Cloudflare wildcard, маскировка, WARP, без лимитов LE)](docs/ГАЙД.md)**

[![Stars](https://img.shields.io/github/stars/proqopev/RemnaSetup?style=social)](https://github.com/proqopev/RemnaSetup)

</div>

---

## Установка

```bash
bash <(curl -fsSL raw.githubusercontent.com/proqopev/RemnaSetup/refs/heads/main/install.sh)
```

или

```bash
curl -fsSL https://raw.githubusercontent.com/proqopev/RemnaSetup/refs/heads/main/install.sh -o install.sh && chmod +x install.sh && sudo bash ./install.sh
```

### Установка из своего форка

Если используете собственную копию репозитория, укажите её через `REMNASETUP_REPO` —
`install.sh` скачает именно её:

```bash
REMNASETUP_REPO=youruser/RemnaSetup \
bash <(curl -fsSL https://raw.githubusercontent.com/youruser/RemnaSetup/refs/heads/main/install.sh)
```

### Установка ноды «всё сразу» одной командой

Полностью неинтерактивно, с Caddy + Cloudflare wildcard:

```bash
NON_INTERACTIVE=true \
DOMAIN=node1.example.com \
CF_API_TOKEN='cloudflare_api_token' \
ACME_EMAIL='you@example.com' \
NODE_PORT=3001 SECRET_KEY='ключ_из_панели' \
WEBSERVER=caddy INSTALL_WARP=y BBR_ANSWER=y \
PANEL_IP=1.2.3.4 \
bash <(curl -fsSL https://raw.githubusercontent.com/proqopev/RemnaSetup/refs/heads/main/install.sh) install-node
```

`PANEL_IP` включает правила ufw, открывающие порты управления `3001,61000`
только для IP панели; публичные порты `22,80,443` открываются всем; `8443`
(self-steal Caddy) наружу **не** открывается — Reality ходит к нему по `127.0.0.1`.
Заодно ставится `fail2ban` (jail `sshd`). Отключить: `SKIP_FIREWALL=true` / `SKIP_FAIL2BAN=true`.

---

## Возможности

### Remnawave (панель)
- Полная установка (Remnawave + Caddy)
- Установка панели / страницы подписок / Caddy по отдельности
- Обновление всех компонентов
- Бэкап и восстановление (ручной, автоматический, с отправкой в Telegram или S3-хранилище)

### Remnanode (нода)
- Полная установка (Remnanode + Caddy/Nginx + BBR + WARP)
- Выбор версии образа ноды (`latest` или `X.Y.Z`) — важно для совместимости с версией панели
- Веб-сервер на выбор: **Caddy** или **Nginx** с self-steal
- **Caddy**: wildcard-сертификат `*.домен` через Cloudflare DNS-01 (плагин `caddy-dns/cloudflare` вкомпилирован автоматически) — в CT-логах виден только wildcard, отдельные имена нод не светятся
- Nginx: поддержка proxy protocol, сертификаты через Cloudflare DNS-01 / HTTP-01 / Gcore DNS-01
- **Случайный сайт-маскировка** из набора естественных шаблонов (кафе, консалтинг, фото, SaaS, книжный, студия, портфолио) — на каждой ноде свой, с уникальной микро-разметкой; настоящий 404 на случайные пути
- **Фаервол ufw**: публичные `22,80,443`, порты управления `3001,61000` только для IP панели, `8443` закрыт наружу
- **fail2ban** (jail `sshd`)
- **WARP-egress для xray**: при установке WARP на ноде настраивается fwmark-маршрутизация (помеченный `mark=1` трафик уходит через Cloudflare, IP ноды не светится как выход). Для уже стоящих нод — команда `setup-warp-routing`. В панели нужно добавить outbound `{tag: warp, protocol: freedom, sockopt.mark: 1}` + правило маршрутизации и `dns.queryStrategy: UseIPv4`
- Управление IPv6
- WARP-NATIVE (by distillium)
- BBR оптимизация

---

## Подготовка: домен на Cloudflare (wildcard-сертификат)

Чтобы Caddy получал один **wildcard**-сертификат `*.example.com` вместо отдельного
на каждое имя ноды (иначе все имена нод светятся в публичных CT-логах и находятся
одним запросом к `crt.sh`), домен нужно держать на Cloudflare, а выпуск вести через
ACME **DNS-01**.

1. **Добавить домен в Cloudflare** → Dashboard → *Add a Site* → ваш домен → тариф **Free**.
   Cloudflare подтянет текущие DNS-записи — проверьте, что A-записи нод на месте.
2. **Сменить NS у регистратора** — Cloudflare выдаст два NS-сервера; впишите их в панели
   регистратора вместо текущих. Распространение — от 10 минут до нескольких часов.
   Проверка: `dig NS example.com` показывает NS Cloudflare.
3. ⚠️ **A-записи нод — только `DNS only` (серая тучка).** Оранжевая тучка (Proxied) ломает
   Reality: клиент должен видеть реальный IP вашего сервера в TLS-хендшейке, а не IP Cloudflare.
4. **Создать API-токен** → иконка профиля → *My Profile* → *API Tokens* → *Create Custom Token*:
   - **Permissions:** `Zone → DNS → Edit`
   - **Zone Resources:** `Include → Specific zone → example.com`
   - Скопировать токен (показывается один раз) — это `CF_API_TOKEN` для скрипта.

Дальше при установке Caddy скрипт сам соберёт Caddy с плагином `caddy-dns/cloudflare`,
положит токен в systemd-override и выпустит `*.example.com` через DNS-01. Имя ноды —
случайная строка (напр. `x7f2qk9z.example.com`), но в CT-логах будет только `*.example.com`.

---

## Настройка Reality-профиля в Remnawave

Серверную часть (Caddy/self-steal, сертификат, WARP на хосте) ставит скрипт, а вот
**xray-конфиг в панели правится вручную**. Минимально нужно следующее.

### 1. Reality-инбаунд (self-steal)
- `target` (он же `dest`) → **`127.0.0.1:8443`** — Reality форвардит «незваных» на локальный
  Caddy (порт = ваш `MONITOR_PORT`). Просто `"8443"` без хоста — не надёжно.
- `serverNames` → полное имя ноды (напр. `x7f2qk9z.example.com`), **не** wildcard.
- `xver` → `0` для Caddy (для Nginx с proxy protocol — `1`).

### 2. WARP-egress (чтобы IP ноды не светился как выход)
Маршрутизацию на хосте ставит скрипт (`install-warp` или `setup-warp-routing`). В панели
в xray-конфиг добавить три вещи:

**DNS — только IPv4** (WARP настроен IPv4-only):
```json
"dns": { "servers": ["https://1.1.1.1/dns-query"], "queryStrategy": "UseIPv4" }
```

**Outbound `warp`** (метка `mark=1` совпадает с fwmark-правилом на хосте):
```json
{
  "tag": "warp",
  "protocol": "freedom",
  "settings": { "domainStrategy": "ForceIPv4" },
  "streamSettings": { "sockopt": { "mark": 1 } }
}
```

**Routing** — блок-правила сверху, «ловушку» в warp последней (весь трафик через Cloudflare):
```json
"rules": [
  { "type": "field", "ip": ["geoip:private"], "outboundTag": "BLOCK" },
  { "type": "field", "domain": ["geosite:private"], "outboundTag": "BLOCK" },
  { "type": "field", "protocol": ["bittorrent"], "outboundTag": "BLOCK" },
  { "type": "field", "network": "tcp,udp", "outboundTag": "warp" }
]
```

Проверка с клиента: `https://www.cloudflare.com/cdn-cgi/trace` → `warp=on` и IP из Cloudflare
(а не IP ноды).

> ⚠️ Не применяйте профиль с `outboundTag: warp` на ноду, где host-маршрутизация WARP
> не настроена (`setup-warp-routing`) — иначе помеченный трафик уходить будет некуда и
> пользователи этой ноды окажутся офлайн.

---

## Non-interactive режим

Можно передать параметры через переменные окружения и команду — скрипт выполнится без вопросов.

### Полная установка ноды с Caddy (Cloudflare DNS-01 wildcard)

```bash
DOMAIN=node1.example.com \
MONITOR_PORT=8443 \
NODE_PORT=3001 \
SECRET_KEY='ваш_ключ' \
WEBSERVER=caddy \
CF_API_TOKEN='cloudflare_api_token' \
ACME_EMAIL='you@example.com' \
INSTALL_WARP=y \
BBR_ANSWER=y \
sudo -E bash /opt/remnasetup/remnasetup.sh install-node
```

> `DOMAIN` — полное имя ноды (`node1.example.com`); wildcard-сертификат
> выпускается на базовую зону (`*.example.com`), извлекаемую автоматически.
> `CF_API_TOKEN` — токен Cloudflare с правами **Zone → DNS → Edit** на вашу зону.
> `ACME_EMAIL` — необязателен. Токен хранится в systemd-override Caddy, а не в Caddyfile.
> Опционально `SITE_TEMPLATE=cafe|consulting|photography|saas|bookshop|studio|devportfolio`
> форсирует конкретный шаблон-маскировку (по умолчанию — случайный).

### Полная установка ноды с Nginx

```bash
DOMAIN=node1.example.com \
MONITOR_PORT=8443 \
NODE_PORT=3001 \
SECRET_KEY='ваш_ключ' \
WEBSERVER=nginx \
USE_PROXY_PROTOCOL=n \
CERT_METHOD=1 \
CF_API_KEY='токен' \
CF_EMAIL='email@example.com' \
INSTALL_WARP=y \
BBR_ANSWER=y \
sudo -E bash /opt/remnasetup/remnasetup.sh install-node
```

### Пропуск компонентов

```bash
DOMAIN=node1.example.com \
WEBSERVER=caddy \
MONITOR_PORT=8443 \
SKIP_REMNANODE=true \
SKIP_WARP=true \
SKIP_BBR=true \
sudo -E bash /opt/remnasetup/remnasetup.sh install-node
```

### Доступные команды

| Команда | Описание |
|---|---|
| `install-node` | Полная установка ноды |
| `install-node-only` | Только Remnanode |
| `install-caddy-node` | Только Caddy |
| `install-nginx-node` | Только Nginx |
| `install-bbr` | Только BBR |
| `install-warp` | Только WARP |
| `setup-warp-routing` | Пустить egress xray через уже установленный WARP (для старых нод) |
| `import-cert` | Перевести Caddy на готовый wildcard-серт (без ACME) — для масштаба на много нод |
| `update-node` | Обновить Remnanode |

### Переменные окружения

| Переменная | Описание | По умолчанию |
|---|---|---|
| `DOMAIN` | Домен ноды | — |
| `MONITOR_PORT` | Порт веб-сервера | `8443` |
| `NODE_PORT` | Порт ноды | `3001` |
| `NODE_VERSION` | Версия образа ноды — `latest` или `X.Y.Z` (напр. `3.2.2`) | `latest` |
| `SECRET_KEY` | Ключ подключения к панели | — |
| `WEBSERVER` | `caddy` или `nginx` | — |
| `CF_API_TOKEN` | Cloudflare API токен для Caddy (Zone:DNS:Edit) | — |
| `ACME_EMAIL` | Email для ACME в Caddy (необязательно) | — |
| `WILDCARD_CRT` | Путь к готовому wildcard-серту → Caddy без ACME | `/root/wildcard.crt` |
| `WILDCARD_KEY` | Путь к ключу готового серта → Caddy без ACME | `/root/wildcard.key` |
| `SITE_TEMPLATE` | Форсировать шаблон-маскировку (иначе случайный) | random |
| `BASE_DOMAIN` | Явно задать зону для wildcard (иначе из `DOMAIN`) | авто |
| `USE_PROXY_PROTOCOL` | `y` / `n` (для nginx) | — |
| `CERT_METHOD` | `1` (Cloudflare) / `2` (HTTP-01) / `3` (Gcore) | — |
| `CF_API_KEY` | Cloudflare API токен (cert_method=1) | — |
| `CF_EMAIL` | Cloudflare email (cert_method=1) | — |
| `LE_EMAIL` | Email для сертификата (cert_method=2/3) | — |
| `GCORE_API_KEY` | Gcore API токен (cert_method=3) | — |
| `INSTALL_WARP` | `y` / `n` | — |
| `BBR_ANSWER` | `y` / `n` | — |
| `PANEL_IP` | IP панели — ограничить порты управления (3001,61000) только для него | — |
| `FIREWALL_TCP_PORTS` | Публичные TCP-порты для ufw | `22,80,443` |
| `NODE_MGMT_PORTS` | Порты управления, открываемые только для `PANEL_IP` | `3001,61000` |
| `SKIP_FIREWALL` | `true` — не настраивать ufw | — |
| `SKIP_FAIL2BAN` | `true` — не ставить fail2ban | — |
| `SKIP_WEBSERVER` | `true` — пропустить веб-сервер | — |
| `SKIP_REMNANODE` | `true` — пропустить ноду | — |
| `SKIP_WARP` | `true` — пропустить WARP | — |
| `SKIP_BBR` | `true` — пропустить BBR | — |
| `UPDATE_REMNANODE` | `true` — переустановить ноду | — |
| `UPDATE_CADDY` | `true` — переустановить Caddy | — |
| `UPDATE_NGINX` | `true` — переустановить Nginx | — |
| `LANGUAGE` | `ru` / `en` | `ru` |

Без аргументов скрипт работает в обычном интерактивном режиме через меню.

---

## Автоматические бэкапы

Расписание: ежедневно в заданное время или каждые N часов (настраивается через cron).

При настройке доступны три варианта хранения:

1. **Telegram** — отправка архива в Telegram-чат через бота
2. **S3-хранилище** — загрузка в любое S3-совместимое хранилище
3. **Локально** — только на сервере

### S3-хранилище

Поддерживается любое S3-совместимое хранилище (Yandex Object Storage, Selectel, Timeweb, MinIO и др.).

При настройке запрашиваются:

| Параметр | Описание | По умолчанию |
|---|---|---|
| Endpoint | URL S3-сервиса | — |
| Access Key | Ключ доступа | — |
| Secret Key | Секретный ключ | — |
| Bucket | Имя бакета | — |
| Region | Регион | — |
| Path | Путь (префикс) внутри бакета | — |
| Keep | Количество хранимых бэкапов в S3 (`0` — хранить все) | — |

При ручном бэкапе, если ранее настроен S3, скрипт предложит загрузить архив в то же хранилище.

---

## Контакты

GitHub: [@proqopev](https://github.com/proqopev)

## Благодарности

Форк проекта [Capybara-z/RemnaSetup](https://github.com/Capybara-z/RemnaSetup).
WARP-NATIVE — by distillium. Сделано при поддержке [SoloBot](https://github.com/Vladless/Solo_bot).

## Лицензия

MIT
