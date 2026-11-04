#!/usr/bin/env bash
set -euo pipefail

# Proces w sesji tmux usługi obserwator.service: Claude Code z Remote Control
# (sesja "obserwator") w folderze obserwatora, z kontynuacją ostatniej rozmowy.

export HOME=/home/obserwator
export PATH="/home/obserwator/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

FOLDER=/home/obserwator/obserwator
CLAUDE=/home/obserwator/.local/bin/claude

cd "$FOLDER"

# Claude Code trzyma zapisy rozmów projektu w ~/.claude/projects/<ścieżka folderu,
# w której każdy znak poza literą i cyfrą zastąpiono "-">/<sesja>.jsonl.
PROJEKT="$HOME/.claude/projects/$(printf '%s' "$FOLDER" | sed 's/[^A-Za-z0-9]/-/g')"

MA_ROZMOWE=0
for plik in "$PROJEKT"/*.jsonl; do
  if [ -e "$plik" ]; then
    MA_ROZMOWE=1
  fi
  break
done

# Bez awaryjnego || między wariantami: zwykłe zakończenie z błędem po długiej
# rozmowie nie może zacząć nowej rozmowy.
if [ "$MA_ROZMOWE" -eq 1 ]; then
  exec "$CLAUDE" --continue --remote-control obserwator
else
  exec "$CLAUDE" --remote-control obserwator
fi
