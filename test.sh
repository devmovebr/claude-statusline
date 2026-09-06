#!/usr/bin/env bash
# Testes da status line.
#
#   bash test.sh          roda tudo e mostra o que cada caso desenha
#   bash test.sh --plain  sem cor, para colar em arquivo
#
# Cada caso monta um payload igual ao que o Claude Code manda no stdin e
# compara o que sai. Quando existe um PowerShell na máquina (`pwsh` ou
# `powershell`), o mesmo payload passa pelo statusline.ps1 e as duas saídas
# precisam bater byte a byte: é o que garante que a versão do Windows não
# desandou.
set -uo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")"

plain=0
[ "${1:-}" = "--plain" ] && plain=1

ps=""
for candidato in pwsh powershell pwsh.exe powershell.exe; do
  if command -v "$candidato" >/dev/null 2>&1; then ps=$candidato; break; fi
done

# Ancora os resets a meio minuto da virada. Sem isso, bash e PowerShell rodando
# em lados opostos de um segundo cheio mostrariam minutos diferentes.
base=$(( $(date +%s) / 60 * 60 + 30 ))
em_2h=$(( base + 8520 ))
em_4d=$(( base + 344400 ))
passado=$(( base - 600 ))

sem_cor() { sed $'s/\033\[[0-9;]*m//g'; }
mostra()  { if [ "$plain" = 1 ]; then sem_cor; else cat; fi; }

total=0
falhas=0

tmp_valida=$(mktemp -t statusline-valida).ps1
trap 'rm -f "$tmp_valida" "${tmp_valida%.ps1}"' EXIT

# caso <nome> <json>
caso() {
  local nome=$1 json=$2 saida_sh saida_ps
  total=$(( total + 1 ))
  saida_sh=$(printf '%s' "$json" | bash statusline.sh)

  printf '\n\033[1m%2d. %s\033[0m\n' "$total" "$nome" | mostra
  if [ -n "$saida_sh" ]; then
    printf '%s\n' "$saida_sh" | sed 's/^/    /' | mostra
  else
    printf '    \033[2m(linha vazia)\033[0m\n' | mostra
  fi

  if [ -n "$ps" ]; then
    saida_ps=$(printf '%s' "$json" | "$ps" -NoProfile -File statusline.ps1 2>/dev/null)
    if [ "$saida_sh" = "$saida_ps" ]; then
      printf '    \033[32m✓ ps1 idêntico\033[0m\n' | mostra
    else
      falhas=$(( falhas + 1 ))
      printf '    \033[31m✗ ps1 divergiu\033[0m\n' | mostra
      printf '%s\n' "$saida_ps" | sed 's/^/      ps1: /' | mostra
    fi
  fi
}

printf '\033[1mstatusline\033[0m  bash %s' "${BASH_VERSION%%(*}" | mostra
if [ -n "$ps" ]; then
  printf '  |  %s %s' "$ps" "$("$ps" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null)" | mostra
else
  printf '  |  \033[2msem PowerShell, statusline.ps1 não testado\033[0m' | mostra
fi
printf '\n' | mostra

caso "payload completo" \
  '{"model":{"display_name":"Opus 5"},"cwd":"/w/valoer-infra","workspace":{"project_dir":"/w/valoer-infra"},"worktree":{"branch":"main"},"session_id":"s1","context_window":{"remaining_percentage":73},"rate_limits":{"five_hour":{"used_percentage":49,"resets_at":'"$em_2h"'},"seven_day":{"used_percentage":42,"resets_at":'"$em_4d"'}}}'

caso "fora de repositório git (sem branch)" \
  '{"model":{"display_name":"Sonnet 5"},"cwd":"/tmp","workspace":{"project_dir":"/tmp"},"session_id":"s2","context_window":{"remaining_percentage":98},"rate_limits":{"five_hour":{"used_percentage":3,"resets_at":'"$em_2h"'},"seven_day":{"used_percentage":11,"resets_at":'"$em_4d"'}}}'

