#!/bin/bash
# Offline regression tests: all external WARP/network commands are mocked.
set -eu
# Resolved before PATH is mocked; the real lock test needs util-linux flock.
real_flock=$(command -v flock || true)
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v jq >/dev/null || ! command -v python3 >/dev/null; then
    echo 'Need jq and python3'
    exit 1
fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
export WARP_TEST_DIR="$work" WARP_LOCK_FILE="$work/warp.lock"
# APT files of the official repository are redirected into the test directory.
export WARP_APT_SOURCE="$work/apt/cloudflare-client.list" WARP_APT_KEYRING="$work/apt/cloudflare-warp.gpg"
export WARP_OS_RELEASE="$work/os-release"
mkdir "$work/apt"
printf 'VERSION_CODENAME=noble\n' > "$WARP_OS_RELEASE"
WARP_TEST_PGID=$(ps -o pgid= -p $$ | tr -d ' ')
export WARP_TEST_PGID
cat > "$work/bin/mock" <<'PY'
#!/usr/bin/env python3
import json, os, pathlib, signal, sys
root = pathlib.Path(os.environ['WARP_TEST_DIR'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
p = root / 'state.json'
s = json.loads(p.read_text())
with (root / 'calls.jsonl').open('a') as f:
    f.write(json.dumps([name] + args) + '\n')
if name == 'timeout':
    if args[0].startswith('--kill-after='):
        args = args[1:]
    os.execvp(args[1], args[1:])
if name == 'sleep':
    sys.exit(0)
if name == 'flock':
    if s.get('flock_busy'):
        sys.exit(1)
    if os.environ.get('REAL_FLOCK'):
        os.execv(os.environ['REAL_FLOCK'], ['flock'] + args)
    sys.exit(0)
if name == 'systemctl':
    if 'is-active' in args:
        sys.exit(int(s.get('service_down', False)))
    if 'is-enabled' in args:
        sys.exit(int(s.get('service_disabled', False)))
    if 'enable' in args:
        s['service_disabled'] = False
        p.write_text(json.dumps(s))
    sys.exit(0)
if name == 'dpkg-query':
    print('install ok installed')
    sys.exit(0)
if name == 'ss':
    if s.get('ss_fail'):
        sys.exit(1)
    if not s.get('no_listener'):
        address = '[::1]' if s.get('ipv6_listener') else '127.0.0.1'
        print(f"LISTEN 0 1024 {address}:{s['settings']['proxy_port']} 0.0.0.0:*")
        if s.get('public_listener'):
            print(f"LISTEN 0 1024 0.0.0.0:{s['settings']['proxy_port']} 0.0.0.0:*")
    sys.exit(0)
def inside_test_dir(path):
    if not os.path.realpath(path).startswith(os.path.realpath(root) + os.sep):
        print('mock refuses to write outside the test directory:', path, file=sys.stderr)
        sys.exit(97)
    return pathlib.Path(path)
if name == 'curl' and '-o' in args:
    pathlib.Path(args[args.index('-o') + 1]).write_text('PUBLIC KEY\n')
    sys.exit(7 if s.get('key_fail') else 0)
if name == 'gpg':
    if s.get('gpg_fail'):
        sys.exit(2)
    inside_test_dir(args[args.index('--output') + 1]).write_text('DEARMORED ' + pathlib.Path(args[-1]).read_text())
    sys.exit(0)
if name == 'apt-get':
    op = next(a for a in args if a in ('update', 'install', 'purge'))
    if op == 'update' and os.path.exists(os.environ['WARP_APT_SOURCE']):
        s['update_saw_source'] = pathlib.Path(os.environ['WARP_APT_SOURCE']).read_text()
        p.write_text(json.dumps(s))
    if s.get(op + '_fail'):
        print('E: simulated apt-get ' + op + ' failure', file=sys.stderr)
        sys.exit(100)
    if op == 'install':
        (root / 'apt-installed').touch()
    sys.exit(0)
if name == 'crontab':
    table = root / 'crontab'
    if args == ['-l']:
        if not table.exists():
            print('no crontab for test', file=sys.stderr)
            sys.exit(1)
        sys.stdout.write(table.read_text())
        sys.exit(0)
    table.write_text(sys.stdin.read())
    sys.exit(0)
if name == 'curl':
    dead = s['settings'].get('override_warp_endpoint') == '198.51.100.1:9'
    if s.get('curl_fail'):
        sys.exit(7)
    print('warp=' + ('off' if dead or s.get('trace_off') else s.get('trace_value', 'on')))
    print('ip=192.0.2.1\ncolo=TEST\nloc=ZZ')
    sys.exit(0)
if name == 'warpscout':
    report = root / 'fixture.txt'
    if report.exists():
        pathlib.Path(args[args.index('-o')+1]).write_text(report.read_text())
    print(s.get('candidate', '192.0.2.2:443'))
    sys.exit(s.get('scan_exit', 0))
if name != 'warp-cli':
    sys.exit(99)
if args == ['--version']:
    print(s.get('version', 'warp-cli 2026.8.2110.0'))
    sys.exit(0)
args = [a for a in args if a not in ('--accept-tos', '--json')]
# Simulates Ctrl+C or an SSH hangup: a signal to the whole process group of the menu session.
if s.get('signal_on') and args[:1] == s['signal_on'][:1]:
    s['signal_on'].pop(0)
    p.write_text(json.dumps(s))
    if os.getpgrp() == int(os.environ['WARP_TEST_PGID']):
        sys.exit(98)
    # Like a real CLI, die from SIGINT without a Python traceback; an inherited SIG_IGN
    # (the rollback ignores signals) stays in effect.
    if signal.getsignal(signal.SIGINT) is signal.default_int_handler:
        signal.signal(signal.SIGINT, signal.SIG_DFL)
    os.killpg(os.getpgrp(), getattr(signal, 'SIG' + s['signal_name']))
if '--help' in args:
    sys.exit(1 if s.get('no_capabilities') else 0)
cfg = s['settings']
if args in (['settings'], ['status'], ['registration', 'show']):
    failures = s.get('daemon_failures_remaining', 0)
    if failures:
        s['daemon_failures_remaining'] = failures - 1
        p.write_text(json.dumps(s))
    if failures or s.get('daemon_unavailable'):
        print(json.dumps({'code':'FailedToConnectToDaemon',
                          'error':'No such file or directory (os error 2)'}), file=sys.stderr)
        sys.exit(1)
if args == ['tunnel', 'stats']:
    if s.get('no_stats'):
        sys.exit(1)
    print(json.dumps({'protocol': s.get('transport', 'MASQUE (HTTPS via UDP)'),
                     'tls': {'sni': 'consumer-masque-proxy.cloudflareclient.com'}}))
    sys.exit(0)
if args == ['settings']:
    output = {'settings': {} if s.get('unknown_schema') else cfg}
    if not s.get('no_sources'):
        output['sources'] = s.get('sources', {k: 'user_set' for k in cfg})
    print(json.dumps(output))
    sys.exit(0)
if args == ['status']:
    print(json.dumps({'status': 'Connected' if cfg['always_on'] and not s.get('registration_missing') else 'Disconnected'}))
    sys.exit(0)
if args == ['registration', 'show']:
    if s.get('registration_error_code'):
        print(json.dumps({'code':s['registration_error_code'], 'error':'unexpected registration error'}), file=sys.stderr)
        sys.exit(1)
    if s.get('registration_error'):
        print('temporary daemon error', file=sys.stderr)
        sys.exit(1)
    if s.get('registration_missing'):
        if s.get('legacy_missing'):
            print('No registration', file=sys.stderr)
            sys.exit(1)
        print(json.dumps({'code':'MissingRegistration',
                          'error':'Missing registration. Try running: "warp-cli registration new"'}),
              file=sys.stdout if s.get('registration_error_zero_exit') else sys.stderr)
        sys.exit(0 if s.get('registration_error_zero_exit') else 1)
    print(json.dumps({'id': 'existing-registration'}))
    sys.exit(0)
if args == ['registration', 'new']:
    if s.get('registration_new_fail'):
        print(json.dumps({'code':'RegistrationFailed', 'error':'registration failed'}), file=sys.stderr)
        sys.exit(1)
    s['registration_missing'] = False
    p.write_text(json.dumps(s))
    print(json.dumps({'status': 'Success'}))
    sys.exit(0)
if args[:3] == ['tunnel', 'endpoint', 'set'] and s.pop('fail_set_once', False):
    p.write_text(json.dumps(s))
    print('simulated set failure', file=sys.stderr)
    sys.exit(1)
if args == ['disconnect']:
    cfg['always_on'] = False
elif args == ['connect']:
    if s.get('connect_fail'):
        sys.exit(1)
    cfg['always_on'] = True
elif args[:1] == ['mode']:
    if s.get('registration_missing'):
        print(json.dumps({'code':'MissingRegistration', 'error':'register first'}), file=sys.stderr)
        sys.exit(1)
    if s.get('mode_fail'):
        sys.exit(1)
    cfg['operation_mode'] = args[1]
elif args[:2] == ['proxy', 'port']:
    if s.get('registration_missing'):
        print(json.dumps({'code':'MissingRegistration', 'error':'register first'}), file=sys.stderr)
        sys.exit(1)
    if s.get('port_fail'):
        sys.exit(1)
    cfg['proxy_port'] = int(args[2])
elif args[:3] == ['tunnel', 'protocol', 'set']:
    cfg['warp_tunnel_protocol'] = args[3].lower()
elif args[:3] == ['tunnel', 'endpoint', 'set']:
    if not s.get('ignore_set'):
        cfg['override_warp_endpoint'] = args[3]
elif args == ['tunnel', 'endpoint', 'reset']:
    cfg.pop('override_warp_endpoint', None)
else:
    print('unhandled mock CLI command', args, file=sys.stderr)
    sys.exit(99)
p.write_text(json.dumps(s))
print(json.dumps({'status': 'Success'}))
PY
chmod +x "$work/bin/mock"
for name in warp-cli systemctl dpkg-query timeout ss curl sleep warpscout flock apt-get gpg crontab; do ln -s mock "$work/bin/$name"; done
export PATH="$work/bin:$PATH"
# Functions and globals are loaded from the canonical script without starting its menu.
# shellcheck disable=SC1091
source "$project_dir/menu_warp.sh"
export RED='' GREEN='' YELLOW='' CYAN='' BLUE='' NC=''
warp_health=''
warp_scan_sni=''
warp_endpoint=''
command() {
    # A command made missing by WARP_MISSING appears once the mocked apt-get installs it.
    if [ "${1:-}" = -v ] && [ "${2:-}" = "${WARP_MISSING:-}" ] && [ ! -e "$work/apt-installed" ]; then
        return 1
    fi
    builtin command "$@"
}
reset_state() {
    printf '%s\n' '{"settings":{"operation_mode":"proxy","proxy_port":45678,"always_on":true,"warp_tunnel_protocol":"masque","masque_http_version":"MASQUE (HTTP/2)"}}' > "$work/state.json"
    : > "$work/calls.jsonl"
    rm -f -- "$work/apt-installed" "$work/crontab" "$work/apt"/*
}
flag() {
    python3 - "$work/state.json" "$1" "$2" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); s=json.loads(p.read_text()); s[sys.argv[2]]=json.loads(sys.argv[3]); p.write_text(json.dumps(s))
PY
}
assert_no_registration_new() {
    python3 - "$work/calls.jsonl" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert not any(call[0]=='warp-cli' and call[-2:]==['registration','new'] for call in calls)
PY
}
assert_install_failure() {
    local expected_status="$1"
    jq -e --arg status "$expected_status" \
        '.status == $status and .operation.success == false and .operation.exitCode != 0' \
        "$work/result.json" >/dev/null
    test "$(wc -l < "$work/result.json")" -eq 1
    test -s "$work/stderr"
}
settings() { jq -Sc '.settings' "$work/state.json"; }
assert_health() {
    check_warp_health quiet || true
    test "$warp_health" = "$1" || { echo "Expected health $1, got $warp_health"; exit 1; }
}
assert_no_warp_mutation() {
    python3 - "$work/calls.jsonl" <<'PY'
import json, pathlib, sys
calls = [json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
for c in calls:
    if c[0] != 'warp-cli' or '--help' in c:
        continue
    args = [x for x in c[1:] if x not in ('--accept-tos', '--json')]
    assert args[:1] not in (['connect'], ['disconnect'], ['mode']), c
    assert args[:2] not in (['proxy', 'port'], ['registration', 'new']), c
    assert args[:3] not in (['tunnel', 'endpoint', 'set'], ['tunnel', 'endpoint', 'reset'],
                            ['tunnel', 'protocol', 'set']), c
PY
}
assert_called() {
    python3 - "$work/calls.jsonl" "$@" <<'PY'
import json, pathlib, sys
calls = [json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert sys.argv[2:] in calls, sys.argv[2:]
PY
}
# Bytes, mode and symlink target of the Cloudflare APT files, for exact restore checks.
apt_snapshot() {
    python3 - "$WARP_APT_SOURCE" "$WARP_APT_KEYRING" "$work/apt/keyring-target" <<'PY'
import hashlib, os, sys
for path in sys.argv[1:]:
    if os.path.islink(path):
        print(path, 'link', os.readlink(path))
    elif os.path.exists(path):
        print(path, oct(os.stat(path).st_mode & 0o777), hashlib.sha256(open(path, 'rb').read()).hexdigest())
    else:
        print(path, 'absent')
PY
}
assert_apt_call() {
    python3 - "$work/calls.jsonl" "$@" <<'PY'
import json, pathlib, sys
calls = [json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert any(c[0] == 'apt-get' and all(a in c for a in sys.argv[2:]) for c in calls), sys.argv[2:]
PY
}
fresh_unregistered_client() {
    python3 - "$work/state.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
state = json.loads(p.read_text())
state['settings']['operation_mode'] = 'warp'
state['settings']['always_on'] = False
del state['settings']['proxy_port']
state['registration_missing'] = True
p.write_text(json.dumps(state))
PY
}
reset_state
assert_health HEALTHY
WARP_MISSING=curl assert_health DEGRADED
WARP_MISSING=warp-cli assert_health DOWN
WARP_MISSING=jq assert_health DEGRADED
saved=$(settings)
if WARP_MISSING=curl apply_warp_change endpoint '192.0.2.1:443'; then exit 1; fi
test "$saved" = "$(settings)"
get_warp_scan_profile
test "$warp_scan_sni" = consumer-masque-proxy.cloudflareclient.com
flag transport '"MASQUE (HTTPS via TCP)"'
if get_warp_scan_profile; then echo 'Unknown transport accepted'; exit 1; fi
flag no_stats true
if get_warp_scan_profile; then echo 'Unverified transport accepted'; exit 1; fi
reset_state
flag version '"warp-cli 2099.1.0.0"'
get_warp_scan_profile
read_warp_state
test "$warp_endpoint" = AUTO
apply_warp_change endpoint '192.0.2.1:443'
apply_warp_change endpoint AUTO
for unknown in 'no_sources true' 'sources {}' 'sources {"new_endpoint_policy":"auto"}'; do
    reset_state
    read -r key value <<< "$unknown"
    flag "$key" "$value"
    read_warp_state
    test "$warp_endpoint" = UNKNOWN
    saved=$(settings)
    if apply_warp_change endpoint '192.0.2.1:443'; then echo 'Unknown AUTO state mutated'; exit 1; fi
    test "$saved" = "$(settings)"
done
for pair in 'service_down DOWN' 'no_listener DOWN' 'curl_fail DEGRADED' 'trace_off DEGRADED' 'unknown_schema DEGRADED'; do
    reset_state
    read -r setting expected <<< "$pair"
    flag "$setting" true
    assert_health "$expected"
done
reset_state
flag ipv6_listener true
assert_health HEALTHY
reset_state
flag ss_fail true
assert_health DEGRADED
reset_state
flag public_listener true
assert_health DOWN
reset_state
WARP_HEALTH_EXPECTED_PORT=40000 assert_health DOWN
unset WARP_HEALTH_EXPECTED_PORT
health_json=$(run_warp_cli_api health --port 45678 --json)
jq -e '.status == "HEALTHY" and .port == 45678 and .mode == "proxy"' <<< "$health_json" >/dev/null
if WARP_MISSING=jq run_warp_cli_api health --port 45678 --json > "$work/result.json"; then
    echo 'missing jq accepted as healthy' >&2; exit 1
else
    test "$?" -eq 2
fi
jq -e '.status == "DEGRADED"' "$work/result.json" >/dev/null
if run_warp_cli_api health --port 0 --json > "$work/result.json" 2>/dev/null; then
    echo 'invalid port accepted' >&2; exit 1
else
    test "$?" -eq 64
fi
test ! -s "$work/result.json"
reset_state
run_warp_cli_api install --port 40000 >/dev/null
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 40000
python3 - "$work/calls.jsonl" <<'PYCLI'
import json,pathlib,sys
calls=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert any(c[0]=='warp-cli' and c[-2:]==['registration','show'] for c in calls)
assert not any(c[0]=='warp-cli' and c[-2:]==['registration','new'] for c in calls)
assert not any(c[0]=='warpscout' for c in calls)
PYCLI
reset_state
run_warp_cli_api install --port 45678 --json > "$work/result.json" 2> "$work/stderr"
jq -e '.status == "HEALTHY" and .operation.success == true' "$work/result.json" >/dev/null
test "$(wc -l < "$work/result.json")" -eq 1
python3 - "$work/calls.jsonl" <<'PYCLI'
import json, pathlib, sys
calls=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
mutations={('disconnect',), ('connect',), ('mode','proxy'), ('proxy','port','45678'),
           ('registration','new')}
assert not any(c[0]=='systemctl' and c[1] in ('start','restart','enable') for c in calls)
assert not any(c[0]=='warp-cli' and tuple(x for x in c[1:] if x not in ('--accept-tos','--json')) in mutations for c in calls)
assert not any(c[0]=='warpscout' for c in calls)
PYCLI
reset_state
flag registration_error true
flag trace_off true
if run_warp_cli_api install --port 40000 --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'registration read failure accepted' >&2; exit 1
fi
jq -e '.operation.success == false and .operation.exitCode != 0' "$work/result.json" >/dev/null
test -s "$work/stderr"
if grep -E 'registration.*new' "$work/calls.jsonl"; then echo 'unexpected registration' >&2; exit 1; fi
reset_state
flag trace_off true
if run_warp_cli_api install --port 45678 --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'unverified WARP accepted' >&2; exit 1
else
    test "$?" -eq 2
fi
jq -e '.status == "DEGRADED" and .operation.success == true' "$work/result.json" >/dev/null
reset_state
flag port_fail true
if run_warp_cli_api install --port 40000 --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'failed configuration accepted' >&2; exit 1
fi
jq -e '.operation.success == false' "$work/result.json" >/dev/null
reset_state
flag registration_missing true
run_warp_cli_api install --port 40000 >/dev/null
python3 - "$work/calls.jsonl" <<'PYCLI'
import json,pathlib,sys
calls=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
commands=[c[1:] for c in calls if c[0]=='warp-cli']
commands=[[x for x in c if x not in ('--accept-tos','--json')] for c in commands]
assert ['registration','new'] in commands
assert commands.index(['registration','new']) < commands.index(['proxy','port','40000'])
PYCLI
test "$(jq -r '.registration_missing' "$work/state.json")" = false
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 40000
assert_health HEALTHY

# A fresh 2026 CLI omits proxy_port until proxy mode is configured.
reset_state
python3 - "$work/state.json" <<'PYCLI'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
state = json.loads(p.read_text())
state['settings']['operation_mode'] = 'warp'
state['settings']['always_on'] = False
del state['settings']['proxy_port']
state['registration_missing'] = True
p.write_text(json.dumps(state))
PYCLI
run_warp_cli_api install --port 40000 --json > "$work/result.json" 2> "$work/stderr"
jq -e '.status == "HEALTHY" and .operation.success == true and .port == 40000' "$work/result.json" >/dev/null
test "$(jq -r '.settings.operation_mode' "$work/state.json")" = proxy
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 40000
assert_health HEALTHY

# An absent port remains invalid when CLI claims it is already in proxy mode.
reset_state
python3 - "$work/state.json" <<'PYCLI'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
state = json.loads(p.read_text())
del state['settings']['proxy_port']
p.write_text(json.dumps(state))
PYCLI
assert_health DEGRADED

# A JSON error remains an error even if a CLI release returns exit status zero.
reset_state
flag registration_missing true
flag registration_error_zero_exit true
run_warp_cli_api install --port 40000 --json > "$work/result.json" 2> "$work/stderr"
jq -e '.status == "HEALTHY" and .operation.success == true' "$work/result.json" >/dev/null
assert_health HEALTHY

# The old text response remains a deliberately narrow compatibility fallback.
reset_state
flag registration_missing true
flag legacy_missing true
run_warp_cli_api install --port 40000 >/dev/null
assert_health HEALTHY

# An installed but unregistered client must be repairable from the menu path.
reset_state
flag registration_missing true
install_official_warp 40000 0 > "$work/interactive-output" 2> "$work/stderr"
test "$(jq -r '.registration_missing' "$work/state.json")" = false
assert_health HEALTHY

# A running systemd unit is not evidence that CLI IPC works. A transient
# daemon failure is retried, while a persistent one stops without registration.
reset_state
WARP_MISSING=warp-cli show_warp_connection > "$work/diagnostics"
grep -Eq 'Пакет WARP: установлен' "$work/diagnostics"
grep -Eq 'CLI/daemon: недоступен' "$work/diagnostics"
flag daemon_unavailable true
show_warp_connection > "$work/diagnostics" 2> "$work/stderr"
grep -Eq 'Пакет WARP: установлен' "$work/diagnostics"
grep -Eq 'CLI/daemon: недоступен' "$work/diagnostics"
grep -Eq 'Регистрация: не определена' "$work/diagnostics"
if grep -Eq 'РАБОТАЕТ|HEALTHY' "$work/diagnostics"; then
    echo 'Daemon failure shown as healthy' >&2; exit 1
fi
if run_warp_cli_api install --port 40000 --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'Unreachable daemon accepted' >&2; exit 1
fi
assert_install_failure DEGRADED
grep -Eq 'WARP daemon недоступен' "$work/stderr"
assert_no_registration_new
reset_state
flag daemon_failures_remaining 3
run_warp_cli_api install --port 45678 --json > "$work/result.json" 2> "$work/stderr"
jq -e '.status == "HEALTHY" and .operation.success == true' "$work/result.json" >/dev/null
assert_no_registration_new

# Unknown JSON errors and a failed registration never authorize config changes.
reset_state
flag registration_error_code '"FutureRegistrationError"'
if run_warp_cli_api install --port 40000 --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'Unknown registration error accepted' >&2; exit 1
fi
assert_install_failure DOWN
assert_no_registration_new
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45678
reset_state
flag registration_missing true
flag registration_new_fail true
if run_warp_cli_api install --port 40000 --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'Failed registration accepted' >&2; exit 1
fi
assert_install_failure DOWN
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45678

# Configuration and connect failures must propagate through the original API.
reset_state
python3 - "$work/state.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); s=json.loads(p.read_text())
s['settings']['operation_mode']='warp'; s['mode_fail']=True
p.write_text(json.dumps(s))
PY
if run_warp_cli_api install --port 40000 --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'Failed mode change accepted' >&2; exit 1
fi
assert_install_failure DOWN
reset_state
flag port_fail true
if run_warp_cli_api install --port 40000 --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'Failed port change accepted' >&2; exit 1
fi
assert_install_failure DOWN
reset_state
flag connect_fail true
python3 - "$work/state.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); s=json.loads(p.read_text())
s['settings']['always_on']=False
p.write_text(json.dumps(s))
PY
if run_warp_cli_api install --port 45678 --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'Failed connect accepted' >&2; exit 1
fi
assert_install_failure DOWN
for endpoint in '192.0.2.1:443' '[2001:db8::1]:1701' '[::ffff:192.0.2.1]:443'; do validate_warp_endpoint "$endpoint"; done
test "$(normalize_warp_endpoint '[2001:0DB8::1]:00443')" = '[2001:db8::1]:443'
for endpoint in '1.2.3.999:443' 'example.com:443' '[1.2.3.4]:443' '::1:443' '[:::1]:443' '1.2.3.4:0' '1.2.3.4:65536' '1.2.3.4:443;id' '1.2.3.4:٤٤٣' $'1.2.3.4:443\n127.0.0.1:22'; do
    if validate_warp_endpoint "$endpoint"; then echo 'Invalid endpoint accepted'; exit 1; fi
done
reset_state
apply_warp_change endpoint '[2001:0DB8::1]:00443'
test "$(jq -r '.settings.override_warp_endpoint' "$work/state.json")" = '[2001:db8::1]:443'
apply_warp_change endpoint AUTO
apply_warp_change endpoint '192.0.2.1:443'
test "$(jq -r '.settings.override_warp_endpoint' "$work/state.json")" = '192.0.2.1:443'
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45678
saved=$(settings)
if apply_warp_change endpoint '198.51.100.1:9'; then echo 'Dead endpoint accepted'; exit 1; fi
test "$saved" = "$(settings)"
flag fail_set_once true
if apply_warp_change endpoint '192.0.2.2:443'; then echo 'Set failure accepted'; exit 1; fi
test "$saved" = "$(settings)"
flag ignore_set true
if apply_warp_change endpoint '192.0.2.2:443'; then echo 'Ignored set accepted'; exit 1; fi
test "$saved" = "$(settings)"
flag ignore_set false
apply_warp_change endpoint AUTO
test "$(jq -r '.settings | has("override_warp_endpoint")' "$work/state.json")" = false
apply_warp_change port 45679
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45679
saved=$(settings)
if apply_warp_change protocol wireguard; then echo 'WireGuard allowed in proxy'; exit 1; fi
test "$saved" = "$(settings)"
reset_state
warp_cli disconnect >/dev/null
saved=$(settings)
if apply_warp_change endpoint '198.51.100.1:9'; then exit 1; fi
test "$saved" = "$(settings)"
reset_state
flag unknown_schema true
saved=$(settings)
if apply_warp_change endpoint '192.0.2.1:443'; then echo 'Unknown state mutated'; exit 1; fi
test "$saved" = "$(settings)"
reset_state
flag no_capabilities true
if apply_warp_change endpoint '192.0.2.1:443'; then echo 'Unknown CLI mutated'; exit 1; fi
python3 - "$work/calls.jsonl" <<'PY'
import json,pathlib,sys
calls=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert not any(c[0]=='warp-cli' and '--help' not in c and 'endpoint' in c and 'set' in c for c in calls)
PY
reset_state
assert_health HEALTHY
python3 - "$work/calls.jsonl" <<'PY'
import json,pathlib,sys
calls=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
c=next(c for c in calls if c[0]=='curl')
assert c[1]=='--disable' and c[c.index('--noproxy')+1]==''
assert c[c.index('--proxy')+1]=='socks5h://127.0.0.1:45678'
assert '--connect-timeout' in c and '--max-time' in c
PY
# Plain report parsing and both upstream scan modes; display failures must not prevent apply.
reset_state
export warpscout_bin="$work/bin/warpscout"
export warpscout_dir="$work"
export warpscout_account="$work/account.json"
warp_candidate_endpoint=''
warp_candidate_metrics=''
warp_scan_sni=consumer-masque-proxy.cloudflareclient.com
mkdir "$work/result"
cat > "$work/fixture.txt" <<'REPORT'
# WARP endpoints: 3 working / 3 probed
ENDPOINT              ENDPOINT PING TUN PING LOSS SPEED SEEN AS NODE NODE LOCATION
192.0.2.20:443        1ms           9ms      1%   999.1 Mbps ZZ TEST Somewhere
192.0.2.2:443         2ms           18.2ms   0%   487.3 Mbps ZZ TEST Somewhere
192.0.2.3:443         3ms           -        -    - ZZ TEST Somewhere

# Best endpoint per node
192.0.2.2:443 1ms 1ms 0% 999.9 Mbps ZZ TEST Elsewhere
REPORT
scan_official_warp_candidate speed "$work/result"
test "$warp_candidate_endpoint" = 192.0.2.2:443
test "$(jq -r '.speed' <<< "$warp_candidate_metrics")" = '487.3 Mbps'
test "$(jq -r '.ping' <<< "$warp_candidate_metrics")" = 18.2ms
test "$(jq -r '.loss' <<< "$warp_candidate_metrics")" = 0%
read_warp_candidate_metrics "$work/fixture.txt" 192.0.2.3:443 | jq -e 'all(.[]; . == null)' >/dev/null
read_warp_candidate_metrics "$work/fixture.txt" 192.0.2.21:443 | jq -e 'all(.[]; . == null)' >/dev/null
# latency format has no SPEED column.
cat > "$work/fixture.txt" <<'REPORT'
# WARP endpoints
ENDPOINT ENDPOINT PING TUN PING LOSS SEEN AS NODE NODE LOCATION
192.0.2.2:443 1ms 750µs 2% ZZ TEST Somewhere
REPORT
scan_official_warp_candidate latency "$work/result"
jq -e '.speed == null and .ping == "750µs" and .loss == "2%"' <<< "$warp_candidate_metrics" >/dev/null
python3 - "$work/calls.jsonl" <<'PYARGS'
import json, pathlib, sys
calls=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
scans=[c for c in calls if c[0]=='warpscout']
assert len(scans)==2
for c in scans:
    assert c[1]=='scan' and '-P' in c and '-best' in c and '-plain' in c
    assert c[c.index('-p')+1]=='masque'
    assert c[c.index('-masque-sni')+1]=='consumer-masque-proxy.cloudflareclient.com'
    assert '-exclude-node' not in c
assert scans[0][scans[0].index('-best-by')+1]=='speed'
assert '-best-by' not in scans[1]
PYARGS
for report in absent partial malformed duplicate; do
    rm -f "$work/fixture.txt" "$work/result/report.txt"
    case "$report" in
        partial) printf 'ENDPOINT ENDPOINT PING TUN PING LOSS SPEED SEEN AS NODE NODE LOCATION\n192.0.2.2:443 1ms' > "$work/fixture.txt" ;;
        malformed) printf 'changed format\n192.0.2.2:443 1ms 2ms 0%% 500 Mbps' > "$work/fixture.txt" ;;
        duplicate) printf 'ENDPOINT ENDPOINT PING TUN PING LOSS SPEED SEEN AS NODE NODE LOCATION\n192.0.2.2:443 1ms 2ms 0%% 500 Mbps ZZ TEST Here\n192.0.2.2:443 1ms 3ms 0%% 100 Mbps ZZ TEST Here\n' > "$work/fixture.txt" ;;
    esac
    scan_official_warp_candidate speed "$work/result"
    jq -e 'all(.[]; . == null)' <<< "$warp_candidate_metrics" >/dev/null
    apply_warp_change endpoint "$warp_candidate_endpoint" speed "$warp_candidate_metrics"
done
saved=$(settings)
flag scan_exit 130
if scan_official_warp_candidate speed "$work/result"; then echo 'Cancelled scan accepted'; exit 1; fi
test "$saved" = "$(settings)"
flag scan_exit 0
for candidate in '"invalid endpoint"' '""' '"192.0.2.2:443\n192.0.2.3:443"'; do
    flag candidate "$candidate"
    if scan_official_warp_candidate speed "$work/result"; then echo 'Invalid candidate accepted'; exit 1; fi
done
for port in 40000 40001; do
    apply_warp_change port "$port"
    generate_warp_xray_outbound | jq -e --argjson port "$port" '
        . == {tag:"warp-outbound",protocol:"socks",settings:{servers:[{address:"127.0.0.1",port:$port,users:[]}]}}' >/dev/null
done
warp_cli mode warp >/dev/null
if generate_warp_xray_outbound; then echo 'Non-proxy snippet accepted'; exit 1; fi
# Post-install recovery must not offer a scan without a verified transport profile.
reset_state
for unavailable in 'no_stats true' 'transport "MASQUE (HTTPS via TCP)"'; do
    reset_state
    read -r key value <<< "$unavailable"
    flag "$key" "$value"
    saved=$(settings)
    if recovery_output=$(
        # Callback invoked indirectly by the sourced recovery function.
        # shellcheck disable=SC2329
        optimize_warp_endpoint() { echo 'UNEXPECTED OPTIMIZER'; }
        offer_warp_endpoint_recovery <<< y
    ); then echo 'Unavailable recovery accepted'; exit 1; fi
    [[ "$recovery_output" == *'transport profile не удалось подтвердить'* ]]
    [[ "$recovery_output" == *'подбор endpoint через WARPSCOUT сейчас недоступен'* ]]
    [[ "$recovery_output" != *'UNEXPECTED OPTIMIZER'* ]]
    test "$saved" = "$(settings)"
done
reset_state
recovery_output=$(
    # shellcheck disable=SC2329
    optimize_warp_endpoint() { echo 'VERIFIED OPTIMIZER'; }
    offer_warp_endpoint_recovery <<< y
)
test "$recovery_output" = 'VERIFIED OPTIMIZER'
if (
    # shellcheck disable=SC2329
    optimize_warp_endpoint() { echo 'Unexpected optimization after decline'; }
    offer_warp_endpoint_recovery <<< n
); then echo 'Declined recovery accepted'; exit 1; fi

# regression: a repeated menu install keeps a custom SOCKS5 port
reset_state
install_official_warp > "$work/out" 2>&1
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45678
assert_no_warp_mutation

# regression: an unhealthy custom-port install fails without moving the port
reset_state
flag trace_off true
if install_official_warp > "$work/out" 2>&1; then echo 'Unverified install accepted' >&2; exit 1; fi
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45678
assert_no_warp_mutation

# regression: a mode repair keeps the configured proxy port
reset_state
warp_cli disconnect >/dev/null
warp_cli mode warp >/dev/null
: > "$work/calls.jsonl"
install_official_warp > "$work/out" 2>&1
test "$(jq -r '.settings.operation_mode' "$work/state.json")" = proxy
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45678

# regression: a new setup without --port uses 40000
reset_state
fresh_unregistered_client
install_official_warp > "$work/out" 2>&1
test "$(jq -r '.settings.operation_mode' "$work/state.json")" = proxy
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 40000
assert_health HEALTHY

# regression: CLI install without --port keeps the configured port
reset_state
run_warp_cli_api install --json > "$work/result.json" 2> "$work/stderr"
jq -e '.status == "HEALTHY" and .port == 45678 and .operation == {success:true,exitCode:0}' \
    "$work/result.json" >/dev/null
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45678
assert_no_warp_mutation

# regression: CLI health without --port checks the configured port
reset_state
run_warp_cli_api health --json > "$work/result.json"
jq -e '.status == "HEALTHY" and .port == 45678' "$work/result.json" >/dev/null

# regression: an explicit --port stays strict for health and is applied by install
reset_state
if run_warp_cli_api health --port 40000 --json > "$work/result.json"; then
    echo 'Port mismatch accepted' >&2; exit 1
else
    test "$?" -eq 3
fi
jq -e '.status == "DOWN" and .port == 45678' "$work/result.json" >/dev/null
run_warp_cli_api install --port 08080 --json > "$work/result.json" 2> "$work/stderr"
jq -e '.status == "HEALTHY" and .port == 8080 and .operation.success == true' "$work/result.json" >/dev/null
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 8080
grep -q 'warp-outbound' "$work/stderr"
for args in '--port' '--port --json' '--port 0'; do
    # shellcheck disable=SC2086
    if run_warp_cli_api install $args > "$work/result.json" 2>/dev/null; then
        echo "Invalid install arguments accepted: $args" >&2; exit 1
    else
        test "$?" -eq 64
    fi
done
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 8080

# regression: the JSON field set is unchanged
reset_state
run_warp_cli_api health --port 45678 --json > "$work/result.json"
jq -e 'keys == ["colo","endpoint","exitIp","location","mode","port","reason","status"]' \
    "$work/result.json" >/dev/null
run_warp_cli_api install --port 45678 --json > "$work/result.json" 2>/dev/null
jq -e '(keys == ["colo","endpoint","exitIp","location","mode","operation","port","reason","status"]) and
    (.operation | keys == ["exitCode","success"])' "$work/result.json" >/dev/null

# regression: a WARP+ trace (warp=plus) is HEALTHY and reported as such; warp=off is not
reset_state
flag trace_value '"plus"'
assert_health HEALTHY
apply_warp_change endpoint '192.0.2.1:443' > "$work/out"
grep -q 'warp=plus' "$work/out"
if grep -q 'warp=on' "$work/out"; then echo 'WARP+ reported as warp=on' >&2; exit 1; fi
reset_state
flag trace_value '"off"'
assert_health DEGRADED

# regression: an active but disabled warp-svc is enabled by install
reset_state
flag service_disabled true
install_official_warp > "$work/out" 2>&1
assert_called systemctl enable warp-svc
test "$(jq -r '.service_disabled' "$work/state.json")" = false
assert_no_warp_mutation

# regression: a port change tells the user to update the Xray outbound
reset_state
apply_warp_change port 45679 > "$work/out"
grep -q 'warp-outbound' "$work/out"

# regression: an unknown settings schema blocks a repeated install without changes
reset_state
flag unknown_schema true
if run_warp_cli_api install --json > "$work/result.json" 2> "$work/stderr"; then
    echo 'Unknown schema install accepted' >&2; exit 1
fi
jq -e '.status == "DEGRADED" and .operation.success == false' "$work/result.json" >/dev/null
assert_no_warp_mutation

# regression: install takes the WARP lock before its first change
reset_state
warp_cli disconnect >/dev/null
warp_cli mode warp >/dev/null
: > "$work/calls.jsonl"
install_official_warp > "$work/out" 2>&1
python3 - "$work/calls.jsonl" <<'PY'
import json, pathlib, sys
calls = [json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
names = [c[0] if c[0] != 'warp-cli' else ' '.join(x for x in c[1:] if x not in ('--accept-tos', '--json'))
         for c in calls]
assert 'flock' in names and 'mode proxy' in names, names
assert names.index('flock') < names.index('mode proxy'), names
PY

# regression: a healthy install only reads state and does not wait for the lock
reset_state
install_official_warp > "$work/out" 2>&1
if grep -q '"flock"' "$work/calls.jsonl"; then echo 'Healthy install took the lock' >&2; exit 1; fi

# regression: a busy WARP lock stops install and apply without changes
reset_state
warp_cli disconnect >/dev/null
warp_cli mode warp >/dev/null
flag flock_busy true
saved=$(settings)
if install_official_warp > "$work/out" 2>&1; then echo 'Locked install accepted' >&2; exit 1; fi
grep -q 'Другая операция WARP' "$work/out"
test "$saved" = "$(settings)"
reset_state
flag flock_busy true
saved=$(settings)
if apply_warp_change port 45679 > "$work/out" 2>&1; then echo 'Locked apply accepted' >&2; exit 1; fi
grep -q 'Другая операция WARP' "$work/out"
test "$saved" = "$(settings)"
if toggle_warp_service > "$work/out" 2>&1; then echo 'Locked stop accepted' >&2; exit 1; fi
if grep -q '"stop"' "$work/calls.jsonl"; then echo 'Stopped during a locked change' >&2; exit 1; fi
flag flock_busy false
toggle_warp_service
assert_called systemctl stop warp-svc

# regression: a concurrent holder of the real WARP lock blocks install and apply
if [ -n "$real_flock" ]; then
    reset_state
    warp_cli disconnect >/dev/null
    warp_cli mode warp >/dev/null
    saved=$(settings)
    exec 8>>"$WARP_LOCK_FILE"
    "$real_flock" -n 8
    if REAL_FLOCK="$real_flock" install_official_warp > "$work/out" 2>&1; then
        echo 'Concurrent install accepted' >&2; exit 1
    fi
    test "$saved" = "$(settings)"
    exec 8>&-
    REAL_FLOCK="$real_flock" install_official_warp > "$work/out" 2>&1
    test "$(jq -r '.settings.operation_mode' "$work/state.json")" = proxy
    saved=$(settings)
    exec 8>>"$WARP_LOCK_FILE"
    "$real_flock" -n 8
    if REAL_FLOCK="$real_flock" apply_warp_change port 45679 > "$work/out" 2>&1; then
        echo 'Concurrent apply accepted' >&2; exit 1
    fi
    test "$saved" = "$(settings)"
    exec 8>&-
else
    echo 'SKIP: util-linux flock is not available; real lock contention not tested'
fi

# regression: a failed rollback is reported and the restorable settings are restored
reset_state
saved=$(jq -c '.settings | del(.always_on)' "$work/state.json")
flag connect_fail true
if apply_warp_change port 45679 > "$work/out" 2>&1; then echo 'Failed change accepted' >&2; exit 1; fi
grep -q 'Rollback не подтверждён' "$work/out"
test "$saved" = "$(jq -c '.settings | del(.always_on)' "$work/state.json")"

# regression: Ctrl+C or an SSH hangup during a change, once or repeated during rollback, still restores it
for signal_case in 'INT ["connect"]' 'INT ["connect","mode"]' 'HUP ["connect"]' 'HUP ["connect","mode"]'; do
    read -r sig signal_plan <<< "$signal_case"
    reset_state
    saved=$(settings)
    flag signal_on "$signal_plan"
    flag signal_name "\"$sig\""
    # The menu runs in its own session and receives the signal as a process group, like a
    # terminal sends it. The trailing exit forks the change subshell as in the menu loop.
    signal_rc=0
    signal_out=$(python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
        bash -c 'source "$1"; apply_warp_change port 45679; exit $?' _ "$project_dir/menu_warp.sh" 2>&1) ||
        signal_rc=$?
    # Both signals were sent, the change ended through the signal path, and the user sees
    # one verified rollback; a lost or suppressed signal would let the change succeed instead.
    expected_rc=130
    [ "$sig" = INT ] || expected_rc=129
    if [ "$(jq -c '.signal_on' "$work/state.json")" != '[]' ] || [ "$signal_rc" -ne "$expected_rc" ] ||
        [ "$(grep -c 'Изменение не прошло проверку' <<< "$signal_out")" -ne 1 ] ||
        [ "$(grep -c 'Rollback завершён' <<< "$signal_out")" -ne 1 ] ||
        grep -q 'Настройки применены\|Traceback' <<< "$signal_out"; then
        printf 'SIG%s %s rollback (exit %s) output:\n%s\n' "$sig" "$signal_plan" "$signal_rc" "$signal_out" >&2
        exit 1
    fi
    test "$saved" = "$(settings)"
done
# regression: a new install writes the Cloudflare APT source and installs the package
reset_state
fresh_unregistered_client
WARP_MISSING=warp-cli install_official_warp > "$work/out" 2>&1
test "$(cat "$WARP_APT_SOURCE")" = "deb [signed-by=$WARP_APT_KEYRING] https://pkg.cloudflareclient.com/ noble main"
test "$(cat "$WARP_APT_KEYRING")" = 'DEARMORED PUBLIC KEY'
assert_apt_call update
assert_apt_call install cloudflare-warp
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 40000
assert_health HEALTHY

# regression: a failed apt-get update removes the APT files this install created
reset_state
fresh_unregistered_client
flag update_fail true
if WARP_MISSING=warp-cli install_official_warp > "$work/out" 2>&1; then echo 'Failed update accepted' >&2; exit 1; fi
jq -e '.update_saw_source | startswith("deb [signed-by=")' "$work/state.json" >/dev/null
test "$(apt_snapshot)" = "$WARP_APT_SOURCE absent
$WARP_APT_KEYRING absent
$work/apt/keyring-target absent"
grep -q 'apt-get update' "$work/out"
grep -q 'simulated apt-get update failure' "$work/out"

# regression: a failed APT setup restores pre-existing files, modes and symlinks exactly
for failure in update_fail gpg_fail key_fail install_fail; do
    reset_state
    fresh_unregistered_client
    printf 'deb [signed-by=/old.gpg] https://example.invalid/ old main\n' > "$WARP_APT_SOURCE"
    chmod 640 "$WARP_APT_SOURCE"
    printf 'OLD KEY\n' > "$work/apt/keyring-target"
    chmod 600 "$work/apt/keyring-target"
    ln -s keyring-target "$WARP_APT_KEYRING"
    before=$(apt_snapshot)
    flag "$failure" true
    if WARP_MISSING=warp-cli install_official_warp > "$work/out" 2>&1; then
        echo "APT setup with $failure accepted" >&2; exit 1
    fi
    test "$before" = "$(apt_snapshot)" || { echo "APT files changed after $failure" >&2; exit 1; }
done

# regression: a package install failure after a good update leaves no APT files of its own
reset_state
fresh_unregistered_client
flag install_fail true
if WARP_MISSING=warp-cli install_official_warp > "$work/out" 2>&1; then echo 'Failed install accepted' >&2; exit 1; fi
assert_apt_call install cloudflare-warp
test ! -e "$WARP_APT_SOURCE"
test ! -e "$WARP_APT_KEYRING"
grep -q 'cloudflare-warp не установлен' "$work/out"

# regression: a failed purge is reported truthfully, keeps cron and APT files, and can be retried
reset_state
printf 'deb [signed-by=%s] https://pkg.cloudflareclient.com/ noble main\n' "$WARP_APT_KEYRING" > "$WARP_APT_SOURCE"
printf 'KEY\n' > "$WARP_APT_KEYRING"
printf '%s\n' '# keep' 'MAILTO=root' '0 3 * * * systemctl restart warp-svc >/dev/null 2>&1' \
    '15 2 * * * /usr/local/bin/backup.sh' > "$work/crontab"
cron_before=$(cat "$work/crontab")
flag purge_fail true
if uninstall_official_warp > "$work/out" 2>&1; then echo 'Failed purge accepted' >&2; exit 1; fi
grep -q 'simulated apt-get purge failure' "$work/out"
grep -q 'purge cloudflare-warp не выполнен' "$work/out"
if grep -q '✅' "$work/out"; then echo 'Failed purge reported as removed' >&2; exit 1; fi
assert_apt_call purge cloudflare-warp DPkg::Lock::Timeout=600
test -e "$WARP_APT_SOURCE"
test -e "$WARP_APT_KEYRING"
test "$cron_before" = "$(cat "$work/crontab")"

# Retrying after the APT problem is fixed removes WARP, its APT files and only its cron rule.
flag purge_fail false
uninstall_official_warp > "$work/out" 2>&1
test ! -e "$WARP_APT_SOURCE"
test ! -e "$WARP_APT_KEYRING"
test "$(cat "$work/crontab")" = "$(printf '%s\n' '# keep' 'MAILTO=root' '15 2 * * * /usr/local/bin/backup.sh')"
grep -q 'warp-outbound' "$work/out"

# regression: a busy WARP lock stops uninstall before anything is removed
reset_state
printf 'KEY\n' > "$WARP_APT_KEYRING"
flag flock_busy true
if uninstall_official_warp > "$work/out" 2>&1; then echo 'Locked uninstall accepted' >&2; exit 1; fi
if grep -q '"apt-get"' "$work/calls.jsonl"; then echo 'Purge ran under a busy lock' >&2; exit 1; fi
if grep -q '"disable"' "$work/calls.jsonl"; then echo 'Service disabled under a busy lock' >&2; exit 1; fi
test -e "$WARP_APT_KEYRING"
echo 'PASS: guarded recovery prompt, Xray warp-outbound/users/actual ports; speed/latency arguments, exact metrics and degraded reports, future compatible schema, unknown AUTO; health layers, endpoint validation, apply, readback, port preservation, rollback (AUTO/custom/disconnected), unknown schema/CLI, protocol isolation, SOCKS DNS/timeouts.'
