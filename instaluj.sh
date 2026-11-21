#!/usr/bin/env bash
set -euo pipefail

# Instalator fabryki i obserwatora na czysty serwer Ubuntu (Hostinger KVM 2).
# Uruchamiany jako root poleceniem z README.md: pobranie z tagu i sprawdzenie sumy SHA-256.
# Dziesięć kroków; każdy sprawdza stan przed działaniem, więc ponowne uruchomienie jest bezpieczne.
#
# Zasada bezpieczeństwa: root nie otwiera żadnej ścieżki pod /home/. Pliki kont czyta i zapisuje
# konto właściciela (sudo -u <konto> tee, cmp -, cp, rm, mkdir, find, diff, git, jq), a treść przychodzi przez
# standardowe wejście z folderu tymczasowego roota. Root zmienia tylko pliki systemu
# (/etc, /usr/local/lib/fabryka, /usr/local/lib/fabryka-serwer, /var/lib/fabryka-serwer, /var/log) i tryby samych
# katalogów domowych. Bez "sudo -u <konto> sh -c" i "sudo -u <konto> bash -c".
#
# Opcje: --tryb-autora (laboratorium autora Factory zostaje klonem; tryb zapisany w pliku roota) i --zestaw <plik>
# (archiwum zestawu Factory z tagu laboratorium, scripts/zestaw_fabryki.py, zamiast archiwum z wydania w trybie
# użytkownika).

REPO="lukeblonski/maestro-install"
WERSJA="v1.0.19"
# Suma SHA-256 pliku zestaw-fabryki.tar.gz wydania WERSJA, zrobionego przez scripts/zestaw_fabryki.py z tagu
# zestaw-<WERSJA> laboratorium; 64 zera do przypięcia przy wydaniu.
ZESTAW_SUMA="49bf36e6554c46c90006bf1e10ece875cb7ce6345029eb64a84a8b9075a106bd"

# gitleaks w wersji z szablonu CI guardrails (skills/guardrails/templates/ci.yml, GITLEAKS_VERSION) i suma SHA-256
# archiwum linux_x64 z oficjalnego pliku sum tego wydania (gitleaks_8.30.1_checksums.txt).
GITLEAKS_WERSJA="8.30.1"
GITLEAKS_SUMA="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"

# mise, menedżer wersji języków projektów konta fabryka, w przypiętej wersji i suma SHA-256 binarki
# mise-v2026.11.4-linux-x64 z pliku SHASUMS256.txt tego wydania (podpisanego GPG, zgodna z polem digest w API GitHuba).
# Języki instaluje potem konto fabryka bez roota, tylko w folderze projektu (plik mise.toml).
MISE_WERSJA="2026.11.4"
MISE_SUMA="0296d9cba9324106d4e0962bb94a2072902f3658813aeb3b09504947bb8ddc2b"

# Obraz przeglądarki do testów aplikacji, przypięty tagiem i skrótem: ten sam co IMAGE w scripts/makieta.py
# laboratorium. PRZEGLADARKA to ścieżka przeglądarki w obrazie (BROWSER w makieta.py), zależna od wersji obrazu.
# PROBA_PRZEGLADARKI to próbny plik kontroli: wypisuje w treści strony parametr state z adresu.
OBRAZ_PRZEGLADARKI="mcr.microsoft.com/playwright:v1.65.0-noble@sha256:6e3fb709361521eb27161606e6da6d2674e5e89fa16516cb37d6fdd91372273d"
PRZEGLADARKA="/ms-playwright/chromium_headless_shell-1254/chrome-headless-shell-linux64/chrome-headless-shell"
PROBA_PRZEGLADARKI='<!doctype html><body><script>document.body.textContent=new URLSearchParams(location.search).get("state")</script>'

# Pliki pobierane z repozytorium instalatora w wersji WERSJA. Adres wskazuje tag pełną nazwą refs/tags/,
# żeby gałąź o tej samej nazwie go nie przesłoniła; pliki tagu chroni niezmienne wydanie.
# Nieudane pobranie kończy instalator kodem 1, zanim cokolwiek się zmieni.
PLIKI=(
  "sudoers-obserwator"
  "start-fabryki.sh"
  "skrzynka.py"
  "start-obserwatora.sh"
  "obserwator.service"
  "fabryka-retencja-obserwatora.service"
  "fabryka-retencja-obserwatora.timer"
  "obserwator/CLAUDE.md"
  "obserwator/CLAUDE-autor.md"
  "obserwator/narzedzia/wyslij.sh"
  "obserwator/narzedzia/porzadki-notatek.sh"
  "obserwator/skills/analiza-w-poprzek/SKILL.md"
  "obserwator/skills/przeglad-po-projekcie/SKILL.md"
  "obserwator/skills/porzadki-notatek/SKILL.md"
)

# Pliki serwera w jednym drzewie roota (wzor_serwera, drzewo_roota): skrypty startowe, wykonawca rozmowy, umowa Maestro
# w $LIB/obserwator/CLAUDE.md i narzędzia Maestro w $LIB/obserwator/narzedzia; konta fabryka i obserwator ich nie zmienią.
LIB=/usr/local/lib/fabryka-serwer
# Foldery wiadomości obserwatora: skrzynkę pisze tylko obserwator, wyniki tylko fabryka.
# W przekazaniu obserwator kładzie plik z wynikiem pracy w panelu usługi, a fabryka go czyta i usuwa.
SERWER=/var/lib/fabryka-serwer
SKRZYNKA="$SERWER/skrzynka"
WYNIKI="$SERWER/wyniki"
PRZEKAZANIE="$SERWER/przekazanie"
JEDNOSTKI=/etc/systemd/system
SUDOERS_CEL=/etc/sudoers.d/fabryka-obserwator
APPARMOR_ROOTLESSKIT=/etc/apparmor.d/usr.bin.rootlesskit
LOG=/var/log/fabryka-instalator.log

OBS_HOME=/home/obserwator
FAB_HOME=/home/fabryka
OBS_DIR=/home/obserwator/obserwator
LAB_DIR=/home/fabryka/fabryka
NOTATKI="$OBS_DIR/notatki"
ARCHIWUM="$OBS_DIR/archiwum"
# Archiwum notatek (umowa, „Pamięć”): poza retencją, która czyści tylko $ARCHIWUM.
ARCHIWUM_NOTATEK="$OBS_DIR/archiwum-notatek"
OBS_SETTINGS="$OBS_HOME/.claude/settings.json"
OBS_SKILLE="$OBS_HOME/.claude/skills"
# Osobiste skille Claude Code konta obserwator w trybie autora: wzór każdego to obserwator/skills/<nazwa>/SKILL.md
# z PLIKI. W trybie użytkownika skill porzadki-notatek jest w $ZARZADZANE, a skille autora (SKILLE_AUTORA) nie ma.
SKILLE_OBSERWATORA=(analiza-w-poprzek przeglad-po-projekcie porzadki-notatek)
SKILLE_AUTORA=(analiza-w-poprzek przeglad-po-projekcie)
OBS_STAN="$OBS_HOME/.claude.json"
OBS_CLAUDE="$OBS_HOME/.local/bin/claude"
FAB_CLAUDE="$FAB_HOME/.local/bin/claude"
FAB_SKILLE="$FAB_HOME/.claude/skills"
# Zapis nazw skilli, które instalator skopiował do FAB_SKILLE (jedna w linii); stan fabryki konta fabryka.
FAB_SKILLE_ZAPIS="$FAB_HOME/.local/state/fabryka/skille-instalatora"
FAB_SETTINGS="$FAB_HOME/.claude/settings.json"

# Tryb instalacji (autor albo uzytkownik) w pliku roota: zapisuje go tylko opcja --tryb-autora albo pierwsze
# uruchomienie bez niej (uzytkownik).
TRYB_PLIK="$SERWER/tryb"
# Tryb użytkownika: zestaw Factory w folderze roota i skille Factory w folderze zarządzanym Claude Code (czytają go
# wszystkie konta, zmienia tylko root). Wzór każdego drzewa roota to lista sum w WZORY, a zmienione pliki trafiają do
# KOPIE (root, 0700).
ZESTAW=/usr/local/lib/fabryka
ZARZADZANE=/etc/claude-code/.claude/skills
WZORY="$SERWER/wzory"
KOPIE="$SERWER/kopie"

ZNACZNIK_PATH="# fabryka-serwer: ścieżka i umask konta (dopisane przez instalator)"
ZNACZNIK_DOCKER="# fabryka-serwer: Docker bez roota (dopisane przez instalator)"

# --- komunikaty ------------------------------------------------------------------------------------------

LOG_GOTOWY=0

# Komunikat instalatora: na ekran i, od chwili założenia dziennika, do dziennika (root, 0600).
napisz() {
  if [ "$LOG_GOTOWY" -eq 1 ]; then
    printf '%s\n' "$*" | tee -a "$LOG"
  else
    printf '%s\n' "$*"
  fi
}

etap() {
  napisz ""
  napisz "[$1/10] $2"
}

gotowe() {
  napisz "  [x] $*"
}

przerwij() {
  napisz "BŁĄD: $*" >&2
  exit 1
}

# --- opcje, tryb i archiwum zestawu (przed każdą zmianą) -----------------------------------------------------

