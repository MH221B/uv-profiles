[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$BootstrapScript)

$ErrorActionPreference = 'Stop'
function Assert-True { param([string]$Name, [bool]$Condition); if (-not $Condition) { throw "$Name failed." } }
function Assert-Equal { param([string]$Name, $Expected, $Actual); if ($Expected -cne $Actual) { throw "$Name failed. Expected [$Expected], actual [$Actual]." } }
function Assert-Contains { param([string]$Name, [string]$Text, [string]$ExpectedText); if ($Text.IndexOf($ExpectedText, [StringComparison]::Ordinal) -lt 0) { throw "$Name failed. [$ExpectedText] was not found." } }
function Assert-ThrowsContaining { param([string]$Name, [scriptblock]$Action, [string]$ExpectedText); $caught=$false;try{&$Action}catch{$caught=$true;Assert-Contains $Name $_.Exception.Message $ExpectedText};Assert-True "$Name raised an error" $caught }

if (-not (Test-Path -LiteralPath $BootstrapScript -PathType Leaf)) { throw "Bootstrap script was not found at '$BootstrapScript'." }
. $BootstrapScript -NoRun
$testRoot = Join-Path $env:TEMP ('uv-profile-bootstrap-test-' + [guid]::NewGuid().ToString('N'))
$disposableProfile = Join-Path $testRoot 'DisposableProfile.ps1'
$oldUv = Get-Command uv -CommandType Function -ErrorAction SilentlyContinue
try {
    $fixtureRoot = Join-Path $testRoot 'fixture\uv-profiles-v0.1.0'
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $fixtureInstaller = Join-Path $fixtureRoot 'Install-UvProfile.ps1'
    Set-Content -LiteralPath $fixtureInstaller -Value @'
param([string]$ProfilePath)
Add-Content -LiteralPath $ProfilePath -Value "function global:uv { 'loaded' }"
'@ -Encoding UTF8
    $archivePath = Join-Path $testRoot 'release.zip'
    Compress-Archive -LiteralPath (Join-Path $testRoot 'fixture\uv-profiles-v0.1.0') -DestinationPath $archivePath
    $release = [pscustomobject]@{tag_name='v0.1.0';draft=$false;prerelease=$false;zipball_url='https://codeload.github.com/MH221B/uv-profiles/zip/refs/tags/v0.1.0'}
    Invoke-UvProfileBootstrap -ProfilePath $disposableProfile -TempParent $testRoot -GetMetadata { param($Uri) $release } -Download { param($Uri,$Destination) Copy-Item $archivePath $Destination -Force }
    Assert-True 'uv function loaded' ($null -ne (Get-Command uv -CommandType Function -ErrorAction SilentlyContinue))
    Assert-Equal 'loaded uv function' 'loaded' (& uv)
    Assert-ThrowsContaining 'missing response' { Get-UvProfileRelease -GetMetadata { param($Uri) $null } } 'response'
    Assert-ThrowsContaining 'missing tag' { Get-UvProfileRelease -GetMetadata { param($Uri) [pscustomobject]@{draft=$false;prerelease=$false;zipball_url='x'} } } 'tag_name'
    Assert-ThrowsContaining 'draft' { Get-UvProfileRelease -GetMetadata { param($Uri) [pscustomobject]@{tag_name='v';draft=$true;prerelease=$false;zipball_url='x'} } } 'non-draft'
    Assert-ThrowsContaining 'prerelease' { Get-UvProfileRelease -GetMetadata { param($Uri) [pscustomobject]@{tag_name='v';draft=$false;prerelease=$true;zipball_url='x'} } } 'stable'
    Assert-ThrowsContaining 'non-GitHub URL' { Get-UvProfileRelease -GetMetadata { param($Uri) [pscustomobject]@{tag_name='v';draft=$false;prerelease=$false;zipball_url='https://example.invalid/x'} } } 'non-GitHub'
    $duplicate = Join-Path $testRoot 'duplicate'
    New-Item -ItemType Directory -Path (Join-Path $duplicate 'one'), (Join-Path $duplicate 'two') -Force | Out-Null
    Set-Content (Join-Path $duplicate 'one\Install-UvProfile.ps1') 'param([string]$ProfilePath)' -Encoding UTF8
    Set-Content (Join-Path $duplicate 'two\Install-UvProfile.ps1') 'param([string]$ProfilePath)' -Encoding UTF8
    $duplicateArchive = Join-Path $testRoot 'duplicate.zip'; Compress-Archive -Path $duplicate -DestinationPath $duplicateArchive
    $duplicateExtract = Join-Path $testRoot 'duplicate-extract'; Expand-UvProfileArchive $duplicateArchive $duplicateExtract
    Assert-ThrowsContaining 'duplicate installers' { Find-UvProfileInstaller $duplicateExtract } 'found 2'
    Assert-ThrowsContaining 'download cleanup' { Invoke-UvProfileBootstrap -ProfilePath $disposableProfile -TempParent $testRoot -GetMetadata { param($Uri) $release } -Download { throw 'download failure' } } 'download failure'
    Assert-Equal 'workspace cleanup' 0 @((Get-ChildItem $testRoot -Directory -Filter 'uv-profile-bootstrap-*' -ErrorAction SilentlyContinue)).Count
    Assert-ThrowsContaining 'empty profile' { Invoke-UvProfileBootstrap -ProfilePath '' -TempParent $testRoot -GetMetadata { throw 'provider called' } } 'empty'
    Write-Output 'All bootstrap verification assertions passed.'
}
finally {
    Remove-Item Function:\uv -ErrorAction SilentlyContinue
    if ($null -ne $oldUv) { Set-Item Function:\global:uv -Value $oldUv.ScriptBlock -Force }
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
}
