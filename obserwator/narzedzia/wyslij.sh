#!/usr/bin/env bash
# Wysłanie wiadomości do sesji głównej fabryki i czekanie na DOKŁADNIE jej plik wyniku
# (umowa obserwatora, „Rozmowa z sesją główną”, kroki 1–4, bez ręcznego układania czekania).
#
#   wyslij.sh <plik JSON wiadomości>   kopiuje plik do skrzynki pod nowym <id>, uruchamia fabrykę, czeka na wynik
#   wyslij.sh czekaj <id>               tylko czeka na wynik <id> (np. po restarcie sesji obserwatora)
#
# Uruchamiać zawsze w tle (Bash run_in_background, timeout 7200000). Koniec polecenia budzi sesję.
# Kody: 0 wynik jest (wypisany); 1/2 start-fabryki.sh odrzucił albo nie ruszył (bez wyniku);
#       4 wyniku jeszcze nie ma po ~115 min, a proces żyje — uruchom ponownie „wyslij.sh czekaj <id>”;
#       5 wyniku nie ma, a proces nie żyje — praca przerwana (umowa: „kontynuuj” jako nowa rozmowa).
set -uo pipefail

SKRZYNKA=/var/lib/fabryka-serwer/skrzynka
WYNIKI=/var/lib/fabryka-serwer/wyniki
START=/usr/local/lib/fabryka-serwer/start-fabryki.sh
LIMIT_S=$((115 * 60))
ODSTEP_S=10

pokaz_wynik() {
  python3 - "$WYNIKI/$1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"WYNIK {d.get('wiadomosc')} kod={d.get('kod')} rozmowa={d.get('rozmowa')} powod={d.get('powod')}")
tury = d.get("tury") or []
odmowy = [t.get("odmowy") for t in tury if t.get("odmowy")]
print(f"tury={len(tury)} odmowy={odmowy}")
if tury:
    print("--- ostatnia odpowiedź sesji ---")
    print(tury[-1].get("tekst") or "")
PY
}

czekaj() {
  local id="$1" start_s=$SECONDS pid
  while [ ! -e "$WYNIKI/$id.json" ]; do
    if [ $((SECONDS - start_s)) -ge "$LIMIT_S" ]; then
      pid=$(grep -o '"pid": *[0-9]*' "$WYNIKI/$id.start" 2>/dev/null | grep -o '[0-9]*$')
      if [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1; then
        echo "TRWA $id (pid $pid): uruchom ponownie: wyslij.sh czekaj $id"; return 4
      fi
      echo "PRZERWANE $id: brak wyniku i proces nie żyje"; return 5
    fi
    sleep "$ODSTEP_S"
  done
  pokaz_wynik "$id"
  return 0
}

if [ "${1:-}" = "czekaj" ]; then
  [[ "${2:-}" =~ ^[0-9]{8}-[0-9]{6}-[a-z0-9]{4}$ ]] || { echo "użycie: wyslij.sh czekaj <id>" >&2; exit 2; }
  czekaj "$2"; exit $?
fi

plik="${1:-}"
[ -f "$plik" ] || { echo "użycie: wyslij.sh <plik JSON wiadomości> | wyslij.sh czekaj <id>" >&2; exit 2; }
id="$(date +%Y%m%d-%H%M%S)-$(tr -dc a-z0-9 < /dev/urandom | head -c4)"
cp -- "$plik" "$SKRZYNKA/$id.json" || { echo "nie mogę zapisać $SKRZYNKA/$id.json" >&2; exit 1; }
chmod 640 "$SKRZYNKA/$id.json"
echo "WYSŁANO $id"
sudo -n -u fabryka "$START" "$id"; kod=$?
if [ "$kod" -ne 0 ]; then
  echo "ODRZUCONE $id: start-fabryki.sh kod $kod (powód wyżej); pliku wyniku nie będzie"
  exit "$kod"
fi
czekaj "$id"; exit $?
