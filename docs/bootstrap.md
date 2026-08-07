# Release Bootstrap

After reviewing the bootstrap source, install and load the latest stable release in the current PowerShell session:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/MH221B/uv-profiles/main/bootstrap/Install-UvProfile.ps1' -ErrorAction Stop)))
```

This downloads only the bootstrap from `main`. The bootstrap resolves `GET /repos/MH221B/uv-profiles/releases/latest`, rejects drafts and prereleases, downloads the tagged source archive, runs its installer, and dot-sources the current effective `$PROFILE` before returning.

The bootstrap has no version override and does not verify a checksum in this version. It requires a stable GitHub release and never falls back to `main` when release metadata is unavailable.

## Review First

The one-line command executes downloaded code. To inspect it first:

```powershell
$bootstrap = Join-Path $env:TEMP 'Install-UvProfile-bootstrap.ps1'
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/MH221B/uv-profiles/main/bootstrap/Install-UvProfile.ps1' -OutFile $bootstrap
notepad $bootstrap
& $bootstrap
Remove-Item -LiteralPath $bootstrap -Force
```

The bootstrap does not change execution policy, elevate, write machine-wide settings, create environments, install packages, or modify the real `WORKON_HOME`. It removes only its own temporary archive directory.

## Testing

The network-free harness uses injected release metadata and download providers with disposable paths:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\Invoke-UvProfileBootstrapVerification.ps1 -BootstrapScript .\bootstrap\Install-UvProfile.ps1
```

PowerShell 7 can run the same command with `pwsh.exe` when available. The test never calls GitHub or the real profile.
