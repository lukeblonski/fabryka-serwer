#!/usr/bin/env bash
set -euo pipefail

# Instalator fabryki i obserwatora na czysty serwer Ubuntu (Hostinger KVM 2).
# Uruchamiany jako root poleceniem z README.md: pobranie z tagu i sprawdzenie sumy SHA-256.
# Dziesięć kroków; każdy sprawdza stan przed działaniem, więc ponowne uruchomienie jest bezpieczne.
#
# Zasada bezpieczeństwa: root nie otwiera żadnej ścieżki pod /home/. Pliki kont czyta i zapisuje
# konto właściciela (sudo -u <konto> tee, cmp -, cp, mkdir, git, jq), a treść przychodzi przez
# standardowe wejście z folderu tymczasowego roota. Root zmienia tylko pliki systemu
# (/etc, /usr/local/lib/fabryka-serwer, /var/log) i tryby samych katalogów domowych.
# Bez "sudo -u <konto> sh -c" i "sudo -u <konto> bash -c".

REPO="lukeblonski/fabryka-serwer"
WERSJA="v1.0.1"

# Pliki pobierane z repozytorium instalatora w wersji WERSJA. Adres wskazuje tag pełną nazwą refs/tags/,
# żeby gałąź o tej samej nazwie go nie przesłoniła; pliki tagu chroni niezmienne wydanie.
# Nieudane pobranie kończy instalator kodem 1, zanim cokolwiek się zmieni.
PLIKI=(
  "sudoers-obserwator"
  "start-fabryki.sh"
  "start-obserwatora.sh"
  "obserwator.service"
  "fabryka-retencja-obserwatora.service"
  "fabryka-retencja-obserwatora.timer"
  "obserwator/CLAUDE.md"
)

LIB=/usr/local/lib/fabryka-serwer
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
OBS_SETTINGS="$OBS_HOME/.claude/settings.json"
OBS_STAN="$OBS_HOME/.claude.json"
OBS_CLAUDE="$OBS_HOME/.local/bin/claude"
FAB_CLAUDE="$FAB_HOME/.local/bin/claude"

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
# umask 022 konta fabryka w jednym miejscu: pam_umask czyta "umask=" z pola GECOS przed ustawieniami
# z /etc/login.defs (USERGROUPS_ENAB daje 002), więc każda sesja PAM konta (sudo -u fabryka, menedżer
# użytkownika, logowanie) tworzy pliki bez zapisu dla grupy fabryka, w której jest obserwator.
case "$(getent passwd fabryka | cut -d: -f5)" in
  *umask=022*) ;;
  *) chfn -o umask=022 fabryka ;;
esac
gotowe "tryby katalogów domowych, grupy, umask konta fabryka i zakresy podrzędnych identyfikatorów ustawione"

install -d -m 0755 -o root -g root "$LIB"
zainstaluj_plik "$POBRANE/start-fabryki.sh" "$LIB/start-fabryki.sh" 0755 || true
zainstaluj_plik "$POBRANE/start-obserwatora.sh" "$LIB/start-obserwatora.sh" 0755 || true

if ! visudo -c -f "$POBRANE/sudoers-obserwator" > /dev/null; then
  przerwij "Reguła sudo obserwatora nie przechodzi visudo -c -f."
fi
zainstaluj_plik "$POBRANE/sudoers-obserwator" "$SUDOERS_CEL" 0440 || true
if ! visudo -c > /dev/null; then
  przerwij "Konfiguracja sudo nie przechodzi visudo -c po dodaniu reguły obserwatora."
fi
gotowe "skrypty startowe i reguła sudo obserwatora zainstalowane"

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
sudo -u obserwator mkdir -p "$OBS_DIR" "$NOTATKI" "$ARCHIWUM" "$OBS_HOME/.claude"

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

WARUNEK_USTAWIEN='.cleanupPeriodDays == 365 and .autoMemoryDirectory == $notatki
  and .inputNeededNotifEnabled == true and .agentPushNotifEnabled == true and .remoteControlAtStartup == true'