# czytaj_opcje <argumenty instalatora>: OPCJA_AUTORA (1 z --tryb-autora, inaczej 0) i ZESTAW_PLIK (ścieżka z --zestaw,
# względna liczona od folderu, z którego uruchomiono instalator). Nieznana opcja, --zestaw bez pliku albo archiwum pod
# /home (także po rozwinięciu dowiązań) przerywa instalator kodem 1.
czytaj_opcje() {
  OPCJA_AUTORA=0
  ZESTAW_PLIK=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tryb-autora) OPCJA_AUTORA=1 ;;
      --zestaw)
        if [ "$#" -lt 2 ] || [ -z "$2" ]; then
          przerwij "Opcja --zestaw wymaga pliku archiwum zestawu Factory. Niczego nie zmieniono."
        fi
        case "$2" in
          /*) ZESTAW_PLIK="$2" ;;
          *) ZESTAW_PLIK="$PWD/$2" ;;
        esac
        # Root nie otwiera ścieżek pod /home: archiwum spod /home, także po rozwinięciu dowiązań, przerywa instalator.
        for sciezka in "$ZESTAW_PLIK" "$(realpath -m -- "$ZESTAW_PLIK" 2> /dev/null || true)"; do
          case "$sciezka" in
            /home|/home/*)
              przerwij "Archiwum zestawu $ZESTAW_PLIK leży pod /home, a root nie otwiera ścieżek pod /home. Skopiuj je do /root (np. /root/zestaw-fabryki.tar.gz) i podaj tę ścieżkę. Niczego nie zmieniono."
              ;;
          esac
        done
        shift
        ;;
      *) przerwij "Nieznana opcja: $1. Instalator zna tylko --tryb-autora i --zestaw <plik>. Niczego nie zmieniono." ;;
    esac
    shift
  done
}

# ustal_tryb: TRYB to autor z opcją --tryb-autora, inaczej treść pliku $TRYB_PLIK (autor albo uzytkownik), a bez pliku
# uzytkownik. Plik trybu, który jest dowiązaniem, nie jest zwykłym plikiem albo ma inną treść, przerywa instalator.
ustal_tryb() {
  if [ "$OPCJA_AUTORA" = 1 ]; then
    TRYB=autor
    return 0
  fi
  if [ ! -e "$TRYB_PLIK" ] && [ ! -L "$TRYB_PLIK" ]; then
    TRYB=uzytkownik
    return 0
  fi
  if [ -L "$TRYB_PLIK" ] || [ ! -f "$TRYB_PLIK" ]; then
    przerwij "Plik trybu $TRYB_PLIK nie jest zwykłym plikiem. Niczego nie zmieniono."
  fi
  TRYB=$(cat -- "$TRYB_PLIK")
  case "$TRYB" in
    autor | uzytkownik) ;;
    *) przerwij "Plik trybu $TRYB_PLIK ma treść inną niż autor albo uzytkownik. Niczego nie zmieniono." ;;
  esac
}

# zapisz_tryb: TRYB do pliku roota $TRYB_PLIK (root:root 0644).
zapisz_tryb() {
  printf '%s\n' "$TRYB" > "$TMP/tryb"
  zainstaluj_plik "$TMP/tryb" "$TRYB_PLIK" 0644 || true
}

# sprawdz_archiwum <archiwum> <nowy folder>: rozpakowuje archiwum zestawu Factory do folderu, gdy archiwum jest zwykłym
# plikiem, jego lista (tar -tvzf, czytana przed rozpakowaniem) ma tylko zwykłe pliki i foldery, bez członu ".." i bez
# ścieżki od /, a po rozpakowaniu pliki folderu poza SUMY i WERSJA to dokładnie pliki z listy SUMY z tymi samymi
# sumami i plik WERSJA jest. Inaczej kod 1 z powodem na wyjściu błędów.
sprawdz_archiwum() {
  local archiwum="$1" folder="$2" typy nazwy linia pliki
  if [ -L "$archiwum" ] || [ ! -f "$archiwum" ]; then
    echo "Archiwum zestawu $archiwum nie jest zwykłym plikiem." >&2
    return 1
  fi
  if ! typy=$(LC_ALL=C tar --quoting-style=escape -tvzf "$archiwum" 2> /dev/null | cut -c 1) \
    || ! nazwy=$(LC_ALL=C tar --quoting-style=escape -tzf "$archiwum" 2> /dev/null); then
    echo "Nie mogę odczytać listy archiwum zestawu $archiwum." >&2
    return 1
  fi
  if [ -z "$nazwy" ] || [ "$(wc -l <<< "$typy")" != "$(wc -l <<< "$nazwy")" ]; then
    echo "Archiwum zestawu $archiwum jest puste albo ma nieczytelną listę." >&2
    return 1
  fi
  while IFS= read -r linia; do
    case "$linia" in
      - | d) ;;
      *)
        echo "Archiwum zestawu $archiwum ma pozycję, która nie jest zwykłym plikiem ani folderem." >&2
        return 1
        ;;
    esac
  done <<< "$typy"
  while IFS= read -r linia; do
    case "$linia" in
      /*)
        echo "Archiwum zestawu $archiwum ma ścieżkę od /: $linia" >&2
        return 1
        ;;
    esac
    case "/$linia/" in
      */../*)
        echo "Archiwum zestawu $archiwum ma ścieżkę z członem ..: $linia" >&2
        return 1
        ;;
    esac
  done <<< "$nazwy"
  mkdir -- "$folder" || return 1
  if ! tar -xzf "$archiwum" -C "$folder" --no-same-owner 2> /dev/null; then
    echo "Nie mogę rozpakować archiwum zestawu $archiwum." >&2
    return 1
  fi
  if [ -n "$(find "$folder" ! -type f ! -type d -print -quit)" ]; then
    echo "Archiwum zestawu $archiwum ma pozycję, która nie jest zwykłym plikiem ani folderem." >&2
    return 1
  fi
  if [ ! -f "$folder/WERSJA" ] || [ ! -s "$folder/SUMY" ]; then
    echo "Archiwum zestawu $archiwum nie ma pliku WERSJA albo listy SUMY." >&2
    return 1
  fi
  if grep -qvE '^[0-9a-f]{64}  [^/].*$' "$folder/SUMY"; then
    echo "Lista SUMY archiwum zestawu $archiwum ma linię spoza postaci <sha256>  <ścieżka>." >&2
    return 1
  fi
  pliki=$(find "$folder" -type f ! -path "$folder/SUMY" ! -path "$folder/WERSJA" -printf '%P\n' | LC_ALL=C sort) || return 1
  if [ "$pliki" != "$(cut -c 67- "$folder/SUMY" | LC_ALL=C sort)" ]; then
    echo "Pliki archiwum zestawu $archiwum różnią się od listy SUMY (plik spoza listy albo brak pliku z listy)." >&2
    return 1
  fi
  if ! (cd "$folder" && sha256sum -c --quiet --strict SUMY > /dev/null 2>&1); then
    echo "Suma pliku archiwum zestawu $archiwum nie zgadza się z listą SUMY." >&2
    return 1
  fi
}

# archiwum_z_opcji: gdy podano --zestaw, kopiuje archiwum do $TMP/zestaw-fabryki.tar.gz i rozpakowuje kopię do
# $TMP/zestaw (sprawdz_archiwum); zły plik albo złe archiwum przerywa instalator kodem 1.
archiwum_z_opcji() {
  [ -n "$ZESTAW_PLIK" ] || return 0
  if [ -L "$ZESTAW_PLIK" ] || [ ! -f "$ZESTAW_PLIK" ]; then
    przerwij "Archiwum zestawu $ZESTAW_PLIK nie jest zwykłym plikiem. Niczego nie zmieniono."
  fi
  cp -P -- "$ZESTAW_PLIK" "$TMP/zestaw-fabryki.tar.gz" || przerwij "Nie mogę odczytać archiwum $ZESTAW_PLIK. Niczego nie zmieniono."
  if [ -L "$TMP/zestaw-fabryki.tar.gz" ]; then
    przerwij "Archiwum zestawu $ZESTAW_PLIK nie jest zwykłym plikiem. Niczego nie zmieniono."
  fi
  sprawdz_archiwum "$TMP/zestaw-fabryki.tar.gz" "$TMP/zestaw" \
    || przerwij "Archiwum zestawu $ZESTAW_PLIK nie przechodzi sprawdzenia. Niczego nie zmieniono."
}

# archiwum_z_wydania: tryb użytkownika bez --zestaw. Pobiera zestaw-fabryki.tar.gz z wydania WERSJA repozytorium REPO
# do $TMP/zestaw-fabryki.tar.gz, sprawdza jego sumę z ZESTAW_SUMA i rozpakowuje je do $TMP/zestaw (sprawdz_archiwum).
# Błąd pobrania, inna suma albo złe archiwum przerywa instalator kodem 1, zanim cokolwiek się zmieni. W trybie autora
# i z --zestaw nic nie robi.
archiwum_z_wydania() {
  local archiwum="$TMP/zestaw-fabryki.tar.gz"
  if [ "$TRYB" = autor ] || [ -n "$ZESTAW_PLIK" ]; then
    return 0
  fi
  if ! curl -fsSL "https://github.com/${REPO}/releases/download/${WERSJA}/zestaw-fabryki.tar.gz" -o "$archiwum"; then
    przerwij "Nie mogę pobrać archiwum zestawu Factory z wydania $WERSJA. Niczego nie zmieniono; sprawdź sieć i uruchom ponownie."
  fi
  if ! echo "$ZESTAW_SUMA  $archiwum" | sha256sum -c - > /dev/null 2>&1; then
    przerwij "Suma SHA-256 archiwum zestawu Factory z wydania $WERSJA nie zgadza się z sumą w instalatorze. Niczego nie zmieniono."
  fi
  sprawdz_archiwum "$archiwum" "$TMP/zestaw" \
    || przerwij "Archiwum zestawu Factory z wydania $WERSJA nie przechodzi sprawdzenia. Niczego nie zmieniono."
  napisz "Archiwum zestawu Factory z wydania $WERSJA pobrane (suma SHA-256 zgodna)."
}

# --- warunki startu ----------------------------------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
  echo "Instalator wymaga roota. Uruchom go jako root: sudo bash $0" >&2
  exit 1
fi

if [ ! -r /etc/os-release ]; then
  echo "Nie rozpoznaję systemu (brak /etc/os-release). Instalator działa tylko na Ubuntu." >&2
  exit 1
fi
SYSTEM_ID=$(. /etc/os-release && printf '%s' "${ID:-}")
SYSTEM_WERSJA=$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")
if [ "$SYSTEM_ID" != "ubuntu" ]; then
  echo "Ten system to nie Ubuntu ($SYSTEM_ID). Instalator działa tylko na Ubuntu." >&2
  exit 1
fi
case "$SYSTEM_WERSJA" in
  24.04 | 26.04) ;;
  *) echo "Uwaga: Ubuntu $SYSTEM_WERSJA nie jest sprawdzone (sprawdzone: 24.04 i 26.04). Instalator idzie dalej." ;;
esac

czytaj_opcje "$@"
cd /
umask 022
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
POBRANE="$TMP/pliki"
# Czas tego uruchomienia w nazwach kopii.
CZAS=$(date +%Y%m%d-%H%M%S)
ustal_tryb
archiwum_z_opcji
archiwum_z_wydania
if [ "$TRYB" = autor ]; then
  FOLDER_FABRYKI="$LAB_DIR"
  FOLDER_INNEGO_TRYBU="$ZESTAW"
else
  FOLDER_FABRYKI="$ZESTAW"
  FOLDER_INNEGO_TRYBU="$LAB_DIR"
fi
# Hak startu sesji konta fabryka z folderu Factory trybu; polecenie z folderu drugiego trybu znika z ustawień.
HAK_FABRYKI="python3 -I -B $FOLDER_FABRYKI/scripts/hook_start_sesji.py"
HAK_INNEGO_TRYBU="python3 -I -B $FOLDER_INNEGO_TRYBU/scripts/hook_start_sesji.py"
if [ "$TRYB" = autor ]; then
  OPIS_TRYBU="tryb autora: laboratorium Factory w $LAB_DIR zostaje klonem"
else
  OPIS_TRYBU="tryb użytkownika: pliki Factory w folderach roota tylko do odczytu"
fi
echo "Instalacja w trybie $TRYB ($OPIS_TRYBU)."

# --- pobranie plików instalatora z tagu (przed każdą zmianą) ------------------------------------------------

echo "Pobieram pliki instalatora w wersji $WERSJA."
for plik in "${PLIKI[@]}"; do
  mkdir -p "$POBRANE/$(dirname "$plik")"
  if ! curl -fsSL "https://raw.githubusercontent.com/${REPO}/refs/tags/${WERSJA}/${plik}" -o "$POBRANE/$plik"; then
    przerwij "Nie mogę pobrać pliku $plik w wersji $WERSJA. Niczego nie zmieniono; sprawdź sieć i uruchom ponownie."
  fi
done

touch "$LOG"
chmod 0600 "$LOG"
LOG_GOTOWY=1
napisz "=== Instalator fabryki $WERSJA, $(date -Is) ==="
napisz "Tryb instalacji: $TRYB ($OPIS_TRYBU)."
gotowe "pliki instalatora w wersji $WERSJA pobrane"

# --- pomocnicze --------------------------------------------------------------------------------------------

# zainstaluj_plik <źródło w folderze roota> <cel w systemie> <tryb>: root:root; kod 0 = treść się zmieniła.
zainstaluj_plik() {
  if [ -f "$2" ] && cmp -s "$1" "$2"; then
    chown root:root "$2" || przerwij "Nie mogę ustawić właściciela $2."
    chmod "$3" "$2" || przerwij "Nie mogę ustawić trybu $2."
    return 1
  fi
  install -m "$3" -o root -g root "$1" "$2" || przerwij "Nie mogę zapisać $2."
  return 0
}

# sumy_drzewa <folder>: jedna linia "<suma SHA-256>  <ścieżka>" na każdy plik folderu, posortowana po ścieżce (LC_ALL=C);
# dowiązanie (bez podążania za nim) ma zamiast sumy "dowiazanie", a inny plik niż zwykły "inny".
sumy_drzewa() {
  local sciezka
  find "$1" -mindepth 1 ! -type d -printf '%P\0' | LC_ALL=C sort -z | while IFS= read -r -d '' sciezka; do
    if [ -L "$1/$sciezka" ]; then
      printf 'dowiazanie  %s\n' "$sciezka"
    elif [ -f "$1/$sciezka" ]; then
      printf '%s  %s\n' "$(sha256sum < "$1/$sciezka" | cut -d ' ' -f 1)" "$sciezka"
    else
      printf 'inny  %s\n' "$sciezka"
    fi
  done
}

# wlasciciel_root <folder>: każdy plik i folder w folderze należy do root:root.
wlasciciel_root() {
  [ -z "$(find "$1" \( ! -uid 0 -o ! -gid 0 \) -print -quit)" ]
}

# tryby_jak_wzor <wzór> <cel>: cel ma te same ścieżki co wzór, foldery 0755, pliki 0644, a wykonywalne we wzorze 0755.
tryby_jak_wzor() {
  local oczekiwane
  oczekiwane=$(find "$1" \( -type d -printf '755 %P\n' \) -o \( -type f -perm /111 -printf '755 %P\n' \) \
    -o \( -type f -printf '644 %P\n' \) | LC_ALL=C sort) || return 1
  [ "$oczekiwane" = "$(find "$2" -printf '%m %P\n' | LC_ALL=C sort)" ]
}

# drzewo_roota <wzór w $TMP> <cel poza /home> <nazwa>: kładzie drzewo roota z wzoru i przy każdym uruchomieniu
# przywraca je do wzoru z kopią i wypisem.
# - Bez celu (pierwsze położenie) kładzie wzór, bez wypisu przywróconych plików i bez kopii.
# - Z celem porównuje go z ostatnim wzorem (lista $WZORY/<nazwa>.sumy), a bez listy z nowym wzorem. Każdy zmieniony
#   albo brakujący plik wypisuje linią "przywrócony do wzoru" (bez listy: "różni się od wydania"), a dodatkowy
#   "usunięty plik spoza wzoru"; zmieniony i dodatkowy plik albo dowiązanie kopiuje, bez podążania za dowiązaniem, do
#   $KOPIE/$CZAS/<nazwa>/<ścieżka>, a folder kopii wypisuje jedną linią. Cel, który jest dowiązaniem albo nie jest
#   folderem, przenosi do kopii w całości.
# - Gdy cel różni się od nowego wzoru albo ma innego właściciela niż root:root lub inne tryby (tryby_jak_wzor), kładzie
#   wzór obok celu i podmienia go dwoma mv, a stare drzewo usuwa (jego zmienione pliki są już w kopii). Przed podmianą
#   $ZESTAW albo $ZARZADZANE przerywa instalator, gdy konto fabryka ma proces autopilota z zestawu albo gdy pgrep
#   nie odpowiada (kod inny niż 0 i 1).
# - Na końcu zapisuje listę sum nowego wzoru. DRZEWO_ZMIENIONE=1, gdy cel się zmienił, inaczej 0.
drzewo_roota() {
  local wzor="$1" cel="$2" nazwa="$3"
  local lista="$WZORY/$3.sumy" kopia="$KOPIE/$CZAS/$3" nowe="$TMP/sumy-$3" stan="$TMP/stan-$3"
  local odniesienie slowo porownanie rodzaj sciezka podmiana=0 obcy=0 skopiowane=0 kod_pgrep
  DRZEWO_ZMIENIONE=0
  if [ -n "$(find "$wzor" ! -type f ! -type d -print -quit)" ]; then
    przerwij "Wzór $cel ma pozycję, która nie jest zwykłym plikiem ani folderem."
  fi
  sumy_drzewa "$wzor" > "$nowe" || przerwij "Nie mogę policzyć sum wzoru $cel."
  folder_systemu "$(dirname "$cel")" root:root 0755
  folder_systemu "$WZORY" root:root 0700
  # Resztki przerwanego uruchomienia obok celu.
  rm -rf --one-file-system -- "$cel".nowy-* "$cel".stary-*
  if [ -L "$cel" ] || { [ -e "$cel" ] && [ ! -d "$cel" ]; }; then
    obcy=1
    podmiana=1
  elif [ -d "$cel" ]; then
    sumy_drzewa "$cel" > "$stan" || przerwij "Nie mogę policzyć sum $cel."
    if ! cmp -s "$stan" "$nowe" || ! wlasciciel_root "$cel" || ! tryby_jak_wzor "$wzor" "$cel"; then
      podmiana=1
    fi
  else
    podmiana=1
  fi
  if [ "$podmiana" = 1 ] && { [ "$cel" = "$ZESTAW" ] || [ "$cel" = "${ZARZADZANE-}" ]; }; then
    kod_pgrep=0
    pgrep -u fabryka -f "$ZESTAW/scripts/autopilot.py" > /dev/null 2>&1 || kod_pgrep=$?
    case "$kod_pgrep" in
      0) przerwij "Konto fabryka ma działający przebieg autopilota z $ZESTAW. Poczekaj na koniec przebiegu i uruchom instalator ponownie; $cel się nie zmienił." ;;
      1) ;;
      *) przerwij "Nie mogę sprawdzić, czy konto fabryka ma działający przebieg autopilota (pgrep, kod $kod_pgrep); $cel się nie zmienił." ;;
    esac
  fi
  if [ "$obcy" = 1 ]; then
    folder_systemu "$KOPIE" root:root 0700
    mkdir -p -- "$KOPIE/$CZAS"
    mv -- "$cel" "$kopia" || przerwij "Nie mogę przenieść $cel do kopii $kopia."
    napisz "  przeniesiony do kopii, bo nie jest folderem: $cel"
    skopiowane=1
  elif [ -d "$cel" ]; then
    if [ -f "$lista" ]; then
      odniesienie="$lista"
      slowo="przywrócony do wzoru"
    else
      odniesienie="$nowe"
      slowo="różni się od wydania"
    fi
    porownanie=$(LC_ALL=C awk '
      { i = index($0, "  "); s = substr($0, 1, i - 1); p = substr($0, i + 2) }
      FILENAME == ARGV[1] { wzor[p] = s; next }
      { jest[p] = 1; if (!(p in wzor)) print "dodatkowy\t" p; else if (wzor[p] != s) print "zmieniony\t" p }
      END { for (p in wzor) if (!(p in jest)) print "brak\t" p }' "$odniesienie" "$stan" | LC_ALL=C sort) \
      || przerwij "Nie mogę porównać $cel ze wzorem."
    while IFS=$'\t' read -r rodzaj sciezka; do
      [ -n "$rodzaj" ] || continue
      if [ "$rodzaj" = dodatkowy ]; then
        napisz "  usunięty plik spoza wzoru: $cel/$sciezka"
      else
        napisz "  $slowo: $cel/$sciezka"
      fi
      # Brakujący plik nie ma wersji do kopii; jego ścieżki root nie otwiera (mogłaby iść przez dowiązanie).
      [ "$rodzaj" != brak ] || continue
      [ "$skopiowane" = 1 ] || folder_systemu "$KOPIE" root:root 0700
      mkdir -p -- "$(dirname -- "$kopia/$sciezka")"
      cp -a -- "$cel/$sciezka" "$kopia/$sciezka" || przerwij "Nie mogę skopiować $cel/$sciezka do kopii $kopia."
      skopiowane=1
    done <<< "$porownanie"
  fi
  if [ "$skopiowane" = 1 ]; then
    napisz "  kopia zmienionych plików: $kopia"
  fi
  if [ "$podmiana" = 1 ]; then
    cp -R -- "$wzor" "$cel.nowy-$CZAS" || przerwij "Nie mogę położyć wzoru obok $cel."
    chown -R -h root:root "$cel.nowy-$CZAS" || przerwij "Nie mogę ustawić właściciela wzoru obok $cel."
    chmod -R u=rwX,go=rX,ug-s "$cel.nowy-$CZAS" || przerwij "Nie mogę ustawić trybów wzoru obok $cel."
    if [ -d "$cel" ]; then
      mv -- "$cel" "$cel.stary-$CZAS" || przerwij "Nie mogę podmienić $cel."
    fi
    mv -- "$cel.nowy-$CZAS" "$cel" || przerwij "Nie mogę podmienić $cel; poprzednie drzewo jest w $cel.stary-$CZAS."
    rm -rf --one-file-system -- "$cel.stary-$CZAS"
    DRZEWO_ZMIENIONE=1
    gotowe "$cel położony ze wzoru"
  else
    gotowe "$cel równy wzorowi"
  fi
  zainstaluj_plik "$nowe" "$lista" 0600 || true
}

# wzor_serwera <folder>: wzór drzewa $LIB z pobranych plików: start-fabryki.sh, skrzynka.py, start-obserwatora.sh,
# umowa Maestro obserwator/CLAUDE.md (w trybie autora umowa i dodatek autora obserwator/CLAUDE-autor.md sklejone w jeden
# plik, z pustą linią między nimi) i narzędzia Maestro obserwator/narzedzia/{wyslij.sh,porzadki-notatek.sh}. Skrypty
# i narzędzia mają tryb 0755, umowa 0644.
wzor_serwera() {
  local wzor="$1" plik
  mkdir -p -- "$wzor/obserwator/narzedzia" || przerwij "Nie mogę założyć wzoru plików serwera $wzor."
  for plik in start-fabryki.sh skrzynka.py start-obserwatora.sh obserwator/narzedzia/wyslij.sh \
    obserwator/narzedzia/porzadki-notatek.sh; do
    cp -- "$POBRANE/$plik" "$wzor/$plik" || przerwij "Nie mogę położyć $plik we wzorze plików serwera."
    chmod 0755 "$wzor/$plik" || przerwij "Nie mogę ustawić trybu $plik we wzorze plików serwera."
  done
  if [ "$TRYB" = autor ]; then
    { cat -- "$POBRANE/obserwator/CLAUDE.md" && printf '\n' && cat -- "$POBRANE/obserwator/CLAUDE-autor.md"; } \
      > "$wzor/obserwator/CLAUDE.md" || przerwij "Nie mogę skleić umowy Maestro z dodatkiem autora."
  else
    cp -- "$POBRANE/obserwator/CLAUDE.md" "$wzor/obserwator/CLAUDE.md" || przerwij "Nie mogę położyć umowy Maestro we wzorze."
  fi
  chmod 0644 "$wzor/obserwator/CLAUDE.md" || przerwij "Nie mogę ustawić trybu umowy Maestro we wzorze."
}

# w_grupie <konto> <grupa>
w_grupie() {
  case " $(id -nG "$1") " in
    *" $2 "*) return 0 ;;
  esac
  return 1
}

# dopisz_blok <konto> <plik konta> <znacznik> <treść>: dopisuje blok raz, z konta właściciela.
dopisz_blok() {
  if sudo -u "$1" grep -qF "$3" "$2" 2> /dev/null; then
    return 0
  fi
  printf '\n%s\n%s\n' "$3" "$4" | sudo -u "$1" tee -a "$2" > /dev/null
}

# zakres_podrzedny <plik /etc/subuid albo /etc/subgid> <opcja usermod>: co najmniej 65 536 identyfikatorów.
zakres_podrzedny() {
  local start
  if awk -F: '$1 == "fabryka" && $3 >= 65536 { ok = 1 } END { exit !ok }' "$1"; then
    return 0
  fi
  start=$(awk -F: 'BEGIN { m = 100000 } { e = $2 + $3; if (e > m) m = e } END { print m }' "$1")
  usermod "$2" "$start-$((start + 65535))" fabryka
}

# --- 1. pakiety --------------------------------------------------------------------------------------------

etap 1 "Pakiety systemu"
export DEBIAN_FRONTEND=noninteractive
# Na świeżym serwerze unattended-upgrades i cloud-init trzymają blokadę dpkg; apt-get czeka do 10 minut.
APT_CZEKAJ=(-o DPkg::Lock::Timeout=600)
napisz "  Gdy system sam instaluje aktualizacje, apt czeka na nie do 10 minut."
apt-get "${APT_CZEKAJ[@]}" update -q
apt-get "${APT_CZEKAJ[@]}" install -y -q ca-certificates curl git jq tmux uidmap dbus-user-session

ARCH=$(dpkg --print-architecture)
KOD_UBUNTU=$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
install -m 0755 -d /etc/apt/keyrings

if [ ! -s /etc/apt/keyrings/githubcli-archive-keyring.gpg ]; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$TMP/githubcli-archive-keyring.gpg"
  install -m 0644 -o root -g root "$TMP/githubcli-archive-keyring.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg
fi
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
  "$ARCH" > "$TMP/github-cli.list"
zainstaluj_plik "$TMP/github-cli.list" /etc/apt/sources.list.d/github-cli.list 0644 || true

if [ ! -s /etc/apt/keyrings/docker.asc ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$TMP/docker.asc"
  install -m 0644 -o root -g root "$TMP/docker.asc" /etc/apt/keyrings/docker.asc
fi
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
  "$ARCH" "$KOD_UBUNTU" > "$TMP/docker.list"
zainstaluj_plik "$TMP/docker.list" /etc/apt/sources.list.d/docker.list 0644 || true

apt-get "${APT_CZEKAJ[@]}" update -q
apt-get "${APT_CZEKAJ[@]}" install -y -q gh docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras \
  docker-buildx-plugin docker-compose-plugin

# Demon Dockera roota jest wyłączony: fabryka używa tylko Dockera bez roota.
systemctl disable --now docker.service docker.socket > /dev/null 2>&1 || true
rm -f /var/run/docker.sock
gotowe "pakiety, GitHub CLI i Docker zainstalowane; demon Dockera roota wyłączony"

# gitleaks: archiwum z wydania na GitHubie, suma SHA-256 sprawdzona przed instalacją; tylko amd64 (suma dotyczy linux_x64).
if [ "$ARCH" = "amd64" ]; then
  if /usr/local/bin/gitleaks version 2> /dev/null | grep -qF "$GITLEAKS_WERSJA"; then
    gotowe "gitleaks $GITLEAKS_WERSJA już jest"
  else
    GITLEAKS_ARCHIWUM="$TMP/gitleaks_${GITLEAKS_WERSJA}_linux_x64.tar.gz"
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_WERSJA}/gitleaks_${GITLEAKS_WERSJA}_linux_x64.tar.gz" \
      -o "$GITLEAKS_ARCHIWUM" || przerwij "Nie mogę pobrać gitleaks $GITLEAKS_WERSJA; sprawdź sieć i uruchom ponownie."
    if ! echo "$GITLEAKS_SUMA  $GITLEAKS_ARCHIWUM" | sha256sum -c - > /dev/null 2>&1; then
      przerwij "Suma SHA-256 pobranego gitleaks $GITLEAKS_WERSJA nie zgadza się z sumą w instalatorze. Niczego nie zainstalowano."
    fi
    mkdir -p "$TMP/gitleaks"
    tar -xzf "$GITLEAKS_ARCHIWUM" -C "$TMP/gitleaks" gitleaks || przerwij "Nie mogę rozpakować gitleaks $GITLEAKS_WERSJA."
    install -m 0755 -o root -g root "$TMP/gitleaks/gitleaks" /usr/local/bin/gitleaks \
      || przerwij "Nie mogę zapisać /usr/local/bin/gitleaks."
    gotowe "gitleaks $GITLEAKS_WERSJA zainstalowany (suma SHA-256 zgodna)"
  fi
else
  napisz "  Uwaga: gitleaks $GITLEAKS_WERSJA instaluję tylko na amd64, a ten serwer to $ARCH. Pomijam gitleaks."
fi

# mise: binarka z wydania na GitHubie, suma SHA-256 sprawdzona przed instalacją; tylko amd64 (suma dotyczy linux-x64).
# Instalator niczego nie odinstalowuje i nie wybiera żadnego języka: dane mise konto fabryka zakłada samo
# przy pierwszym użyciu, a wersję języka zapisuje krok fabryki w folderze projektu.
if [ "$ARCH" = "amd64" ]; then
  if /usr/local/bin/mise --version 2> /dev/null | grep -qF "$MISE_WERSJA"; then
    gotowe "mise $MISE_WERSJA już jest"
  else
    MISE_PLIK="$TMP/mise-v${MISE_WERSJA}-linux-x64"
    curl -fsSL "https://github.com/jdx/mise/releases/download/v${MISE_WERSJA}/mise-v${MISE_WERSJA}-linux-x64" \
      -o "$MISE_PLIK" || przerwij "Nie mogę pobrać mise $MISE_WERSJA; sprawdź sieć i uruchom ponownie."
    if ! echo "$MISE_SUMA  $MISE_PLIK" | sha256sum -c - > /dev/null 2>&1; then
      przerwij "Suma SHA-256 pobranego mise $MISE_WERSJA nie zgadza się z sumą w instalatorze. Niczego nie zainstalowano."
    fi
    install -m 0755 -o root -g root "$MISE_PLIK" /usr/local/bin/mise \
      || przerwij "Nie mogę zapisać /usr/local/bin/mise."
    gotowe "mise $MISE_WERSJA zainstalowany (suma SHA-256 zgodna)"
  fi
else
  napisz "  Uwaga: mise $MISE_WERSJA instaluję tylko na amd64, a ten serwer to $ARCH. Pomijam mise."
fi

# --- 2. konta, grupy i reguła sudo -------------------------------------------------------------------------

etap 2 "Konta obserwator i fabryka"
for konto in fabryka obserwator; do
  if id -u "$konto" > /dev/null 2>&1; then
    gotowe "konto $konto już jest"
  else
    useradd -m -s /bin/bash "$konto"
    gotowe "konto $konto założone"
  fi
done

# Fabryka nie widzi obserwatora; obserwator czyta pliki fabryki przez grupę fabryka.
chmod 0700 "$OBS_HOME"
chmod 0750 "$FAB_HOME"
if ! w_grupie obserwator fabryka; then
  usermod -aG fabryka obserwator
fi
for grupa in sudo docker; do
  if w_grupie fabryka "$grupa"; then
    gpasswd -d fabryka "$grupa" > /dev/null
    napisz "  usunięto konto fabryka z grupy $grupa"
  fi
done
zakres_podrzedny /etc/subuid --add-subuids
zakres_podrzedny /etc/subgid --add-subgids
# umask 022 kont fabryka i obserwator w jednym miejscu: pam_umask czyta "umask=" z pola GECOS przed
# ustawieniami z /etc/login.defs (USERGROUPS_ENAB daje 002), więc każda sesja PAM konta (sudo -u, menedżer
# użytkownika, logowanie) tworzy pliki bez zapisu dla grupy. Fabryka nie daje zapisu grupie fabryka,
# w której jest obserwator; obserwator nie daje grupie fabryka zapisu w skrzynce.
for konto in fabryka obserwator; do
  case "$(getent passwd "$konto" | cut -d: -f5)" in
    *umask=022*) ;;
    *) chfn -o umask=022 "$konto" ;;
  esac
done
gotowe "tryby katalogów domowych, grupy, umask kont fabryka i obserwator i zakresy podrzędnych identyfikatorów ustawione"

if ! visudo -c -f "$POBRANE/sudoers-obserwator" > /dev/null; then
  przerwij "Reguła sudo obserwatora nie przechodzi visudo -c -f."
fi
zainstaluj_plik "$POBRANE/sudoers-obserwator" "$SUDOERS_CEL" 0440 || true
if ! visudo -c > /dev/null; then
  przerwij "Konfiguracja sudo nie przechodzi visudo -c po dodaniu reguły obserwatora."
fi
gotowe "reguła sudo obserwatora zainstalowana"

# folder_systemu <folder> <właściciel:grupa> <tryb>: folder systemu zakłada i poprawia root.
folder_systemu() {
  install -d -m "$3" -o "${2%%:*}" -g "${2##*:}" "$1" || przerwij "Nie mogę założyć folderu $1."
  chown "$2" "$1" || przerwij "Nie mogę ustawić właściciela $1."
  chmod "$3" "$1" || przerwij "Nie mogę ustawić trybu $1."
}
# Skrzynkę pisze tylko obserwator, a fabryka czyta przez grupę (setgid: nowe pliki dostają grupę fabryka).
# Wyniki pisze tylko fabryka, a obserwator czyta przez grupę fabryka.
folder_systemu "$SERWER" root:root 0755
folder_systemu "$SKRZYNKA" obserwator:fabryka 2750
folder_systemu "$WYNIKI" fabryka:fabryka 0750
# Przekazanie: obserwator kładzie plik, fabryka czyta go i usuwa (grupa fabryka z zapisem, setgid, bez bitu sticky).
folder_systemu "$PRZEKAZANIE" obserwator:fabryka 2770
gotowe "foldery $SKRZYNKA, $WYNIKI i $PRZEKAZANIE założone"
# Folder z v1.0.4, którego od v1.0.5 nie ma: zgody zapisuje autopilot jak na Macu.
rm -rf --one-file-system -- "$SERWER/zaufane" || przerwij "Nie mogę usunąć folderu $SERWER/zaufane z v1.0.4."
gotowe "folderu $SERWER/zaufane nie ma"
zapisz_tryb
gotowe "tryb $TRYB zapisany w $TRYB_PLIK"
# Pliki serwera, umowa i narzędzia Maestro w drzewie roota $LIB: każde uruchomienie przywraca je do wzoru z kopią
# i wypisem. Zmiana drzewa restartuje sesję obserwatora w etapie 7, bo umowę sesja dostaje przy starcie.
WZOR_SERWERA="$TMP/serwer"
wzor_serwera "$WZOR_SERWERA"
drzewo_roota "$WZOR_SERWERA" "$LIB" serwer
ZMIANA_SERWERA=$DRZEWO_ZMIENIONE

# --- 3. Claude Code --------------------------------------------------------------------------------------

etap 3 "Claude Code na obu kontach"
for konto in obserwator fabryka; do
  if sudo -u "$konto" test -x "/home/$konto/.local/bin/claude"; then
    gotowe "Claude Code na koncie $konto już jest"
  else
    napisz "  instaluję Claude Code na koncie $konto"
    curl -fsSL https://claude.ai/install.sh | sudo -u "$konto" bash
  fi
done

BLOK_OBSERWATORA='export PATH="$HOME/.local/bin:$PATH"'
BLOK_FABRYKI='export PATH="$HOME/.local/bin:$PATH"
umask 022'
for plik in .profile .bashrc; do
  dopisz_blok obserwator "$OBS_HOME/$plik" "$ZNACZNIK_PATH" "$BLOK_OBSERWATORA"
  dopisz_blok fabryka "$FAB_HOME/$plik" "$ZNACZNIK_PATH" "$BLOK_FABRYKI"
done
gotowe "ścieżka do Claude Code w .profile i .bashrc obu kont"

# --- 4. Docker bez roota ---------------------------------------------------------------------------------

etap 4 "Docker bez roota na koncie fabryka"
FAB_UID=$(id -u fabryka)
FAB_RUN="/run/user/$FAB_UID"

# Polecenie konta fabryka z jej sesją systemd (sudo nie daje XDG_RUNTIME_DIR ani D-Bus).
jako_fabryka_z_sesja() {
  sudo -u fabryka env "XDG_RUNTIME_DIR=$FAB_RUN" "DBUS_SESSION_BUS_ADDRESS=unix:path=$FAB_RUN/bus" "$@"
}

# Polecenie docker konta fabryka (Docker bez roota) z jej sesją.
docker_fabryki() {
  jako_fabryka_z_sesja env "DOCKER_HOST=unix://$FAB_RUN/docker.sock" docker "$@"
}

# Ubuntu 24.04+ ogranicza przestrzenie nazw bez profilu AppArmor; profil tylko dla rootlesskit,
# bez wyłączania ograniczenia w całym systemie.
if [ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2> /dev/null || echo 0)" = "1" ]; then
  if grep -rqsF "/usr/bin/rootlesskit" /etc/apparmor.d; then
    gotowe "profil AppArmor dla rootlesskit już jest"
  else
    cat > "$TMP/usr.bin.rootlesskit" << 'PROFIL'
abi <abi/4.0>,
include <tunables/global>

"/usr/bin/rootlesskit" flags=(unconfined) {
  userns,

  include if exists <local/usr.bin.rootlesskit>
}
PROFIL
    zainstaluj_plik "$TMP/usr.bin.rootlesskit" "$APPARMOR_ROOTLESSKIT" 0644 || true
    apparmor_parser -r "$APPARMOR_ROOTLESSKIT"
    gotowe "profil AppArmor dla rootlesskit dodany"
  fi
fi

loginctl enable-linger fabryka
systemctl start "user@$FAB_UID.service"
for _ in $(seq 1 30); do
  if [ -S "$FAB_RUN/bus" ]; then
    break
  fi
  sleep 1
done
if [ ! -S "$FAB_RUN/bus" ]; then
  przerwij "Sesja systemd konta fabryka nie wystartowała ($FAB_RUN/bus). Uruchom instalator ponownie."
fi

if jako_fabryka_z_sesja systemctl --user is-active --quiet docker.service; then
  gotowe "Docker bez roota już działa"
else
  jako_fabryka_z_sesja /usr/bin/dockerd-rootless-setuptool.sh install
  jako_fabryka_z_sesja systemctl --user enable --now docker.service
  gotowe "Docker bez roota uruchomiony"
fi
BLOK_DOCKERA="export DOCKER_HOST=unix://$FAB_RUN/docker.sock"
for plik in .profile .bashrc; do
  dopisz_blok fabryka "$FAB_HOME/$plik" "$ZNACZNIK_DOCKER" "$BLOK_DOCKERA"
done

# Przeglądarka do testów aplikacji: obraz pobiera konto fabryka raz; kolejne uruchomienie go nie pobiera.
if docker_fabryki image inspect "$OBRAZ_PRZEGLADARKI" > /dev/null 2>&1; then
  gotowe "obraz przeglądarki do testów aplikacji już jest"
else
  napisz "  Pobieram obraz przeglądarki do testów aplikacji: ok. 1 GB pobierania, 3,6 GB na dysku."
  docker_fabryki pull "$OBRAZ_PRZEGLADARKI" \
    || przerwij "Nie mogę pobrać obrazu przeglądarki $OBRAZ_PRZEGLADARKI. Sprawdź sieć i wolne miejsce na dysku (df -h), potem uruchom instalator ponownie."
  gotowe "obraz przeglądarki do testów aplikacji pobrany"
fi

# --- 5. logowania ------------------------------------------------------------------------------------------

etap 5 "Logowania"
napisz "  Każde logowanie pokaże adres do otwarcia w przeglądarce. Po zalogowaniu strona"
napisz "  pokaże kod; wklej go tutaj i naciśnij Enter. Kody nie trafiają do dziennika."

# zaloguj_claude <konto> <plik claude> <opis>
zaloguj_claude() {
  if sudo -u "$1" "$2" auth status > /dev/null 2>&1; then
    gotowe "$3 jest zalogowany"
    return 0
  fi
  napisz "  Zaloguj $3 (konto Claude z subskrypcją i Remote Control)."
  sudo -u "$1" "$2" auth login || true
  if ! sudo -u "$1" "$2" auth status > /dev/null 2>&1; then
    przerwij "Logowanie: $3 nie jest zalogowany. Uruchom instalator ponownie; zrobione kroki zostaną pominięte."
  fi
  gotowe "$3 zalogowany"
}

zaloguj_claude obserwator "$OBS_CLAUDE" "Claude obserwatora"
zaloguj_claude fabryka "$FAB_CLAUDE" "Claude fabryki"

if sudo -u fabryka gh auth status > /dev/null 2>&1; then
  gotowe "GitHub fabryki jest zalogowany"
else
  napisz "  Zaloguj GitHub fabryki: otwórz github.com/login/device i wpisz kod, który pokaże się niżej."
  sudo -u fabryka gh auth login --web --git-protocol https --hostname github.com || true
  if ! sudo -u fabryka gh auth status > /dev/null 2>&1; then
    przerwij "Logowanie: GitHub fabryki nie jest zalogowany. Uruchom instalator ponownie."
  fi
  gotowe "GitHub fabryki zalogowany"
fi
sudo -u fabryka gh auth setup-git

# --- 6. folder obserwatora i ustawienia --------------------------------------------------------------------

etap 6 "Folder obserwatora, umowa i ustawienia"
sudo -u obserwator mkdir -p "$OBS_DIR" "$NOTATKI" "$ARCHIWUM" "$ARCHIWUM_NOTATEK" "$OBS_HOME/.claude"
# Klucze usług od człowieka (umowa obserwatora, „Panele usług”): folder tylko konta obserwator.
sudo -u obserwator mkdir -p "$OBS_DIR/klucze"
sudo -u obserwator chmod 0700 "$OBS_DIR/klucze"

# przejscie_plikow_obserwatora: dawne pliki Maestro w folderze konta (do v1.0.17): umowa CLAUDE.md i narzędzia
# narzedzia/wyslij.sh i narzedzia/porzadki-notatek.sh, gdy są, konto obserwator przenosi do nazw
# <plik>.przed-instalatorem-$CZAS, bo umowa i narzędzia są w plikach roota $LIB/obserwator, a CLAUDE.md w folderze
# sesji byłby drugą umową. Notatki, archiwum, archiwum notatek i klucze zostają nietknięte.
przejscie_plikow_obserwatora() {
  local plik
  for plik in CLAUDE.md narzedzia/wyslij.sh narzedzia/porzadki-notatek.sh; do
    if sudo -u obserwator test -e "$OBS_DIR/$plik" || sudo -u obserwator test -L "$OBS_DIR/$plik"; then
      sudo -u obserwator mv -- "$OBS_DIR/$plik" "$OBS_DIR/$plik.przed-instalatorem-$CZAS" \
        || przerwij "Konto obserwator nie może przenieść $OBS_DIR/$plik do kopii."
      gotowe "dawny plik Maestro $OBS_DIR/$plik przeniesiony do $OBS_DIR/$plik.przed-instalatorem-$CZAS (jest w $LIB/obserwator)"
    fi
  done
}

# przejscie_skilli_obserwatora: tryb użytkownika. Konto obserwator przenosi każdy osobisty skill Maestro
# z SKILLE_OBSERWATORA z ~/.claude/skills do $OBS_DIR/skille-przed-instalatorem-$CZAS/: skill porzadki-notatek jest
# w $ZARZADZANE, a skille autora u użytkownika nie ma; kopia w folderze skilli dalej byłaby skillem. Przeniesienie
# ustawia ZMIANA_SKILLA=1 (restart sesji w etapie 7). Inne skille zostają.
przejscie_skilli_obserwatora() {
  local skill kopia="$OBS_DIR/skille-przed-instalatorem-$CZAS" przeniesione=0
  for skill in "${SKILLE_OBSERWATORA[@]}"; do
    if sudo -u obserwator test -e "$OBS_SKILLE/$skill" || sudo -u obserwator test -L "$OBS_SKILLE/$skill"; then
      if [ "$przeniesione" = 0 ]; then
        sudo -u obserwator mkdir -p -- "$kopia"
      fi
      sudo -u obserwator mv -- "$OBS_SKILLE/$skill" "$kopia/$skill" \
        || przerwij "Konto obserwator nie może przenieść skilla $OBS_SKILLE/$skill do $kopia."
      przeniesione=1
      ZMIANA_SKILLA=1
      gotowe "osobisty skill Maestro $skill przeniesiony z $OBS_SKILLE do $kopia"
    fi
  done
}

przejscie_plikow_obserwatora
gotowe "umowa i narzędzia Maestro w plikach roota $LIB/obserwator"

# Skille obserwatora w trybie autora (osobiste skille Claude Code konta obserwator, SKILLE_OBSERWATORA): wzór zastępuje
# inną treść, poprzednia wersja zostaje jako kopia zapasowa. Nowy albo zmieniony skill restartuje sesję obserwatora
# w etapie 7, bo działająca sesja Claude Code nie widzi folderu skilli, którego nie było przy jej starcie. W trybie
# użytkownika osobiste skille Maestro wychodzą z folderu skilli (przejscie_skilli_obserwatora).
ZMIANA_SKILLA=0
if [ "$TRYB" = autor ]; then
  for skill in "${SKILLE_OBSERWATORA[@]}"; do
    sudo -u obserwator mkdir -p "$OBS_SKILLE/$skill"
  done
  for skill in "${SKILLE_OBSERWATORA[@]}"; do
    if sudo -u obserwator test -f "$OBS_SKILLE/$skill/SKILL.md"; then
      if sudo -u obserwator cmp -s - "$OBS_SKILLE/$skill/SKILL.md" \
        < "$POBRANE/obserwator/skills/$skill/SKILL.md"; then
        gotowe "skill obserwatora $skill równy wzorowi"
      else
        KOPIA="$OBS_SKILLE/$skill/SKILL.md.przed-instalatorem-$(date +%Y%m%d-%H%M%S)"
        sudo -u obserwator cp "$OBS_SKILLE/$skill/SKILL.md" "$KOPIA"
        sudo -u obserwator tee "$OBS_SKILLE/$skill/SKILL.md" \
          < "$POBRANE/obserwator/skills/$skill/SKILL.md" > /dev/null
        ZMIANA_SKILLA=1
        gotowe "skill obserwatora $skill zastąpiony wzorem; poprzednia wersja w $KOPIA"
      fi
    else
      sudo -u obserwator tee "$OBS_SKILLE/$skill/SKILL.md" \
        < "$POBRANE/obserwator/skills/$skill/SKILL.md" > /dev/null
      ZMIANA_SKILLA=1
      gotowe "skill obserwatora $skill zapisany"
    fi
  done
else
  przejscie_skilli_obserwatora
fi

# Folder serwera i projektów do odczytu, w trybie autora także laboratorium, a w trybie użytkownika zestaw Factory
# ($foldery); zapis narzędziami plikowymi tylko w skrzynce, a w projektach i w trybie autora w laboratorium reguła deny
# dla Edit ($zakazy). Inne wpisy permissions zostają, nowe dochodzą bez duplikatów, a znika każdy wpis z folderem
# $SERWER/zaufane z v1.0.4, każdy folder konta fabryka spoza $foldery w additionalDirectories (w trybie użytkownika
# także laboratorium), każda reguła allow z folderem konta fabryka i w trybie użytkownika reguła deny laboratorium.
# Zapis narzędziami plikowymi także w archiwum notatek, bez pytania (umowa, „Pamięć”). Dwa haki uruchamiają
# sprawdzenie notatek z $LIB/obserwator/narzedzia bez duplikatu: SessionStart przy każdym starcie sesji (także
# wznowieniu i po kompaktowaniu) i UserPromptSubmit z --co-miesiac raz na miesiąc kalendarzowy; polecenia z dawną
# ścieżką narzędzia w folderze obserwatora znikają, a inne haki zostają.
ARGI_USTAWIEN=(--arg notatki "$NOTATKI" --arg serwer "$SERWER" --arg skrzynka "$SKRZYNKA" --arg zaufane "$SERWER/zaufane"
  --arg lab "$LAB_DIR" --arg projekty "$FAB_HOME/projekty" --arg dom "$FAB_HOME"
  --arg zestaw "$ZESTAW" --arg tryb "$TRYB"
  --arg porzadki "$LIB/obserwator/narzedzia/porzadki-notatek.sh"
  --arg porzadki_miesiac "$LIB/obserwator/narzedzia/porzadki-notatek.sh --co-miesiac"
  --arg stary_porzadki "$OBS_DIR/narzedzia/porzadki-notatek.sh"
  --arg stary_porzadki_miesiac "$OBS_DIR/narzedzia/porzadki-notatek.sh --co-miesiac"
  --arg archiwum_notatek "$ARCHIWUM_NOTATEK")
WARUNEK_USTAWIEN='(if $tryb == "autor" then [$serwer, $lab, $projekty] else [$serwer, $projekty, $zestaw] end) as $foldery
  | ((if $tryb == "autor" then ["Edit(/\($lab)/**)"] else [] end) + ["Edit(/\($projekty)/**)"]) as $zakazy
  | .cleanupPeriodDays == 365 and .autoMemoryDirectory == $notatki
  and .inputNeededNotifEnabled == true and .agentPushNotifEnabled == true and .remoteControlAtStartup == true
  and ($foldery - (.permissions.additionalDirectories // []) | length == 0)
  and ([.permissions.additionalDirectories[]? | select(type == "string" and (. == $dom or startswith($dom + "/")))
      | select(. as $f | any($foldery[]; . == $f) | not)] | length == 0)
  and (["Edit(/\($skrzynka)/**)", "Edit(/\($archiwum_notatek)/**)"] - (.permissions.allow // []) | length == 0)
  and ([.permissions.allow[]? | select(contains($zaufane) or contains($dom))] | length == 0)
  and ($zakazy - (.permissions.deny // []) | length == 0)
  and ($tryb == "autor" or (any(.permissions.deny[]?; . == "Edit(/\($lab)/**)") | not))
  and any(.hooks.SessionStart[]?.hooks[]?; .type == "command" and .command == $porzadki)
  and any(.hooks.UserPromptSubmit[]?.hooks[]?; .type == "command" and .command == $porzadki_miesiac)
  and (any(.hooks.SessionStart[]?.hooks[]?; .type == "command" and .command == $stary_porzadki) | not)
  and (any(.hooks.UserPromptSubmit[]?.hooks[]?; .type == "command" and .command == $stary_porzadki_miesiac) | not)'
FILTR_USTAWIEN='(if $tryb == "autor" then [$serwer, $lab, $projekty] else [$serwer, $projekty, $zestaw] end) as $foldery
  | ((if $tryb == "autor" then ["Edit(/\($lab)/**)"] else [] end) + ["Edit(/\($projekty)/**)"]) as $zakazy
  | . + {cleanupPeriodDays: 365, autoMemoryDirectory: $notatki,
  inputNeededNotifEnabled: true, agentPushNotifEnabled: true, remoteControlAtStartup: true}
  | .permissions = (.permissions // {})
  | .permissions.additionalDirectories = ((.permissions.additionalDirectories // [])
      | map(select((type == "string" and (. == $dom or startswith($dom + "/"))
          and (. as $f | any($foldery[]; . == $f) | not)) | not))
        as $a | $a + ($foldery - $a))
  | .permissions.allow = ((.permissions.allow // []) | map(select((contains($zaufane) or contains($dom)) | not)) as $a
      | $a + (["Edit(/\($skrzynka)/**)", "Edit(/\($archiwum_notatek)/**)"] - $a))
  | .permissions.deny = ((.permissions.deny // []) | map(select((. == "Edit(/\($lab)/**)" and $tryb != "autor") | not))
      as $a | $a + ($zakazy - $a))
  | .hooks = (.hooks // {})
  | .hooks.SessionStart = ((.hooks.SessionStart // [])
      | map(if any(.hooks[]?; .type == "command" and .command == $stary_porzadki)
          then (.hooks |= map(select((.type == "command" and .command == $stary_porzadki) | not)))
            | select(.hooks | length > 0)
          else . end) as $s
      | if any($s[]?.hooks[]?; .type == "command" and .command == $porzadki) then $s
        else $s + [{hooks: [{type: "command", command: $porzadki}]}] end)
  | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
      | map(if any(.hooks[]?; .type == "command" and .command == $stary_porzadki_miesiac)
          then (.hooks |= map(select((.type == "command" and .command == $stary_porzadki_miesiac) | not)))
            | select(.hooks | length > 0)
          else . end) as $s
      | if any($s[]?.hooks[]?; .type == "command" and .command == $porzadki_miesiac) then $s
        else $s + [{hooks: [{type: "command", command: $porzadki_miesiac}]}] end)'
if ! sudo -u obserwator test -s "$OBS_SETTINGS"; then
  printf '{}\n' | sudo -u obserwator tee "$OBS_SETTINGS" > /dev/null
fi
if sudo -u obserwator jq -e "${ARGI_USTAWIEN[@]}" "$WARUNEK_USTAWIEN" "$OBS_SETTINGS" > /dev/null 2>&1; then
  gotowe "ustawienia Claude Code obserwatora już są"
else
  if ! sudo -u obserwator jq "${ARGI_USTAWIEN[@]}" "$FILTR_USTAWIEN" "$OBS_SETTINGS" > "$TMP/settings.json"; then
    przerwij "Ustawienia Claude Code obserwatora (.claude/settings.json) nie są poprawnym JSON-em."
  fi
  sudo -u obserwator tee "$OBS_SETTINGS" < "$TMP/settings.json" > /dev/null
  gotowe "ustawienia Claude Code obserwatora scalone (inne klucze bez zmian)"
fi

# Zaufanie folderu obserwatora i koniec wprowadzenia: bez tego sesja bez terminala się zatrzyma.
WARUNEK_STANU='.hasCompletedOnboarding == true and .projects[$folder].hasTrustDialogAccepted == true'
FILTR_STANU='.hasCompletedOnboarding = true | .projects[$folder].hasTrustDialogAccepted = true'
if ! sudo -u obserwator test -s "$OBS_STAN"; then
  printf '{}\n' | sudo -u obserwator tee "$OBS_STAN" > /dev/null
fi
if sudo -u obserwator jq -e --arg folder "$OBS_DIR" "$WARUNEK_STANU" "$OBS_STAN" > /dev/null 2>&1; then
  gotowe "zaufanie folderu obserwatora już jest"
else
  if ! sudo -u obserwator jq --arg folder "$OBS_DIR" "$FILTR_STANU" "$OBS_STAN" > "$TMP/claude.json"; then
    przerwij "Stan Claude Code obserwatora (.claude.json) nie jest poprawnym JSON-em."
  fi
  sudo -u obserwator tee "$OBS_STAN" < "$TMP/claude.json" > /dev/null
  gotowe "zaufanie folderu obserwatora zapisane (inne klucze bez zmian)"
fi

# --- 7. usługa obserwatora ---------------------------------------------------------------------------------

etap 7 "Usługa sesji obserwatora"
ZMIANA_USLUGI=0
if zainstaluj_plik "$POBRANE/obserwator.service" "$JEDNOSTKI/obserwator.service" 0644; then
  ZMIANA_USLUGI=1
  systemctl daemon-reload
fi
systemctl enable obserwator.service > /dev/null 2>&1 || przerwij "Nie mogę włączyć usługi obserwator.service."
if { [ "$ZMIANA_USLUGI" -eq 1 ] || [ "$ZMIANA_SKILLA" -eq 1 ] || [ "$ZMIANA_SERWERA" -eq 1 ]; } \
  && systemctl is-active --quiet obserwator.service; then
  systemctl restart obserwator.service || napisz "  Uwaga: usługa obserwator.service nie wystartowała; szczegóły na liście sprawdzeń."
else
  systemctl start obserwator.service || napisz "  Uwaga: usługa obserwator.service nie wystartowała; szczegóły na liście sprawdzeń."
fi

ekran_obserwatora() {
  sudo -u obserwator tmux capture-pane -p -t obserwator 2> /dev/null || true
}

PYTANIE=0
for _ in $(seq 1 20); do
  sleep 1
  case "$(ekran_obserwatora)" in
    *"(y/n)"*)
      PYTANIE=1
      break
      ;;
  esac
done
if [ "$PYTANIE" -eq 1 ]; then
  napisz "  Sesja obserwatora czeka na jednorazową odpowiedź. Ekran sesji:"
  ekran_obserwatora | tail -n 8 | tee -a "$LOG"
  napisz "  Po Enterze instalator otworzy ekran sesji poleceniem:"
  napisz "    sudo -u obserwator tmux attach -t obserwator"
  napisz "  Wpisz y i Enter, potem naciśnij Ctrl-b, a następnie d, żeby wrócić do instalatora."
  read -r _ || true
  sudo -u obserwator tmux attach -t obserwator || true
fi
if pgrep -u obserwator -f remote-control > /dev/null; then
  gotowe "sesja obserwatora działa z Remote Control"
else
  napisz "  Uwaga: brak procesu remote-control. Ekran sesji:"
  ekran_obserwatora | tail -n 8 | tee -a "$LOG"
  napisz "  Sprawdź: sudo -u obserwator tmux attach -t obserwator (wyjście: Ctrl-b, potem d)."
fi

# --- 8. retencja archiwum ----------------------------------------------------------------------------------

etap 8 "Codzienna retencja archiwum obserwatora (bez notatek i archiwum notatek)"
ZMIANA_RETENCJI=0
if zainstaluj_plik "$POBRANE/fabryka-retencja-obserwatora.service" \
  "$JEDNOSTKI/fabryka-retencja-obserwatora.service" 0644; then
  ZMIANA_RETENCJI=1
fi
if zainstaluj_plik "$POBRANE/fabryka-retencja-obserwatora.timer" \
  "$JEDNOSTKI/fabryka-retencja-obserwatora.timer" 0644; then
  ZMIANA_RETENCJI=1
fi
if [ "$ZMIANA_RETENCJI" -eq 1 ]; then
  systemctl daemon-reload
fi
systemctl enable --now fabryka-retencja-obserwatora.timer > /dev/null 2>&1 \
  || przerwij "Nie mogę włączyć zadania fabryka-retencja-obserwatora.timer."
gotowe "zadanie retencji włączone (pliki archiwum starsze niż 365 dni; notatki i archiwum notatek zostają)"

# --- 9. pliki Factory ---------------------------------------------------------------------------------------

etap 9 "Pliki Factory"

# skille_laboratorium: nazwy folderów skilli klonu, po jednej w linii (czyta konto fabryka).
skille_laboratorium() {
  sudo -u fabryka -H find "$LAB_DIR/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
}

# skille_zainstalowane: nazwy skilli, które instalator skopiował wcześniej, po jednej w linii: linie zapisu
# $FAB_SKILLE_ZAPIS; bez zapisu, gdy klon był przed tym uruchomieniem (KLON_BYL=1), nazwy folderów skills/<nazwa>/
# z historii klonu (instalacje sprzed zapisu); na świeżym klonie nic. Czyta konto fabryka; błąd gita daje kod 1.
skille_zainstalowane() {
  local historia
  if sudo -u fabryka -H test -f "$FAB_SKILLE_ZAPIS"; then
    sudo -u fabryka -H cat -- "$FAB_SKILLE_ZAPIS"
  elif [ "${KLON_BYL:-0}" = 1 ]; then
    historia=$(sudo -u fabryka -H git -C "$LAB_DIR" log --format= --name-only -- skills/) || return 1
    printf '%s\n' "$historia" | awk -F/ 'NF > 2 && $1 == "skills" { print $2 }' | sort -u
  fi
}

# skille_fabryki: folder każdego skilla laboratorium w ~/.claude/skills konta fabryka zastępuje kopia z klonu.
# Potem usuwa folder albo dowiązanie każdego skilla ze skille_zainstalowane, którego klon już nie ma, i wypisuje
# każdy usunięty; nazwa spoza wzoru ^[A-Za-z0-9][A-Za-z0-9._-]*$ (np. z „..” albo „/”) nie jest usuwana. Na końcu
# zapis $FAB_SKILLE_ZAPIS dostaje nazwy skilli klonu (plik tymczasowy i mv). Usuwanie i zapis tylko wtedy, gdy klon
# stoi na gałęzi master: gałąź zmiany zatrzymanej przed scaleniem nie usuwa skilla, który master dalej uruchamia.
# Inne foldery zostają. Kopiuje, usuwa i zapisuje konto fabryka.
skille_fabryki() {
  local lista wczesniej nazwa nowy_zapis galaz
  lista=$(skille_laboratorium) || przerwij "Nie mogę odczytać skilli laboratorium w $LAB_DIR/skills."
  [ -n "$lista" ] || przerwij "Laboratorium nie ma skilli w $LAB_DIR/skills."
  wczesniej=$(skille_zainstalowane) \
    || przerwij "Nie mogę odczytać skilli, które instalator skopiował wcześniej ($FAB_SKILLE_ZAPIS albo historia skills/ w $LAB_DIR)."
  sudo -u fabryka -H mkdir -p "$FAB_SKILLE"
  while IFS= read -r nazwa; do
    sudo -u fabryka -H rm -rf -- "$FAB_SKILLE/$nazwa"
    sudo -u fabryka -H cp -R -- "$LAB_DIR/skills/$nazwa" "$FAB_SKILLE/$nazwa"
  done <<< "$lista"
  galaz=$(sudo -u fabryka -H git -C "$LAB_DIR" symbolic-ref --short -q HEAD) || galaz=""
  if [ "$galaz" != master ]; then
    gotowe "skille spoza klonu nie są usuwane: klon laboratorium nie jest na gałęzi master (${galaz:-odłączony HEAD})"
    gotowe "skille laboratorium skopiowane do $FAB_SKILLE"
    return 0
  fi
  while IFS= read -r nazwa; do
    [[ "$nazwa" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
    if grep -qxF -- "$nazwa" <<< "$lista"; then
      continue
    fi
    if sudo -u fabryka -H test -e "$FAB_SKILLE/$nazwa" || sudo -u fabryka -H test -L "$FAB_SKILLE/$nazwa"; then
      sudo -u fabryka -H rm -rf -- "$FAB_SKILLE/$nazwa"
      gotowe "usunięty skill $nazwa: fabryka go zainstalowała, a laboratorium go już nie ma"
    fi
  done <<< "$wczesniej"
  sudo -u fabryka -H mkdir -p -- "${FAB_SKILLE_ZAPIS%/*}"
  nowy_zapis=$(sudo -u fabryka -H mktemp -- "$FAB_SKILLE_ZAPIS.XXXXXX") \
    || przerwij "Nie mogę zapisać listy skilli w ${FAB_SKILLE_ZAPIS%/*}."
  printf '%s\n' "$lista" | sudo -u fabryka -H tee -- "$nowy_zapis" > /dev/null
  sudo -u fabryka -H mv -f -- "$nowy_zapis" "$FAB_SKILLE_ZAPIS"
  gotowe "skille laboratorium skopiowane do $FAB_SKILLE"
}

# Hak startu sesji konta fabryka w bloku jak w docs/start-projektu.md; inne klucze zostają, bez duplikatu. Polecenie
# haka z folderu Factory drugiego trybu ($stary) znika, a blok, który miał tylko je, znika razem z nim.
WARUNEK_HAKA='any(.hooks.SessionStart[]?.hooks[]?; .type == "command" and .command == $polecenie)
  and (any(.hooks.SessionStart[]?.hooks[]?; .type == "command" and .command == $stary) | not)'
FILTR_HAKA='.hooks = (.hooks // {})
  | .hooks.SessionStart = (((.hooks.SessionStart // [])
      | map(if any(.hooks[]?; .type == "command" and .command == $stary)
          then (.hooks |= map(select((.type == "command" and .command == $stary) | not))) | select(.hooks | length > 0)
          else . end)) as $s
      | if any($s[]?.hooks[]?; .type == "command" and .command == $polecenie) then $s
        else $s + [{hooks: [{type: "command", command: $polecenie}]}] end)'

# ustawienia_fabryki: hak startu sesji z folderu Factory trybu (HAK_FABRYKI) w ~/.claude/settings.json konta fabryka
# (pusty {}, gdy pliku nie ma), bez polecenia haka drugiego trybu (HAK_INNEGO_TRYBU); niepoprawny JSON przerywa
# instalator.
ustawienia_fabryki() {
  sudo -u fabryka -H mkdir -p "$FAB_HOME/.claude"
  if ! sudo -u fabryka -H test -s "$FAB_SETTINGS"; then
    printf '{}\n' | sudo -u fabryka -H tee "$FAB_SETTINGS" > /dev/null
  fi
  if sudo -u fabryka -H jq -e --arg polecenie "$HAK_FABRYKI" --arg stary "$HAK_INNEGO_TRYBU" "$WARUNEK_HAKA" \
    "$FAB_SETTINGS" > /dev/null 2>&1; then
    gotowe "hak startu sesji w ustawieniach Claude Code konta fabryka już jest"
    return 0
  fi
  if ! sudo -u fabryka -H jq --arg polecenie "$HAK_FABRYKI" --arg stary "$HAK_INNEGO_TRYBU" "$FILTR_HAKA" \
    "$FAB_SETTINGS" > "$TMP/settings-fabryki.json"; then
    przerwij "Ustawienia Claude Code konta fabryka (.claude/settings.json) nie są poprawnym JSON-em."
  fi
  sudo -u fabryka -H tee "$FAB_SETTINGS" < "$TMP/settings-fabryki.json" > /dev/null
  gotowe "hak startu sesji z $FOLDER_FABRYKI w ustawieniach Claude Code konta fabryka (inne klucze bez zmian)"
}

# przejscie_skilli_fabryki: tryb użytkownika. Konto fabryka przenosi każdy skill ze skille_zainstalowane (zapis
# $FAB_SKILLE_ZAPIS, a bez zapisu historia skills/ klonu sprzed tego uruchomienia) z ~/.claude/skills do
# ~/.local/state/fabryka/skille-przed-instalatorem-$CZAS/, bo skille Factory są już w $ZARZADZANE, a kopia w folderze
# skilli dalej byłaby skillem. Potem usuwa zapis. Nazwa spoza wzoru ^[A-Za-z0-9][A-Za-z0-9._-]*$ zostaje; inne foldery
# skilli, projekty i klon zostają.
przejscie_skilli_fabryki() {
  local nazwy nazwa kopia="$FAB_HOME/.local/state/fabryka/skille-przed-instalatorem-$CZAS" przeniesione=0
  nazwy=$(skille_zainstalowane) \
    || przerwij "Nie mogę odczytać skilli, które instalator skopiował wcześniej ($FAB_SKILLE_ZAPIS albo historia skills/ w $LAB_DIR)."
  while IFS= read -r nazwa; do
    [[ "$nazwa" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
    if sudo -u fabryka -H test -e "$FAB_SKILLE/$nazwa" || sudo -u fabryka -H test -L "$FAB_SKILLE/$nazwa"; then
      if [ "$przeniesione" = 0 ]; then
        sudo -u fabryka -H mkdir -p -- "$kopia"
      fi
      sudo -u fabryka -H mv -- "$FAB_SKILLE/$nazwa" "$kopia/$nazwa" \
        || przerwij "Konto fabryka nie może przenieść skilla $FAB_SKILLE/$nazwa do $kopia."
      przeniesione=1
      gotowe "kopia skilla Factory $nazwa przeniesiona z $FAB_SKILLE do $kopia"
    fi
  done <<< "$nazwy"
  sudo -u fabryka -H rm -f -- "$FAB_SKILLE_ZAPIS"
}

# zestaw_fabryki: tryb użytkownika. Wzór zestawu to archiwum rozpakowane w $TMP/zestaw przed pobraniem plików: z wydania
# WERSJA (archiwum_z_wydania) albo z --zestaw (archiwum_z_opcji). drzewo_roota kładzie zestaw w $ZESTAW i skille zestawu
# ze skillem porzadki-notatek Maestro z pobranych plików w $ZARZADZANE.
zestaw_fabryki() {
  [ -d "$TMP/zestaw/skills" ] || przerwij "Zestaw Factory nie ma folderu skills."
  [ ! -e "$TMP/zestaw/skills/porzadki-notatek" ] || przerwij "Zestaw Factory ma skill porzadki-notatek, który jest skillem Maestro."
  mkdir -p -- "$TMP/zarzadzane/porzadki-notatek"
  cp -R -- "$TMP/zestaw/skills/." "$TMP/zarzadzane/"
  cp -- "$POBRANE/obserwator/skills/porzadki-notatek/SKILL.md" "$TMP/zarzadzane/porzadki-notatek/SKILL.md"
  folder_systemu "${ZARZADZANE%/.claude/skills}" root:root 0755
  drzewo_roota "$TMP/zestaw" "$ZESTAW" zestaw
  drzewo_roota "$TMP/zarzadzane" "$ZARZADZANE" zarzadzane
  gotowe "zestaw Factory $(head -n 1 -- "$ZESTAW/WERSJA") w $ZESTAW, skille Factory w $ZARZADZANE"
}

# tozsamosc_gita: gdy konto fabryka nie ma globalnej tożsamości gita (user.name), ustawia ją: w trybie autora z lokalnej
# konfiguracji klonu laboratorium, w trybie użytkownika z konta GitHub fabryki (login i adres
# <id>+<login>@users.noreply.github.com). Bez źródła wypisuje uwagę i nic nie zmienia. Czyta i zapisuje konto fabryka.
tozsamosc_gita() {
  local nazwa="" adres="" konto=""
  if [ -n "$(sudo -u fabryka -H git config --global user.name 2> /dev/null || true)" ]; then
    gotowe "globalna tożsamość gita konta fabryka już jest"
    return 0
  fi
  if [ "$TRYB" = autor ]; then
    nazwa=$(sudo -u fabryka -H git -C "$LAB_DIR" config --local user.name 2> /dev/null) || nazwa=""
    adres=$(sudo -u fabryka -H git -C "$LAB_DIR" config --local user.email 2> /dev/null) || adres=""
  else
    konto=$(sudo -u fabryka -H gh api user --jq '"\(.id) \(.login)"' 2> /dev/null) || konto=""
    if [[ "$konto" =~ ^([0-9]+)\ ([A-Za-z0-9-]+)$ ]]; then
      nazwa="${BASH_REMATCH[2]}"
      adres="${BASH_REMATCH[1]}+${BASH_REMATCH[2]}@users.noreply.github.com"
    fi
  fi
  if [ -z "$nazwa" ] || [ -z "$adres" ]; then
    napisz "  Uwaga: konto fabryka nie ma globalnej tożsamości gita i nie mam jej źródła; ustaw ją: sudo -u fabryka -H git config --global user.name <nazwa> i user.email <adres>."
    return 0
  fi
  sudo -u fabryka -H git config --global user.name "$nazwa"
  sudo -u fabryka -H git config --global user.email "$adres"
  gotowe "globalna tożsamość gita konta fabryka ustawiona ($nazwa)"
}

if [ "$TRYB" = autor ]; then
  if sudo -u fabryka test -d "$LAB_DIR/.git"; then
    KLON_BYL=1
    gotowe "klon laboratorium już jest (bez pobierania zmian)"
  else
    KLON_BYL=0
    if [ -z "${FABRYKA_REPO:-}" ]; then
      LOGIN_GITHUB=$(sudo -u fabryka gh api user --jq .login)
      FABRYKA_REPO="$LOGIN_GITHUB/fabryka"
    fi
    if ! sudo -u fabryka gh repo view "$FABRYKA_REPO" > /dev/null 2>&1; then
      napisz "  Nie widzę repozytorium $FABRYKA_REPO na koncie GitHub fabryki."
      read -r -p "  Podaj repozytorium laboratorium (właściciel/nazwa): " FABRYKA_REPO || true
      if ! sudo -u fabryka gh repo view "$FABRYKA_REPO" > /dev/null 2>&1; then
        przerwij "Repozytorium $FABRYKA_REPO nie jest dostępne dla konta GitHub fabryki."
      fi
    fi
    sudo -u fabryka git clone "https://github.com/${FABRYKA_REPO}.git" "$LAB_DIR"
    gotowe "laboratorium sklonowane z $FABRYKA_REPO"
  fi
  if [ -n "$ZESTAW_PLIK" ]; then
    napisz "  Uwaga: w trybie autora Factory działa z klonu laboratorium; archiwum zestawu $ZESTAW_PLIK nie jest kładzione."
  fi
  skille_fabryki
else
  if sudo -u fabryka test -d "$LAB_DIR/.git"; then
    KLON_BYL=1
  else
    KLON_BYL=0
  fi
  zestaw_fabryki
  # Etap 7 startuje sesję obserwatora przed założeniem $ZARZADZANE (ze skillem porzadki-notatek), a działająca sesja
  # nie widzi folderu skilli, którego nie było przy jej starcie: zmiana drzewa $ZARZADZANE restartuje sesję.
  if [ "$DRZEWO_ZMIENIONE" -eq 1 ] && systemctl is-active --quiet obserwator.service; then
    systemctl restart obserwator.service || napisz "  Uwaga: usługa obserwator.service nie wystartowała; szczegóły na liście sprawdzeń."
  fi
  przejscie_skilli_fabryki
fi
ustawienia_fabryki
tozsamosc_gita

# Folder projektów aplikacji konta fabryka (obserwator czyta go przez grupę fabryka); zakłada go konto fabryka.
sudo -u fabryka mkdir -p "$FAB_HOME/projekty"
gotowe "folder $FAB_HOME/projekty jest"

# --- 10. lista sprawdzeń -----------------------------------------------------------------------------------

etap 10 "Lista sprawdzeń"
DZIALA=0
NIE_DZIALA=0

# sprawdz <opis> <co sprawdzić, gdy nie działa> <polecenie...>
sprawdz() {
  local opis="$1" rada="$2"
  shift 2
  if "$@" > /dev/null 2>&1; then
    napisz "  działa:     $opis"
    DZIALA=$((DZIALA + 1))
  else
    napisz "  nie działa: $opis. Sprawdź: $rada"
    NIE_DZIALA=$((NIE_DZIALA + 1))
  fi
}

fabryka_nie_widzi_obserwatora() {
  ! sudo -u fabryka ls "$OBS_HOME" && ! sudo -u fabryka test -w "$OBS_HOME"
}

# obserwator_czyta_laboratorium: obserwator czyta CLAUDE.md folderu Factory trybu (klon laboratorium w trybie autora,
# zestaw w trybie użytkownika) i folder projektów.
obserwator_czyta_laboratorium() {
  sudo -u obserwator cat "$FOLDER_FABRYKI/CLAUDE.md" > /dev/null && sudo -u obserwator ls "$FAB_HOME/projekty" > /dev/null
}

regula_sudo_obserwatora() {
  local wynik reguly
  wynik=$(sudo -l -U obserwator 2>&1) || return 1
  reguly=$(printf '%s\n' "$wynik" | grep -E '^[[:space:]]+\(' | sed 's/^[[:space:]]*//') || return 1
  [ "$reguly" = "(fabryka) NOPASSWD: $LIB/start-fabryki.sh" ]
}

