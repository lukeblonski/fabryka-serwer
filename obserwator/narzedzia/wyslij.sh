#!/usr/bin/env bash
# Wysłanie wiadomości do sesji głównej fabryki i czekanie na DOKŁADNIE jej plik wyniku
# (umowa obserwatora, „Rozmowa z sesją główną”, kroki 1–4, bez ręcznego układania czekania).
#
#   wyslij.sh <plik JSON wiadomości>   kopiuje plik do skrzynki pod nowym <id>, uruchamia fabrykę, czeka na wynik
#   wyslij.sh czekaj <id>               tylko czeka na wynik <id> (np. po restarcie sesji obserwatora)
#
# Uruchamiać zawsze narzędziem Monitor: każda linia wyjścia to zdarzenie, a koniec narzędzia budzi sesję.
# Linia statusu: przy każdym nowym kroku claude -p autopilota, który działa w folderze wiadomości, jedna linia
#   <Projekt> <zmiana> · <krok> · krok <n>/<N> · od <GG:MM>   (n/N z pola kroki w stan.json autopilota, czas serwera)
# bez autopilota nic; ostatnia wypisana linia leży w skrzynka/<id>.status, więc ponowne czekanie jej nie powtarza.
# Kody: 0 wynik jest: linie WYNIK, tury=… odmowy=… i „plik wyniku: <ścieżka>” (odpowiedź sesji czytaj z pliku);
#       1/2 start-fabryki.sh odrzucił albo nie ruszył (bez wyniku), zły plik wyniku, złe użycie;
#       4 wyniku jeszcze nie ma po LIMIT_S czekania, a praca trwa — uruchom od razu „wyslij.sh czekaj <id>”;
#       5 wyniku nie ma, a praca nie żyje (proces ze znacznika nie żyje albo to inny proces, albo nie ma znacznika
#         KARENCJA_S po wysłaniu) — praca przerwana (umowa: „kontynuuj” jako nowa rozmowa);
#       6 folder wiadomości nie istnieje (usunięty) — bez „kontynuuj” i bez dalszego czekania.
# Życie pracy i folder sprawdza każdy obrót pętli (co ODSTEP_S), a przed kodem 5 albo 6 jeszcze raz plik wyniku.
# Zmienne WYSLIJ_* podmieniają ścieżki i czasy (testy); reguła sudo przepuszcza tylko stałą ścieżkę start-fabryki.sh.
set -uo pipefail

SKRZYNKA="${WYSLIJ_SKRZYNKA:-/var/lib/fabryka-serwer/skrzynka}"
WYNIKI="${WYSLIJ_WYNIKI:-/var/lib/fabryka-serwer/wyniki}"
START="${WYSLIJ_START:-/usr/local/lib/fabryka-serwer/start-fabryki.sh}"
LAB="${WYSLIJ_LAB:-/home/fabryka/fabryka}"
LIMIT_S="${WYSLIJ_LIMIT_S:-480}"
ODSTEP_S="${WYSLIJ_ODSTEP_S:-10}"
KARENCJA_S="${WYSLIJ_KARENCJA_S:-120}"

