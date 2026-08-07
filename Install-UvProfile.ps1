[CmdletBinding()]
param([string]$ProfilePath = [string]$PROFILE)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $root 'src\uv-profile.ps1'
$runtimeRoot = Join-Path $env:LOCALAPPDATA 'uv'
$runtime = Join-Path $runtimeRoot 'uv-profile.ps1'
$line = '. "$env:LOCALAPPDATA\uv\uv-profile.ps1"'

if ([string]::IsNullOrWhiteSpace($ProfilePath)) { throw 'The effective PowerShell profile path is empty.' }
if ((Get-ExecutionPolicy) -in @('Restricted', 'AllSigned')) { throw 'The effective execution policy prevents profile installation. The installer will not change policy.' }
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "The repository runtime was not found at '$source'." }

New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $runtime -Force
$parent = Split-Path -Parent $ProfilePath
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$text = if (Test-Path -LiteralPath $ProfilePath) { [IO.File]::ReadAllText($ProfilePath) } else { '' }
if ($text -match '(?m)^[ \t]*\.\s+\[?"?\$env:LOCALAPPDATA\\uv\\uv-profile\.ps1') {
    Write-Output "uv PowerShell profile loader already exists in '$ProfilePath'."
    return
}
if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += [Environment]::NewLine }
[IO.File]::WriteAllText($ProfilePath, $text + $line + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
Write-Output "Installed uv PowerShell profile loader in '$ProfilePath'."