obserwator_bez_pelnego_sudo() {
  ! sudo -u obserwator sudo -n true
}

fabryka_bez_sudo() {
  local wynik
  # Dodatni sygnał: błąd sudo -l albo nieznany format wyjścia to "nie działa", a nie "działa".
  wynik=$(LC_ALL=C sudo -l -U fabryka 2>&1 || true)
  case "$wynik" in
    *"is not allowed to run sudo"*) ;;
    *) return 1 ;;
  esac
  ! printf '%s\n' "$wynik" | grep -qE '^[[:space:]]+\('
}

remote_control_obserwatora() {
  pgrep -u obserwator -f remote-control > /dev/null || return 1
  # Proces startuje z --remote-control w wierszu polecenia, zanim sesja odpowie na pytanie (y/n).
  case "$(ekran_obserwatora)" in
    *"(y/n)"*) return 1 ;;
  esac
  return 0
}

grupy_kont() {
  ! w_grupie fabryka sudo && ! w_grupie fabryka docker && w_grupie obserwator fabryka
}

docker_bez_roota() {
  local opcje
  opcje=$(jako_fabryka_z_sesja env "DOCKER_HOST=unix://$FAB_RUN/docker.sock" docker info --format '{{.SecurityOptions}}') \
    || return 1
  case "$opcje" in
    *rootless*) return 0 ;;
  esac
  return 1
}