caso "sem rate limits no payload" \
  '{"model":{"display_name":"Haiku 4.5"},"cwd":"/w/api","workspace":{"project_dir":"/w/api"},"worktree":{"branch":"feat/cobranca"},"session_id":"s3","context_window":{"remaining_percentage":40}}'

caso "só rate limits, sem contexto" \
  '{"model":{"display_name":"Opus 5"},"cwd":"/w/api","workspace":{"project_dir":"/w/api"},"session_id":"s4","rate_limits":{"five_hour":{"used_percentage":88,"resets_at":'"$em_2h"'},"seven_day":{"used_percentage":97,"resets_at":'"$em_4d"'}}}'

caso "extremos: barra vazia e barra cheia" \
  '{"model":{"display_name":"Opus 5"},"cwd":"/w/api","workspace":{"project_dir":"/w/api"},"session_id":"s5","context_window":{"remaining_percentage":100},"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":'"$em_2h"'},"seven_day":{"used_percentage":100,"resets_at":'"$em_4d"'}}}'

caso "percentual fracionário (trunca, não arredonda)" \
  '{"model":{"display_name":"Opus 5"},"cwd":"/w/api","workspace":{"project_dir":"/w/api"},"session_id":"s6","context_window":{"remaining_percentage":36.9},"rate_limits":{"five_hour":{"used_percentage":12.4,"resets_at":'"$em_2h"'},"seven_day":{"used_percentage":66.7,"resets_at":'"$em_4d"'}}}'

caso "reset já vencido (não vai a negativo)" \
  '{"model":{"display_name":"Opus 5"},"cwd":"/w/api","workspace":{"project_dir":"/w/api"},"session_id":"s7","rate_limits":{"five_hour":{"used_percentage":5,"resets_at":'"$passado"'},"seven_day":{"used_percentage":9,"resets_at":'"$passado"'}}}'

caso "percentual acima de 100 (limite de gasto estourado)" \
  '{"model":{"display_name":"Opus 5"},"cwd":"/w/api","workspace":{"project_dir":"/w/api"},"session_id":"s8","rate_limits":{"five_hour":{"used_percentage":140,"resets_at":'"$em_2h"'},"seven_day":{"used_percentage":100,"resets_at":'"$em_4d"'}}}'

caso "session_id sujo cai no diretório default" \
  '{"model":{"display_name":"Opus 5"},"cwd":"/w/api","workspace":{"project_dir":"/w/api"},"session_id":"../../etc","context_window":{"remaining_percentage":50}}'

caso "json inválido" 'nao sou json'

caso "payload vazio" ''

# Subagentes: cria os marcadores que os hooks criariam, conta, e limpa.
sub_dir="${TMPDIR:-/tmp}/claude-subagentes/teste-subagentes"
mkdir -p "$sub_dir" && : > "$sub_dir/m.1" && : > "$sub_dir/m.2" && : > "$sub_dir/m.3"
caso "três subagentes vivos" \
  '{"model":{"display_name":"Opus 5"},"cwd":"/w/api","workspace":{"project_dir":"/w/api"},"worktree":{"branch":"main"},"session_id":"teste-subagentes","context_window":{"remaining_percentage":73}}'
rm -rf "${TMPDIR:-/tmp}/claude-subagentes/teste-subagentes"

# A barra em cada faixa de oitavo: 8 células × 8 subdivisões = 1/64, ou 1,5625%
# por passo visível.
printf '\n\033[1m%2d. resolução da barra, um passo de oitavo por linha\033[0m\n' "$(( total + 1 ))" | mostra
total=$(( total + 1 ))
for pct in 0 1 2 3 5 6 8 12 25 27 33 50 66 75 88 99 100; do
  linha=$(printf '{"model":{"display_name":"m"},"rate_limits":{"five_hour":{"used_percentage":%s}}}' "$pct" \
    | bash statusline.sh | tail -1)
  printf '    %3s%%  %s\n' "$pct" "${linha#⏳ }" | mostra
