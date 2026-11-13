# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

- Гипервизор: Oracle VirtualBox 7.2.22.
- Операционная система: Ubuntu Server 24.04.5 LTS (64-bit).
- Оперативная память: 2048 МБ.
- Процессоры: 2 виртуальных ядра.
- Виртуальный диск: 25 ГБ, VDI.
- Имя виртуальной машины: `devops-vm`.

## 2. Сетевые интерфейсы

- Адаптер 1: NAT, интерфейс `enp0s3`, адрес `10.0.2.15`. Используется для доступа в интернет.
- Адаптер 2: Host-only, интерфейс `enp0s8`, адрес `192.168.56.101/24`. Используется для связи Windows и Ubuntu.
- Адрес Windows в Host-only: `192.168.56.1`.

В Windows в файл `C:\Windows\System32\drivers\etc\hosts` добавлена запись:

`192.168.56.101 devops.local`

Для проверки используются `ping devops.local` и подключение по SSH.

В Ubuntu задано имя `devops-vm` и запись `/etc/hosts`:

`127.0.1.1 devops-vm.devops.local devops-vm`

Проверка: `hostname -f`.

## 3. Правило проброса портов

В адаптере NAT VirtualBox настроено правило:

- Имя: `ssh`
- Протокол: TCP
- IP хоста: `127.0.0.1`
- Порт хоста: `2222`
- IP гостя: пусто
- Порт гостя: `2222`

При начальной настройке гостевой порт был `22`. После перенастройки SSH он изменён на `2222`.

## 4. Учётные записи

`student` — первоначальный пользователь Ubuntu, UID 1000.

`devops` — пользователь для администрирования, UID 1001. Входит в группы `devops`, `sudo`, `users`.

Для `devops` используется SSH-аутентификация по ключу ED25519.

Закрытый ключ Windows: `~/.ssh/devops_vm`.

Открытый ключ установлен в `/home/devops/.ssh/authorized_keys`.

Права доступа: `.ssh` — 700, `authorized_keys` — 600.

В Windows настроен SSH-псевдоним `devops` в файле `~/.ssh/config`. Команда `ssh devops` подключает к `127.0.0.1:2222` с использованием ключа.

Закрытый ключ и пароли не добавляются в Git.

## 5. Служба SSH

Основная конфигурация: `/etc/ssh/sshd_config`.

Дополнительная конфигурация: `/etc/ssh/sshd_config.d/99-hardening.conf`.

Установлены параметры:

- `Port 2222`
- `PermitRootLogin no`
- `PasswordAuthentication no`
- `PubkeyAuthentication yes`
- `PermitEmptyPasswords no`
- `MaxAuthTries 3`
- `LoginGraceTime 30`
- `AllowUsers devops`
- `X11Forwarding no`
- `ClientAliveInterval 300`
- `ClientAliveCountMax 2`

Конфликтующая настройка `PasswordAuthentication yes` в файле `50-cloud-init.conf` закомментирована.

Служба `ssh.socket` отключена, используется `ssh.service` с автозапуском.

Проверки:

- `sudo sshd -t`
- `sudo sshd -T`
- `sudo ss -tlnp | grep sshd`

После любых изменений необходимо проверять новое SSH-подключение в отдельном терминале до закрытия текущей сессии.

## 6. Правила межсетевого экрана

Используется UFW.

- Входящие соединения: `deny`.
- Исходящие соединения: `allow`.
- Порт `2222/tcp`: `LIMIT` для SSH.
- Порт `80/tcp`: `ALLOW` для HTTP.
- Порт `443/tcp`: `ALLOW` для HTTPS.
- Регистрация событий: `medium`.

Проверка: `sudo ufw status verbose`.

Блокировка порта 8080 подтверждена запросом с Windows и записью `[UFW BLOCK]` с `SRC=192.168.56.1`, `DST=192.168.56.101`, `PROTO=TCP`, `DPT=8080`.

## 7. Снимки состояния

Созданы три снимка VirtualBox:

- `01-clean-install` — 23.10.2026, 01:44. Исходная установленная Ubuntu.
- `02-keys-configured` — 23.10.2026, 02:17. Создан пользователь `devops`, настроен вход по ключу.
- `03-ssh-hardened` — 23.10.2026, 03:12. Настроена защита SSH и сетевой экран.

### Порядок восстановления после отката

После восстановления снимка `01-clean-install`:

1. Запустить VM и убедиться в наличии адаптеров NAT и Host-only.
2. Проверить или запустить OpenSSH: `sudo systemctl enable --now ssh`.
3. Создать пользователя `devops` через `sudo adduser devops` и добавить его в группу sudo командой `sudo usermod -aG sudo devops`.
4. Установить открытый SSH-ключ с Windows в `/home/devops/.ssh/authorized_keys`, настроить права 700/600.
5. Восстановить файл `99-hardening.conf` с параметрами из раздела 5.
6. Устранить конфликтующую настройку cloud-init.
7. Проверить `sudo sshd -t`, отключить `ssh.socket`, активировать и перезапустить `ssh.service`.
8. Изменить в VirtualBox гостевой порт проброса NAT с 22 на 2222.
9. Проверить `ssh devops` с Windows.
10. Настроить UFW: разрешить 2222, 80 и 443, включить политику deny для входящих, allow для исходящих и добавить ограничение `LIMIT` для SSH.
11. Проверить имя `devops.local` в Windows и FQDN `devops-vm.devops.local` в Ubuntu.
12. Выполнить `bash ~/audit.sh`, убедиться в результате 6 OK и коде возврата 0.