# przegladarka_testow: dodatni sygnał; konto fabryka zapisuje próbny plik w swoim folderze tymczasowym w /tmp,
# a kontener obrazu przeglądarki bez sieci otwiera go z dysku z parametrem w adresie: --dump-dom ma tekst parametru,
# a --screenshot daje plik PNG. Folder sprząta konto fabryka; root nie otwiera ścieżek pod /home.
przegladarka_testow() {
  local folder dom naglowek wynik=1
  folder=$(sudo -u fabryka mktemp -d /tmp/fabryka-przegladarka.XXXXXX) || return 1
  if printf '%s' "$PROBA_PRZEGLADARKI" | sudo -u fabryka tee "$folder/proba.html" > /dev/null \
    && dom=$(docker_fabryki run --rm --network none -v "$folder:/m:ro" "$OBRAZ_PRZEGLADARKI" "$PRZEGLADARKA" \
      --no-sandbox --dump-dom 'file:///m/proba.html?state=proba') \
    && docker_fabryki run --rm --network none -v "$folder:/m" "$OBRAZ_PRZEGLADARKI" "$PRZEGLADARKA" \
      --no-sandbox --hide-scrollbars --window-size=1280,800 --screenshot=/m/proba.png 'file:///m/proba.html?state=proba' \
    && naglowek=$(sudo -u fabryka head -c 8 "$folder/proba.png" | od -An -tx1 | tr -d ' \n'); then
    case "$dom" in
      *"<body>proba</body>"*) [ "$naglowek" = "89504e470d0a1a0a" ] && wynik=0 ;;
    esac
  fi
  sudo -u fabryka rm -rf -- "$folder"
  return "$wynik"
}

