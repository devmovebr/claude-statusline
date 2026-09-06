<#
.SYNOPSIS
  Instala a status line do Claude Code no Windows.

.DESCRIPTION
  irm https://raw.githubusercontent.com/devmovebr/claude-statusline/main/install.ps1 | iex

  Ou, de um clone:  powershell -ExecutionPolicy Bypass -File install.ps1

  Copia o script para %USERPROFILE%\.claude\statusline-command.ps1 e aponta o
  statusLine do settings.json para ele. Guarda cópia do que havia antes nos dois
  casos.

  No Windows o Claude Code roda a status line pelo Git Bash quando ele existe e
  pelo PowerShell quando não existe. Chamar `powershell -File` funciona nos dois
  caminhos, então a instalação é a mesma com ou sem Git Bash, e não precisa de
  jq.

  Dentro do WSL, use o install.sh.
#>

$ErrorActionPreference = 'Stop'

$Repo = if ($env:CLAUDE_STATUSLINE_REPO) { $env:CLAUDE_STATUSLINE_REPO } else { 'devmovebr/claude-statusline' }
$Ref  = if ($env:CLAUDE_STATUSLINE_REF)  { $env:CLAUDE_STATUSLINE_REF }  else { 'main' }

function Falhar([string]$msg) { Write-Host "erro: $msg" -ForegroundColor Red; exit 1 }

$lar = if ($HOME) { $HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { $null }
if (-not $lar) { Falhar 'não achei a pasta do usuário (HOME nem USERPROFILE).' }

$claudeDir = Join-Path $lar '.claude'
$destino   = Join-Path $claudeDir 'statusline-command.ps1'
$settings  = Join-Path $claudeDir 'settings.json'
$carimbo   = Get-Date -Format 'yyyyMMdd-HHmmss'

# Caminho com barra normal. O Git Bash come a contrabarra como escape e o
# comando falha sem mensagem nenhuma.
$destinoBarra = $destino -replace '\\', '/'
$comando = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $destinoBarra + '"'

# Rodando de um clone, o statusline.ps1 está ao lado. Rodando por `irm | iex`,
# não está: aí baixa do repositório.
$origem = $null
$temporario = $null
if ($PSScriptRoot) {
  $vizinho = Join-Path $PSScriptRoot 'statusline.ps1'
  if (Test-Path -LiteralPath $vizinho) { $origem = $vizinho }
}
if (-not $origem) {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
  $url = "https://raw.githubusercontent.com/$Repo/$Ref/statusline.ps1"
  $temporario = Join-Path ([System.IO.Path]::GetTempPath()) ("statusline-$carimbo.ps1")
  try {
    Invoke-WebRequest -Uri $url -OutFile $temporario -UseBasicParsing
  } catch {
    Falhar "não consegui baixar statusline.ps1 de $Repo@$Ref. $($_.Exception.Message)"
  }
  $origem = $temporario
}

# Equivalente ao `bash -n`: lê o arquivo e só reclama de erro de sintaxe.
$erros = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($origem, [ref]$tokens, [ref]$erros) | Out-Null
if ($erros -and $erros.Count -gt 0) {
  Falhar "statusline.ps1 não passou na checagem de sintaxe: $($erros[0].Message)"
}

New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

if (Test-Path -LiteralPath $destino) {
  $antigo = [System.IO.File]::ReadAllBytes($destino)
  $novoConteudo = [System.IO.File]::ReadAllBytes($origem)
  if (-not [System.Linq.Enumerable]::SequenceEqual($antigo, $novoConteudo)) {
    Copy-Item -LiteralPath $destino -Destination "$destino.bak-$carimbo" -Force
    Write-Host "status line anterior guardada em $destino.bak-$carimbo"
  }
}
Copy-Item -LiteralPath $origem -Destination $destino -Force
if ($temporario) { Remove-Item -LiteralPath $temporario -Force -ErrorAction SilentlyContinue }

# O settings.json guarda hooks, permissões e modelo. Reescrever o arquivo
# inteiro perderia tudo isso, então só o campo statusLine é trocado.
$config = $null
if ((Test-Path -LiteralPath $settings) -and ((Get-Item -LiteralPath $settings).Length -gt 0)) {
  $texto = [System.IO.File]::ReadAllText($settings)
  try {
    $config = $texto | ConvertFrom-Json
  } catch {
    Falhar "$settings não é JSON válido. Corrija antes de instalar."
  }
  if ($config -isnot [PSCustomObject]) { Falhar "$settings não tem um objeto JSON na raiz." }
  Copy-Item -LiteralPath $settings -Destination "$settings.bak-$carimbo" -Force
} else {
  $config = New-Object PSCustomObject
}

$novoStatusLine = [PSCustomObject]@{ type = 'command'; command = $comando }
if ($config.PSObject.Properties['statusLine']) { $config.PSObject.Properties.Remove('statusLine') }
$config | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $novoStatusLine

# UTF-8 sem BOM: o parser de JSON do Claude Code engasga com o BOM, e o
# Set-Content do Windows PowerShell 5.1 escreve um.
$saidaJson = $config | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($settings, $saidaJson, (New-Object System.Text.UTF8Encoding($false)))

$agora = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$demo = @{
  model         = @{ display_name = 'Opus 5' }
  cwd           = (Get-Location).Path
  workspace     = @{ project_dir = (Get-Location).Path }
  context_window = @{ remaining_percentage = 73 }
  rate_limits   = @{
    five_hour = @{ used_percentage = 49; resets_at = ($agora + 8520) }
    seven_day = @{ used_percentage = 42; resets_at = ($agora + 344400) }
  }
} | ConvertTo-Json -Depth 10 -Compress

Write-Host ''
Write-Host 'instalado. Prévia:'
Write-Host ''
$exe = (Get-Process -Id $PID).Path
$demo | & $exe -NoProfile -File $destino
Write-Host ''
Write-Host ''
Write-Host 'Abra uma sessão nova do Claude Code para valer.'