При восстановлении сначала необходимо обеспечить рабочее SSH-подключение и только потом вводить ограничения доступа.


## 8. Веб-сервер

На виртуальной машине установлен веб-сервер Nginx.

- Пакет: nginx.
- Конфигурация сайта: `/etc/nginx/sites-available/devops-site`.
- Активная конфигурация: `/etc/nginx/sites-enabled/devops-site`.
- Стандартный сайт Nginx отключён.
- Каталог сайта: `/var/www/devops-site`.
- Владелец каталога и файлов: `devops:devops`.
- Права каталогов: 755.
- Права файлов: 644.

Веб-сервер обслуживает домен `devops.local`.
Порт 80 используется для перенаправления HTTP на HTTPS с кодом 301.
Порт 443 используется для защищённого соединения TLS 1.2 и TLS 1.3.

### TLS-сертификат

- Сертификат: `/etc/ssl/certs/devops.crt`, права 644.
- Закрытый ключ: `/etc/ssl/private/devops.key`, права 600.
- Владелец ключа: root.
- Тип сертификата: самоподписанный.
- CN: devops.local.
- SAN: DNS:devops.local.
- Срок действия: 365 дней, с 13.11.2026 по 13.11.2027.

Команда создания сертификата:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"
```

### Проверка сервера

Проверка конфигурации:

```bash
sudo nginx -t
```

Применение конфигурации:

```bash
sudo systemctl reload nginx
```

Проверка работы службы:

```bash
systemctl is-active nginx
```

Проверка HTTP-перенаправления:

```bash
curl -I http://devops.local
```

Проверка HTTPS с доверенным сертификатом:

```bash
curl --cacert ~/devops.crt -I https://devops.local
```

Содержимое сайта доставляется из каталога `site/` репозитория через `rsync` с использованием SSH и сценария `scripts/deploy.sh`.

Сценарий устанавливает права 755 для каталогов и 644 для файлов, проверяет чистоту Git и доступность сайта после доставки.

Для диагностики используются журналы:

- `/var/log/nginx/devops-site.access.log`
- `/var/log/nginx/devops-site.error.log`

Состояние веб-сервера сохранено в снимке VirtualBox `04-nginx-https`.

## 9. Контейнеризация

В Ubuntu 24.04 установлен Docker Engine 29.9.3 из официального репозитория Docker
(`https://download.docker.com/linux/ubuntu`), а не через Snap или пакет `docker.io`.
GPG-ключ репозитория хранится в `/etc/apt/keyrings/docker.asc`, конфигурация
репозитория — `/etc/apt/sources.list.d/docker.sources`.
Установлены `docker-ce`, `docker-ce-cli`, `containerd.io`,
`docker-buildx-plugin` и `docker-compose-plugin` (Compose 5.7.1).
Служба Docker запускается через systemd. Пользователь `devops` входит в
группу `docker`; это даёт расширенные права, сопоставимые с root.

Проект находится на сервере в `/home/devops/app`. Исходные файлы создаются
в каталоге `app/` репозитория Windows и доставляются по SSH.
В `Dockerfile` используется базовый образ `python:3.12-slim`, а Flask
запускается через Gunicorn непривилегированным пользователем `app`.
Проверка: `docker compose exec app id`.

Переменные окружения размещены в `/home/devops/app/.env`, права доступа —
`600`. Пароль PostgreSQL сгенерирован командой `openssl rand -hex 16`.
Содержимое `.env` не включается ни в Git, ни в Docker-образ; в репозитории
хранится только `.env.example`. Для проверки прав применяется
`stat -c '%a' ~/app/.env`.

Конфигурация `docker-compose.yml` создаёт два сервиса: `app` (Flask) и
`db` (PostgreSQL `postgres:16-alpine`). Сеть проекта — `app_backend`
типа bridge. Приложение находит базу по DNS-имени `db` внутри этой сети.
Запуск приложения зависит от проверки `pg_isready` (состояние `healthy`).
Порт приложения проброшен только на `127.0.0.1:5000`, порт PostgreSQL
`5432` на хост не публикуется. Проверки: `docker compose ps`,
`docker compose exec app getent hosts db`, `sudo ss -tlnp`.

Именованный том `app_db_data` подключён к `/var/lib/postgresql/data`
и хранит счётчик посещений независимо от контейнера.
`docker compose down` оставляет том, а `docker compose down -v` удаляет
том и все данные — эту команду применяют только для демонстрационного
сброса или при осознанном удалении базы.

Nginx использует `/etc/nginx/sites-available/devops-site`. В HTTPS-блоке
путь `/app/` проксируется на `http://127.0.0.1:5000/` с заголовками
`Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`.
Статический ресурс по адресу `https://devops.local/` сохранён.
Проверки: `sudo nginx -t`,
`curl --cacert ~/devops.crt https://devops.local/app/`,
`curl --cacert ~/devops.crt -I https://devops.local/`.
Если контейнер остановлен, Nginx возвращает `502 Bad Gateway`,
а причина фиксируется в `/var/log/nginx/devops-site.error.log`.

Проверка работоспособности всей конфигурации реализована в
`scripts/audit.sh` (раздел `[5] Контейнеризация`). Скрипт проверяет
Docker, состояние PostgreSQL, публикацию портов и права `.env`.
После успешного завершения ПР №7 требуется создать снимок VirtualBox
`05-docker-compose` и сохранить его вместе с предыдущими снимками.
