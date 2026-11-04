#!/usr/bin/env bash
set -euo pipefail

# Skrypt startowy fabryki: cel jedynej reguły sudo obserwatora
# (sudo -n -u fabryka /usr/local/lib/fabryka-serwer/start-fabryki.sh).
# Zakłada sesję tmux "fabryka" z powłoką w folderze laboratorium, gdy jej nie ma.
# Kod 0: sesja "fabryka" istnieje po przebiegu. Kod 1: inne konto niż fabryka
# albo sesja nie powstała. Kod 2: podano argument (ten skrypt nie przyjmuje żadnego).

if [ "$(id -un)" != "fabryka" ]; then
  echo "start-fabryki.sh: uruchom jako konto fabryka (sudo -n -u fabryka $0)." >&2
  exit 1
fi

if [ "$#" -ne 0 ]; then
  echo "start-fabryki.sh: skrypt nie przyjmuje argumentów." >&2
  exit 2
fi

# sudo resetuje środowisko, więc skrypt ustawia je sam.
export HOME=/home/fabryka
export PATH="/home/fabryka/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
umask 022

LAB=/home/fabryka/fabryka
if [ -d "$LAB" ]; then
  FOLDER="$LAB"
else
  FOLDER="$HOME"
fi
cd "$FOLDER"

if ! tmux has-session -t fabryka 2>/dev/null; then
  # Serwer tmux startuje w menedżerze użytkownika fabryka (linger włącza instalator), a nie w grupie
  # procesów usługi obserwatora, z której przychodzi sudo: restart obserwator.service go nie zabija.
  # Usługa przejściowa, nie --scope: konto nie może przenieść procesu z grupy usługi systemowej.
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  systemd-run --user --quiet --collect -p Type=forking \
    /usr/bin/tmux new-session -d -s fabryka -c "$FOLDER"
fi

if tmux has-session -t fabryka 2>/dev/null; then
  exit 0
fi
echo "start-fabryki.sh: sesja tmux fabryka nie powstała." >&2
exit 1
