# claude-statusline

Status line de duas linhas para o Claude Code.

```
🧠 Opus 5 | 📁 valoer-infra | 🌿 main | 🤖 2
📊 ctx ██▏░░░░░ 27% | ⏳ 5h ███▉░░░░ 49% (2h 22min) (Dom 17:54) | 📅 sem ███▎░░░░ 42% (3d 23h) (Qui 15:12)
```

Em cima, modelo, pasta do projeto, branch e quantidade de subagentes vivos.
Embaixo, contexto consumido, limite de 5 horas e limite semanal. Nos dois
limites, quanto falta para reiniciar e a hora em que isso acontece.

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/devmovebr/claude-statusline/main/install.sh | bash
```

Precisa de `jq` e `bash`. Roda no bash 3.2 que vem no macOS.

O instalador copia o script para `~/.claude/statusline-command.sh` e troca o
campo `statusLine` do `~/.claude/settings.json`. O resto do settings fica
intacto, e uma cópia do arquivo anterior é guardada com carimbo de data.

Para atualizar, rode o mesmo comando.

## As barras

As três mostram porcentagem usada e enchem conforme se consome. O Claude Code
entrega o contexto como percentual restante, e o script inverte para as três
lerem do mesmo jeito.

A borda usa os blocos parciais de oitavo (`▏▎▍▌▋▊▉`), então a resolução é de
1/64 e não de uma célula inteira. O trecho vazio fica hachurado e vira sólido:
em oito colunas, cada 1,5% move alguma coisa.

## Os limites

O payload traz `rate_limits.five_hour.resets_at` e o par semanal como epoch em
segundos. Abaixo de 24 horas o formato é `2h 22min`, acima vira `3d 23h`.

O dia da semana sai de `date +%w` mapeado para um array em português, porque
`%a` depende do locale. O teste `date -r 0 +%s` distingue BSD de GNU: `-r`
significa epoch num e arquivo de referência no outro.

## Subagentes

O contador lê marcadores em `$TMPDIR/claude-subagentes/<sessão>`, criados e
apagados por hooks `SubagentStart` e `SubagentStop`. Sem esses hooks
configurados o campo some da linha, e nada mais muda. Marcador com mais de seis
horas é resto de crash e é apagado na próxima leitura.

## assets/

PNGs coloridos dos ícones, em 64px. Não entram na status line: o Claude Code
desenha essa linha como texto e mede a largura visual dela, e suporte a
protocolo gráfico de terminal ainda é pedido em aberto
([#2266](https://github.com/anthropics/claude-code/issues/2266),
[#29254](https://github.com/anthropics/claude-code/issues/29254)). O Warp
renderiza imagem inline, o limite está do lado do Claude Code.

O caminho que funcionaria é virar fonte de ícones em codepoints da área de uso
privado, instalada no terminal. Aí o glifo é monocromático e recebe a cor ANSI
da coluna.
