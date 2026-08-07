$script:__UvProfileState = @{
    ManagedActive = $false
    ActiveProfileName = $null
    ActiveProfilePath = $null
    BaselinePath = $null
    SavedVirtualEnvPresent = $false
    SavedVirtualEnv = $null
    SavedVirtualEnvPromptPresent = $false
    SavedVirtualEnvPrompt = $null
    SavedPromptFunction = @{ Present = $false; Script = $null }
    SavedDeactivateFunction = @{ Present = $false; Script = $null }
}

if ($global:__UvProfileState -is [hashtable] -and $global:__UvProfileState.ContainsKey('ManagedActive')) {
    $script:__UvProfileState = $global:__UvProfileState
}
$global:__UvProfileState = $script:__UvProfileState

$uv = Get-Command uv.exe -CommandType Application -ErrorAction SilentlyContinue
$global:__UvExePath = if ($null -ne $uv) { if ($uv.Source) { $uv.Source } else { $uv.Path } } else { $null }
if ($null -eq $global:__UvExePath) { Write-Warning 'uv.exe was not found during profile loading; custom uv profile commands remain available.' }

function global:__UvWorkonHome {
    if ([string]::IsNullOrWhiteSpace($env:WORKON_HOME)) { $env:WORKON_HOME = Join-Path $HOME '.virtualenvs' }
    if (Test-Path -LiteralPath $env:WORKON_HOME) { return (Get-Item -LiteralPath $env:WORKON_HOME -Force).FullName.TrimEnd('\') }
    return [IO.Path]::GetFullPath($env:WORKON_HOME).TrimEnd('\')
}

function global:__UvPath($Path) {
    if (Test-Path -LiteralPath $Path) { return (Get-Item -LiteralPath $Path -Force).FullName.TrimEnd('\') }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { return $full.TrimEnd('\') }
    return $full
}

function global:__UvValidateName($Name) {
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -in @('.', '..') -or $Name.IndexOfAny([char[]]('/\:')) -ge 0 -or $Name.IndexOf([char]0) -ge 0 -or $Name.StartsWith('-') -or $Name.EndsWith('.') -or $Name.EndsWith(' ')) { throw "Invalid profile name '$Name'." }
}

function global:__UvProfile($Name, [switch]$RequirePython) {
    __UvValidateName $Name
    $root = __UvWorkonHome
    $item = Get-Item -LiteralPath (Join-Path $root $Name) -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or -not $item.PSIsContainer) { throw "Profile '$Name' was not found in WORKON_HOME '$root'." }
    $scripts = Join-Path $item.FullName 'Scripts'; $python = Join-Path $scripts 'python.exe'; $activate = Join-Path $scripts 'Activate.ps1'
    $hasPython = Test-Path -LiteralPath $python -PathType Leaf; $hasActivate = Test-Path -LiteralPath $activate -PathType Leaf
    if ($RequirePython -and (-not $hasPython -or -not $hasActivate)) { throw "Profile '$Name' is not a valid uv profile." }
    [pscustomobject]@{ Name=$Name; ProfilePath=__UvPath $item.FullName; ScriptsPath=$scripts; PythonPath=$python; HasPython=$hasPython; HasActivate=$hasActivate }
}

function global:__UvFunction($Name) {
    $c = Get-Command $Name -CommandType Function -ErrorAction SilentlyContinue
    if ($null -eq $c) { return @{ Present=$false; Script=$null } }
    return @{ Present=$true; Script=$c.ScriptBlock }
}
function global:__UvRestoreFunction($Name, $Saved) {
    Remove-Item -LiteralPath "Function:\$Name" -Force -ErrorAction SilentlyContinue
    if ($Saved.Present) { Set-Item -LiteralPath "Function:\global:$Name" -Value $Saved.Script -Force }
}
function global:__UvNewState { return @{ ManagedActive=$false; ActiveProfileName=$null; ActiveProfilePath=$null; BaselinePath=$null; SavedVirtualEnvPresent=$false; SavedVirtualEnv=$null; SavedVirtualEnvPromptPresent=$false; SavedVirtualEnvPrompt=$null; SavedPromptFunction=@{Present=$false;Script=$null}; SavedDeactivateFunction=@{Present=$false;Script=$null} } }

function global:__UvClear {
    $s = $global:__UvProfileState; if (-not $s.ManagedActive) { return }
    $env:PATH = $s.BaselinePath
    if ($s.SavedVirtualEnvPresent) { $env:VIRTUAL_ENV=$s.SavedVirtualEnv } else { Remove-Item Env:VIRTUAL_ENV -ErrorAction SilentlyContinue }
    if ($s.SavedVirtualEnvPromptPresent) { $env:VIRTUAL_ENV_PROMPT=$s.SavedVirtualEnvPrompt } else { Remove-Item Env:VIRTUAL_ENV_PROMPT -ErrorAction SilentlyContinue }
    __UvRestoreFunction prompt $s.SavedPromptFunction; __UvRestoreFunction deactivate $s.SavedDeactivateFunction
    $global:__UvProfileState = __UvNewState
}

function global:__UvActivate([object[]]$A) {
    if ($A.Count -eq 2 -and $A[1] -in @('-h','--help')) { Write-Output 'Usage: uv activate <profile-name>'; return }
    if ($A.Count -ne 2) { throw 'Usage: uv activate <profile-name>' }
    $name=[string]$A[1]; __UvValidateName $name; $target=__UvProfile $name -RequirePython; $old=$global:__UvProfileState
    if ($old.ManagedActive -and $old.ActiveProfileName -ieq $name) { Write-Output "Profile '$name' is already active."; return }
    $rollback = @{ Path=$env:PATH; VE=(if (Test-Path Env:VIRTUAL_ENV) {@{P=$true;V=$env:VIRTUAL_ENV}} else {@{P=$false;V=$null}}); VEP=(if (Test-Path Env:VIRTUAL_ENV_PROMPT) {@{P=$true;V=$env:VIRTUAL_ENV_PROMPT}} else {@{P=$false;V=$null}}); Prompt=__UvFunction prompt; Deactivate=__UvFunction deactivate; State=$old }
    try {
        if ($old.ManagedActive) { __UvClear }
        elseif (Test-Path Env:VIRTUAL_ENV) { $root=__UvWorkonHome; if ((__UvPath $env:VIRTUAL_ENV).StartsWith((__UvPath $root)+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "Cannot activate '$name': VIRTUAL_ENV is set inside WORKON_HOME without managed state. Start a fresh PowerShell session or remove VIRTUAL_ENV first." }; throw "Cannot activate '$name': VIRTUAL_ENV points outside WORKON_HOME. Deactivate the external environment first." }
        $s=__UvNewState; $s.ManagedActive=$true; $s.ActiveProfileName=$name; $s.ActiveProfilePath=$target.ProfilePath; $s.BaselinePath=$env:PATH; $s.SavedVirtualEnvPresent=(Test-Path Env:VIRTUAL_ENV); $s.SavedVirtualEnv=$env:VIRTUAL_ENV; $s.SavedVirtualEnvPromptPresent=(Test-Path Env:VIRTUAL_ENV_PROMPT); $s.SavedVirtualEnvPrompt=$env:VIRTUAL_ENV_PROMPT; $s.SavedPromptFunction=__UvFunction prompt; $s.SavedDeactivateFunction=__UvFunction deactivate
        $env:VIRTUAL_ENV=$target.ProfilePath; $env:VIRTUAL_ENV_PROMPT=$name; $env:PATH="$($target.ScriptsPath);$($s.BaselinePath)"; $global:__UvProfileState=$s
        function global:deactivate { __UvClear }; function global:prompt { $s=$global:__UvProfileState; $base=if($s.SavedPromptFunction.Present){& $s.SavedPromptFunction.Script}else{"PS $($executionContext.SessionState.Path.CurrentLocation)> "}; "($($s.ActiveProfileName)) $base" }
    } catch { $env:PATH=$rollback.Path; if($rollback.VE.P){$env:VIRTUAL_ENV=$rollback.VE.V}else{Remove-Item Env:VIRTUAL_ENV -ErrorAction SilentlyContinue}; if($rollback.VEP.P){$env:VIRTUAL_ENV_PROMPT=$rollback.VEP.V}else{Remove-Item Env:VIRTUAL_ENV_PROMPT -ErrorAction SilentlyContinue}; __UvRestoreFunction prompt $rollback.Prompt; __UvRestoreFunction deactivate $rollback.Deactivate; $global:__UvProfileState=$rollback.State; Write-Error "uv activate failed: $($_.Exception.Message)" }
}

function global:__UvProfiles([object[]]$A) {
    if ($A.Count -eq 1 -and $A[0] -in @('-h','--help')) { Write-Output 'Usage: uv profiles'; return }; if ($A.Count -gt 0) { throw 'Usage: uv profiles' }
    $root=__UvWorkonHome; if(-not(Test-Path -LiteralPath $root -PathType Container)){Write-Output "No uv profiles found in '$root'.";return}; $rows=@()
    foreach($item in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop)){ $p=__UvProfile $item.Name; if(-not $p.HasActivate){continue}; $v='unknown'; if($p.HasPython){$o=(& $p.PythonPath --version 2>&1|Out-String).Trim();if($LASTEXITCODE -eq 0 -and $o -match '^Python\s+(.+)$'){$v=$Matches[1]}}; $status=if($global:__UvProfileState.ManagedActive -and (__UvPath $p.ProfilePath) -ieq (__UvPath $global:__UvProfileState.ActiveProfilePath)){'active'}else{'inactive'};$rows += [pscustomobject]@{NAME=$p.Name;PYTHON=$v;STATUS=$status} }
    if($rows.Count -eq 0){Write-Output "No uv profiles found in '$root'."}else{$rows|Sort-Object NAME|Format-Table -AutoSize}
}
function global:uv { if($args.Count -gt 0 -and $args[0] -ieq 'activate'){__UvActivate @args;return};if($args.Count -gt 0 -and $args[0] -ieq 'profiles'){$pa=@();if($args.Count -gt 1){$pa=@($args[1..($args.Count-1)])};__UvProfiles $pa;return};if([string]::IsNullOrWhiteSpace($global:__UvExePath)){Write-Error 'uv.exe was not found on PATH; custom uv profile commands are available, but standard uv commands cannot run.';return};& $global:__UvExePath @args }
