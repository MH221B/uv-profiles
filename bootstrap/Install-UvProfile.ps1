[CmdletBinding()]
param(
    [string]$ProfilePath = [string]$PROFILE,
    [string]$TempParent = [string]$env:TEMP,
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'
$script:UvProfileLatestReleaseUri = 'https://api.github.com/repos/MH221B/uv-profiles/releases/latest'

function Get-UvProfileRelease {
    param(
        [string]$Uri = $script:UvProfileLatestReleaseUri,
        [scriptblock]$GetMetadata
    )

    if ($null -eq $GetMetadata) {
        $GetMetadata = {
            param([string]$RequestUri)
            Invoke-RestMethod -Uri $RequestUri -Headers @{ 'User-Agent' = 'uv-profiles-bootstrap' } -ErrorAction Stop
        }
    }

    try { $release = & $GetMetadata $Uri }
    catch { throw "Unable to retrieve the latest uv-profiles release from '$Uri': $($_.Exception.Message)" }
    if ($null -eq $release) { throw "The latest uv-profiles release response from '$Uri' was empty." }
    if ([string]::IsNullOrWhiteSpace([string]$release.tag_name)) { throw 'The latest uv-profiles release has no tag_name.' }
    if ($release.draft -ne $false) { throw "Release '$($release.tag_name)' did not identify itself as a non-draft release." }
    if ($release.prerelease -ne $false) { throw "Release '$($release.tag_name)' did not identify itself as a stable release." }
    if ([string]::IsNullOrWhiteSpace([string]$release.zipball_url)) { throw "Release '$($release.tag_name)' has no zipball_url." }
    try { $archiveUri = [System.Uri]$release.zipball_url }
    catch { throw "Release '$($release.tag_name)' has an invalid zipball_url." }
    if ($archiveUri.Scheme -ne 'https' -or $archiveUri.Host -notin @('api.github.com', 'codeload.github.com')) {
        throw "Release '$($release.tag_name)' has a non-GitHub HTTPS zipball_url."
    }
    return $release
}

function New-UvProfileBootstrapWorkspace {
    param([Parameter(Mandatory = $true)][string]$Parent)
    if ([string]::IsNullOrWhiteSpace($Parent)) { throw 'The bootstrap temporary parent is empty.' }
    $workspace = Join-Path $Parent ('uv-profile-bootstrap-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    $extracted = Join-Path $workspace 'extracted'
    New-Item -ItemType Directory -Path $extracted -Force | Out-Null
    [pscustomobject]@{ Root = $workspace; Archive = Join-Path $workspace 'archive.zip'; Extracted = $extracted }
}

function Save-UvProfileArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [scriptblock]$Download
    )
    if ($null -eq $Download) {
        $Download = {
            param([string]$RequestUri, [string]$OutputPath)
            Invoke-WebRequest -UseBasicParsing -Uri $RequestUri -OutFile $OutputPath -ErrorAction Stop
        }
    }
    try { & $Download $Uri $Destination }
    catch { throw "Unable to download release archive from '$Uri': $($_.Exception.Message)" }
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) { throw "The release archive was not created at '$Destination'." }
}

function Expand-UvProfileArchive {
    param([string]$Archive, [string]$Destination)
    try { Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force -ErrorAction Stop }
    catch { throw "Unable to extract release archive '$Archive': $($_.Exception.Message)" }
}

function Find-UvProfileInstaller {
    param([string]$ExtractionRoot)
    $matches = @(Get-ChildItem -LiteralPath $ExtractionRoot -Filter 'Install-UvProfile.ps1' -File -Recurse -ErrorAction Stop)
    if ($matches.Count -ne 1) { throw "Expected exactly one Install-UvProfile.ps1 under '$ExtractionRoot', but found $($matches.Count)." }
    $matches[0].FullName
}

function Assert-UvProfilePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'The effective PowerShell profile path is empty.' }
}

function Assert-UvProfileLoaded {
    if ($null -eq (Get-Command -Name uv -CommandType Function -ErrorAction SilentlyContinue)) {
        throw 'The uv profile was installed, but the uv PowerShell function was not loaded into the current session.'
    }
}

function Invoke-UvProfileBootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$ProfilePath,
        [Parameter(Mandatory = $true)][string]$TempParent,
        [scriptblock]$GetMetadata,
        [scriptblock]$Download,
        [scriptblock]$InvokeInstaller
    )

    Assert-UvProfilePath $ProfilePath
    $release = Get-UvProfileRelease -GetMetadata $GetMetadata
    $workspace = New-UvProfileBootstrapWorkspace -Parent $TempParent
    try {
        Save-UvProfileArchive -Uri $release.zipball_url -Destination $workspace.Archive -Download $Download
        Expand-UvProfileArchive -Archive $workspace.Archive -Destination $workspace.Extracted
        $installerPath = Find-UvProfileInstaller -ExtractionRoot $workspace.Extracted
        if ($null -eq $InvokeInstaller) { & $installerPath -ProfilePath $ProfilePath }
        else { & $InvokeInstaller $installerPath $ProfilePath }
        . $ProfilePath
        Assert-UvProfileLoaded
        Write-Output "Installed uv PowerShell profile release '$($release.tag_name)' and loaded '$ProfilePath'."
    }
    finally {
        if (Test-Path -LiteralPath $workspace.Root) { Remove-Item -LiteralPath $workspace.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

if (-not $NoRun) { Invoke-UvProfileBootstrap -ProfilePath $ProfilePath -TempParent $TempParent }