klon_laboratorium() {
  sudo -u fabryka git -C "$LAB_DIR" status --porcelain > /dev/null
}

# skille_fabryki_rowne_klonowi: dodatni sygnał; kod 0 tylko, gdy klon ma skille i folder każdego z nich
# w ~/.claude/skills konta fabryka ma tę samą treść.
skille_fabryki_rowne_klonowi() {
  local lista nazwa
  lista=$(skille_laboratorium) || return 1
  [ -n "$lista" ] || return 1
  while IFS= read -r nazwa; do
    sudo -u fabryka -H diff -r -q -- "$LAB_DIR/skills/$nazwa" "$FAB_SKILLE/$nazwa" > /dev/null || return 1
  done <<< "$lista"
}

# drzewo_rowne_wzorowi <cel> <nazwa>: dodatni sygnał; cel jest folderem (nie dowiązaniem), a jego sumy (sumy_drzewa)
# równają się liście $WZORY/<nazwa>.sumy ostatnio położonego wzoru.
drzewo_rowne_wzorowi() {
  local stan
  [ -s "$WZORY/$2.sumy" ] && [ -d "$1" ] && [ ! -L "$1" ] || return 1
  stan=$(sumy_drzewa "$1") || return 1
  [ -n "$stan" ] && [ "$stan" = "$(cat -- "$WZORY/$2.sumy")" ]
}