czekaj() {
  python3 -I - "$1" "$SKRZYNKA" "$WYNIKI" "$LAB" "$LIMIT_S" "$ODSTEP_S" "$KARENCJA_S" <<'PY'
import datetime, json, os, stat, sys, time

ID, SKRZYNKA, WYNIKI, LAB = sys.argv[1:5]
LIMIT_S, ODSTEP_S, KARENCJA_S = (float(x) for x in sys.argv[5:8])
START_ID = "start-projektu"
WYNIK = os.path.join(WYNIKI, ID + ".json")
ZNACZNIK = os.path.join(WYNIKI, ID + ".start")
STATUS = os.path.join(SKRZYNKA, ID + ".status")
POCZATEK = time.monotonic()


def pisz(tekst):
    print(tekst, flush=True)


def pokaz_wynik():
    """Kod 0 i trzy linie wyniku albo kod 1, gdy pliku wyniku nie da się odczytać."""
    try:
        with open(WYNIK, encoding="utf-8") as plik:
            d = json.load(plik)
        tury = d.get("tury") or []
        odmowy = [t.get("odmowy") for t in tury if t.get("odmowy")]
        linie = [f"WYNIK {d.get('wiadomosc')} kod={d.get('kod')} rozmowa={d.get('rozmowa')} powod={d.get('powod')}",
                 f"tury={len(tury)} odmowy={odmowy}", f"plik wyniku: {WYNIK}"]
    except (OSError, ValueError, AttributeError, TypeError) as blad:
        pisz(f"BŁĄD WYNIKU {ID}: nie mogę odczytać {WYNIK}: {blad}")
        return 1
    for linia in linie:
        pisz(linia)
    return 0


def folder_wiadomosci():
    try:
        with open(os.path.join(SKRZYNKA, ID + ".json"), encoding="utf-8") as plik:
            folder = json.load(plik).get("folder")
    except (OSError, ValueError, AttributeError):
        return None
    return os.path.normpath(folder) if isinstance(folder, str) and folder else None


# --- status kroku autopilota (ten sam odczyt blokad co skrzynka.autopilot_trwa, bez własnej blokady) ---

def blokady_flock():
    try:
        with open("/proc/locks", encoding="ascii", errors="replace") as plik:
            linie = plik.read().splitlines()
    except OSError:
        return set()
    blokady = set()
    for linia in linie:
        pola = linia.split()
        if len(pola) < 6 or "->" in pola or pola[1] != "FLOCK":
            continue
        czesci = pola[5].split(":")
        if len(czesci) != 3:
            continue
        try:
            blokady.add((int(czesci[0], 16), int(czesci[1], 16), int(czesci[2])))
        except ValueError:
            continue
    return blokady


def aktywny_autopilot(folder):
    """Podfolder <folder>/.autopilot-local/<cid>/ (bez dowiązań), którego stan.lock ma blokadę FLOCK; albo None."""
    korzen = os.path.join(folder, ".autopilot-local")
    if os.path.islink(korzen) or not os.path.isdir(korzen):
        return None
    wezly = {}
    for wpis in sorted(os.scandir(korzen), key=lambda w: w.name):
        if not wpis.is_dir(follow_symlinks=False):
            continue
        try:
            info = os.lstat(os.path.join(wpis.path, "stan.lock"))
        except OSError:
            continue
        if stat.S_ISREG(info.st_mode):
            wezly[(os.major(info.st_dev), os.minor(info.st_dev), info.st_ino)] = wpis.path
    if not wezly:
        return None
    blokady = blokady_flock()
    for wezel, sciezka in wezly.items():
        if wezel in blokady:
            return sciezka
    return None


def nazwa_z_prd(folder):
    """Pole project: ze wstępu context/foundation/prd.md folderu albo None."""
    try:
        with open(os.path.join(folder, "context", "foundation", "prd.md"), encoding="utf-8") as plik:
            linie = plik.read(65536).splitlines()
    except (OSError, UnicodeDecodeError):
        return None
    if not linie or linie[0].strip() != "---":
        return None
    for linia in linie[1:]:
        if linia.strip() == "---":
            return None
        if linia.startswith("project:"):
            wartosc = linia[len("project:"):].strip()
            if len(wartosc) >= 2 and wartosc[0] == wartosc[-1] and wartosc[0] in "\"'":
                wartosc = wartosc[1:-1].strip()
            return wartosc if wartosc and wartosc not in ("null", "~") else None
    return None


def linia_statusu(folder):
    """<Projekt> <zmiana> · <krok> · krok <n>/<N> · od <GG:MM>, gdy w folderze działa krok claude -p autopilota z
    listy kroki; inaczej None (także przy każdym błędzie odczytu)."""
    try:
        podfolder = aktywny_autopilot(folder)
        if podfolder is None:
            return None
        with open(os.path.join(podfolder, "stan.json"), encoding="utf-8") as plik:
            stan = json.load(plik)
        krok, kroki = stan.get("krok"), stan.get("kroki")
        if stan.get("pid_kroku") is None or not isinstance(kroki, list) or not isinstance(krok, str) \
                or krok not in kroki:
            return None
        poczatek = stan["procesy"][stan["sesja"]]["poczatek"]
        godzina = datetime.datetime.fromisoformat(poczatek).astimezone().strftime("%H:%M")
        cid = os.path.basename(podfolder)
        if folder == os.path.normpath(LAB):
            projekt, zmiana = "Laboratorium", cid
        else:
            nazwa = os.path.basename(folder)
            projekt = nazwa_z_prd(folder) or nazwa[:1].upper() + nazwa[1:]
            zmiana = "start" if cid == START_ID else cid
        return f"{projekt} {zmiana} · {krok} · krok {kroki.index(krok) + 1}/{len(kroki)} · od {godzina}"
    except Exception:  # noqa: BLE001 — błąd statusu nie przerywa czekania
        return None


def ostatnia_linia():
    try:
        with open(STATUS, encoding="utf-8") as plik:
            return plik.read().strip("\n") or None
    except (OSError, UnicodeDecodeError):
        return None


def zapisz_linie(linia):
    try:
        fd = os.open(STATUS, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o640)
        with os.fdopen(fd, "w", encoding="utf-8") as plik:
            plik.write(linia + "\n")
    except OSError:
        pass


# --- życie pracy ---

def czas_wyslania():
    """Czas z identyfikatora (RRRRMMDD-GGMMSS, czas serwera) w sekundach epoki; bez niego start tego czekania."""
    try:
        return time.mktime(time.strptime(ID[:15], "%Y%m%d-%H%M%S"))
    except (ValueError, OverflowError):
        return time.time() - (time.monotonic() - POCZATEK)


def pid_znacznika():
    try:
        with open(ZNACZNIK, encoding="utf-8") as plik:
            pid = json.load(plik).get("pid")
    except (OSError, ValueError, AttributeError):
        return None
    return pid if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0 else None


def praca_zyje(pid):
    """Proces pid żyje, a jego argumenty kończą się na wykonaj <id> (nie inny proces pod tym numerem)."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as plik:
            argumenty = plik.read().split(b"\0")
    except OSError:
        return False
    if argumenty and argumenty[-1] == b"":
        argumenty.pop()
    return argumenty[-2:] == [b"wykonaj", ID.encode("ascii")]


def koniec_pracy(folder, wyslano):
    """(kod, linia) dla usuniętego folderu (6) albo martwej pracy (5); None, gdy praca może trwać."""
    jest_znacznik = os.path.lexists(ZNACZNIK)
    po_karencji = time.time() - wyslano >= KARENCJA_S
    if folder is not None and not os.path.isdir(folder) and (jest_znacznik or po_karencji):
        return 6, f"USUNIĘTY {ID}: folder {folder} nie istnieje"
    pid = pid_znacznika() if jest_znacznik else None
    if pid is not None:
        if praca_zyje(pid):
            return None
        return 5, f"PRZERWANE {ID}: brak wyniku, a proces {pid} ze znacznika nie żyje albo to inny proces"
    # Bez znacznika (albo z nieczytelnym, bo zapis może trwać) praca może jeszcze startować.
    if po_karencji:
        return 5, f"PRZERWANE {ID}: brak wyniku i znacznika pracy {KARENCJA_S:g} s po wysłaniu"
    return None


def main():
    wyslano = czas_wyslania()
    ostatnia = ostatnia_linia()
    while True:
        if os.path.exists(WYNIK):
            return pokaz_wynik()
        folder = folder_wiadomosci()
        if folder is not None:
            linia = linia_statusu(folder)
            if linia is not None and linia != ostatnia:
                pisz(linia)
                ostatnia = linia
                zapisz_linie(linia)
        koniec = koniec_pracy(folder, wyslano)
        if koniec is not None:
            # Wynik w ostatniej chwili (D-565): zanim narzędzie zgłosi 5 albo 6.
            if os.path.exists(WYNIK):
                return pokaz_wynik()
            pisz(koniec[1])
            return koniec[0]
        if time.monotonic() - POCZATEK >= LIMIT_S:
            pisz(f"TRWA {ID}: uruchom ponownie: wyslij.sh czekaj {ID}")
            return 4
        time.sleep(ODSTEP_S)


sys.exit(main())
PY
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
