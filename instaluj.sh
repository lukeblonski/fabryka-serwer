#!/usr/bin/env bash
set -euo pipefail

# Instalator fabryki i obserwatora na czysty serwer Ubuntu (Hostinger KVM 2).
# Uruchamiany jako root poleceniem z README.md: pobranie z tagu i sprawdzenie sumy SHA-256.
# Dziesięć kroków; każdy sprawdza stan przed działaniem, więc ponowne uruchomienie jest bezpieczne.
#
# Zasada bezpieczeństwa: root nie otwiera żadnej ścieżki pod /home/. Pliki kont czyta i zapisuje
# konto właściciela (sudo -u <konto> tee, cmp -, cp, rm, mkdir, find, diff, git, jq), a treść przychodzi przez
# standardowe wejście z folderu tymczasowego roota. Root zmienia tylko pliki systemu
# (/etc, /usr/local/lib/fabryka-serwer, /var/lib/fabryka-serwer, /var/log) i tryby samych katalogów domowych.
# Bez "sudo -u <konto> sh -c" i "sudo -u <konto> bash -c".

REPO="lukeblonski/fabryka-serwer"
WERSJA="v1.0.13"

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
  "obserwator/narzedzia/wyslij.sh"
  "obserwator/narzedzia/porzadki-notatek.sh"
  "obserwator/skills/analiza-w-poprzek/SKILL.md"
  "obserwator/skills/przeglad-po-projekcie/SKILL.md"
  "obserwator/skills/porzadki-notatek/SKILL.md"
)

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
# Osobiste skille Claude Code konta obserwator: wzór każdego to obserwator/skills/<nazwa>/SKILL.md z PLIKI.
SKILLE_OBSERWATORA=(analiza-w-poprzek przeglad-po-projekcie porzadki-notatek)
OBS_STAN="$OBS_HOME/.claude.json"
OBS_CLAUDE="$OBS_HOME/.local/bin/claude"
FAB_CLAUDE="$FAB_HOME/.local/bin/claude"
FAB_SKILLE="$FAB_HOME/.claude/skills"
FAB_SETTINGS="$FAB_HOME/.claude/settings.json"
HAK_FABRYKI="python3 -I -B $LAB_DIR/scripts/hook_start_sesji.py"

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

cd /
umask 022
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
POBRANE="$TMP/pliki"

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

install -d -m 0755 -o root -g root "$LIB"
zainstaluj_plik "$POBRANE/start-fabryki.sh" "$LIB/start-fabryki.sh" 0755 || true
zainstaluj_plik "$POBRANE/skrzynka.py" "$LIB/skrzynka.py" 0755 || true
zainstaluj_plik "$POBRANE/start-obserwatora.sh" "$LIB/start-obserwatora.sh" 0755 || true

if ! visudo -c -f "$POBRANE/sudoers-obserwator" > /dev/null; then
  przerwij "Reguła sudo obserwatora nie przechodzi visudo -c -f."
fi
zainstaluj_plik "$POBRANE/sudoers-obserwator" "$SUDOERS_CEL" 0440 || true
if ! visudo -c > /dev/null; then
  przerwij "Konfiguracja sudo nie przechodzi visudo -c po dodaniu reguły obserwatora."
fi
gotowe "skrypty startowe i reguła sudo obserwatora zainstalowane"

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
sudo -u obserwator mkdir -p "$OBS_DIR" "$OBS_DIR/narzedzia" "$NOTATKI" "$ARCHIWUM" "$ARCHIWUM_NOTATEK" "$OBS_HOME/.claude"
# Klucze usług od człowieka (umowa obserwatora, „Panele usług”): folder tylko konta obserwator.
sudo -u obserwator mkdir -p "$OBS_DIR/klucze"
sudo -u obserwator chmod 0700 "$OBS_DIR/klucze"
for skill in "${SKILLE_OBSERWATORA[@]}"; do
  sudo -u obserwator mkdir -p "$OBS_SKILLE/$skill"
