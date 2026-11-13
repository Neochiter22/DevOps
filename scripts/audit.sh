
#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo "[OK] $desc"
        ((PASS+=1))
    else
        echo "[FAIL] $desc (ожидалось: $expected, получено: $actual)"
        ((FAIL+=1))
    fi
}

echo "Аудит конфигурации: $(hostname -f)"
echo "Дата: $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"

SSH_CONFIG=$(sudo sshd -T)

check "Вход root запрещён" "no" \
    "$(echo "$SSH_CONFIG" | awk '/^permitrootlogin /{print $2}')"

check "Парольная аутентификация отключена" "no" \
    "$(echo "$SSH_CONFIG" | awk '/^passwordauthentication /{print $2}')"

SSH_PORT=$(echo "$SSH_CONFIG" | awk '/^port /{print $2}')

if [[ "$SSH_PORT" =~ ^[0-9]+$ && "$SSH_PORT" -ne 22 ]]; then
    check "Порт SSH отличается от 22" "yes" "yes"
else
    check "Порт SSH отличается от 22" "yes" "no"
fi

check "MaxAuthTries равен 3" "3" \
    "$(echo "$SSH_CONFIG" | awk '/^maxauthtries /{print $2}')"

echo "[2] Межсетевой экран"

UFW_STATUS=$(sudo ufw status verbose)

check "UFW активен" "active" \
    "$(echo "$UFW_STATUS" | awk '/^Status:/{print $2}')"

check "Входящий трафик запрещён по умолчанию" "deny" \
    "$(echo "$UFW_STATUS" | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"

awk -F: '$3>=1000 && $3<65534 {
    printf "%s (uid=%s)\n", $1, $3
}' /etc/passwd


echo "[4] Веб-сервер"

check "Nginx активен" "active" \
    "$(systemctl is-active nginx 2>/dev/null || true)"

if sudo nginx -t >/dev/null 2>&1; then
    check "Конфигурация Nginx корректна" "yes" "yes"
else
    check "Конфигурация Nginx корректна" "yes" "no"
fi

CERT_CHECK_SECONDS="${CERT_CHECK_SECONDS:-2592000}"

if openssl x509 -in /etc/ssl/certs/devops.crt \
    -noout -checkend "$CERT_CHECK_SECONDS" >/dev/null 2>&1; then
    check "Сертификат действителен минимум 30 дней" "yes" "yes"
else
    check "Сертификат действителен минимум 30 дней" "yes" "no"
fi

WRITABLE=$(find /var/www/devops-site -perm -o+w -print -quit 2>/dev/null)
KEY_MODE=$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)

if [[ -z "$WRITABLE" && "$KEY_MODE" == "600" ]]; then
    check "Права файлов и TLS-ключа безопасны" "yes" "yes"
else
    check "Права файлов и TLS-ключа безопасны" "yes" "no"
fi

echo "[5] Контейнеризация"

check "Docker активен" "active" \
    "$(systemctl is-active docker 2>/dev/null || true)"

check "PostgreSQL находится в состоянии healthy" "healthy" \
    "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || true)"

if SOCKETS=$(sudo ss -tlnH 2>/dev/null); then
    UNSAFE_PORTS=$(printf '%s\n' "$SOCKETS" | awk '
        $4 ~ /:(5000|5432)$/ &&
        $4 !~ /^127[.]0[.]0[.]1:(5000|5432)$/ { print $4 }
    ')
    if [[ -z "$UNSAFE_PORTS" ]]; then
        check "Порты 5000 и 5432 не опубликованы наружу" "safe" "safe"
    else
        check "Порты 5000 и 5432 не опубликованы наружу" "safe" "$UNSAFE_PORTS"
    fi
else
    check "Порты 5000 и 5432 не опубликованы наружу" "safe" "ss-error"
fi

check "Права файла ~/app/.env" "600" \
    "$(stat -c '%a' "$HOME/app/.env" 2>/dev/null || true)"

echo "Пройдено: $PASS, не пройдено: $FAIL"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
