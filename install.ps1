# Installs the Claude Code status line on Windows.
#
#   irm https://raw.githubusercontent.com/devmovebr/claude-statusline/main/install.ps1 | iex
#
# Or, from a clone:  powershell -ExecutionPolicy Bypass -File install.ps1
#
# Copies the script to %USERPROFILE%\.claude\statusline-command.ps1 and points
# the statusLine field of settings.json at it. Keeps a timestamped copy of what
# was there before in both cases.
#
# On Windows, Claude Code runs the status line through Git Bash when Git Bash is
# installed and through PowerShell when it is not. Calling `powershell -File`
# works on both paths, so the install is the same either way, and there is no jq
# to install first.
#
# Inside WSL, use install.sh.
#
# This file is ASCII only and carries no byte order mark, on purpose. `irm` hands
# `iex` a string with the BOM still in it, and a BOM in front of a multi-line
# `<# #>` block stops PowerShell from reading the block as a comment. Without a
# BOM, Windows PowerShell 5.1 reads the file from disk as ANSI, so any accented
# character here would come out mangled. Staying in ASCII keeps both paths clean.
# Messages are in English for the same reason.

$ErrorActionPreference = 'Stop'

$Repo = if ($env:CLAUDE_STATUSLINE_REPO) { $env:CLAUDE_STATUSLINE_REPO } else { 'devmovebr/claude-statusline' }
$Ref  = if ($env:CLAUDE_STATUSLINE_REF)  { $env:CLAUDE_STATUSLINE_REF }  else { 'main' }

function Fail([string]$msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

$home_dir = if ($HOME) { $HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { $null }
if (-not $home_dir) { Fail 'could not find your home folder (neither HOME nor USERPROFILE is set).' }

$claudeDir = Join-Path $home_dir '.claude'
$target    = Join-Path $claudeDir 'statusline-command.ps1'
$settings  = Join-Path $claudeDir 'settings.json'
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'

# Forward slashes in the path. Git Bash eats a backslash as an escape character
# and the command then fails with nothing on screen.
$targetSlash = $target -replace '\\', '/'
$command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $targetSlash + '"'

# Running from a clone, statusline.ps1 sits next to this file. Running through
# `irm | iex` it does not, so then it gets downloaded.
$source = $null
$temp = $null
if ($PSScriptRoot) {
  $neighbour = Join-Path $PSScriptRoot 'statusline.ps1'
  if (Test-Path -LiteralPath $neighbour) { $source = $neighbour }
}
if (-not $source) {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
  $url = "https://raw.githubusercontent.com/$Repo/$Ref/statusline.ps1"
  $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("statusline-$stamp.ps1")
  try {
    Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing
  } catch {
    Fail "could not download statusline.ps1 from $Repo@$Ref. $($_.Exception.Message)"
  }
  $source = $temp
}

# The equivalent of `bash -n`: read the file and complain only about syntax.
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
  Fail "statusline.ps1 failed the syntax check: $($errors[0].Message)"
}

New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

if (Test-Path -LiteralPath $target) {
  $old = [System.IO.File]::ReadAllBytes($target)
  $new = [System.IO.File]::ReadAllBytes($source)
  if (-not [System.Linq.Enumerable]::SequenceEqual($old, $new)) {
    Copy-Item -LiteralPath $target -Destination "$target.bak-$stamp" -Force
    Write-Host "previous status line kept at $target.bak-$stamp"
  }
}
Copy-Item -LiteralPath $source -Destination $target -Force
if ($temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }

# settings.json holds hooks, permissions and the model. Rewriting the whole file
# would lose all of that, so only the statusLine field is replaced.
$config = $null
if ((Test-Path -LiteralPath $settings) -and ((Get-Item -LiteralPath $settings).Length -gt 0)) {
  $text = [System.IO.File]::ReadAllText($settings)
  try {
    $config = $text | ConvertFrom-Json
  } catch {
    Fail "$settings is not valid JSON. Fix it before installing."
  }
  if ($config -isnot [PSCustomObject]) { Fail "$settings does not have a JSON object at its root." }
  Copy-Item -LiteralPath $settings -Destination "$settings.bak-$stamp" -Force
} else {
  $config = New-Object PSCustomObject
}

$newStatusLine = [PSCustomObject]@{ type = 'command'; command = $command }
if ($config.PSObject.Properties['statusLine']) { $config.PSObject.Properties.Remove('statusLine') }
$config | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $newStatusLine

# UTF-8 with no BOM: the Claude Code JSON parser chokes on a BOM, and
# Set-Content on Windows PowerShell 5.1 writes one.
$json = $config | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($settings, $json, (New-Object System.Text.UTF8Encoding($false)))

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$demo = @{
  model          = @{ display_name = 'Opus 5' }
  cwd            = (Get-Location).Path
  workspace      = @{ project_dir = (Get-Location).Path }
  context_window = @{ remaining_percentage = 73 }
  rate_limits    = @{
    five_hour = @{ used_percentage = 49; resets_at = ($now + 8520) }
    seven_day = @{ used_percentage = 42; resets_at = ($now + 344400) }
  }
} | ConvertTo-Json -Depth 10 -Compress

Write-Host ''
Write-Host 'installed. Preview:'
Write-Host ''
$exe = (Get-Process -Id $PID).Path
$demo | & $exe -NoProfile -File $target
Write-Host ''
Write-Host ''
Write-Host 'Open a new Claude Code session for it to take effect.'
