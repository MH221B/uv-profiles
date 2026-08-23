#!/usr/bin/env bash
# uv-profiles installer + OS dispatcher for Linux/WSL (and best-effort macOS).
# Usage: bash install.sh [--profile-root <rc-file>] [--skip-uv]
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash install.sh [--profile-root <rc-file>] [--skip-uv]

Installs the uv-profiles bash runtime and adds its loader to ~/.bashrc.
  --profile-root <rc-file>   install the loader into <rc-file> instead
  --skip-uv                  don't install uv if it is missing
EOF
}

PROFILE_ROOT=""
SKIP_UV=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile-root)
            [ "$#" -ge 2 ] || { printf '%s\n' '--profile-root requires an argument' >&2; usage >&2; exit 1; }
            PROFILE_ROOT="$2"; shift 2 ;;
        --skip-uv) SKIP_UV=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
done

# --- OS dispatch (the redirect) ---------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Linux*)
            if uname -r | grep -qi microsoft; then printf 'wsl'; else printf 'linux'; fi ;;
        Darwin*) printf 'macos' ;;
        MINGW*|MSYS*|CYGWIN*) printf 'windows' ;;
        *) printf 'unsupported' ;;
    esac
}

os="$(detect_os)"
if [ "$os" = "windows" ]; then
    cat >&2 <<'EOF'
uv-profiles: this installer targets Linux/WSL bash.
On Windows, use the PowerShell runtime instead:

  & .\Install-UvProfile.ps1

or the release bootstrap:

  & ([scriptblock]::Create((Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/MH221B/uv-profiles/main/bootstrap/Install-UvProfile.ps1' -ErrorAction Stop)))
EOF
    exit 1
fi
if [ "$os" = "unsupported" ]; then
    printf 'uv-profiles: unsupported platform (%s).\n' "$(uname -s)" >&2
    exit 1
fi

# --- install ----------------------------------------------------------------
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source_file="$script_dir/src/uv-profile.sh"
[ -f "$source_file" ] || { printf "uv-profiles runtime not found at '%s'.\n" "$source_file" >&2; exit 1; }

install_dir="${XDG_DATA_HOME:-$HOME/.local/share}/uv"
mkdir -p -- "$install_dir"
runtime="$install_dir/uv-profile.sh"
cp -- "$source_file" "$runtime"
loader=". \"$runtime\""
printf 'Installed runtime to %s\n' "$runtime"

rc="${PROFILE_ROOT:-$HOME/.bashrc}"
escaped="$(printf '%s' "$runtime" | sed 's#[]\[\./^$*+?(){}|\\-]#\\&#g')"
match="^[[:space:]]*\\.[[:space:]]*\"?${escaped}\"?[[:space:]]*$"
if grep -qE "$match" "$rc" 2>/dev/null; then
    printf "uv-profiles loader already exists in '%s'.\n" "$rc"
else
    if [ ! -f "$rc" ]; then
        : > "$rc"
    elif [ -s "$rc" ] && [ "$(tail -c 1 "$rc")" != "$(printf '\n')" ]; then
        printf '\n' >> "$rc"
    fi
    printf '%s\n' "$loader" >> "$rc"
    printf "Installed uv-profiles loader in '%s'.\n" "$rc"
fi

# --- uv availability (non-fatal) --------------------------------------------
uv_path="$(command -v uv 2>/dev/null || true)"
if [ -n "$uv_path" ]; then
    printf "Found uv at '%s'.\n" "$uv_path"
elif [ "$SKIP_UV" -eq 1 ]; then
    printf '%s\n' 'uv was not found on PATH (--skip-uv). The profile will load, but standard uv commands cannot run until uv is installed.' >&2
else
    printf '%s\n' 'uv was not found. Installing uv via the official installer...'
    if command -v curl >/dev/null 2>&1; then
        curl -LsSf https://astral.sh/uv/install.sh | sh || true
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- https://astral.sh/uv/install.sh | sh || true
    else
        printf '%s\n' 'Neither curl nor wget is available; skipping uv install.' >&2
    fi
    if [ -n "${HOME:-}" ] && [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        PATH="$HOME/.local/bin:$PATH"; export PATH
    fi
    if command -v uv >/dev/null 2>&1; then
        printf "Found uv at '%s'.\n" "$(command -v uv)"
    else
        printf '%s\n' 'uv could not be found on PATH after install. Open a new shell so PATH refreshes, then standard uv commands will work.' >&2
    fi
fi

printf '%s\n' "Installation complete. Start a new shell (or run: . $rc) to load uv-profiles."