# root_bez_zapisu_innych <folder>: dodatni sygnał; folder (nie dowiązanie) i każdy plik i folder w nim należą do
# root:root bez zapisu dla grupy i innych, a każdy folder nadrzędny aż do / należy do roota bez zapisu dla grupy
# i innych.
root_bez_zapisu_innych() {
  local folder="$1" lista linia nadrzedny
  [ -d "$folder" ] && [ ! -L "$folder" ] || return 1
  lista=$(find "$folder" -print0 | xargs -0 stat -c '%u:%g %a') || return 1
  [ -n "$lista" ] || return 1
  while IFS= read -r linia; do
    [ "${linia%% *}" = "0:0" ] || return 1
    [ $((8#${linia#* } & 8#022)) -eq 0 ] || return 1
  done <<< "$lista"
  nadrzedny=$(dirname -- "$folder")
  while :; do
    linia=$(stat -c '%u:%g %a' -- "$nadrzedny") || return 1
    [ "${linia%%:*}" = 0 ] || return 1
    [ $((8#${linia#* } & 8#022)) -eq 0 ] || return 1
    [ "$nadrzedny" != / ] || break
    nadrzedny=$(dirname -- "$nadrzedny")
  done
}

# konto_nie_zmienia_zestawu <konto>: dodatni sygnał czterech warunków. Root kładzie w $ZESTAW plik próbny i w
# $ZARZADZANE folder próbny skilla; konto nie tworzy nowego pliku w zestawie, nie dopisuje do pliku próbnego, nie usuwa
# go i nie zmienia nazwy folderu skilla. Kod 0 tylko, gdy zachodzą wszystkie cztery; próby sprząta root.
konto_nie_zmienia_zestawu() {
  local konto="$1" wynik=0
  local probny="$ZESTAW/.proba-roota-$$" nowy="$ZESTAW/.proba-$1-$$" skill="$ZARZADZANE/.proba-roota-$$"
  [ -d "$ZESTAW" ] && [ -d "$ZARZADZANE" ] || return 1
  printf 'proba\n' > "$probny" || return 1
  if ! mkdir -- "$skill"; then
    rm -f -- "$probny"
    return 1
  fi
  if sudo -u "$konto" touch "$nowy" 2> /dev/null; then
    wynik=1
  fi
  if sudo -u "$konto" tee -a "$probny" < /dev/null > /dev/null 2>&1; then
    wynik=1
  fi
  sudo -u "$konto" rm -f "$probny" 2> /dev/null || true
  if [ ! -e "$probny" ]; then
    wynik=1
  fi
  if sudo -u "$konto" mv "$skill" "$skill.nowa" 2> /dev/null; then
    wynik=1
  fi
  rm -rf -- "$probny" "$nowy" "$skill" "$skill.nowa"
  return "$wynik"
}

# konto_czyta_zestaw <konto>: konto czyta $ZESTAW/CLAUDE.md i SKILL.md pierwszego skilla w $ZARZADZANE.
konto_czyta_zestaw() {
  local skill
  skill=$(find "$ZARZADZANE" -mindepth 2 -maxdepth 2 -name SKILL.md -print -quit) || return 1
  [ -n "$skill" ] || return 1
  sudo -u "$1" cat "$ZESTAW/CLAUDE.md" > /dev/null && sudo -u "$1" cat "$skill" > /dev/null
}

hak_fabryki() {
  sudo -u fabryka -H jq -e --arg polecenie "$HAK_FABRYKI" --arg stary "$HAK_INNEGO_TRYBU" "$WARUNEK_HAKA" \
    "$FAB_SETTINGS" > /dev/null
}

# bez_zaufanych: folderu $SERWER/zaufane z v1.0.4 nie ma (ani dowiązania o tej nazwie).
bez_zaufanych() {
  [ ! -e "$SERWER/zaufane" ] && [ ! -L "$SERWER/zaufane" ]
}

# plik_serwera <plik w $LIB> <wzór>: dodatni sygnał; plik (nie dowiązanie) należy do root:root bez zapisu dla grupy
# i innych, ma treść wzoru, a konto obserwator go czyta.
plik_serwera() {
  local prawa
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  prawa=$(stat -c '%u:%g %a' -- "$1") || return 1
  [ "${prawa%% *}" = "0:0" ] || return 1
  [ $((8#${prawa#* } & 8#022)) -eq 0 ] || return 1
  cmp -s -- "$2" "$1" && sudo -u obserwator test -r "$1"
}

# umowa_rowna_wzorowi: umowa Maestro w $LIB/obserwator/CLAUDE.md to wzór trybu (w trybie autora z dodatkiem autora).
umowa_rowna_wzorowi() {
  plik_serwera "$LIB/obserwator/CLAUDE.md" "$WZOR_SERWERA/obserwator/CLAUDE.md"
}

wyslij_rowny_wzorowi() {
  plik_serwera "$LIB/obserwator/narzedzia/wyslij.sh" "$POBRANE/obserwator/narzedzia/wyslij.sh" \
    && sudo -u obserwator test -x "$LIB/obserwator/narzedzia/wyslij.sh"
}

porzadki_notatek_rowne_wzorowi() {
  plik_serwera "$LIB/obserwator/narzedzia/porzadki-notatek.sh" "$POBRANE/obserwator/narzedzia/porzadki-notatek.sh" \
    && sudo -u obserwator test -x "$LIB/obserwator/narzedzia/porzadki-notatek.sh"
}

# obserwator_nie_zmienia_umowy: dodatni sygnał czterech warunków. Root kładzie w $LIB/obserwator plik próbny; konto
# obserwator nie dopisuje do umowy ani do pliku próbnego, nie usuwa pliku próbnego i nie tworzy nowego pliku obok
# umowy. Kod 0 tylko, gdy zachodzą wszystkie cztery; próby sprząta root.
obserwator_nie_zmienia_umowy() {
  local folder="$LIB/obserwator" wynik=0
  local probny="$LIB/obserwator/.proba-roota-$$" nowy="$LIB/obserwator/.proba-obserwatora-$$"
  [ -f "$folder/CLAUDE.md" ] || return 1
  printf 'proba\n' > "$probny" || return 1
  if sudo -u obserwator tee -a "$folder/CLAUDE.md" < /dev/null > /dev/null 2>&1; then
    wynik=1
  fi
  if sudo -u obserwator tee -a "$probny" < /dev/null > /dev/null 2>&1; then
    wynik=1
  fi
  sudo -u obserwator rm -f "$probny" 2> /dev/null || true
  if [ ! -e "$probny" ]; then
    wynik=1
  fi
  if sudo -u obserwator touch "$nowy" 2> /dev/null; then
    wynik=1
  fi
  rm -f -- "$probny" "$nowy"
  return "$wynik"
}

# obserwator_bez_skilli_autora: tryb użytkownika, dodatni sygnał; konto obserwator czyta swój folder skilli (albo
# folder domowy, gdy folderu skilli nie ma), a w nim nie ma żadnego skilla z SKILLE_AUTORA.
obserwator_bez_skilli_autora() {
  local lista skill
  if sudo -u obserwator test -d "$OBS_SKILLE"; then
    lista=$(sudo -u obserwator find "$OBS_SKILLE" -mindepth 1 -maxdepth 1 -printf '%f\n') || return 1
  else
    sudo -u obserwator test -d "$OBS_HOME" || return 1
    lista=""
  fi
  for skill in "${SKILLE_AUTORA[@]}"; do
    if grep -qxF -- "$skill" <<< "$lista"; then
      return 1
    fi
  done
}

# skill_obserwatora_rowny_wzorowi <nazwa>: skill obserwatora z SKILLE_OBSERWATORA ma treść pobranego wzoru.
skill_obserwatora_rowny_wzorowi() {
  sudo -u obserwator cmp -s - "$OBS_SKILLE/$1/SKILL.md" \
    < "$POBRANE/obserwator/skills/$1/SKILL.md"
}

ustawienia_obserwatora() {
  sudo -u obserwator jq -e "${ARGI_USTAWIEN[@]}" "$WARUNEK_USTAWIEN" "$OBS_SETTINGS" > /dev/null \
    && sudo -u obserwator jq -e --arg folder "$OBS_DIR" "$WARUNEK_STANU" "$OBS_STAN" > /dev/null
}

# tylko_obserwator_pisze <folder>: dodatni sygnał czterech warunków. Obserwator tworzy plik próbny, fabryka
# nie tworzy nowego pliku, nie dopisuje do próbnego i nie usuwa go, obserwator go usuwa. Kod 0 tylko, gdy
# zachodzą wszystkie cztery; plik, który fabryka wbrew oczekiwaniu zapisała, sprząta root.
tylko_obserwator_pisze() {
  local folder="$1" wynik=0
  local probny="$folder/.proba-obserwatora-$$" nowy="$folder/.proba-fabryki-$$"
  if ! sudo -u obserwator touch "$probny" 2> /dev/null; then
    return 1
  fi
  if sudo -u fabryka touch "$nowy" 2> /dev/null; then
    wynik=1
    rm -f "$nowy"
  fi
  if sudo -u fabryka tee -a "$probny" < /dev/null > /dev/null 2>&1; then
    wynik=1
  fi
  sudo -u fabryka rm -f "$probny" 2> /dev/null || true
  if ! sudo -u obserwator test -e "$probny"; then
    wynik=1
  fi
  if ! sudo -u obserwator rm "$probny" 2> /dev/null; then
    wynik=1
    rm -f "$probny"
  fi
  return "$wynik"
}

# klucze_obserwatora: dodatni sygnał; folder kluczy obserwatora ma tryb 0700 (czyta go konto obserwator), a konto
# fabryka go nie czyta. Root nie otwiera ścieżek pod /home.
klucze_obserwatora() {
  local tryb
  tryb=$(sudo -u obserwator stat -c %a "$OBS_DIR/klucze") || return 1
  [ "$tryb" = "700" ] || return 1
  ! sudo -u fabryka test -r "$OBS_DIR/klucze"
}

# obserwator_przekazuje_fabryce <folder>: dodatni sygnał czterech warunków. Folder ma właściciela obserwator:fabryka
# i tryb 2770; obserwator tworzy plik próbny z umask 027 pod losową nazwą jednym otwarciem, które nie idzie za
# dowiązaniem (O_CREAT|O_EXCL|O_NOFOLLOW; nazwa nie stoi w argumentach procesu), fabryka go czyta i usuwa, a pliku
# potem nie ma. Kod 0 tylko, gdy zachodzą wszystkie cztery; plik, który został po próbie, sprząta root.
obserwator_przekazuje_fabryce() {
  local folder="$1" wynik=0 prawa probny
  local tworz='import os, secrets, sys
p = os.path.join(sys.argv[1], ".proba-przekazania-" + secrets.token_hex(8))
os.close(os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o640))
print(p)'
  prawa=$(stat -c '%U:%G %a' "$folder") || return 1
  [ "$prawa" = "obserwator:fabryka 2770" ] || return 1
  if ! probny=$( (umask 027; sudo -u obserwator python3 -I -c "$tworz" "$folder") 2> /dev/null); then
    return 1
  fi
  case "$probny" in
    "$folder"/.proba-przekazania-*) ;;
    *) return 1 ;;
  esac
  if ! sudo -u fabryka cat "$probny" > /dev/null 2>&1; then
    wynik=1
  fi
  if ! sudo -u fabryka rm -f "$probny" 2> /dev/null; then
    wynik=1
  fi
  if [ -e "$probny" ] || [ -L "$probny" ]; then
    wynik=1
    rm -f "$probny"
  fi
  return "$wynik"
}

# ocena_w_skrzynce <folder> <konto>: dodatni sygnał trzech warunków. Konto obserwator zapisuje w folderze plik próbny
# pod losową nazwą jednym otwarciem, które nie idzie za dowiązaniem, tak jak plik oceny Maestro
# (ocena-<change-id>.md, zapisany narzędziem Write); konto fabryka otwiera go bez podążania za dowiązaniem i widzi
# zwykły plik z treścią próby, którego właścicielem jest <konto> (tak sprawdza ocenę ocena_problem w
# scripts/przebieg_rozmowy.py laboratorium); obserwator go potem usuwa. Kod 0 tylko, gdy zachodzą wszystkie trzy;
# plik, który został po próbie, sprząta root.
ocena_w_skrzynce() {
  local folder="$1" konto="$2" wynik=0 probny
  local tworz='import os, secrets, sys
p = os.path.join(sys.argv[1], ".proba-oceny-" + secrets.token_hex(8))
fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
os.write(fd, b"commit: proba\n")
os.close(fd)
print(p)'
  local czytaj='import os, pwd, stat, sys
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
info = os.fstat(fd)
dane = os.read(fd, 64)
os.close(fd)
wlasciciel = pwd.getpwnam(sys.argv[2]).pw_uid
sys.exit(0 if stat.S_ISREG(info.st_mode) and info.st_uid == wlasciciel and dane == b"commit: proba\n" else 1)'
  if ! probny=$(sudo -u obserwator python3 -I -c "$tworz" "$folder" 2> /dev/null); then
    return 1
  fi
  case "$probny" in
    "$folder"/.proba-oceny-*) ;;
    *) return 1 ;;
  esac
  if ! sudo -u fabryka python3 -I -c "$czytaj" "$probny" "$konto" 2> /dev/null; then
    wynik=1
  fi
  if ! sudo -u obserwator rm -f "$probny" 2> /dev/null; then
    wynik=1
  fi
  if [ -e "$probny" ] || [ -L "$probny" ]; then
    wynik=1
    rm -f "$probny"
  fi
  return "$wynik"
}

gitleaks_w_wersji_szablonu() {
  local wynik
  wynik=$(sudo -u fabryka gitleaks version 2>&1) || return 1
  case "$wynik" in
    *"$GITLEAKS_WERSJA"*) return 0 ;;
  esac
  return 1
}

mise_w_wersji_instalatora() {
  local wynik
  wynik=$(sudo -u fabryka mise --version 2>&1) || return 1
  case "$wynik" in
    *"$MISE_WERSJA"*) return 0 ;;
  esac
  return 1
}

umask_kont() {
  local konto
  for konto in fabryka obserwator; do
    case "$(getent passwd "$konto" | cut -d: -f5)" in
      *umask=022*) ;;
      *) return 1 ;;
    esac
  done
}

