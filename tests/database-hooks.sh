#!/usr/bin/env bash
# Exercise lifecycle ordering and fail-closed behavior using only command fakes.
# Each case gets a private throwaway directory, never a real WordPress database.
set -euo pipefail
SCRIPT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wp-env-sync.sh
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

cat > "$TEST_ROOT/bin/wp" <<'FAKE'
#!/usr/bin/env bash
printf 'wp %s\n' "$*" >> "$EVENTS"
case "$*" in
    'config has MULTISITE --quiet') exit 1 ;;
    'maintenance-mode is-active --quiet') [[ -f .maintenance ]] ;;
    'maintenance-mode activate --force') touch .maintenance ;;
    'maintenance-mode deactivate') rm -f .maintenance ;;
    'db import '*) [[ ${FAIL_AT:-} != import ]] ;;
    'db reset --yes') [[ ${FAIL_AT:-} != reset ]] ;;
esac
FAKE
cat > "$TEST_ROOT/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
# The source export is faked, including its failure, without opening a connection.
if [[ "$*" == *'/bin/bash'* ]]; then
    cat >/dev/null
    [[ ${FAIL_AT:-} != export ]]
fi
FAKE
cat > "$TEST_ROOT/bin/scp" <<'FAKE'
#!/usr/bin/env bash
touch "${!#}"
FAKE
cat > "$TEST_ROOT/bin/gunzip" <<'FAKE'
#!/usr/bin/env bash
mv "$1" "${1%.gz}"
FAKE
chmod +x "$TEST_ROOT/bin/"*
export PATH="$TEST_ROOT/bin:$PATH"

# Build hooks that deliberately fail before their final command. This catches
# the historical behavior where a later success silently masked a hook error.
function run_case() {
    local name=$1 expected=$2
    shift 2
    local dir="$TEST_ROOT/$name"
    mkdir -p "$dir/wp-env-sync"
    cat > "$dir/.env.wpenvsync" <<'ENV'
SSH_USER=fake-source
SSH_KEY_PATH=/fake-key
LOCAL_ENV=staging
REMOTE_ENV=prod
REMOTE_PATH=files
REMOTE_DOMAIN=production.invalid
LOCAL_DOMAIN=staging.invalid
FULL_REMOTE_PATH=/source/files
REMOTE_ENV_IS_HTTPS=true
LOCAL_ENV_IS_HTTPS=true
ENV
    cat > "$dir/wp-env-sync/before-db-import.sh" <<'HOOK'
printf 'before:%s\n' "$WP_ENV_SYNC_DB_IMPORTED" >> "$EVENTS"
if [[ ${FAIL_AT:-} == before ]]; then false; fi
printf 'before-end\n' >> "$EVENTS"
HOOK
    cat > "$dir/wp-env-sync/after-db-import.sh" <<'HOOK'
printf 'after:%s\n' "$WP_ENV_SYNC_DB_IMPORTED" >> "$EVENTS"
if [[ ${FAIL_AT:-} == after ]]; then false; fi
if [[ ${FAIL_AT:-} == pipeline ]]; then false | true; fi
printf 'after-end\n' >> "$EVENTS"
HOOK
    cat > "$dir/wp-env-sync/sync-prod-ext-staging.sh" <<'HOOK'
printf 'extension:%s\n' "$WP_ENV_SYNC_DB_IMPORTED" >> "$EVENTS"
if [[ ${FAIL_AT:-} == extension ]]; then false; fi
printf 'extension-end\n' >> "$EVENTS"
HOOK
    if [[ ${FAIL_AT:-} == search ]]; then
        printf '%s\n' 'false' 'echo should-not-reach' > "$dir/wp-env-sync/db-search-replace.sh"
    fi
    export EVENTS="$dir/events"
    touch "$EVENTS"
    local status=0
    (cd "$dir" && bash "$SCRIPT" --no-file-sync "$@") >"$dir/output" 2>&1 || status=$?
    if [[ $expected == success ]]; then
        [[ $status == 0 && ! -e "$dir/.maintenance" ]] || exit 1
        grep -q '^wp maintenance-mode deactivate$' "$EVENTS"
    else
        [[ $status != 0 && -e "$dir/.maintenance" ]] || exit 1
        grep -q 'upgrading = time();' "$dir/.maintenance"
        if grep -q '^wp maintenance-mode deactivate$' "$EVENTS"; then exit 1; fi
        if grep -q 'Sync completed' "$dir/output"; then exit 1; fi
    fi
    printf 'PASS %s\n' "$name"
}

run_case success success
# The after hook must run between import and search-replace, with correct markers.
python3 - "$EVENTS" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
assert lines.index('before:no') < lines.index('wp db reset --yes')
assert next(i for i,l in enumerate(lines) if l.startswith('wp db import ')) < lines.index('after:yes')
assert lines.index('after-end') < next(i for i,l in enumerate(lines) if l.startswith('wp search-replace '))
PY
run_case file_only success --no-db-sync
if grep -Eq '^(before|after):' "$EVENTS"; then exit 1; fi
grep -q '^extension:no$' "$EVENTS"
for phase in export before reset import after pipeline search extension; do
    export FAIL_AT=$phase
    run_case "failed_$phase" failure
    if [[ $phase == export || $phase == before || $phase == reset || $phase == import ]]; then
        if grep -q '^after:' "$EVENTS"; then exit 1; fi
    fi
    if [[ $phase == before || $phase == export ]]; then
        if grep -q '^wp db reset' "$EVENTS"; then exit 1; fi
    fi
done
unset FAIL_AT
printf 'All database lifecycle tests passed.\n'
