#!/usr/bin/env bash
# Disposable-root verification harness for the uv-profiles bash runtime.
# Usage: bash tests/Invoke-UvProfileVerification.sh
# Env:  UV_EXE       override the uv binary path
#       UV_PYTHON    override the --python value passed to uv venv (default 3.12)
set -u   # deliberately NOT -e: we assert on non-zero exits

UV_EXE="${UV_EXE:-}"
[ -n "$UV_EXE" ] || UV_EXE="$(command -v uv 2>/dev/null || true)"
[ -n "$UV_EXE" ] || { echo "uv not found on PATH (set UV_EXE)." >&2; exit 1; }

PY="${UV_PYTHON:-3.12}"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/uv-profile-verif.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
H="$ROOT/home"
mkdir -p "$H"
export HOME="$H"                 # isolate: the default WORKON_HOME points here
RR="$ROOT/profiles"
mkdir -p "$RR"
export WORKON_HOME="$RR"

fail() { echo "FAIL: $1" >&2; exit 1; }
check() {   # check <desc> <expected> <actual>
    [ "$2" = "$3" ] || fail "$1: expected [$2], got [$3]"
}
check_contains() {   # check_contains <desc> <needle> <haystack>
    case "$3" in *"$2"*) ;; *) fail "$1: expected to contain [$2], got [$3]";; esac
}
expect_error() {   # expect_error <desc> <pattern> cmd...  (cmd must fail, output must contain pattern)
    local desc="$1" pat="$2"; shift 2
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] || fail "$desc: expected failure, got success"
    check_contains "$desc" "$pat" "$out"
}

# --- fixture venvs (direct uv calls, before sourcing the runtime) ---
"$UV_EXE" venv "$RR/alpha" --python "$PY" >/dev/null || fail "create alpha"
"$UV_EXE" venv "$RR/beta" --python "$PY" >/dev/null || fail "create beta"
"$UV_EXE" venv "$RR/no_activate" --python "$PY" >/dev/null || fail "create no_activate"
rm -f "$RR/no_activate/bin/activate"
mkdir -p "$RR/missing_python/bin"
mkdir -p "$ROOT/working"

ARGS="$ROOT/capture_args.py"
cat > "$ARGS" <<'EOF'
import json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text(json.dumps(sys.argv[2:]), encoding="utf-8")
EOF
FR="$ROOT/exit_42.py"
cat > "$FR" <<'EOF'
import sys
sys.exit(42)
EOF
WL="$ROOT/[literal].py"
printf '%s\n' "print('wildcard path ran')" > "$WL"
CAP="$ROOT/captures with spaces.json"

RUNTIME="${RUNTIME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/src/uv-profile.sh}"
. "$RUNTIME"

# --- uv venv: managed names and passthrough ---
( cd "$ROOT/working" && uv venv named --python "$PY" >/dev/null ) || fail "named venv creation"
[ -f "$RR/named/bin/python" ] || fail "named venv python is under WORKON_HOME"
[ ! -e "$ROOT/working/named" ] || fail "named venv must not be created in CWD"

( cd "$ROOT/working" && uv venv "$ROOT/explicit" --python "$PY" >/dev/null ) || fail "explicit path venv"
[ -f "$ROOT/explicit/bin/python" ] || fail "explicit path venv python"
[ ! -e "$RR/explicit" ] || fail "explicit path venv must not be managed"

mkdir -p "$ROOT/dot-working"
( cd "$ROOT/dot-working" && uv venv .venv --python "$PY" >/dev/null ) || fail ".venv venv"
[ -f "$ROOT/dot-working/.venv/bin/python" ] || fail ".venv python"
[ ! -e "$RR/.venv" ] || fail ".venv must not be managed"

mkdir -p "$ROOT/option-working"
( cd "$ROOT/option-working" && uv venv --python "$PY" option-env >/dev/null ) || fail "option-first venv"
[ -f "$ROOT/option-working/option-env/bin/python" ] || fail "option-first python"
[ ! -e "$RR/option-env" ] || fail "option-first must not be managed"

mkdir -p "$ROOT/colon-working"
( cd "$ROOT/colon-working" && uv venv 'foo:bar' --python "$PY" >/dev/null ) || fail "colon path passthrough"
[ -d "$ROOT/colon-working/foo:bar" ] || fail "colon target created in CWD"
[ ! -e "$RR/foo:bar" ] || fail "colon target must not be managed"

check_contains 'venv help passthrough' 'Usage:' "$(uv venv -h 2>&1)"
expect_error 'invalid plain venv name' 'Invalid profile name' uv venv 'invalid.' --python "$PY"