done

# Os dois caminhos de instalação entregam o .ps1 de jeitos diferentes, e o
# parser do PowerShell não vê a mesma coisa nos dois. O `-File` lê do disco e
# descarta o BOM. O `irm | iex` passa a string com o BOM dentro, e um BOM na
# frente de um bloco `<# #>` de várias linhas faz o PowerShell parar de ler o
# bloco como comentário. Cada arquivo é conferido nos dois caminhos.
if [ -n "$ps" ]; then
  printf '\n\033[1m%2d. os .ps1 nos dois caminhos de entrega\033[0m\n' "$(( total + 1 ))" | mostra
  total=$(( total + 1 ))
  cat > "$tmp_valida" <<'PSVALIDA'
$falhou = 0
function Diz($ok, $texto) {
  if ($ok) { Write-Host ("    " + [char]0x2713 + " " + $texto) -ForegroundColor Green }
  else     { Write-Host ("    " + [char]0x2717 + " " + $texto) -ForegroundColor Red; $script:falhou++ }
}
function Erros($txt) {
  $e = $null; $t = $null
  [System.Management.Automation.Language.Parser]::ParseInput($txt, [ref]$t, [ref]$e) | Out-Null
  return $e
}
foreach ($nome in @('statusline.ps1', 'install.ps1')) {
  $caminho = Join-Path $args[0] $nome
  $bytes = [System.IO.File]::ReadAllBytes($caminho)
  $temBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $soAscii = -not ($bytes | Where-Object { $_ -gt 0x7F })

  # caminho `-File`: o PowerShell lê do disco e tira o BOM
  $e = $null; $t = $null
  [System.Management.Automation.Language.Parser]::ParseFile($caminho, [ref]$t, [ref]$e) | Out-Null
  Diz (-not $e -or $e.Count -eq 0) "$nome parseia via -File"

  # caminho `irm | iex`: a string chega com o BOM
  $comBom = [System.Text.Encoding]::UTF8.GetString($bytes)
  $e2 = Erros $comBom
  Diz (-not $e2 -or $e2.Count -eq 0) "$nome parseia via irm | iex$(if ($e2) { ' (linha ' + $e2[0].Extent.StartLineNumber + ' char ' + $e2[0].Extent.StartColumnNumber + ': ' + $e2[0].Message + ')' })"

  if ($nome -eq 'install.ps1') {
    # Sem BOM o Windows PowerShell 5.1 lê o arquivo do disco como ANSI. Em
    # ASCII puro isso dá exatamente os mesmos bytes, então não há o que estragar.
    Diz (-not $temBom) 'install.ps1 sem BOM, que o iex nao tolera na frente de <# #>'
    Diz $soAscii       'install.ps1 em ASCII puro, imune ao code page do 5.1'
  } else {
    # A barra e os emojis precisam do BOM para o 5.1 não ler o arquivo em ANSI.
    Diz $temBom 'statusline.ps1 com BOM, que o 5.1 precisa para os blocos e emojis'
  }
}
exit $falhou
PSVALIDA
  if "$ps" -NoProfile -File "$tmp_valida" "$PWD" 2>&1 | mostra; then :; else
    falhas=$(( falhas + 1 ))
  fi
fi

printf '\n' | mostra
if [ -n "$ps" ] && [ "$falhas" -gt 0 ]; then
  printf '\033[31m%d de %d casos falharam.\033[0m\n' "$falhas" "$total" | mostra
  exit 1
fi
if [ -n "$ps" ]; then
  printf '\033[32m%d casos, bash e PowerShell com a mesma saída.\033[0m\n' "$total" | mostra
else
  printf '%d casos rodados.\n' "$total" | mostra
fi
