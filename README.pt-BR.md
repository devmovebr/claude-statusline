# claude-statusline

Status line de duas linhas para o [Claude Code](https://code.claude.com/docs/en/statusline). Em
cima, modelo, pasta do projeto, branch e quantidade de subagentes vivos. Embaixo, contexto
consumido, limite de 5 horas e limite semanal, cada um com barra, quanto falta para reiniciar e a
hora em que isso acontece.

```
🧠 Opus 5 | 📁 valoer-infra | 🌿 main | 🤖 2
📊 ctx ██▏░░░░░ 27% | ⏳ 5h ███▉░░░░ 49% (2h 22min) (Dom 17:54) | 📅 sem ███▎░░░░ 42% (3d 23h) (Qui 15:12)
```

Roda em macOS, Linux, WSL e Windows. Duas implementações com a mesma saída: `statusline.sh` para
bash, `statusline.ps1` para PowerShell.

[Read in English](README.md)

## De onde sai cada campo

| Campo | Origem no payload |
| --- | --- |
| 🧠 modelo | `model.display_name` |
| 📁 pasta | `workspace.project_dir`, caindo para `cwd` |
| 🌿 branch | `worktree.branch`, caindo para `git branch --show-current` |
| 🤖 subagentes | marcadores escritos pelos hooks `SubagentStart` e `SubagentStop` |
| 📊 ctx | `context_window.remaining_percentage`, invertido para mostrar o consumo |
| ⏳ 5h | `rate_limits.five_hour.used_percentage` e `.resets_at` |
| 📅 sem | `rate_limits.seven_day.used_percentage` e `.resets_at` |

Campo sem dado sai da linha. Fora de um repositório git o branch some e o resto fica no lugar.

## Instalar no macOS, Linux e WSL

```bash
curl -fsSL https://raw.githubusercontent.com/devmovebr/claude-statusline/main/install.sh | bash
```

Precisa de `jq` e `bash`. Roda no bash 3.2 que vem no macOS.

O instalador copia o script para `~/.claude/statusline-command.sh` e troca o campo `statusLine` do
`~/.claude/settings.json`. O resto do settings fica intacto, e uma cópia do arquivo anterior é
guardada com carimbo de data.

## Instalar no Windows

```powershell
irm https://raw.githubusercontent.com/devmovebr/claude-statusline/main/install.ps1 | iex
```

Não precisa de nada além do Windows PowerShell 5.1, que é o `powershell` já presente na máquina. O
`ConvertFrom-Json` faz o papel do `jq`, então não há dependência para instalar antes.

O instalador copia o script para `%USERPROFILE%\.claude\statusline-command.ps1` e aponta o
`statusLine` para ele, guardando cópia com carimbo de data do script e do settings anteriores.

Dentro do WSL, use o `install.sh`: WSL é Linux, e o `~` de lá é a home do Linux, não a do Windows.

## Instalar de um clone

```bash
git clone https://github.com/devmovebr/claude-statusline.git
cd claude-statusline
bash install.sh
```

```powershell
git clone https://github.com/devmovebr/claude-statusline.git
cd claude-statusline
powershell -ExecutionPolicy Bypass -File install.ps1
```

Os dois instaladores usam o script que estiver ao lado deles e baixam quando não tem. Para instalar
de um fork, use `CLAUDE_STATUSLINE_REPO` e `CLAUDE_STATUSLINE_REF`.

## Atualizar

Rode o mesmo comando de novo.

## Configurar na mão

Os instaladores só escrevem esses dois arquivos. Para dispensar eles, copie o script para
`~/.claude/` e adicione o campo `statusLine`.

No macOS, Linux e WSL:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline-command.sh\""
  }
}
```

No Windows:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/VOCE/.claude/statusline-command.ps1\""
  }
}
```

A barra normal no caminho do Windows é obrigatória. O Claude Code roda a status line pelo Git Bash
quando ele está instalado, e o Git Bash come a contrabarra como escape, então um caminho
`C:\Users\...` chega sem os separadores e o comando falha sem mensagem na tela.

O redesenho acontece nos eventos do Claude Code: mensagem nova do assistente, `/compact` que
terminou, troca de modo de permissão. Para a contagem andar sozinha, coloque `"refreshInterval":
30` ao lado de `"command"`.

## Desinstalar

```bash
jq 'del(.statusLine)' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
rm ~/.claude/statusline-command.sh
```