FILTR_USTAWIEN='. + {cleanupPeriodDays: 365, autoMemoryDirectory: $notatki,
  inputNeededNotifEnabled: true, agentPushNotifEnabled: true, remoteControlAtStartup: true}'
if ! sudo -u obserwator test -s "$OBS_SETTINGS"; then
  printf '{}\n' | sudo -u obserwator tee "$OBS_SETTINGS" > /dev/null
fi
if sudo -u obserwator jq -e --arg notatki "$NOTATKI" "$WARUNEK_USTAWIEN" "$OBS_SETTINGS" > /dev/null 2>&1; then
  gotowe "ustawienia Claude Code obserwatora już są"
else
  if ! sudo -u obserwator jq --arg notatki "$NOTATKI" "$FILTR_USTAWIEN" "$OBS_SETTINGS" > "$TMP/settings.json"; then
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
if [ "$ZMIANA_USLUGI" -eq 1 ] && systemctl is-active --quiet obserwator.service; then
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

etap 8 "Codzienna retencja archiwum obserwatora"
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
gotowe "zadanie retencji włączone (pliki archiwum starsze niż 365 dni; notatki zostają)"

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
  sudo -u obserwator cat "$LAB_DIR/CLAUDE.md" > /dev/null
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

klon_laboratorium() {
  sudo -u fabryka git -C "$LAB_DIR" status --porcelain > /dev/null
}

umowa_rowna_wzorowi() {
  sudo -u obserwator cmp -s - "$OBS_DIR/CLAUDE.md" < "$POBRANE/obserwator/CLAUDE.md"
}

ustawienia_obserwatora() {
  sudo -u obserwator jq -e --arg notatki "$NOTATKI" "$WARUNEK_USTAWIEN" "$OBS_SETTINGS" > /dev/null \
    && sudo -u obserwator jq -e --arg folder "$OBS_DIR" "$WARUNEK_STANU" "$OBS_STAN" > /dev/null
}

sprawdz "konto fabryka nie czyta i nie zmienia katalogu obserwatora" \
  "tryb 0700 katalogu $OBS_HOME (ls -ld $OBS_HOME)" fabryka_nie_widzi_obserwatora
sprawdz "obserwator czyta pliki laboratorium" \
  "tryb 0750 katalogu $FAB_HOME i grupę fabryka obserwatora (id obserwator)" obserwator_czyta_laboratorium
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
sprawdz "laboratorium sklonowane" "folder $LAB_DIR" klon_laboratorium
sprawdz "umowa obserwatora równa wzorowi" "plik $OBS_DIR/CLAUDE.md" umowa_rowna_wzorowi
sprawdz "ustawienia Claude Code obserwatora" "pliki $OBS_SETTINGS i $OBS_STAN" ustawienia_obserwatora
sprawdz "usługa obserwator.service działa" "systemctl status obserwator.service" \
  systemctl is-active --quiet obserwator.service
sprawdz "zadanie retencji archiwum włączone" "systemctl list-timers fabryka-retencja-obserwatora.timer" \
  systemctl is-active --quiet fabryka-retencja-obserwatora.timer
sprawdz "proces remote-control obserwatora działa i nie czeka na pytanie (y/n)" \
  "sudo -u obserwator tmux attach -t obserwator (odpowiedz y, wyjście: Ctrl-b, potem d)" remote_control_obserwatora
sprawdz "obserwator uruchamia skrypt startowy fabryki" "plik $SUDOERS_CEL i $LIB/start-fabryki.sh" \
  sudo -u obserwator sudo -n -u fabryka "$LIB/start-fabryki.sh"

napisz ""
napisz "Wynik: działa $DZIALA, nie działa $NIE_DZIALA."
napisz "Otwórz Claude Desktop, zakładka Code, sesja »obserwator«."
if [ "$NIE_DZIALA" -eq 0 ]; then
  exit 0
fi
exit 1
