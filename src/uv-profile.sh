# uv-profiles bash runtime (Linux/WSL)
# Dot-sourced from ~/.bashrc by install.sh. POSIX venv layout only:
# bin/python, bin/activate marker, ':' PATH separator.
# Part of the uv-profiles repository (MIT).

: "${WORKON_HOME:=$HOME/.virtualenvs}"

# --- resolved uv binary (executables only; unaffected by the 'uv' function) ---
__uvp_uv_path="$(type -P uv 2>/dev/null || true)"
if [ -z "$__uvp_uv_path" ]; then
    printf '%s\n' 'uv-profiles: uv was not found on PATH; custom uv profile commands are available, but standard uv commands cannot run.' >&2
fi

# --- managed activation state (empty active path = inactive) ---
__uvp_active=""
__uvp_active_name=""
__uvp_profile_path=""
__uvp_scripts_path=""
__uvp_python_path=""
__uvp_has_python=0
__uvp_has_marker=0
__uvp_saved_path=""
__uvp_saved_ve_present=0
__uvp_saved_ve=""
__uvp_saved_vep_present=0
__uvp_saved_vep=""
__uvp_saved_ps1_present=0
__uvp_saved_ps1=""
__uvp_saved_deactivate=""

# --- helpers ---------------------------------------------------------------

# Canonical path: absolutize, resolve when the directory exists, trim trailing
# slashes (keep the root '/'). Mirrors __UvPath.
__uvp_path() {
    local p="$1"
    case "$p" in
        /*) ;;
        *) p="$PWD/$p" ;;
    esac
    if [ -d "$p" ]; then
        p="$(cd -- "$p" 2>/dev/null && pwd -P || printf '%s' "$p")"
    fi
    if [ "$p" != "/" ]; then p="${p%/}"; fi
    printf '%s' "$p"
}

# Resolved WORKON_HOME (default $HOME/.virtualenvs). Mirrors __UvWorkonHome.
__uvp_workon_home() {
    __uvp_path "${WORKON_HOME:-$HOME/.virtualenvs}"
}

# Reject invalid profile names. Mirrors __UvValidateName (NUL is N/A in bash).
# Prints the error and returns 1 when invalid.
__uvp_validate_name() {
    local name="$1"
    if [ -z "$name" ] || ! printf '%s' "$name" | grep -q '[^[:space:]]'; then
        printf "Invalid profile name '%s'.\n" "$name" >&2
        return 1
    fi
    case "$name" in
        .|..|*/*|*\\*|*:*|-*|*.|*" ")
            printf "Invalid profile name '%s'.\n" "$name" >&2
            return 1
            ;;
    esac
    return 0
}

# Resolve a profile dir. Sets __uvp_profile_path, __uvp_scripts_path,
# __uvp_python_path, __uvp_has_python, __uvp_has_marker.
# Arg 2 is require_python (0 or 1). On failure prints the error, returns 1.
__uvp_profile() {
    local name="$1" require_python="$2" root dir
    __uvp_validate_name "$name" || return 1
    root="$(__uvp_workon_home)"
    dir="$root/$name"
    if [ ! -d "$dir" ]; then
        printf "Profile '%s' was not found in WORKON_HOME '%s'.\n" "$name" "$root" >&2
        return 1
    fi
    __uvp_profile_path="$(__uvp_path "$dir")"
    __uvp_scripts_path="$__uvp_profile_path/bin"
    __uvp_python_path="$__uvp_scripts_path/python"
    __uvp_has_python=0; __uvp_has_marker=0
    [ -f "$__uvp_python_path" ] && __uvp_has_python=1
    [ -f "$__uvp_scripts_path/activate" ] && __uvp_has_marker=1
    if [ "$require_python" -eq 1 ] && { [ "$__uvp_has_python" -ne 1 ] || [ "$__uvp_has_marker" -ne 1 ]; }; then
        printf "Profile '%s' is not a valid uv profile.\n" "$name" >&2
        return 1
    fi
    return 0
}