```powershell
$s = "$HOME\.claude\settings.json"
$c = Get-Content -Raw $s | ConvertFrom-Json
$c.PSObject.Properties.Remove('statusLine')
[IO.File]::WriteAllText($s, ($c | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
Remove-Item "$HOME\.claude\statusline-command.ps1"
```

## Testes

```bash
bash test.sh          # colorido, do jeito que aparece no terminal
bash test.sh --plain  # sem escapes, para jogar em arquivo
```

Cada caso monta um payload igual ao que o Claude Code manda no stdin. Quando existe um PowerShell
na máquina, o mesmo payload passa pelo `statusline.ps1` e as duas saídas precisam bater byte a
byte, que é o que garante que a versão do Windows não desandou.

Rodada capturada no macOS 26.6 com bash 3.2.57 e PowerShell 7.5.4:

```
statusline  bash 3.2.57  |  pwsh 7.5.4

 1. payload completo
    🧠 Opus 5 | 📁 valoer-infra | 🌿 main
    📊 ctx ██▏░░░░░ 27% | ⏳ 5h ███▉░░░░ 49% (2h 22min) (Dom 20:40) | 📅 sem ███▎░░░░ 42% (3d 23h) (Qui 17:58)
    ✓ ps1 idêntico

 2. fora de repositório git (sem branch)
    🧠 Sonnet 5 | 📁 tmp
    📊 ctx ▏░░░░░░░ 2% | ⏳ 5h ▏░░░░░░░ 3% (2h 22min) (Dom 20:40) | 📅 sem ▉░░░░░░░ 11% (3d 23h) (Qui 17:58)
    ✓ ps1 idêntico

 3. sem rate limits no payload
    🧠 Haiku 4.5 | 📁 api | 🌿 feat/cobranca
    📊 ctx ████▊░░░ 60%
    ✓ ps1 idêntico

 4. só rate limits, sem contexto
    🧠 Opus 5 | 📁 api
    ⏳ 5h ███████░ 88% (2h 22min) (Dom 20:40) | 📅 sem ███████▊ 97% (3d 23h) (Qui 17:58)
    ✓ ps1 idêntico

 5. extremos: barra vazia e barra cheia
    🧠 Opus 5 | 📁 api
    📊 ctx ░░░░░░░░ 0% | ⏳ 5h ░░░░░░░░ 0% (2h 22min) (Dom 20:40) | 📅 sem ████████ 100% (3d 23h) (Qui 17:58)
    ✓ ps1 idêntico

 6. percentual fracionário (trunca, não arredonda)
    🧠 Opus 5 | 📁 api
    📊 ctx █████░░░ 64% | ⏳ 5h ▉░░░░░░░ 12% (2h 22min) (Dom 20:40) | 📅 sem █████▎░░ 66% (3d 23h) (Qui 17:58)
    ✓ ps1 idêntico

 7. reset já vencido (não vai a negativo)
    🧠 Opus 5 | 📁 api
    ⏳ 5h ▍░░░░░░░ 5% (0min) (Dom 18:08) | 📅 sem ▋░░░░░░░ 9% (0min) (Dom 18:08)
    ✓ ps1 idêntico

 8. percentual acima de 100 (limite de gasto estourado)
    🧠 Opus 5 | 📁 api
    ⏳ 5h ████████ 100% (2h 22min) (Dom 20:40) | 📅 sem ████████ 100% (3d 23h) (Qui 17:58)
    ✓ ps1 idêntico

 9. session_id sujo cai no diretório default
    🧠 Opus 5 | 📁 api
    📊 ctx ████░░░░ 50%
    ✓ ps1 idêntico

10. json inválido
    (linha vazia)
    ✓ ps1 idêntico

11. payload vazio
    (linha vazia)
    ✓ ps1 idêntico

12. três subagentes vivos
    🧠 Opus 5 | 📁 api | 🌿 main | 🤖 3
    📊 ctx ██▏░░░░░ 27%
    ✓ ps1 idêntico

13. resolução da barra, um passo de oitavo por linha
      0%  5h ░░░░░░░░ 0%
      1%  5h ░░░░░░░░ 1%
      2%  5h ▏░░░░░░░ 2%
      3%  5h ▏░░░░░░░ 3%
      5%  5h ▍░░░░░░░ 5%
      6%  5h ▍░░░░░░░ 6%
      8%  5h ▋░░░░░░░ 8%
     12%  5h ▉░░░░░░░ 12%
     25%  5h ██░░░░░░ 25%
     27%  5h ██▏░░░░░ 27%
     33%  5h ██▋░░░░░ 33%
     50%  5h ████░░░░ 50%
     66%  5h █████▎░░ 66%
     75%  5h ██████░░ 75%
     88%  5h ███████░ 88%
     99%  5h ███████▉ 99%
    100%  5h ████████ 100%

13 casos, bash e PowerShell com a mesma saída.
```

