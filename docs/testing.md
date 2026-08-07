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
