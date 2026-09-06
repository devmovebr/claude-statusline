#!/usr/bin/env bash
# Instala a status line do Claude Code.
#
#   curl -fsSL https://raw.githubusercontent.com/devmovebr/claude-statusline/main/install.sh | bash
#
# Ou, de um clone:  bash install.sh
#
# Copia o script para ~/.claude/statusline-command.sh e aponta o statusLine do
# settings.json para ele. Guarda cópia do que havia antes nos dois casos.
set -euo pipefail

REPO=${CLAUDE_STATUSLINE_REPO:-devmovebr/claude-statusline}
REF=${CLAUDE_STATUSLINE_REF:-main}

destino="$HOME/.claude/statusline-command.sh"
settings="$HOME/.claude/settings.json"
comando='bash "$HOME/.claude/statusline-command.sh"'
carimbo=$(date '+%Y%m%d-%H%M%S')

erro() { printf '%s\n' "erro: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || erro "jq não encontrado. Instale com 'brew install jq' (macOS) ou 'apt install jq' (Debian/Ubuntu)."

# Rodando de um clone, o statusline.sh está ao lado. Rodando por curl | bash,
# não está: aí baixa do repositório.
aqui=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)
origem="${aqui:-.}/statusline.sh"
temporario=""
if [ ! -f "$origem" ]; then
  command -v curl >/dev/null 2>&1 || erro "curl não encontrado."
  temporario=$(mktemp)
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/statusline.sh" -o "$temporario" \
    || erro "não consegui baixar statusline.sh de $REPO@$REF."
  origem="$temporario"
fi

bash -n "$origem" || erro "statusline.sh não passou na checagem de sintaxe."

mkdir -p "$HOME/.claude"

if [ -f "$destino" ] && ! cmp -s "$origem" "$destino"; then
  cp "$destino" "$destino.bak-$carimbo"
  printf 'status line anterior guardada em %s\n' "$destino.bak-$carimbo"
fi
cp "$origem" "$destino"
chmod +x "$destino"
[ -n "$temporario" ] && rm -f "$temporario"

# O settings.json guarda hooks, permissões e modelo. Reescrever o arquivo
# inteiro perderia tudo isso, então só o campo statusLine é trocado.
novo=$(mktemp)
if [ -s "$settings" ]; then
  jq empty "$settings" 2>/dev/null || erro "$settings não é JSON válido. Corrija antes de instalar."
  cp "$settings" "$settings.bak-$carimbo"
  jq --arg cmd "$comando" '.statusLine = {type: "command", command: $cmd}' "$settings" > "$novo"
else
  jq -n --arg cmd "$comando" '{statusLine: {type: "command", command: $cmd}}' > "$novo"
fi
mv "$novo" "$settings"

printf '\ninstalado. Prévia:\n\n'
printf '%s' '{"model":{"display_name":"Opus 5"},"cwd":"'"$PWD"'","workspace":{"project_dir":"'"$PWD"'"},"context_window":{"remaining_percentage":73},"rate_limits":{"five_hour":{"used_percentage":49,"resets_at":'$(( $(date +%s) + 8520 ))'},"seven_day":{"used_percentage":42,"resets_at":'$(( $(date +%s) + 344400 ))'}}}' \
  | bash "$destino"
printf '\n\nAbra uma sessão nova do Claude Code para valer.\n'