( cd "$ROOT/working" && uv venv -- dash_marker --python "$PY" >/dev/null ) || fail "dash-marker venv"
[ -f "$RR/dash_marker/bin/python" ] || fail "dash-marker profile is managed under WORKON_HOME"
[ ! -e "$ROOT/working/dash_marker" ] || fail "dash-marker must not be created in CWD"

# --- runenv ---
check_contains 'runenv short help' 'Usage: uv runenv' "$(uv runenv -h 2>&1)"
check_contains 'runenv long help' 'Usage: uv runenv' "$(uv runenv --help 2>&1)"
expect_error 'bare runenv usage' 'Usage: uv runenv' uv runenv
expect_error 'runenv missing script' 'Usage: uv runenv' uv runenv alpha
expect_error 'runenv help-as-name' 'Invalid profile name' uv runenv --help alpha
expect_error 'runenv missing profile' "Profile 'missing'" uv runenv missing "$ARGS"
expect_error 'runenv missing python' 'bin/python' uv runenv missing_python "$ARGS"
expect_error 'runenv missing script file' 'was not found as a file' uv runenv alpha "$ROOT/not-there.py"
expect_error 'runenv directory as script' 'was not found as a file' uv runenv alpha "$ROOT"
expect_error 'runenv invalid name' "Invalid profile name 'bad/name'" uv runenv 'bad/name' "$ARGS"
expect_error 'runenv literal wildcard' 'missing*.py' uv runenv alpha "$ROOT/missing*.py"

uv runenv alpha "$ARGS" "$CAP" '--input' 'data file.csv' '--count' '3' '--input' 'second.csv' || fail "runenv arg passthrough"
check 'runenv captured args' '["--input", "data file.csv", "--count", "3", "--input", "second.csv"]' "$(cat "$CAP")"

uv RunEnv no_activate "$WL" || fail "case-insensitive subcommand RunEnv"

uv runenv alpha "$FR"; rc=$?
[ "$rc" -eq 42 ] || fail "runenv exit-code propagation: got $rc"

# --- profiles listing (before activation) ---
OUT="$(WORKON_HOME="$ROOT/empty-profiles" uv profiles)"
check_contains 'profiles on empty root' "No uv profiles found in '$ROOT/empty-profiles'." "$OUT"
rm -rf "$ROOT/empty-profiles"
OUT="$(uv profiles)"
check_contains 'profiles header' 'NAME' "$OUT"
check_contains 'profiles python column' 'PYTHON' "$OUT"
check_contains 'profiles status column' 'STATUS' "$OUT"
check_contains 'profiles lists alpha' 'alpha' "$OUT"
check_contains 'profiles inactive marker' 'inactive' "$OUT"

# --- activation ---
PS1_BEFORE='user@host:prompt$'
PATH_BEFORE="$PATH"
export PS1="$PS1_BEFORE"

uv activate alpha || fail "activate alpha"
check 'path prefix after activate' "$RR/alpha/bin" "${PATH%%:*}"
[ "${PATH%%:*}" = "$RR/alpha/bin" ] || fail "PATH prefix wrong: ${PATH%%:*}"
check 'VIRTUAL_ENV after activate' "$RR/alpha" "$VIRTUAL_ENV"
check 'VIRTUAL_ENV_PROMPT after activate' 'alpha' "$VIRTUAL_ENV_PROMPT"
check 'PS1 prefix after activate' "(alpha) $PS1_BEFORE" "$PS1"

OUT="$(uv activate alpha 2>&1)"
check_contains 're-activate message' "Profile 'alpha' is already active." "$OUT"
check 're-activate no drift (PATH prefix)' "$RR/alpha/bin" "${PATH%%:*}"

uv runenv no_activate "$ARGS" "$CAP" '--active-test' || fail "runenv while active"
PATH_ACT="$PATH"; VE_ACT="$VIRTUAL_ENV"; PROMPT_ACT="$PS1"
expect_error 'failed runenv while active' 'was not found as a file' uv runenv no_activate "$ROOT/not-there.py"
check 'active PATH preserved after failed runenv' "$PATH_ACT" "$PATH"
check 'active PS1 preserved after failed runenv' "$PROMPT_ACT" "$PS1"
check 'active VIRTUAL_ENV preserved after failed runenv' "$VE_ACT" "$VIRTUAL_ENV"

uv venv while_active --python "$PY" >/dev/null || fail "venv while active"
check 'active PATH preserved after venv' "$PATH_ACT" "$PATH"
check 'active PS1 preserved after venv' "$PROMPT_ACT" "$PS1"
check 'active VIRTUAL_ENV preserved after venv' "$VE_ACT" "$VIRTUAL_ENV"

deactivate
check 'deactivate restores PATH' "$PATH_BEFORE" "$PATH"
[ -z "${VIRTUAL_ENV:-}" ] || fail "deactivate unsets VIRTUAL_ENV"
[ -z "${VIRTUAL_ENV_PROMPT:-}" ] || fail "deactivate unsets VIRTUAL_ENV_PROMPT"
check 'deactivate restores PS1' "$PS1_BEFORE" "$PS1"

