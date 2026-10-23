
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

echo "Пройдено: $PASS, не пройдено: $FAIL"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
