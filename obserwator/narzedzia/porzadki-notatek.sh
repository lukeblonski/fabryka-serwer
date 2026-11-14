#!/usr/bin/env bash
# Sprawdzenie notatek Maestro (umowa, „Pamięć”): wypisuje każdy plik notatek, także w podfolderze, większy niż
# 20 KB (więcej niż 20 480 bajtów), żeby sesja Maestro uporządkowała go skillem porzadki-notatek.
#
#   porzadki-notatek.sh                sprawdza zawsze (hak SessionStart: start, wznowienie, kompaktowanie sesji)
#   porzadki-notatek.sh --co-miesiac   sprawdza raz na miesiąc kalendarzowy według znacznika (hak UserPromptSubmit)
#
# Bez pliku ponad 20 KB nic nie wypisuje. Kod 0 albo 1, nigdy 2: kod 2 haka UserPromptSubmit zablokowałby wiadomość
# człowieka. Brak folderu notatek albo inny błąd: komunikat na stderr, kod 1 i znacznik bez zmian.
# Zmienne PORZADKI_* podmieniają ścieżki (testy).
set -euo pipefail

# Każdy kod różny od 0 (także 2 z polecenia, które zawiodło przy set -e) kończy narzędzie kodem 1.
trap 'kod=$?; [ "$kod" -eq 0 ] || exit 1' EXIT

NOTATKI="${PORZADKI_NOTATKI:-/home/obserwator/obserwator/notatki}"
ZNACZNIK="${PORZADKI_ZNACZNIK:-/home/obserwator/obserwator/.porzadki-notatek-miesiac}"

blad() {
  printf 'porzadki-notatek: %s\n' "$*" >&2
  exit 1
}

CO_MIESIAC=0
if [ "$#" -eq 1 ] && [ "$1" = "--co-miesiac" ]; then
  CO_MIESIAC=1
elif [ "$#" -ne 0 ]; then
  blad "nieznane użycie: $*; bez argumentu albo --co-miesiac"
fi

MIESIAC=$(date +%Y-%m)
if [ "$CO_MIESIAC" -eq 1 ] && [ -f "$ZNACZNIK" ] && [ "$(head -n 1 "$ZNACZNIK")" = "$MIESIAC" ]; then
  exit 0
fi

[ -d "$NOTATKI" ] || blad "brak folderu notatek $NOTATKI"

# -size +20k liczy rozmiar w 1 KiB zaokrąglonych w górę: trafia dokładnie pliki większe niż 20 480 bajtów.
# Wpisy rozdziela NUL, którego nie ma w nazwie pliku, a rozmiar idzie do arytmetyki tylko jako same cyfry: nazwa pliku
# ze znakiem nowej linii i $(...) nie wykona polecenia (CWE-78).
PLIK_LISTY=$(mktemp)
trap 'kod=$?; rm -f "$PLIK_LISTY"; [ "$kod" -eq 0 ] || exit 1' EXIT
find "$NOTATKI" -type f -size +20k -printf '%s\t%p\0' | sort -z -t "$(printf '\t')" -k 2 > "$PLIK_LISTY"

ZGLOSZONE=0
while IFS= read -r -d '' wpis; do
  bajty="${wpis%%$'\t'*}"
  sciezka="${wpis#*$'\t'}"
  [[ "$bajty" =~ ^[0-9]+$ ]] || continue
  printf '%s: %s KB\n' "$sciezka" "$(( (bajty + 1023) / 1024 ))"
  ZGLOSZONE=1
done < "$PLIK_LISTY"
if [ "$ZGLOSZONE" -eq 1 ]; then
  echo "Pliki notatek wyżej mają ponad 20 KB: Maestro porządkuje je skillem porzadki-notatek bez pytania" \
    "i daje człowiekowi jedno zdanie po fakcie."
fi

if [ "$CO_MIESIAC" -eq 1 ]; then
  printf '%s\n' "$MIESIAC" > "$ZNACZNIK"
fi