done

if sudo -u obserwator test -f "$OBS_DIR/CLAUDE.md"; then
  if sudo -u obserwator cmp -s - "$OBS_DIR/CLAUDE.md" < "$POBRANE/obserwator/CLAUDE.md"; then
    gotowe "umowa obserwatora równa wzorowi"
  else
    KOPIA="$OBS_DIR/CLAUDE.md.przed-instalatorem-$(date +%Y%m%d-%H%M%S)"
    sudo -u obserwator cp "$OBS_DIR/CLAUDE.md" "$KOPIA"
    sudo -u obserwator tee "$OBS_DIR/CLAUDE.md" < "$POBRANE/obserwator/CLAUDE.md" > /dev/null
    gotowe "umowa obserwatora zastąpiona wzorem; poprzednia wersja w $KOPIA"
  fi
else
  sudo -u obserwator tee "$OBS_DIR/CLAUDE.md" < "$POBRANE/obserwator/CLAUDE.md" > /dev/null
  gotowe "umowa obserwatora zapisana"
fi

# Narzędzie wysyłania wiadomości do sesji głównej (umowa, „Rozmowa z sesją główną”): wzór zastępuje inną treść,
# poprzednia wersja zostaje jako kopia zapasowa; bit wykonywania ustawia konto obserwator.
if sudo -u obserwator test -f "$OBS_DIR/narzedzia/wyslij.sh"; then
  if sudo -u obserwator cmp -s - "$OBS_DIR/narzedzia/wyslij.sh" < "$POBRANE/obserwator/narzedzia/wyslij.sh"; then
    gotowe "narzędzie wysyłania obserwatora równe wzorowi"
  else
    KOPIA="$OBS_DIR/narzedzia/wyslij.sh.przed-instalatorem-$(date +%Y%m%d-%H%M%S)"
    sudo -u obserwator cp "$OBS_DIR/narzedzia/wyslij.sh" "$KOPIA"
    sudo -u obserwator tee "$OBS_DIR/narzedzia/wyslij.sh" < "$POBRANE/obserwator/narzedzia/wyslij.sh" > /dev/null
    gotowe "narzędzie wysyłania obserwatora zastąpione wzorem; poprzednia wersja w $KOPIA"
  fi
else
  sudo -u obserwator tee "$OBS_DIR/narzedzia/wyslij.sh" < "$POBRANE/obserwator/narzedzia/wyslij.sh" > /dev/null
  gotowe "narzędzie wysyłania obserwatora zapisane"
fi
sudo -u obserwator chmod 0755 "$OBS_DIR/narzedzia/wyslij.sh"

# Narzędzie sprawdzenia notatek (umowa, „Pamięć”), uruchamiane hakami z ustawień obserwatora niżej: wzór zastępuje
# inną treść, poprzednia wersja zostaje jako kopia zapasowa; bit wykonywania ustawia konto obserwator.
if sudo -u obserwator test -f "$OBS_DIR/narzedzia/porzadki-notatek.sh"; then
  if sudo -u obserwator cmp -s - "$OBS_DIR/narzedzia/porzadki-notatek.sh" \
    < "$POBRANE/obserwator/narzedzia/porzadki-notatek.sh"; then
    gotowe "narzędzie sprawdzenia notatek obserwatora równe wzorowi"
  else
    KOPIA="$OBS_DIR/narzedzia/porzadki-notatek.sh.przed-instalatorem-$(date +%Y%m%d-%H%M%S)"
    sudo -u obserwator cp "$OBS_DIR/narzedzia/porzadki-notatek.sh" "$KOPIA"
    sudo -u obserwator tee "$OBS_DIR/narzedzia/porzadki-notatek.sh" \
      < "$POBRANE/obserwator/narzedzia/porzadki-notatek.sh" > /dev/null
    gotowe "narzędzie sprawdzenia notatek obserwatora zastąpione wzorem; poprzednia wersja w $KOPIA"
  fi