# Restore the environment from the saved snapshot and clear managed state.
__uvp_clear() {
    if [ -z "$__uvp_active" ]; then return 0; fi
    PATH="$__uvp_saved_path"; export PATH
    if [ "$__uvp_saved_ve_present" -eq 1 ]; then VIRTUAL_ENV="$__uvp_saved_ve"; export VIRTUAL_ENV; else unset VIRTUAL_ENV; fi
    if [ "$__uvp_saved_vep_present" -eq 1 ]; then VIRTUAL_ENV_PROMPT="$__uvp_saved_vep"; export VIRTUAL_ENV_PROMPT; else unset VIRTUAL_ENV_PROMPT; fi
    if [ "$__uvp_saved_ps1_present" -eq 1 ]; then PS1="$__uvp_saved_ps1"; export PS1; else unset PS1; fi
    unset -f deactivate 2>/dev/null || true
    if [ -n "$__uvp_saved_deactivate" ]; then eval "$__uvp_saved_deactivate"; fi
    __uvp_active=""
    __uvp_active_name=""
}

# --- commands ---------------------------------------------------------------

__uvp_activate() {
    local name
    if [ "$#" -eq 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
        printf 'Usage: uv activate <profile-name>\n'
        return 0
    fi
    if [ "$#" -ne 1 ]; then
        printf 'Usage: uv activate <profile-name>\n' >&2
        return 1
    fi
    name="$1"

    # Re-activating the current profile is a no-op.
    if [ -n "$__uvp_active" ] && [ "$__uvp_active_name" = "$name" ]; then
        printf "Profile '%s' is already active.\n" "$name"
        return 0
    fi

    __uvp_profile "$name" 1 || return 1

    # External-VIRTUAL_ENV guards (only when no managed profile is active).
    if [ -z "$__uvp_active" ] && [ -n "${VIRTUAL_ENV:-}" ]; then
        local ve root
        ve="$(__uvp_path "$VIRTUAL_ENV")"
        root="$(__uvp_workon_home)"
        if [ "${ve#"$root"/}" != "$ve" ]; then
            printf "Cannot activate '%s': VIRTUAL_ENV is set inside WORKON_HOME without managed state. Start a fresh shell or remove VIRTUAL_ENV first.\n" "$name" >&2
            return 1
        fi
        printf "Cannot activate '%s': VIRTUAL_ENV points outside WORKON_HOME. Deactivate the external environment first.\n" "$name" >&2
        return 1
    fi

    # Switching profiles: clear first so the snapshot starts from a clean baseline.
    if [ -n "$__uvp_active" ]; then __uvp_clear; fi

    # Snapshot (rollback baseline = deactivate restore target).
    __uvp_saved_path="$PATH"
    __uvp_saved_ve_present=0; __uvp_saved_ve="${VIRTUAL_ENV:-}"
    [ -n "${VIRTUAL_ENV:-}" ] && __uvp_saved_ve_present=1
    __uvp_saved_vep_present=0; __uvp_saved_vep="${VIRTUAL_ENV_PROMPT:-}"
    [ -n "${VIRTUAL_ENV_PROMPT:-}" ] && __uvp_saved_vep_present=1
    __uvp_saved_ps1_present=0; __uvp_saved_ps1=""
    if [ -n "${PS1+x}" ]; then __uvp_saved_ps1_present=1; __uvp_saved_ps1="$PS1"; fi
    __uvp_saved_deactivate="$(declare -f deactivate 2>/dev/null || true)"

    # Apply (pure assignments; cannot fail after all validation above).
    PATH="$__uvp_scripts_path:$__uvp_saved_path"; export PATH
    VIRTUAL_ENV="$__uvp_profile_path"; export VIRTUAL_ENV
    VIRTUAL_ENV_PROMPT="$name"; export VIRTUAL_ENV_PROMPT
    if [ "$__uvp_saved_ps1_present" -eq 1 ]; then PS1="($name) $__uvp_saved_ps1"; export PS1; fi
    __uvp_active="$__uvp_profile_path"
    __uvp_active_name="$name"
    deactivate() { __uvp_clear; }
}

__uvp_profiles() {
    local root name pyver status name_len max_len=0
    local -a names=() pythons=() statuses=()
    if [ "$#" -eq 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
        printf 'Usage: uv profiles\n'
        return 0
    fi
    if [ "$#" -ne 0 ]; then
        printf 'Usage: uv profiles\n' >&2
        return 1
    fi
    root="$(__uvp_workon_home)"
    if [ ! -d "$root" ]; then
        printf "No uv profiles found in '%s'.\n" "$root"
        return 0
    fi
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        name="${name##*/}"
        __uvp_profile "$name" 0 || continue
        [ "$__uvp_has_marker" -eq 1 ] || continue
        pyver="unknown"
        if [ "$__uvp_has_python" -eq 1 ]; then
            local out
            out="$("$__uvp_python_path" --version 2>&1)"
            if [[ "$out" =~ ^Python[[:space:]]+(.+)$ ]]; then pyver="${BASH_REMATCH[1]}"; fi
        fi
        if [ -n "$__uvp_active" ] && [ "$__uvp_active" = "$__uvp_profile_path" ]; then status="active"; else status="inactive"; fi
        name_len="${#name}"
        [ "$name_len" -gt "$max_len" ] && max_len="$name_len"
        names+=("$name"); pythons+=("$pyver"); statuses+=("$status")
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
    if [ "${#names[@]}" -eq 0 ]; then
        printf "No uv profiles found in '%s'.\n" "$root"
        return 0
    fi
    printf '%-*s %-10s %s\n' "$max_len" NAME PYTHON STATUS
    for ((i = 0; i < ${#names[@]}; i++)); do
        printf '%-*s %-10s %s\n' "$max_len" "${names[$i]}" "${pythons[$i]}" "${statuses[$i]}"
    done
}

__uvp_runenv() {
    local name script
    if [ "$#" -eq 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
        printf 'Usage: uv runenv <profile-name> <script-path> [script-arguments...]\n'
        return 0
    fi
    if [ "$#" -lt 2 ]; then
        printf 'Usage: uv runenv <profile-name> <script-path> [script-arguments...]\n' >&2
        return 1
    fi
    name="$1"; script="$2"; shift 2
    __uvp_profile "$name" 0 || return 1
    if [ "$__uvp_has_python" -ne 1 ]; then
        printf "Profile '%s' does not contain a usable Python executable at '%s'.\n" "$name" "$__uvp_python_path" >&2
        return 1
    fi
    if [ ! -f "$script" ]; then
        printf "Python script '%s' was not found as a file.\n" "$script" >&2
        return 1
    fi
    "$__uvp_python_path" "$script" "$@"
    return $?
}

__uvp_venv() {
    # $@ = arguments after 'uv venv'. A leading '--' is dropped (mirrors
    # PowerShell 5.1, which strips '--' before the wrapper sees it).
    if [ "$#" -ge 1 ] && [ "$1" = "--" ]; then shift; fi
    if [ "$#" -lt 1 ]; then
        "$__uvp_uv_path" venv "$@"
        return $?
    fi
    local target="$1"
    shift
    case "$target" in
        */*|*\\*|*:*|.*|~*|-*)
            # path-like / option-first / leading-dash: passthrough unchanged
            "$__uvp_uv_path" venv "$target" "$@"
            return $?
            ;;
    esac
    # a bare plain name: manage under WORKON_HOME
    __uvp_validate_name "$target" || return 1
    "$__uvp_uv_path" venv "$(__uvp_workon_home)/$target" "$@"
    return $?
}

uv() {
    local sub=""
    [ "$#" -ge 1 ] && sub="${1,,}"
    case "$sub" in
        activate)
            __uvp_activate "${@:2}"
            return $?
            ;;
        profiles)
            __uvp_profiles "${@:2}"
            return $?
            ;;
        runenv)
            __uvp_runenv "${@:2}"
            return $?
            ;;
        venv)
            if [ -z "$__uvp_uv_path" ]; then
                printf '%s\n' 'uv was not found on PATH; custom uv profile commands are available, but standard uv commands cannot run.' >&2
                return 1
            fi
            __uvp_venv "${@:2}"
            return $?
            ;;
        *)
            if [ -z "$__uvp_uv_path" ]; then
                printf '%s\n' 'uv was not found on PATH; custom uv profile commands are available, but standard uv commands cannot run.' >&2
                return 1
            fi
            "$__uvp_uv_path" "$@"
            return $?
            ;;
    esac
}
