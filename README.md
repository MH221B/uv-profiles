# uv PowerShell Profiles

A small Windows PowerShell workflow for named `uv` virtual environments. I made this mainly because I wanted something similar to miniconda but doesnt auto hook on every powershell instance opened.

## Install

After reviewing the bootstrap source, install and load the latest stable release in the current PowerShell session:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/MH221B/uv-profiles/main/bootstrap/Install-UvProfile.ps1' -ErrorAction Stop)))
```

This executes downloaded code. See [`docs/bootstrap.md`](docs/bootstrap.md) for the review-first flow, release behavior, and security details.

Review `src/uv-profile.ps1` and `Install-UvProfile.ps1`, then run from this repository in PowerShell:

```powershell
& .\Install-UvProfile.ps1
. $PROFILE
```

The installer updates only the current shell's effective `$PROFILE`. It does not change execution policy or machine-wide configuration. By default profiles live under `$HOME\.virtualenvs`.

## Use

```powershell
uv venv "$env:WORKON_HOME\data" --python 3.12
uv profiles
uv activate data
uv pip install requests
deactivate
uv --version
```

`uv activate` validates names and never dot-sources a generated activation script. Other uv commands pass through to `uv.exe`.

## Uninstall

Remove the exact loader line from the effective `$PROFILE`, then remove the installed runtime copy under `$env:LOCALAPPDATA\uv`. Do not remove environments unless you explicitly want to delete them.

## Security

Review scripts before execution. This project makes no execution-policy changes, accepts no arbitrary activation paths, and performs no machine-wide writes. Verification uses disposable roots only.

## Testing

Run the disposable test script in `tests` from Windows PowerShell 5.1. PowerShell 7 can use the same scripts when installed.
