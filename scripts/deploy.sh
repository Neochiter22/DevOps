
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="${REPO_ROOT}/site/"

DRY_RUN=false

if [[ $# -gt 1 ]]; then
    echo "Использование: deploy.sh [--dry-run]" >&2
    exit 1
fi

if [[ $# -eq 1 ]]; then
    if [[ "$1" == "--dry-run" ]]; then
        DRY_RUN=true
    else
        echo "Неизвестный аргумент: $1" >&2
        exit 1
    fi
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: site/index.html отсутствует" >&2
    exit 1
fi

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения" >&2
    exit 1
fi

RSYNC_ARGS=(
    -avz
    --delete
    --chmod=D755,F644
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5"
)

if [[ "$DRY_RUN" == true ]]; then
    RSYNC_ARGS+=(--dry-run)
fi

if ! rsync "${RSYNC_ARGS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"; then
    echo "Ошибка: rsync завершился неуспешно" >&2
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "Пробный деплой завершён"
    exit 0
fi

if ! curl -fsS --cacert "$CA_CERT" -o /dev/null "$SITE_URL"; then
    echo "Ошибка: сайт недоступен по HTTPS" >&2
    exit 1
fi

COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
echo "Деплой успешен. Коммит: $COMMIT"
