# Testing

Use a disposable `WORKON_HOME`; never point verification at the user's real profile root.

```powershell
$root = Join-Path $env:TEMP ('uv-profile-test-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory $root | Out-Null
  $env:WORKON_HOME = $root
  uv venv (Join-Path $root 'alpha') --python 3.10
  . .\src\uv-profile.ps1
  uv activate alpha
  if ($env:VIRTUAL_ENV -ne (Join-Path $root 'alpha')) { throw 'activation failed' }
  deactivate
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
```

The runtime uses Windows PowerShell 5.1 syntax. Test PowerShell 7 separately when `pwsh.exe` is available.

## Bootstrap Verification

Run the network-free bootstrap harness with a disposable profile and temporary root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\Invoke-UvProfileBootstrapVerification.ps1 -BootstrapScript .\bootstrap\Install-UvProfile.ps1
```

The harness injects release metadata and archive downloads, never calls GitHub, never invokes the real profile, and removes its generated temporary root in `finally`.
