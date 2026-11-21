#!/usr/bin/env bash
set -euo pipefail

# Proces w sesji tmux usługi obserwator.service: Claude Code z Remote Control
# (sesja "obserwator") w folderze obserwatora, z kontynuacją ostatniej rozmowy, gdy umowa się nie zmieniła.
# Umowę Maestro sesja dostaje z pliku roota UMOWA (opcja --append-system-prompt-file), którego konto obserwator
# nie zmieni; bez tego pliku skrypt kończy się kodem 1 i Maestro nie startuje bez umowy.

export HOME=/home/obserwator
export PATH="/home/obserwator/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

FOLDER=/home/obserwator/obserwator
CLAUDE=/home/obserwator/.local/bin/claude
UMOWA=/usr/local/lib/fabryka-serwer/obserwator/CLAUDE.md

if [ ! -f "$UMOWA" ]; then
  echo "start-obserwatora.sh: brak umowy Maestro $UMOWA; uruchom instalator ponownie. Maestro nie startuje bez umowy." >&2
  exit 1
fi

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

# Claude Code zapisuje prompt rozmowy, razem z umową z --append-system-prompt-file, przy jej pierwszym zapytaniu,
# a wznowienie wysyła ten zapis także wtedy, gdy kolejny start podaje inną umowę (--system-prompt-snapshot,
# domyślnie on). Gdy suma umowy różni się od sumy z ZNACZNIK (umowa, z którą zaczęła się ostatnia rozmowa), albo
# znacznika nie ma, sesja zaczyna nową rozmowę; pamięć Maestro jest w notatkach.
ZNACZNIK="$HOME/.local/state/obserwator/umowa.sha256"
SUMA_UMOWY=$(sha256sum < "$UMOWA" | cut -d ' ' -f 1)
if [ "$MA_ROZMOWE" -eq 1 ] && [ "$(cat -- "$ZNACZNIK" 2> /dev/null || true)" != "$SUMA_UMOWY" ]; then
  MA_ROZMOWE=0
fi
mkdir -p -- "$(dirname -- "$ZNACZNIK")"
printf '%s\n' "$SUMA_UMOWY" > "$ZNACZNIK"

# Bez awaryjnego || między wariantami: zwykłe zakończenie z błędem po długiej
# rozmowie nie może zacząć nowej rozmowy.
if [ "$MA_ROZMOWE" -eq 1 ]; then
  exec "$CLAUDE" --continue --remote-control obserwator --append-system-prompt-file "$UMOWA"
else
  exec "$CLAUDE" --remote-control obserwator --append-system-prompt-file "$UMOWA"
fi