sprawdz "konto fabryka nie czyta i nie zmienia katalogu obserwatora" \
  "tryb 0700 katalogu $OBS_HOME (ls -ld $OBS_HOME)" fabryka_nie_widzi_obserwatora
sprawdz "obserwator czyta pliki Factory i projektów" \
  "tryb 0750 katalogu $FAB_HOME, grupę fabryka obserwatora (id obserwator), plik $FOLDER_FABRYKI/CLAUDE.md i folder $FAB_HOME/projekty" \
  obserwator_czyta_laboratorium
sprawdz "jedyna reguła sudo obserwatora to skrypt startowy fabryki" \
  "sudo -l -U obserwator i plik $SUDOERS_CEL" regula_sudo_obserwatora
sprawdz "obserwator nie ma pełnego sudo" "sudo -l -U obserwator" obserwator_bez_pelnego_sudo
sprawdz "konto fabryka nie ma reguł sudo" "sudo -l -U fabryka i pliki w /etc/sudoers.d" fabryka_bez_sudo
sprawdz "grupy: fabryka poza sudo i docker, obserwator w grupie fabryka" "id fabryka i id obserwator" grupy_kont
sprawdz "Claude obserwatora zalogowany" "uruchom instalator ponownie i zaloguj konto" \
  sudo -u obserwator "$OBS_CLAUDE" auth status