# --- switching profiles restores the pre-first-activation baseline ---
uv activate alpha || fail "switch: activate alpha"
uv activate beta || fail "switch: activate beta"
check 'switch: VIRTUAL_ENV is beta' "$RR/beta" "$VIRTUAL_ENV"
check 'switch: PS1 prefix is beta' "(beta) $PS1_BEFORE" "$PS1"
deactivate
check 'switch: PATH fully restored' "$PATH_BEFORE" "$PATH"
[ -z "${VIRTUAL_ENV:-}" ] || fail "switch: VIRTUAL_ENV not restored"
[ -z "${VIRTUAL_ENV_PROMPT:-}" ] || fail "switch: VIRTUAL_ENV_PROMPT not restored"
check 'switch: PS1 fully restored' "$PS1_BEFORE" "$PS1"

# --- pre-existing deactivate function is captured and restored ---
deactivate() { printf '%s\n' 'SAVED-DEACTIVATE'; }
uv activate alpha
check_contains 'managed deactivate replaces saved' '__uvp_clear' "$(declare -f deactivate)"
deactivate
check_contains 'saved deactivate restored' 'SAVED-DEACTIVATE' "$(declare -f deactivate)"

# --- external VIRTUAL_ENV guards ---
mkdir -p "$RR/stray"
export VIRTUAL_ENV="$RR/stray"
expect_error 'VIRTUAL_ENV inside WORKON_HOME rejected' 'inside WORKON_HOME without managed state' uv activate alpha
export VIRTUAL_ENV="$ROOT/outside"
mkdir -p "$ROOT/outside"
expect_error 'VIRTUAL_ENV outside rejected' 'points outside WORKON_HOME' uv activate alpha
unset VIRTUAL_ENV

# --- activate requires marker+python; missing profile ---
expect_error 'activate missing marker' 'not a valid uv profile' uv activate no_activate
expect_error 'activate missing profile' "Profile 'nope'" uv activate nope
expect_error 'activate whitespace-only name' 'Invalid profile name' uv activate '   '

# --- failed venv cases ---
O="$(uv venv failed --python 0.0.0 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "failed named venv must fail"
[ -n "$O" ] || fail "failed named venv must produce output"
O="$(uv venv named --python "$PY" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "existing named venv must fail"
[ -n "$O" ] || fail "existing named venv must produce output"

# --- passthrough verification ---
check_contains 'uv version passthrough' 'uv ' "$(uv --version 2>&1)"
check_contains 'uv run passthrough' 'run' "$(uv run --help 2>&1)"

# --- missing-uv behavior (child bash with uv removed from PATH) ---
CHILD="$ROOT/runenv-no-uv.sh"
cat > "$CHILD" <<EOF
#!/usr/bin/env bash
set -u
export WORKON_HOME="$RR"
UV_BIN="\$(dirname "$UV_EXE")"
PATH="\$(printf '%s' "\$PATH" | tr ':' '\n' | grep -vxF "\$UV_BIN" | paste -sd: -)"
. "$RUNTIME" 2> "$ROOT/load_err" || { echo "load failed: \$(cat "$ROOT/load_err")" >&2; exit 1; }
expect_err() {  # expect_err <pattern> cmd...
    local pat="\$1"; shift
    local out rc
    out="\$("\$@" 2>&1)"; rc=\$?
    [ \$rc -ne 0 ] || { echo "expected failure for \$*" >&2; exit 1; }
    case "\$out" in *"\$pat"*) ;; *) echo "expected [\$pat] in [\$out]" >&2; exit 1;; esac
}
uv runenv no_activate "$ARGS" "$CAP" '--without-uv' || { echo "runenv failed without uv" >&2; exit 1; }
[ -f "$CAP" ] || { echo "runenv did not execute without uv" >&2; exit 1; }
uv venv no_uv --python "$PY" >/dev/null 2>&1 && { echo "venv must fail without uv" >&2; exit 1; }
O="\$(uv --version 2>&1)"; rc=\$?
[ \$rc -ne 0 ] || { echo "passthrough must fail without uv" >&2; exit 1; }
case "\$O" in *'uv was not found on PATH'*) ;; *) echo "missing-uv message missing: \$O" >&2; exit 1;; esac
O="\$(uv profiles | head -1)"; rc=\$?
[ \$rc -eq 0 ] || { echo "profiles must work without uv" >&2; exit 1; }
echo 'missing-uv-child-ok'
EOF
OUTCHILD="$(bash "$CHILD")" || fail "missing-uv child verification"
check 'missing-uv child' 'missing-uv-child-ok' "$OUTCHILD"

echo 'All verification assertions passed.'
