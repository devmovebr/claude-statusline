# Status line do Claude Code no Windows, duas linhas:
#   modelo | pasta | branch | subagentes
#   contexto | limite 5h | limite semanal
#
# Porte do statusline.sh para PowerShell. Serve o Windows sem Git Bash, onde o
# Claude Code roda a status line pelo PowerShell, e o Windows com Git Bash, onde
# `powershell -File` funciona do mesmo jeito.
#
# Escrito para Windows PowerShell 5.1, que e o `powershell` presente em toda
# instalacao. Roda igual no PowerShell 7.
#
# Nao usa jq: ConvertFrom-Json ja vem na caixa.
#
# As tres metricas mostram a porcentagem USADA, e a barra enche conforme se
# consome. O payload entrega o contexto como `remaining_percentage`, entao ele e
# invertido aqui para as tres barras se lerem do mesmo jeito.

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

# Os blocos e os emojis saem em UTF-8. Sem isto o console reescreve tudo no
# code page ANSI e a barra vira interrogacao.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$raw = ''
try { $raw = [Console]::In.ReadToEnd() } catch { }
if (-not $raw) { return }

$dados = $null
try { $dados = $raw | ConvertFrom-Json } catch { }
if ($null -eq $dados) { return }

# Caminha por um caminho pontilhado sem estourar em campo ausente, que e o que
# `// ""` faz no jq.
function Get-Campo {
  param($raiz, [string]$caminho)
  $atual = $raiz
  foreach ($parte in $caminho.Split('.')) {
    if ($null -eq $atual) { return $null }
    $prop = $atual.PSObject.Properties[$parte]
    if ($null -eq $prop) { return $null }
    $atual = $prop.Value
  }
  return $atual
}

# Trunca o decimal, igual ao ${pct%%.*} do shell. O cast [double] do PowerShell
# usa cultura invariante, entao "49.5" le certo mesmo com virgula decimal no
# Windows em portugues.
function ConvertTo-Inteiro {
  param($valor)
  if ($null -eq $valor -or "$valor" -eq '') { return $null }
  try { return [int][math]::Floor([double]$valor) } catch { return $null }
}

$model        = Get-Campo $dados 'model.display_name'
$branch       = Get-Campo $dados 'worktree.branch'
$cwd          = Get-Campo $dados 'cwd'
if (-not $cwd) { $cwd = Get-Campo $dados 'workspace.current_dir' }
$project      = Get-Campo $dados 'workspace.project_dir'
$ctxRestante  = Get-Campo $dados 'context_window.remaining_percentage'
$h5           = Get-Campo $dados 'rate_limits.five_hour.used_percentage'
$h5Reset      = Get-Campo $dados 'rate_limits.five_hour.resets_at'
$d7           = Get-Campo $dados 'rate_limits.seven_day.used_percentage'
$d7Reset      = Get-Campo $dados 'rate_limits.seven_day.resets_at'
$sessao       = Get-Campo $dados 'session_id'

# Sem branch no payload, pergunta ao git. Local, sem rede, sem tocar em lock.
if (-not $branch -and $cwd) {
  try {
    $branch = (& git -C "$cwd" --no-optional-locks branch --show-current 2>$null | Select-Object -First 1)
  } catch { $branch = '' }
}

if (-not $project) { $project = $cwd }
$pasta = ''
if ($project) { $pasta = Split-Path -Path $project -Leaf }

# Subagentes: um marcador por subagente vivo, criado/apagado pelos hooks
# SubagentStart/SubagentStop. Marcador com mais de 6h e resto de crash e some.
if (-not $sessao) { $sessao = 'default' }
if ($sessao -notmatch '^[A-Za-z0-9._-]+$') { $sessao = 'default' }
$dirSub = Join-Path ([System.IO.Path]::GetTempPath()) (Join-Path 'claude-subagentes' $sessao)
$subagentes = 0
if (Test-Path -LiteralPath $dirSub) {
  $corte = (Get-Date).AddHours(-6)
  Get-ChildItem -LiteralPath $dirSub -Filter 'm.*' -File |
    Where-Object { $_.LastWriteTime -lt $corte } |
    Remove-Item -Force -ErrorAction SilentlyContinue
  $subagentes = @(Get-ChildItem -LiteralPath $dirSub -File).Count
}

