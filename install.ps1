# agent-playbook installer for Windows when the repo is checked out on the Windows side.
# Runs install.sh through Git for Windows' bash with --home $env:USERPROFILE --copy
# (copy mode, because Windows symlinks need extra rights).
# If the repo lives in WSL, run install.sh from WSL with --home /mnt/c/Users/<name> --copy instead.
param(
  [Parameter(Position = 0)][ValidateSet('install', 'uninstall', 'status', 'doctor')][string]$Command = 'install',
  [string]$Harness = '',
  [switch]$DryRun,
  [switch]$Force,
  [switch]$Yes
)

$candidates = @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
# Note: C:\Windows\System32\bash.exe is the WSL launcher, not Git Bash. Do not use it here.
$bash = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bash) {
  Write-Error 'Git for Windows bash not found. Install Git for Windows, or run install.sh from WSL with --home /mnt/c/Users/<name> --copy.'
  exit 3
}

$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = (Join-Path $repo 'install.sh') -replace '\\', '/'
$homeDir = $env:USERPROFILE -replace '\\', '/'

$argsList = @($script, $Command, '--home', $homeDir, '--copy')
if ($Harness) { $argsList += @('--harness', $Harness) }
if ($DryRun) { $argsList += '--dry-run' }
if ($Force) { $argsList += '--force' }
if ($Yes) { $argsList += '--yes' }

& $bash @argsList
exit $LASTEXITCODE
