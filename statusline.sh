#!/bin/bash
# Status line, duas linhas:
#   modelo | pasta | branch | subagentes
#   contexto | limite 5h | limite semanal
#
# As três métricas mostram a porcentagem USADA, e a barra enche conforme se
# consome. O payload entrega o contexto como `remaining_percentage`, então ele é
# invertido aqui para as três barras se lerem do mesmo jeito.
#
# O payload também é repassado, intacto, para o hook de telemetria do Orca, que
# é quem o settings.json chamava antes deste wrapper. Sem esse repasse, apontar
# o statusLine.command para cá cortaria a telemetria em silêncio. Vai para
# segundo plano porque o hook faz uma chamada HTTP com até 1,5s de timeout, e a
# linha não pode esperar por isso a cada redesenho.

input=$(cat)

orca="$HOME/.orca/agent-hooks/claude-statusline.sh"
if [ -x "$orca" ]; then
  printf '%s' "$input" | "$orca" >/dev/null 2>&1 &
fi

# Uma chamada de jq, não uma por campo: a status line é redesenhada a cada
# poucos segundos e cada invocação é um processo novo.
#
# Um campo por linha, e não @tsv: com IFS=tab o `read` trata tabs seguidos como
# um separador só, então um campo vazio no meio (branch, fora de repo) desloca
# todos os seguintes em silêncio.
{
  IFS= read -r model
  IFS= read -r branch
  IFS= read -r cwd
  IFS= read -r project
  IFS= read -r ctx_restante
  IFS= read -r h5
  IFS= read -r h5_reset
  IFS= read -r d7
  IFS= read -r d7_reset
  IFS= read -r sessao
} <<EOF
$(printf '%s' "$input" | jq -r '
  .model.display_name // "",
  .worktree.branch // "",
  (.cwd // .workspace.current_dir // ""),
  .workspace.project_dir // "",
  (.context_window.remaining_percentage // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.rate_limits.seven_day.resets_at // ""),
  .session_id // ""' 2>/dev/null)
EOF

# Sem branch no payload, pergunta ao git. Local, sem rede, sem tocar em lock.
if [ -z "$branch" ] && [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
fi

[ -z "$project" ] && project="$cwd"
pasta=""
[ -n "$project" ] && pasta=$(basename "$project")

# Subagentes: um marcador por subagente vivo, criado/apagado pelos hooks
# SubagentStart/SubagentStop. Marcador com mais de 6h é resto de crash e some.
[ -z "$sessao" ] && sessao=default
case "$sessao" in *[!A-Za-z0-9._-]*) sessao=default ;; esac
dir_sub="${TMPDIR:-/tmp}/claude-subagentes/$sessao"
subagentes=0
if [ -d "$dir_sub" ]; then
  find "$dir_sub" -name 'm.*' -mmin +360 -delete 2>/dev/null || :
  subagentes=$(ls -1 "$dir_sub" 2>/dev/null | wc -l | tr -d ' ')
fi

R=$'\033[0m'
CIANO=$'\033[36m'
AMARELO=$'\033[33m'
AZUL=$'\033[34m'
VERDE=$'\033[32m'
MAGENTA=$'\033[35m'
LARANJA=$'\033[38;5;208m'

# A barra tem a altura de um bloco inteiro, igual à do emoji ao lado. O trecho
# vazio fica hachurado e vira sólido conforme enche. A borda usa os blocos
# parciais de oitavo, então a resolução é de 1/64 e não de uma célula.
CELULAS=8
CHEIA='█'
VAZIA='░'
PARCIAIS=('' '▏' '▎' '▍' '▌' '▋' '▊' '▉')

# barra <cor> <rótulo> <percentual usado>
barra() {
  local cor=$1 rotulo=$2 pct=$3
  local inteiro oitavos cheias resto i out=""
  inteiro=${pct%%.*}
  case "$inteiro" in ''|*[!0-9]*) inteiro=0 ;; esac
  [ "$inteiro" -gt 100 ] && inteiro=100
  oitavos=$(( inteiro * CELULAS * 8 / 100 ))
  cheias=$(( oitavos / 8 ))
  resto=$(( oitavos % 8 ))
  for ((i = 0; i < cheias; i++)); do out="$out$CHEIA"; done
  if [ "$cheias" -lt "$CELULAS" ]; then
    if [ "$resto" -gt 0 ]; then out="$out${PARCIAIS[$resto]}"; else out="$out$VAZIA"; fi
    for ((i = cheias + 1; i < CELULAS; i++)); do out="$out$VAZIA"; done
  fi
  # O % vai literal: a string inteira é argumento de um %s, não formato.
  printf '%s' "${cor}${rotulo} ${out} ${inteiro}%${R}"
}

# `date -r` lê epoch no BSD e arquivo de referência no GNU, então o teste
# distingue os dois sem depender de uname.
if date -r 0 '+%s' >/dev/null 2>&1; then
  data_local() { date -r "$1" '+%w %H:%M'; }
else
  data_local() { date -d "@$1" '+%w %H:%M'; }
fi

DIAS=(Dom Seg Ter Qua Qui Sex Sáb)
agora=$(date '+%s')

# reinicio <epoch> -> "(2h 22min) (Qui 15:40)"
reinicio() {
  local ts=$1 falta d h m quanto
  case "$ts" in ''|*[!0-9]*) return ;; esac
  falta=$(( ts - agora ))
  [ "$falta" -lt 0 ] && falta=0
  d=$(( falta / 86400 ))
  h=$(( falta % 86400 / 3600 ))
  m=$(( falta % 3600 / 60 ))
  if [ "$d" -gt 0 ]; then quanto="${d}d ${h}h"
  elif [ "$h" -gt 0 ]; then quanto="${h}h ${m}min"
  else quanto="${m}min"; fi
  set -- $(data_local "$ts")
  printf ' (%s) (%s %s)' "$quanto" "${DIAS[$1]}" "$2"
}

topo=()
[ -n "$model" ]  && topo+=("${CIANO}🧠 ${model}${R}")
[ -n "$pasta" ]  && topo+=("${AZUL}📁 ${pasta}${R}")
[ -n "$branch" ] && topo+=("${AMARELO}🌿 ${branch}${R}")
[ "$subagentes" -gt 0 ] 2>/dev/null && topo+=("${CIANO}🤖 ${subagentes}${R}")

partes=()
if [ -n "$ctx_restante" ]; then
  # Trunca o decimal em vez de chamar bc ou awk: é um processo a menos por
  # redesenho, e o que a fração moveria na barra é menos de um oitavo de célula.
  restante_int=${ctx_restante%%.*}
  case "$restante_int" in ''|*[!0-9]*) restante_int=0 ;; esac
  partes+=("📊 $(barra "$VERDE" ctx "$(( 100 - restante_int ))")")
fi
[ -n "$h5" ] && partes+=("⏳ $(barra "$MAGENTA" 5h "$h5")$(reinicio "$h5_reset")")
[ -n "$d7" ] && partes+=("📅 $(barra "$LARANJA" sem "$d7")$(reinicio "$d7_reset")")

junta() {
  local i saida=""
  for ((i = 1; i <= $#; i++)); do
    [ "$i" -gt 1 ] && saida="$saida | "
    saida="$saida${!i}"
  done
  printf '%s' "$saida"
}

linha1=$(junta "${topo[@]}")
linha2=$(junta "${partes[@]}")
if [ -n "$linha1" ] && [ -n "$linha2" ]; then
  printf '%s\n%s' "$linha1" "$linha2"
else
  printf '%s%s' "$linha1" "$linha2"
fi
