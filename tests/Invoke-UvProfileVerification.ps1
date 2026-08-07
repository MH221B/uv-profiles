[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$TestRoot,[Parameter(Mandatory=$true)][string]$SharedScript)
$ErrorActionPreference='Stop';$env:WORKON_HOME=$TestRoot;. $SharedScript
if(-not(Test-Path -LiteralPath (Join-Path $TestRoot 'alpha\Scripts\python.exe'))){throw 'Create alpha with uv venv before running this test.'}
uv profiles | Out-String | Write-Output
uv activate alpha
if(-not $env:VIRTUAL_ENV){throw 'VIRTUAL_ENV was not set'}
if(-not (Get-Command deactivate -CommandType Function -ErrorAction SilentlyContinue)){throw 'deactivate was not defined'}
deactivate
if(Get-Command deactivate -CommandType Function -ErrorAction SilentlyContinue){throw 'deactivate was not removed'}
Write-Output 'All verification assertions passed.'