## As barras

As três mostram porcentagem usada e enchem conforme se consome. O Claude Code entrega o contexto
como percentual restante, e o script inverte para as três lerem do mesmo jeito.

A borda usa os blocos parciais de oitavo (`▏▎▍▌▋▊▉`), então a resolução é de 1/64 e não de uma
célula inteira. O trecho vazio fica hachurado e vira sólido: em oito colunas, cada 1,5% move alguma
coisa.

## Os limites

O payload traz `rate_limits.five_hour.resets_at` e o par semanal como epoch em segundos. Abaixo de
24 horas o formato é `2h 22min`, acima vira `3d 23h`.

O dia da semana sai de `date +%w` mapeado para um array em português, porque `%a` depende do locale.
O teste `date -r 0 +%s` distingue BSD de GNU: `-r` significa epoch num e arquivo de referência no
outro. A versão em PowerShell usa `DateTimeOffset` e dispensa os dois testes.

## Subagentes

O contador lê marcadores em `$TMPDIR/claude-subagentes/<sessão>` no Unix e em
`%TEMP%\claude-subagentes\<sessão>` no Windows. Sem os hooks que escrevem esses marcadores o campo
some da linha, e nada mais muda. Marcador com mais de seis horas é resto de crash e é apagado na
próxima leitura.

Hooks para macOS, Linux e WSL, no `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '[.session_id, .agent_id] | @tsv' | { IFS=$(printf '\\t') read -r s a; d=\"${TMPDIR:-/tmp}/claude-subagentes/$s\"; mkdir -p \"$d\"; : > \"$d/m.$a\"; }"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '[.session_id, .agent_id] | @tsv' | { IFS=$(printf '\\t') read -r s a; rm -f \"${TMPDIR:-/tmp}/claude-subagentes/$s/m.$a\"; }"
          }
        ]
      }
    ]
  }
}
```

No Windows, salve isto como `%USERPROFILE%\.claude\subagente.ps1`:

```powershell
param([ValidateSet('start','stop')][string]$Acao)
$j = [Console]::In.ReadToEnd() | ConvertFrom-Json
$dir = Join-Path $env:TEMP (Join-Path 'claude-subagentes' $j.session_id)
$marca = Join-Path $dir ('m.' + $j.agent_id)
if ($Acao -eq 'start') {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  New-Item -ItemType File -Path $marca -Force | Out-Null
} else {
  Remove-Item -LiteralPath $marca -Force -ErrorAction SilentlyContinue
}
```

e aponte os dois hooks para ele:

```json
{
  "hooks": {
    "SubagentStart": [
      { "hooks": [ { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/VOCE/.claude/subagente.ps1\" start" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/VOCE/.claude/subagente.ps1\" stop" } ] }
    ]
  }
}
```

## Quando não aparece nada

Rode o script na mão com um payload e veja o que sai:

```bash
echo '{"model":{"display_name":"Opus 5"},"cwd":"'"$PWD"'","context_window":{"remaining_percentage":73}}' \
  | bash ~/.claude/statusline-command.sh
```

```powershell
'{"model":{"display_name":"Opus 5"},"context_window":{"remaining_percentage":73}}' |
  powershell -NoProfile -File "$HOME\.claude\statusline-command.ps1"
```

Se isso imprime a linha e o Claude Code não, as causas de sempre são contrabarra no caminho do
Windows, `jq` fora do `PATH` que o Claude Code entrega ao script, ou um `settings.json` reescrito
por outra ferramenta. O `claude --debug` mostra o código de saída do comando da status line.

Quadradinho no lugar da barra é fonte do terminal sem os blocos de oitavo. Qualquer fonte com
cobertura Powerline ou Nerd Font tem.

## assets/

PNGs coloridos dos ícones, em 64px. Não entram na status line: o Claude Code desenha essa linha
como texto e mede a largura visual dela, e suporte a protocolo gráfico de terminal ainda é pedido
em aberto ([#2266](https://github.com/anthropics/claude-code/issues/2266),
[#29254](https://github.com/anthropics/claude-code/issues/29254)). O Warp renderiza imagem inline,
o limite está do lado do Claude Code.

O caminho que funcionaria é virar fonte de ícones em codepoints da área de uso privado, instalada
no terminal. Aí o glifo é monocromático e recebe a cor ANSI da coluna.
