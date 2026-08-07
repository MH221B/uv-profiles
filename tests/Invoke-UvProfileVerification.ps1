[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TestRoot,
    [Parameter(Mandatory = $true)][string]$SharedScript,
    [Parameter(Mandatory = $true)][string]$UvExe
)

$ErrorActionPreference = 'Stop'

function Assert-True { param([string]$Name, [bool]$Condition) if (-not $Condition) { throw "$Name failed." } }
function Assert-Equal { param([string]$Name, $Expected, $Actual) if ($Expected -cne $Actual) { throw "$Name failed. Expected [$Expected], actual [$Actual]." } }
function Assert-Contains { param([string]$Name, [string]$Text, [string]$ExpectedText) if ($Text.IndexOf($ExpectedText, [StringComparison]::Ordinal) -lt 0) { throw "$Name failed. [$ExpectedText] was not found in [$Text]." } }
function Assert-ThrowsContaining {
    param([string]$Name, [scriptblock]$Action, [string]$ExpectedText)
    $caught = $false
    try { & $Action } catch { $caught = $true; Assert-Contains $Name $_.Exception.Message $ExpectedText }
    Assert-True "$Name raised an error" $caught
}
function Get-FunctionText { param([string]$Name) $command = Get-Command -Name $Name -CommandType Function -ErrorAction SilentlyContinue; if ($null -eq $command) { return $null }; return $command.ScriptBlock.ToString() }
function Get-EnvState { param([string]$Name) if (Test-Path -LiteralPath "Env:$Name") { return @{ Present = $true; Value = [Environment]::GetEnvironmentVariable($Name, 'Process') } }; return @{ Present = $false; Value = $null } }

if (-not (Test-Path -LiteralPath $UvExe -PathType Leaf)) { throw "uv executable was not found at '$UvExe'." }
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
$alpha = Join-Path $TestRoot 'alpha'
$noActivate = Join-Path $TestRoot 'no_activate'
$missingPython = Join-Path $TestRoot 'missing_python\Scripts'
& $UvExe venv $alpha --python 3.12
if ($LASTEXITCODE -ne 0) { throw "uv venv failed for '$alpha'." }
& $UvExe venv $noActivate --python 3.12
if ($LASTEXITCODE -ne 0) { throw "uv venv failed for '$noActivate'." }
Remove-Item -LiteralPath (Join-Path $noActivate 'Scripts\Activate.ps1') -Force
New-Item -ItemType Directory -Path $missingPython -Force | Out-Null

$argumentScript = Join-Path $TestRoot 'capture_args.py'
Set-Content -LiteralPath $argumentScript -Encoding UTF8 -Value @'
import json
import pathlib
import sys
pathlib.Path(sys.argv[1]).write_text(json.dumps(sys.argv[2:]), encoding="utf-8")
'@
$failureScript = Join-Path $TestRoot 'exit_42.py'
Set-Content -LiteralPath $failureScript -Encoding UTF8 -Value @'
import sys
sys.exit(42)
'@
$wildcardScript = Join-Path $TestRoot '[literal].py'
Set-Content -LiteralPath $wildcardScript -Encoding UTF8 -Value "print('wildcard path ran')"
$capturePath = Join-Path $TestRoot 'captures with spaces.json'

$env:WORKON_HOME = $TestRoot
. $SharedScript

$pathBeforeHelp = $env:PATH
$promptBeforeHelp = Get-FunctionText 'prompt'
$deactivateBeforeHelp = Get-FunctionText 'deactivate'
$help = @(uv runenv -h | Out-String) -join ''
Assert-Contains 'runenv short help' $help 'Usage: uv runenv <profile-name> <script-path> [script-arguments...]'
$helpLong = @(uv runenv --help | Out-String) -join ''
Assert-Contains 'runenv long help' $helpLong 'Usage: uv runenv <profile-name> <script-path> [script-arguments...]'
Assert-Equal 'help PATH preservation' $pathBeforeHelp $env:PATH
Assert-Equal 'help prompt preservation' $promptBeforeHelp (Get-FunctionText 'prompt')
Assert-Equal 'help deactivate preservation' $deactivateBeforeHelp (Get-FunctionText 'deactivate')
Assert-ThrowsContaining 'bare runenv usage' { uv runenv } 'Usage: uv runenv'
Assert-ThrowsContaining 'missing script usage' { uv runenv alpha } 'Usage: uv runenv'
Assert-ThrowsContaining 'extra help rejection' { uv runenv --help alpha } 'Invalid profile name'
Assert-ThrowsContaining 'missing profile' { uv runenv missing $argumentScript } "Profile 'missing'"
Assert-ThrowsContaining 'missing Python' { uv runenv missing_python $argumentScript } 'Scripts\python.exe'
Assert-ThrowsContaining 'missing script' { uv runenv alpha (Join-Path $TestRoot 'missing.py') } 'was not found'
Assert-ThrowsContaining 'directory script' { uv runenv alpha $TestRoot } 'was not found as a file'
Assert-ThrowsContaining 'invalid name' { uv runenv 'bad/name' $argumentScript } "Invalid profile name 'bad/name'"
Assert-ThrowsContaining 'literal missing wildcard' { uv runenv alpha (Join-Path $TestRoot 'missing*.py') } 'missing*.py'