else
  sudo -u obserwator tee "$OBS_DIR/narzedzia/porzadki-notatek.sh" \
    < "$POBRANE/obserwator/narzedzia/porzadki-notatek.sh" > /dev/null
  gotowe "narzędzie sprawdzenia notatek obserwatora zapisane"
fi
sudo -u obserwator chmod 0755 "$OBS_DIR/narzedzia/porzadki-notatek.sh"

# Skille obserwatora (osobiste skille Claude Code konta obserwator, SKILLE_OBSERWATORA): wzór zastępuje inną treść,
# poprzednia wersja zostaje jako kopia zapasowa. Nowy albo zmieniony skill restartuje sesję obserwatora w etapie 7,
# bo działająca sesja Claude Code nie widzi folderu skilli, którego nie było przy jej starcie.
ZMIANA_SKILLA=0
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

# Folder serwera, laboratorium i projektów do odczytu, zapis narzędziami plikowymi tylko w skrzynce, a w laboratorium
# i projektach reguła deny dla Edit; inne wpisy permissions zostają, nowe dochodzą bez duplikatów, a znika każdy wpis
# z folderem $SERWER/zaufane z v1.0.4, każdy inny folder konta fabryka w additionalDirectories i każda reguła allow
# z folderem konta fabryka. Zapis narzędziami plikowymi także w archiwum notatek, bez pytania (umowa, „Pamięć”).
# Dwa haki uruchamiają sprawdzenie notatek bez duplikatu: SessionStart przy każdym starcie sesji (także wznowieniu
# i po kompaktowaniu) i UserPromptSubmit z --co-miesiac raz na miesiąc kalendarzowy; inne haki zostają.
ARGI_USTAWIEN=(--arg notatki "$NOTATKI" --arg serwer "$SERWER" --arg skrzynka "$SKRZYNKA" --arg zaufane "$SERWER/zaufane"
  --arg lab "$LAB_DIR" --arg projekty "$FAB_HOME/projekty" --arg dom "$FAB_HOME"
  --arg porzadki "$OBS_DIR/narzedzia/porzadki-notatek.sh"
  --arg porzadki_miesiac "$OBS_DIR/narzedzia/porzadki-notatek.sh --co-miesiac"
  --arg archiwum_notatek "$ARCHIWUM_NOTATEK")
