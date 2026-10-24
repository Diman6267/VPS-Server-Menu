#!/bin/bash
set -eu
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/crontab" <<'SH'
#!/bin/bash
if [ "$1" = -l ]; then
    cat "$WARP_CRON_FIXTURE"
elif [ "$1" = - ]; then
    candidate=$(cat)
    if [ -f "$WARP_CRON_REJECT" ] || printf '%s\n' "$candidate" | grep -q '^a b c d e '; then
        exit 1
    fi
    printf '%s\n' "$candidate" > "$WARP_CRON_FIXTURE"
else
    exit 2
fi
SH
chmod +x "$work/bin/crontab"
export PATH="$work/bin:$PATH" WARP_CRON_FIXTURE="$work/cron" WARP_CRON_REJECT="$work/reject"
# shellcheck disable=SC1091
source "$project_dir/menu_warp.sh"
export RED='' GREEN='' YELLOW='' NC=''
cat > "$WARP_CRON_FIXTURE" <<'CRON'
MAILTO=root
0 3 * * * systemctl restart warp-svc >/dev/null 2>&1
15 2 * * * echo warp-svc
0 2 * * * echo systemctl restart warp-svc
# 0 2 * * * systemctl restart warp-svc
30 1 * * * systemctl restart another-service >/dev/null 2>&1
CRON
original=$(cat "$WARP_CRON_FIXTURE")
if update_warp_cron_rule 'a b c d e systemctl restart warp-svc >/dev/null 2>&1' 2>"$work/error"; then
    echo 'Invalid cron rule was accepted' >&2; exit 1
fi
test "$(cat "$WARP_CRON_FIXTURE")" = "$original"
grep -Eq 'прежнее расписание сохранено' "$work/error"
touch "$WARP_CRON_REJECT"
if update_warp_cron_rule '0 4 * * * systemctl restart warp-svc >/dev/null 2>&1' 2>"$work/error"; then
    echo 'Rejected crontab was accepted' >&2; exit 1
fi
test "$(cat "$WARP_CRON_FIXTURE")" = "$original"
rm "$WARP_CRON_REJECT"
update_warp_cron_rule '0 08 * * * systemctl restart warp-svc >/dev/null 2>&1'
test "$(grep -Ec '^0 08 \* \* \* systemctl restart warp-svc' "$WARP_CRON_FIXTURE")" = 1
grep -Eq '^15 2 \* \* \* echo warp-svc$' "$WARP_CRON_FIXTURE"
grep -Eq '^0 2 \* \* \* echo systemctl restart warp-svc$' "$WARP_CRON_FIXTURE"
grep -Eq '^# 0 2 \* \* \* systemctl restart warp-svc$' "$WARP_CRON_FIXTURE"
grep -Eq '^30 1 \* \* \* systemctl restart another-service' "$WARP_CRON_FIXTURE"
test "$(get_warp_cron_status)" = 'Ежедневно в 08:00'
update_warp_cron_rule '09 08 * * * systemctl restart warp-svc >/dev/null 2>&1'
test "$(get_warp_cron_status)" = 'Ежедневно в 08:09'
update_warp_cron_rule ''
test "$(get_warp_cron_status)" = 'ВЫКЛЮЧЕН'
grep -Eq '^15 2 \* \* \* echo warp-svc$' "$WARP_CRON_FIXTURE"
grep -Eq '^0 2 \* \* \* echo systemctl restart warp-svc$' "$WARP_CRON_FIXTURE"
grep -Eq '^# 0 2 \* \* \* systemctl restart warp-svc$' "$WARP_CRON_FIXTURE"
echo 'PASS: atomic cron replacement, validation failure, scoped removal, leading zeros'