$E = [char]27
$R       = "$E[0m"
$CIANO   = "$E[36m"
$AMARELO = "$E[33m"
$AZUL    = "$E[34m"
$VERDE   = "$E[32m"
$MAGENTA = "$E[35m"
$LARANJA = "$E[38;5;208m"

# A barra tem a altura de um bloco inteiro, igual a do emoji ao lado. O trecho
# vazio fica hachurado e vira solido conforme enche. A borda usa os blocos
# parciais de oitavo, entao a resolucao e de 1/64 e nao de uma celula.
$CELULAS  = 8
$CHEIA    = '█'
$VAZIA    = '░'
$PARCIAIS = @('', '▏', '▎', '▍', '▌', '▋', '▊', '▉')

function Get-Barra {
  param([string]$cor, [string]$rotulo, $pct)
  $inteiro = ConvertTo-Inteiro $pct
  if ($null -eq $inteiro -or $inteiro -lt 0) { $inteiro = 0 }
  if ($inteiro -gt 100) { $inteiro = 100 }
  $oitavos = [int][math]::Floor(($inteiro * $CELULAS * 8) / 100)
  $cheias  = [int][math]::Floor($oitavos / 8)
  $resto   = $oitavos % 8
  $out = $CHEIA * $cheias
  if ($cheias -lt $CELULAS) {
    if ($resto -gt 0) { $out += $PARCIAIS[$resto] } else { $out += $VAZIA }
    $out += $VAZIA * ($CELULAS - $cheias - 1)
  }
  return "$cor$rotulo $out $inteiro%$R"
}

$DIAS = @('Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb')
$agora = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# Get-Reinicio <epoch> -> " (2h 22min) (Qui 15:40)"
function Get-Reinicio {
  param($ts)
  $t = ConvertTo-Inteiro $ts
  if ($null -eq $t -or $t -le 0) { return '' }
  $falta = $t - $agora
  if ($falta -lt 0) { $falta = 0 }
  $d = [int][math]::Floor($falta / 86400)
  $h = [int][math]::Floor(($falta % 86400) / 3600)
  $m = [int][math]::Floor(($falta % 3600) / 60)
  if ($d -gt 0)      { $quanto = "${d}d ${h}h" }
  elseif ($h -gt 0)  { $quanto = "${h}h ${m}min" }
  else               { $quanto = "${m}min" }
  $local = [DateTimeOffset]::FromUnixTimeSeconds($t).ToLocalTime()
  $dia = $DIAS[[int]$local.DayOfWeek]
  return (' ({0}) ({1} {2})' -f $quanto, $dia, $local.ToString('HH:mm'))
}

$topo = @()
if ($model)          { $topo += "$CIANO🧠 $model$R" }
if ($pasta)          { $topo += "$AZUL📁 $pasta$R" }
if ($branch)         { $topo += "$AMARELO🌿 $branch$R" }
if ($subagentes -gt 0) { $topo += "$CIANO🤖 $subagentes$R" }

$partes = @()
$restanteInt = ConvertTo-Inteiro $ctxRestante
if ($null -ne $restanteInt) {
  $partes += '📊 ' + (Get-Barra $VERDE 'ctx' (100 - $restanteInt))
}
if ($null -ne (ConvertTo-Inteiro $h5)) {
  $partes += '⏳ ' + (Get-Barra $MAGENTA '5h' $h5) + (Get-Reinicio $h5Reset)
}
if ($null -ne (ConvertTo-Inteiro $d7)) {
  $partes += '📅 ' + (Get-Barra $LARANJA 'sem' $d7) + (Get-Reinicio $d7Reset)
}

$linha1 = ($topo -join ' | ')
$linha2 = ($partes -join ' | ')
if ($linha1 -and $linha2) { $saida = "$linha1`n$linha2" } else { $saida = "$linha1$linha2" }
[Console]::Out.Write($saida)