WARUNEK_USTAWIEN='.cleanupPeriodDays == 365 and .autoMemoryDirectory == $notatki
  and .inputNeededNotifEnabled == true and .agentPushNotifEnabled == true and .remoteControlAtStartup == true
  and ([$serwer, $lab, $projekty] - (.permissions.additionalDirectories // []) | length == 0)
  and ([.permissions.additionalDirectories[]? | select(type == "string" and (. == $dom or startswith($dom + "/"))
      and . != $lab and . != $projekty)] | length == 0)
  and (["Edit(/\($skrzynka)/**)", "Edit(/\($archiwum_notatek)/**)"] - (.permissions.allow // []) | length == 0)
  and ([.permissions.allow[]? | select(contains($zaufane) or contains($dom))] | length == 0)
  and (["Edit(/\($lab)/**)", "Edit(/\($projekty)/**)"] - (.permissions.deny // []) | length == 0)
  and any(.hooks.SessionStart[]?.hooks[]?; .type == "command" and .command == $porzadki)
  and any(.hooks.UserPromptSubmit[]?.hooks[]?; .type == "command" and .command == $porzadki_miesiac)'
FILTR_USTAWIEN='. + {cleanupPeriodDays: 365, autoMemoryDirectory: $notatki,
  inputNeededNotifEnabled: true, agentPushNotifEnabled: true, remoteControlAtStartup: true}
  | .permissions = (.permissions // {})
  | .permissions.additionalDirectories = ((.permissions.additionalDirectories // [])
      | map(select((type == "string" and (. == $dom or startswith($dom + "/")) and . != $lab and . != $projekty) | not))
        as $a | $a + ([$serwer, $lab, $projekty] - $a))
  | .permissions.allow = ((.permissions.allow // []) | map(select((contains($zaufane) or contains($dom)) | not)) as $a
      | $a + (["Edit(/\($skrzynka)/**)", "Edit(/\($archiwum_notatek)/**)"] - $a))
  | .permissions.deny = ((.permissions.deny // []) as $a | $a + (["Edit(/\($lab)/**)", "Edit(/\($projekty)/**)"] - $a))
  | .hooks = (.hooks // {})
  | .hooks.SessionStart = ((.hooks.SessionStart // []) as $s
      | if any($s[]?.hooks[]?; .type == "command" and .command == $porzadki) then $s
        else $s + [{hooks: [{type: "command", command: $porzadki}]}] end)
  | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) as $s
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
if { [ "$ZMIANA_USLUGI" -eq 1 ] || [ "$ZMIANA_SKILLA" -eq 1 ]; } && systemctl is-active --quiet obserwator.service; then
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

# --- 9. klon laboratorium ----------------------------------------------------------------------------------

etap 9 "Laboratorium fabryki na koncie fabryka"
if sudo -u fabryka test -d "$LAB_DIR/.git"; then
  gotowe "klon laboratorium już jest (bez pobierania zmian)"
else
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

# skille_laboratorium: nazwy folderów skilli klonu, po jednej w linii (czyta konto fabryka).
skille_laboratorium() {
  sudo -u fabryka -H find "$LAB_DIR/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
}

# skille_fabryki: folder każdego skilla laboratorium w ~/.claude/skills konta fabryka zastępuje kopia z klonu;
# inne foldery zostają. Kopiuje i usuwa konto fabryka.
skille_fabryki() {
  local lista nazwa
  lista=$(skille_laboratorium) || przerwij "Nie mogę odczytać skilli laboratorium w $LAB_DIR/skills."
  [ -n "$lista" ] || przerwij "Laboratorium nie ma skilli w $LAB_DIR/skills."
  sudo -u fabryka -H mkdir -p "$FAB_SKILLE"
  while IFS= read -r nazwa; do
    sudo -u fabryka -H rm -rf -- "$FAB_SKILLE/$nazwa"
    sudo -u fabryka -H cp -R -- "$LAB_DIR/skills/$nazwa" "$FAB_SKILLE/$nazwa"
  done <<< "$lista"
  gotowe "skille laboratorium skopiowane do $FAB_SKILLE"
}

# Hak startu sesji konta fabryka w bloku jak w docs/start-projektu.md; inne klucze zostają, bez duplikatu.
WARUNEK_HAKA='any(.hooks.SessionStart[]?.hooks[]?; .type == "command" and .command == $polecenie)'
FILTR_HAKA='.hooks = (.hooks // {})
  | .hooks.SessionStart = ((.hooks.SessionStart // []) as $s
      | if any($s[]?.hooks[]?; .type == "command" and .command == $polecenie) then $s
        else $s + [{hooks: [{type: "command", command: $polecenie}]}] end)'

# ustawienia_fabryki: hak startu sesji w ~/.claude/settings.json konta fabryka (pusty {}, gdy pliku nie ma);
# niepoprawny JSON przerywa instalator.
ustawienia_fabryki() {
  sudo -u fabryka -H mkdir -p "$FAB_HOME/.claude"
  if ! sudo -u fabryka -H test -s "$FAB_SETTINGS"; then
    printf '{}\n' | sudo -u fabryka -H tee "$FAB_SETTINGS" > /dev/null
  fi
  if sudo -u fabryka -H jq -e --arg polecenie "$HAK_FABRYKI" "$WARUNEK_HAKA" "$FAB_SETTINGS" > /dev/null 2>&1; then
    gotowe "hak startu sesji w ustawieniach Claude Code konta fabryka już jest"
    return 0
  fi
  if ! sudo -u fabryka -H jq --arg polecenie "$HAK_FABRYKI" "$FILTR_HAKA" "$FAB_SETTINGS" > "$TMP/settings-fabryki.json"; then
    przerwij "Ustawienia Claude Code konta fabryka (.claude/settings.json) nie są poprawnym JSON-em."
  fi
  sudo -u fabryka -H tee "$FAB_SETTINGS" < "$TMP/settings-fabryki.json" > /dev/null
  gotowe "hak startu sesji dopisany do ustawień Claude Code konta fabryka (inne klucze bez zmian)"
}

skille_fabryki
ustawienia_fabryki

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

obserwator_czyta_laboratorium() {
  sudo -u obserwator cat "$LAB_DIR/CLAUDE.md" > /dev/null && sudo -u obserwator ls "$FAB_HOME/projekty" > /dev/null
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

hak_fabryki() {
  sudo -u fabryka -H jq -e --arg polecenie "$HAK_FABRYKI" "$WARUNEK_HAKA" "$FAB_SETTINGS" > /dev/null
}

# bez_zaufanych: folderu $SERWER/zaufane z v1.0.4 nie ma (ani dowiązania o tej nazwie).
bez_zaufanych() {
  [ ! -e "$SERWER/zaufane" ] && [ ! -L "$SERWER/zaufane" ]
}

umowa_rowna_wzorowi() {
  sudo -u obserwator cmp -s - "$OBS_DIR/CLAUDE.md" < "$POBRANE/obserwator/CLAUDE.md"
}

wyslij_rowny_wzorowi() {
  sudo -u obserwator cmp -s - "$OBS_DIR/narzedzia/wyslij.sh" < "$POBRANE/obserwator/narzedzia/wyslij.sh" \
    && sudo -u obserwator test -x "$OBS_DIR/narzedzia/wyslij.sh"
}

porzadki_notatek_rowne_wzorowi() {
  sudo -u obserwator cmp -s - "$OBS_DIR/narzedzia/porzadki-notatek.sh" \
    < "$POBRANE/obserwator/narzedzia/porzadki-notatek.sh" \
    && sudo -u obserwator test -x "$OBS_DIR/narzedzia/porzadki-notatek.sh"
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
sprawdz "obserwator czyta pliki laboratorium i projektów" \
  "tryb 0750 katalogu $FAB_HOME, grupę fabryka obserwatora (id obserwator) i folder $FAB_HOME/projekty" \
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
sprawdz "laboratorium sklonowane" "folder $LAB_DIR" klon_laboratorium
sprawdz "skille laboratorium w ~/.claude/skills konta fabryka równe klonowi" \
  "foldery $LAB_DIR/skills i $FAB_SKILLE (uruchom instalator ponownie)" skille_fabryki_rowne_klonowi
sprawdz "hak startu sesji w ustawieniach Claude Code konta fabryka" "plik $FAB_SETTINGS" hak_fabryki
sprawdz "umowa obserwatora równa wzorowi" "plik $OBS_DIR/CLAUDE.md" umowa_rowna_wzorowi
sprawdz "narzędzie wysyłania obserwatora równe wzorowi i wykonywalne" "plik $OBS_DIR/narzedzia/wyslij.sh" \
  wyslij_rowny_wzorowi
sprawdz "narzędzie sprawdzenia notatek obserwatora równe wzorowi i wykonywalne" \
  "plik $OBS_DIR/narzedzia/porzadki-notatek.sh" porzadki_notatek_rowne_wzorowi
sprawdz "folder archiwum notatek jest" "sudo -u obserwator ls -ld $ARCHIWUM_NOTATEK" \
  sudo -u obserwator test -d "$ARCHIWUM_NOTATEK"
for skill in "${SKILLE_OBSERWATORA[@]}"; do
  sprawdz "skill obserwatora $skill równy wzorowi" "plik $OBS_SKILLE/$skill/SKILL.md" \
    skill_obserwatora_rowny_wzorowi "$skill"
done
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
