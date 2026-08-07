# uv PowerShell Profiles

A small Windows PowerShell workflow for named `uv` virtual environments. I made this mainly because I wanted something similar to Miniconda but doesn't auto-hook on every PowerShell instance opened.

## Requirements

- Windows PowerShell 5.1. PowerShell 7 can run the same scripts when `pwsh.exe` is available, but the runtime is authored against 5.1 syntax.
- `uv.exe` on `PATH`. The profile still loads if `uv.exe` is unavailable, but standard `uv` commands cannot run until it is installed and discoverable.

## Install

After reviewing the bootstrap source, install and load the latest stable release in the current PowerShell session:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/MH221B/uv-profiles/main/bootstrap/Install-UvProfile.ps1' -ErrorAction Stop)))
```

This executes downloaded code. The bootstrap resolves the latest stable GitHub release, rejects drafts and prereleases, and does not fall back to `main` if release metadata is unavailable. It does not currently verify a checksum. See [`docs/bootstrap.md`](docs/bootstrap.md) for the review-first flow, release behavior, and security details.

Review `src/uv-profile.ps1` and `Install-UvProfile.ps1`, then run from this repository in PowerShell:

```powershell
& .\Install-UvProfile.ps1
. $PROFILE
```

The installer updates only the current shell's effective `$PROFILE`. It does not change execution policy or machine-wide configuration. If the effective execution policy is `Restricted` or `AllSigned`, it refuses to run. By default profiles live under `$HOME\.virtualenvs`.

## Configuration

Set `$env:WORKON_HOME` to change the profile root. If it is unset, profiles are stored under `$HOME\.virtualenvs`. The installed runtime is copied to `$env:LOCALAPPDATA\uv\uv-profile.ps1`.

## Use

```powershell
uv venv data --python 3.12
uv profiles
uv activate data
uv pip install requests
deactivate
uv --version
```

`uv venv <name>` creates the environment under `$env:WORKON_HOME` (which defaults to `$HOME\.virtualenvs`). Explicit path-like targets such as `.\temporary-env`, `.venv`, `~\envs\data`, or `C:\envs\data`, leading-dash targets, and option-first invocations pass through to `uv.exe` unchanged. PowerShell 5.1 removes `--` before the wrapper sees it, so use explicit path syntax when bypassing managed-name resolution. Creating a new environment while a profile is active preserves the active session.

`uv activate` validates names and never dot-sources a generated activation script. The environment must contain both `Scripts\python.exe` and `Scripts\Activate.ps1`; the activation script is used only as a validity marker. Activation snapshots the current `PATH`, `VIRTUAL_ENV`, `VIRTUAL_ENV_PROMPT`, `prompt`, and `deactivate` state, then prepends the profile's `Scripts` directory to `PATH` and prefixes the prompt with `(name)`. `deactivate` restores the previous state. Activation is session-local and reversible.

`uv profiles` lists valid profiles in sorted order with `NAME`, `PYTHON`, and `STATUS` columns. Profiles are marked `active` or `inactive`; an empty or missing profile root reports that no profiles were found. If `VIRTUAL_ENV` is already set outside the managed profile state, start a fresh session or deactivate it before using `uv activate`.

### Run Without Activation

Run a script with a named profile's Python without changing the current shell:

```powershell
uv runenv pulse_env .\report.py
uv runenv pulse_env .\report.py --input data.csv --count 3
uv runenv pulse_env .\report.py "file with spaces.txt" --verbose
```

Only the profile name and script path are consumed by `runenv`; arguments after
the script path are passed to the script in order. The command requires
`Scripts\python.exe` but does not require `Activate.ps1` and does not change
`PATH`, `VIRTUAL_ENV`, or the prompt.

Use `uv runenv --help` for usage. The script's exit code is propagated as
`$LASTEXITCODE`, and script paths are treated literally rather than as wildcard
patterns.

## How It Works

Loading the profile defines a `uv` function that intercepts `activate`,
`profiles`, `runenv`, and plain-name `venv` calls. All other arguments are
passed to the resolved `uv.exe` unchanged. `uv venv` with an existing managed
name also remains a native `uv` error rather than replacing that environment.

## Uninstall

Remove the exact loader line from the effective `$PROFILE`, then remove the installed runtime copy under `$env:LOCALAPPDATA\uv`. Do not remove environments unless you explicitly want to delete them.

## Security

Review scripts before execution. This project makes no execution-policy changes, accepts no arbitrary activation paths, and performs no machine-wide writes. Verification uses disposable roots only.

## Repository Layout

- `src/uv-profile.ps1` — dot-sourced runtime defining the `uv` wrapper function
- `Install-UvProfile.ps1` — local installer for the runtime and profile loader
- `bootstrap/Install-UvProfile.ps1` — release bootstrap; see [`docs/bootstrap.md`](docs/bootstrap.md)
- `tests/` — disposable verification harnesses; see [`docs/testing.md`](docs/testing.md)
- `docs/design.md` — design summary

## Testing

Run verification from Windows PowerShell 5.1 and never point it at the real
`WORKON_HOME`:

```powershell
$testRoot = Join-Path $env:TEMP ('uv-profile-runenv-' + [guid]::NewGuid().ToString('N'))
$uvExe = (Get-Command uv.exe -CommandType Application).Source
try {
    powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\Invoke-UvProfileVerification.ps1 -TestRoot $testRoot -SharedScript (Resolve-Path .\src\uv-profile.ps1) -UvExe $uvExe
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
```

The bootstrap harness is network-free:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\Invoke-UvProfileBootstrapVerification.ps1 -BootstrapScript .\bootstrap\Install-UvProfile.ps1
```

See [`docs/testing.md`](docs/testing.md) for the manual disposable-root flow and test coverage details.

## License

MIT. See [`LICENSE`](LICENSE).
