# RemnaSetup

<div align="center">

[English](README.en.md) | [Русский](README.md)

![RemnaSetup](https://img.shields.io/badge/RemnaSetup-2.5-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-orange)

Скрипт для установки и управления инфраструктурой **Remnawave** и **Remnanode**

[![Stars](https://img.shields.io/github/stars/Capybara-z/RemnaSetup?style=social)](https://github.com/Capybara-z/RemnaSetup)

</div>

---

## Установка

```bash
bash <(curl -fsSL raw.githubusercontent.com/Capybara-z/RemnaSetup/refs/heads/main/install.sh)
```

или

```bash
curl -fsSL https://raw.githubusercontent.com/Capybara-z/RemnaSetup/refs/heads/main/install.sh -o install.sh && chmod +x install.sh && sudo bash ./install.sh
```

### Установка из своего форка

Если вы используете собственную копию репозитория (со своими шаблонами-маскировками
и настройками), укажите её через `REMNASETUP_REPO` — `install.sh` скачает именно её:

```bash
REMNASETUP_REPO=youruser/RemnaSetup \
bash <(curl -fsSL https://raw.githubusercontent.com/youruser/RemnaSetup/refs/heads/main/install.sh)
```

### Установка ноды «всё сразу» одной командой

Полностью неинтерактивно, из своего форка, с Caddy + Cloudflare wildcard:

```bash
REMNASETUP_REPO=youruser/RemnaSetup \
NON_INTERACTIVE=true \
DOMAIN=abc123.datahubfiles.com \
CF_API_TOKEN='cloudflare_api_token' \
ACME_EMAIL='you@example.com' \
NODE_PORT=3001 SECRET_KEY='ключ_из_панели' \
WEBSERVER=caddy INSTALL_WARP=y BBR_ANSWER=y \
PANEL_IP=1.2.3.4 \
bash <(curl -fsSL https://raw.githubusercontent.com/youruser/RemnaSetup/refs/heads/main/install.sh) install-node
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
- Веб-сервер на выбор: **Caddy** или **Nginx** с self-steal
- **Caddy**: wildcard-сертификат `*.домен` через Cloudflare DNS-01 (плагин `caddy-dns/cloudflare` вкомпилирован автоматически) — в CT-логах виден только wildcard, отдельные имена нод не светятся
- Nginx: поддержка proxy protocol, сертификаты через Cloudflare DNS-01 / HTTP-01 / Gcore DNS-01
- **Случайный сайт-маскировка** из набора естественных шаблонов (кафе, консалтинг, фото, SaaS, книжный, студия, портфолио) — на каждой ноде свой, с уникальной микро-разметкой; настоящий 404 на случайные пути
- **Фаервол ufw**: публичные `22,80,443`, порты управления `3001,61000` только для IP панели, `8443` закрыт наружу
- **fail2ban** (jail `sshd`)
- Управление IPv6
- WARP-NATIVE (by distillium)
- BBR оптимизация

---

## Non-interactive режим

Можно передать параметры через переменные окружения и команду — скрипт выполнится без вопросов.

### Полная установка ноды с Caddy (Cloudflare DNS-01 wildcard)

```bash
DOMAIN=abc123.datahubfiles.com \
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

> `DOMAIN` — полное имя ноды (`abc123.datahubfiles.com`); wildcard-сертификат
> выпускается на базовую зону (`*.datahubfiles.com`), извлекаемую автоматически.
> `CF_API_TOKEN` — токен Cloudflare с правами **Zone → DNS → Edit** на вашу зону.
> `ACME_EMAIL` — необязателен. Токен хранится в systemd-override Caddy, а не в Caddyfile.
> Опционально `SITE_TEMPLATE=cafe|consulting|photography|saas|bookshop|studio|devportfolio`
> форсирует конкретный шаблон-маскировку (по умолчанию — случайный).

### Полная установка ноды с Nginx

```bash
DOMAIN=node.example.com \
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
DOMAIN=node.example.com \
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
| `update-node` | Обновить Remnanode |

### Переменные окружения

| Переменная | Описание | По умолчанию |
|---|---|---|
| `DOMAIN` | Домен ноды | — |
| `MONITOR_PORT` | Порт веб-сервера | `8443` |
| `NODE_PORT` | Порт ноды | `3001` |
| `SECRET_KEY` | Ключ подключения к панели | — |
| `WEBSERVER` | `caddy` или `nginx` | — |
| `CF_API_TOKEN` | Cloudflare API токен для Caddy (Zone:DNS:Edit) | — |
| `ACME_EMAIL` | Email для ACME в Caddy (необязательно) | — |
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

Telegram: [@KaTTuBaRa](https://t.me/KaTTuBaRa)

## Поддержка проекта

Сделано при поддержке [SoloBot](https://github.com/Vladless/Solo_bot) ([@solonet_sup](https://t.me/solonet_sup))

## Лицензия

MIT