sprawdz "Claude fabryki zalogowany" "uruchom instalator ponownie i zaloguj konto" \
  sudo -u fabryka "$FAB_CLAUDE" auth status
sprawdz "GitHub fabryki zalogowany" "sudo -u fabryka gh auth status" sudo -u fabryka gh auth status
sprawdz "Docker bez roota na koncie fabryka" "systemctl --user status docker na koncie fabryka" docker_bez_roota
sprawdz "przeglądarka do testów aplikacji otwiera bez sieci próbny plik z parametrem w adresie i robi jego zrzut" \
  "obraz przeglądarki na koncie fabryka (docker image inspect $OBRAZ_PRZEGLADARKI); uruchom instalator ponownie" \
  przegladarka_testow
sprawdz "mise dla konta fabryka ($MISE_WERSJA)" \
  "sudo -u fabryka mise --version i plik /usr/local/bin/mise" mise_w_wersji_instalatora
sprawdz "gitleaks w wersji z szablonu CI ($GITLEAKS_WERSJA)" \
  "sudo -u fabryka gitleaks version i plik /usr/local/bin/gitleaks" gitleaks_w_wersji_szablonu
if [ "$TRYB" = autor ]; then
  sprawdz "laboratorium sklonowane" "folder $LAB_DIR" klon_laboratorium
  sprawdz "skille laboratorium w ~/.claude/skills konta fabryka równe klonowi" \
    "foldery $LAB_DIR/skills i $FAB_SKILLE (uruchom instalator ponownie)" skille_fabryki_rowne_klonowi
else
  sprawdz "zestaw Factory w $ZESTAW równy wzorowi" "uruchom instalator ponownie (przywróci zestaw)" \
    drzewo_rowne_wzorowi "$ZESTAW" zestaw
  sprawdz "skille Factory w $ZARZADZANE równe wzorowi" "uruchom instalator ponownie (przywróci skille)" \
    drzewo_rowne_wzorowi "$ZARZADZANE" zarzadzane
  sprawdz "zestaw Factory i jego foldery nadrzędne należą do roota bez zapisu dla grupy i innych" \
    "ls -ld $ZESTAW i find $ZESTAW ! -user root" root_bez_zapisu_innych "$ZESTAW"
  sprawdz "skille Factory i ich foldery nadrzędne należą do roota bez zapisu dla grupy i innych" \
    "ls -ld $ZARZADZANE i find $ZARZADZANE ! -user root" root_bez_zapisu_innych "$ZARZADZANE"
  for konto in fabryka obserwator; do
    sprawdz "konto $konto nie tworzy, nie zmienia i nie usuwa plików zestawu ani nie zmienia nazwy folderu skilla" \
      "właściciel root i tryby $ZESTAW i $ZARZADZANE (ls -ld)" konto_nie_zmienia_zestawu "$konto"
    sprawdz "konto $konto czyta zestaw Factory i skille Factory" \
      "tryby $ZESTAW i $ZARZADZANE (ls -ld)" konto_czyta_zestaw "$konto"
  done
  sprawdz "w ~/.claude/skills obserwatora nie ma skilli autora (${SKILLE_AUTORA[*]})" \
    "folder $OBS_SKILLE (sudo -u obserwator ls $OBS_SKILLE); uruchom instalator ponownie" obserwator_bez_skilli_autora
fi
sprawdz "hak startu sesji z $FOLDER_FABRYKI w ustawieniach Claude Code konta fabryka" "plik $FAB_SETTINGS" hak_fabryki
sprawdz "umowa obserwatora równa wzorowi" "plik $LIB/obserwator/CLAUDE.md (ls -l)" \
  umowa_rowna_wzorowi
sprawdz "konto obserwator nie zmienia umowy" "właściciel root i tryby $LIB/obserwator (ls -ld)" \
  obserwator_nie_zmienia_umowy
sprawdz "narzędzie wysyłania obserwatora równe wzorowi i wykonywalne" \
  "plik $LIB/obserwator/narzedzia/wyslij.sh (ls -l)" wyslij_rowny_wzorowi
sprawdz "narzędzie sprawdzenia notatek obserwatora równe wzorowi i wykonywalne" \
  "plik $LIB/obserwator/narzedzia/porzadki-notatek.sh (ls -l)" porzadki_notatek_rowne_wzorowi
sprawdz "folder archiwum notatek jest" "sudo -u obserwator ls -ld $ARCHIWUM_NOTATEK" \
  sudo -u obserwator test -d "$ARCHIWUM_NOTATEK"
if [ "$TRYB" = autor ]; then
  for skill in "${SKILLE_OBSERWATORA[@]}"; do
    sprawdz "skill obserwatora $skill równy wzorowi" "plik $OBS_SKILLE/$skill/SKILL.md" \
      skill_obserwatora_rowny_wzorowi "$skill"
  done
fi
sprawdz "ustawienia Claude Code obserwatora" "pliki $OBS_SETTINGS i $OBS_STAN" ustawienia_obserwatora
sprawdz "usługa obserwator.service działa" "systemctl status obserwator.service" \
  systemctl is-active --quiet obserwator.service
sprawdz "zadanie retencji archiwum włączone" "systemctl list-timers fabryka-retencja-obserwatora.timer" \
  systemctl is-active --quiet fabryka-retencja-obserwatora.timer
sprawdz "proces remote-control obserwatora działa i nie czeka na pytanie (y/n)" \
  "sudo -u obserwator tmux attach -t obserwator (wpisz y, wyjście: Ctrl-b, potem d)" remote_control_obserwatora
sprawdz "umask 022 kont fabryka i obserwator" "pole GECOS: getent passwd fabryka obserwator" umask_kont
sprawdz "skrzynkę pisze i czyści tylko obserwator, fabryka nie zapisuje ani nie usuwa" \
  "właściciel obserwator:fabryka i tryb 2750 folderu $SKRZYNKA (ls -ld $SKRZYNKA)" tylko_obserwator_pisze "$SKRZYNKA"
sprawdz "ocenę Maestro w skrzynce czyta konto fabryka, a jej właścicielem jest obserwator" \
  "właściciel obserwator:fabryka i tryb 2750 folderu $SKRZYNKA (ls -ld $SKRZYNKA) i umask 022 obserwatora" \
  ocena_w_skrzynce "$SKRZYNKA" obserwator
sprawdz "klucze obserwatora 0700, fabryka ich nie czyta" \
  "tryb 0700 folderu $OBS_DIR/klucze (sudo -u obserwator ls -ld $OBS_DIR/klucze)" klucze_obserwatora
sprawdz "przekazanie: obserwator kładzie, fabryka czyta i usuwa" \
  "właściciel obserwator:fabryka i tryb 2770 folderu $PRZEKAZANIE (ls -ld $PRZEKAZANIE)" \
  obserwator_przekazuje_fabryce "$PRZEKAZANIE"
sprawdz "folderu $SERWER/zaufane z v1.0.4 nie ma" "ls -ld $SERWER/zaufane" bez_zaufanych
sprawdz "obserwator uruchamia skrypt startowy fabryki" "plik $SUDOERS_CEL i $LIB/start-fabryki.sh" \
  sudo -u obserwator sudo -n -u fabryka "$LIB/start-fabryki.sh"

napisz ""
napisz "Wynik: działa $DZIALA, nie działa $NIE_DZIALA."
napisz "Otwórz Claude Desktop, zakładka Code, sesja »obserwator«."
if [ "$NIE_DZIALA" -eq 0 ]; then
  exit 0
fi
exit 1
