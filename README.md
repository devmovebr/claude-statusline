# claude-statusline

Two-line status line for [Claude Code](https://code.claude.com/docs/en/statusline). The first
line has the model, the project folder, the git branch and how many subagents are running. The
second has context window usage, the 5-hour rate limit and the weekly rate limit, each with a
progress bar, how long until the window resets and the clock time it resets at.

```
🧠 Opus 5 | 📁 valoer-infra | 🌿 main | 🤖 2
📊 ctx ██▏░░░░░ 27% | ⏳ 5h ███▉░░░░ 49% (2h 22min) (Dom 17:54) | 📅 sem ███▎░░░░ 42% (3d 23h) (Qui 15:12)
```

Works on macOS, Linux, WSL and Windows. Two implementations with the same output: `statusline.sh`
for bash, `statusline.ps1` for PowerShell.

[Leia em português](README.pt-BR.md)

## What each field reads

| Field | Source in the payload |
| --- | --- |
| 🧠 model | `model.display_name` |
| 📁 folder | `workspace.project_dir`, falling back to `cwd` |
| 🌿 branch | `worktree.branch`, falling back to `git branch --show-current` |
| 🤖 subagents | marker files written by the `SubagentStart` and `SubagentStop` hooks |
| 📊 ctx | `context_window.remaining_percentage`, inverted to show usage |
| ⏳ 5h | `rate_limits.five_hour.used_percentage` and `.resets_at` |
| 📅 sem | `rate_limits.seven_day.used_percentage` and `.resets_at` |

A field with no data drops out of the line. Outside a git repository the branch disappears and
nothing else moves.

Labels and weekday names are in Portuguese: `sem` is the weekly limit, and the days read `Dom Seg
Ter Qua Qui Sex Sáb`. To translate them, edit the `DIAS` array and the `barra` labels near the
bottom of the script.

## Install on macOS, Linux and WSL

```bash
curl -fsSL https://raw.githubusercontent.com/devmovebr/claude-statusline/main/install.sh | bash
```

Needs `jq` and `bash`. Runs on the bash 3.2 that ships with macOS.

The installer copies the script to `~/.claude/statusline-command.sh` and replaces the `statusLine`
field in `~/.claude/settings.json`. Everything else in that file stays as it was, and a timestamped
copy of the previous version is kept.

## Install on Windows

```powershell
irm https://raw.githubusercontent.com/devmovebr/claude-statusline/main/install.ps1 | iex
```

Needs nothing beyond Windows PowerShell 5.1, which is the `powershell` already on the machine.
`ConvertFrom-Json` replaces `jq`, so there is nothing to install first.

The installer copies the script to `%USERPROFILE%\.claude\statusline-command.ps1` and points
`statusLine` at it, keeping a timestamped copy of both the old script and the old settings.

Inside WSL, use `install.sh` instead: WSL is Linux, and `~` there is the Linux home, not the
Windows one.

## Install from a clone

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

Both installers use the script sitting next to them when there is one, and download it otherwise.
To install from a fork, set `CLAUDE_STATUSLINE_REPO` and `CLAUDE_STATUSLINE_REF`.

## Update

Run the same command again.

## Configure it by hand

The installers only write these two files. To skip them, copy the script to `~/.claude/` yourself
and add the `statusLine` field.

On macOS, Linux and WSL:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline-command.sh\""
  }
}
```

On Windows:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/YOU/.claude/statusline-command.ps1\""
  }
}
```

Forward slashes in the Windows path are required. Claude Code routes the status line through Git
Bash when Git Bash is installed, and Git Bash eats an unquoted backslash as an escape character, so
a `C:\Users\...` path arrives with its separators gone and the command fails with no error on
screen.

The countdown redraws on Claude Code events: a new assistant message, a finished `/compact`, a
permission mode change. To make it tick on its own, add `"refreshInterval": 30` next to
`"command"`.

## Uninstall

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

## Tests

```bash
bash test.sh          # colored, as it appears in the terminal
bash test.sh --plain  # no escape codes, for piping into a file
```

Each case feeds `statusline.sh` a payload shaped like the one Claude Code sends on stdin. When a
PowerShell is on the machine, the same payload goes through `statusline.ps1` and the two outputs
have to match byte for byte, which is what keeps the Windows version from drifting.

Run captured on macOS 26.6 with bash 3.2.57 and PowerShell 7.5.4:

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

## The bars

All three show the percentage used and fill up as it is consumed. Claude Code reports the context
window as a remaining percentage, and the script inverts it so the three read the same way.

The edge uses the eighth-block characters (`▏▎▍▌▋▊▉`), so the resolution is 1/64 rather than a
whole cell. The empty stretch is hatched and turns solid as it fills: across eight columns, every
1.5% moves something.

## The limits

The payload carries `rate_limits.five_hour.resets_at` and the weekly pair as epoch seconds. Under
24 hours the format is `2h 22min`, above it becomes `3d 23h`.

The weekday comes from `date +%w` mapped onto an array, because `%a` depends on the locale. The
`date -r 0 +%s` test tells BSD from GNU: `-r` means epoch on one and reference file on the other.
The PowerShell version uses `DateTimeOffset` and needs neither test.

## Subagents

The counter reads marker files in `$TMPDIR/claude-subagentes/<session>` on Unix and
`%TEMP%\claude-subagentes\<session>` on Windows. Without the hooks that write them, the field drops
off the line and nothing else changes. A marker older than six hours is crash residue and gets
deleted on the next read.

Hooks for macOS, Linux and WSL, in `~/.claude/settings.json`:

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

On Windows, save this as `%USERPROFILE%\.claude\subagente.ps1`:

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

and point both hooks at it:

```json
{
  "hooks": {
    "SubagentStart": [
      { "hooks": [ { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/YOU/.claude/subagente.ps1\" start" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/YOU/.claude/subagente.ps1\" stop" } ] }
    ]
  }
}
```

## When nothing shows up

Run the script by hand with a payload and see what comes out:

```bash
echo '{"model":{"display_name":"Opus 5"},"cwd":"'"$PWD"'","context_window":{"remaining_percentage":73}}' \
  | bash ~/.claude/statusline-command.sh
```

```powershell
'{"model":{"display_name":"Opus 5"},"context_window":{"remaining_percentage":73}}' |
  powershell -NoProfile -File "$HOME\.claude\statusline-command.ps1"
```

If that prints the line and Claude Code does not, the usual causes are a backslash in the Windows
path, `jq` missing from the `PATH` that Claude Code hands the script, or a `settings.json` that
another tool rewrote. `claude --debug` shows the exit code of the status line command.

Boxes instead of bars mean the terminal font has no eighth-block glyphs. Any font with Powerline
or Nerd Font coverage has them.

## assets/

Colored 64px PNGs of the icons. They do not go into the status line: Claude Code draws that line as
text and measures its visual width, and terminal graphics protocol support is still an open request
([#2266](https://github.com/anthropics/claude-code/issues/2266),
[#29254](https://github.com/anthropics/claude-code/issues/29254)). Warp renders inline images, the
limit is on the Claude Code side.

What would work is turning them into an icon font at private use area codepoints, installed in the
terminal. Then the glyph is monochrome and takes the ANSI color of its column.