uv runenv alpha $argumentScript $capturePath '--input' 'data file.csv' '--count' '3' '--input' 'second.csv'
$captured = ConvertFrom-Json ([IO.File]::ReadAllText($capturePath))
Assert-Equal 'argument count' 6 $captured.Count
Assert-Equal 'argument output path' '--input' $captured[0]
Assert-Equal 'argument value with spaces' 'data file.csv' $captured[1]
Assert-Equal 'argument count flag' '--count' $captured[2]
Assert-Equal 'argument count value' '3' $captured[3]
Assert-Equal 'repeated flag' '--input' $captured[4]
Assert-Equal 'repeated value' 'second.csv' $captured[5]
uv RunEnv no_activate $wildcardScript

uv activate alpha
$pathBeforeRunenv = $env:PATH
$virtualEnvBeforeRunenv = Get-EnvState 'VIRTUAL_ENV'
$virtualEnvPromptBeforeRunenv = Get-EnvState 'VIRTUAL_ENV_PROMPT'
$promptBeforeRunenv = Get-FunctionText 'prompt'
$deactivateBeforeRunenv = Get-FunctionText 'deactivate'
$activeNameBeforeRunenv = $global:__UvProfileState.ActiveProfileName
uv runenv no_activate $argumentScript $capturePath '--active-test'
Assert-Equal 'active PATH after successful runenv' $pathBeforeRunenv $env:PATH
Assert-Equal 'active VIRTUAL_ENV after successful runenv' $virtualEnvBeforeRunenv.Value $env:VIRTUAL_ENV
Assert-Equal 'active VIRTUAL_ENV_PROMPT after successful runenv' $virtualEnvPromptBeforeRunenv.Value $env:VIRTUAL_ENV_PROMPT
Assert-Equal 'active prompt after successful runenv' $promptBeforeRunenv (Get-FunctionText 'prompt')
Assert-Equal 'active deactivate after successful runenv' $deactivateBeforeRunenv (Get-FunctionText 'deactivate')
Assert-Equal 'active profile name after successful runenv' $activeNameBeforeRunenv $global:__UvProfileState.ActiveProfileName
$global:LASTEXITCODE = 91
Assert-ThrowsContaining 'failed runenv while active' { uv runenv no_activate (Join-Path $TestRoot 'not-there.py') } 'was not found'
Assert-Equal 'LASTEXITCODE after validation failure' 91 $LASTEXITCODE
Assert-Equal 'active PATH after failed runenv' $pathBeforeRunenv $env:PATH
Assert-Equal 'active VIRTUAL_ENV after failed runenv' $virtualEnvBeforeRunenv.Value $env:VIRTUAL_ENV
Assert-Equal 'active prompt after failed runenv' $promptBeforeRunenv (Get-FunctionText 'prompt')
Assert-Equal 'active profile name after failed runenv' $activeNameBeforeRunenv $global:__UvProfileState.ActiveProfileName
$global:LASTEXITCODE = 92
Assert-ThrowsContaining 'invalid name exit preservation' { uv runenv 'bad/name' $argumentScript } "Invalid profile name 'bad/name'"
Assert-Equal 'LASTEXITCODE after invalid name' 92 $LASTEXITCODE
deactivate

$global:LASTEXITCODE = 7
uv runenv alpha $failureScript
Assert-Equal 'Python exit code' 42 $LASTEXITCODE
Assert-Contains 'uv version passthrough' ((@(uv --version | Out-String) -join '')) 'uv '
Assert-Contains 'uv help passthrough' ((@(uv --help | Out-String) -join '')) 'Usage:'
Assert-Contains 'uv run passthrough' ((@(uv run --help | Out-String) -join '')) 'run'

$childScript = Join-Path $TestRoot 'runenv-no-uv.ps1'
Set-Content -LiteralPath $childScript -Encoding UTF8 -Value @'
param([string]$SharedScript, [string]$Root, [string]$ScriptPath, [string]$OutputPath, [string]$UvBin)
$ErrorActionPreference = 'Stop'
$env:WORKON_HOME = $Root
$normalizedUvBin = $UvBin.TrimEnd('\')
$env:PATH = (($env:PATH -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ine $normalizedUvBin) }) -join ';')
. $SharedScript
uv runenv no_activate $ScriptPath $OutputPath '--without-uv'
if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw 'runenv did not execute without uv.exe.' }
'@
$withoutUvCapture = Join-Path $TestRoot 'without-uv.json'
$uvBin = Split-Path -Parent $UvExe
$child = powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File $childScript -SharedScript $SharedScript -Root $TestRoot -ScriptPath $argumentScript -OutputPath $withoutUvCapture -UvBin $uvBin
if ($LASTEXITCODE -ne 0) { throw 'missing-uv child verification failed.' }
Assert-True 'missing-uv output' (Test-Path -LiteralPath $withoutUvCapture -PathType Leaf)

Write-Output 'All verification assertions passed.'
