[CmdletBinding()]
param(
    [string]$ProfilePath = '',
    [switch]$SkipUv
)

$ErrorActionPreference = 'Stop'

function Get-UvHostProfile {
    param([Parameter(Mandatory = $true)][string]$HostCommand)
    try { $value = (& $HostCommand -NoProfile -Command '$PROFILE' 2>$null | Out-String).Trim() } catch { return $null }
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $value
}

function Resolve-UvProfilePath {
    param([string]$Requested)
    if (-not [string]::IsNullOrWhiteSpace($Requested)) { return $Requested }
    if ($null -ne (Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        $ps7 = Get-UvHostProfile -HostCommand 'pwsh'
        if ($ps7) { return $ps7 }
    }
    $ps5 = Get-UvHostProfile -HostCommand 'powershell'
    if ($ps5) { return $ps5 }
    [string]$PROFILE
}

function Assert-UvAvailable {
    param([switch]$SkipInstall)
    $uv = Get-Command uv.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $uv) { Write-Output "Found uv.exe at '$($uv.Source)'."; return }
    if ($SkipInstall) { Write-Warning 'uv.exe was not found on PATH. The profile will load, but standard uv commands cannot run until uv is installed.'; return }
    $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $winget) { Write-Warning 'uv.exe was not found and no winget.exe was detected. The profile will load, but standard uv commands cannot run until uv is installed.'; return }
    Write-Output 'uv.exe was not found. Installing uv via winget...'
    & $winget.Source install --id astral-sh.uv -e --accept-source-agreements --accept-package-agreements
    $wingetExit = $LASTEXITCODE
    # winget updates PATH in the registry; refresh this session's PATH and re-check.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not [string]::IsNullOrWhiteSpace($machine) -or -not [string]::IsNullOrWhiteSpace($user)) { $env:Path = "$env:Path;$machine;$user" }
    $uv = Get-Command uv.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $uv) { Write-Output "uv.exe is available at '$($uv.Source)'."; return }
    Write-Warning "uv.exe could not be found on PATH after the winget install (winget exit code $wingetExit). Open a new PowerShell session so PATH refreshes, then standard uv commands will work."
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $root 'src\uv-profile.ps1'
$runtimeRoot = Join-Path $env:LOCALAPPDATA 'uv'
$runtime = Join-Path $runtimeRoot 'uv-profile.ps1'
$line = '. "$env:LOCALAPPDATA\uv\uv-profile.ps1"'

$ProfilePath = Resolve-UvProfilePath -Requested $ProfilePath

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
} else {
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += [Environment]::NewLine }
    [IO.File]::WriteAllText($ProfilePath, $text + $line + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    Write-Output "Installed uv PowerShell profile loader in '$ProfilePath'."
}

Assert-UvAvailable -SkipInstall:$SkipUv
