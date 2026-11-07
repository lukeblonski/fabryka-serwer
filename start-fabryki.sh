#!/usr/bin/env bash
set -euo pipefail

# Skrypt startowy fabryki: cel jedynej reguły sudo obserwatora
# (sudo -n -u fabryka /usr/local/lib/fabryka-serwer/start-fabryki.sh [<id polecenia>]).
#
# Bez argumentu: zakłada sesję tmux "fabryka" z powłoką w folderze laboratorium, gdy jej nie ma.
# Kod 0: sesja "fabryka" istnieje po przebiegu. Kod 1: inne konto niż fabryka albo sesja nie powstała.
#
# Z jednym argumentem <id polecenia> (wzorzec RRRRMMDD-GGMMSS-xxxx): wykonuje polecenie obserwatora
# z pliku /var/lib/fabryka-serwer/skrzynka/<id>.json. Rodzaje poleceń: intencja, autopilot, odpowiedz,
# przyjecie, start. Sprawdzenie (rodzaj, format, właściciel i prawa pliku) robi skrzynka.py sprawdz, zanim
# cokolwiek ruszy; pracę uruchamia skrzynka.py wykonaj w usłudze systemd-run --user konta fabryka i skrypt
# wraca od razu. Koniec pracy to zawsze plik /var/lib/fabryka-serwer/wyniki/<id>.json.
# Kod 0: usługa wystartowała. Kod 1: inne konto niż fabryka albo usługa nie wystartowała.
# Kod 2: zły identyfikator, odmowa skrzynka.py sprawdz albo więcej niż jeden argument.

# poprawny_id <id>: identyfikator polecenia według stałego wzorca, w locale C (zakresy liter bez wyjątków).
poprawny_id() {
  local LC_ALL=C
  [[ "$1" =~ ^[0-9]{8}-[0-9]{6}-[a-z0-9]{4}$ ]]
}

if [ "$(id -un)" != "fabryka" ]; then
  echo "start-fabryki.sh: uruchom jako konto fabryka (sudo -n -u fabryka $0)." >&2
  exit 1
fi

if [ "$#" -gt 1 ]; then
  echo "start-fabryki.sh: skrypt przyjmuje najwyżej jeden argument: identyfikator polecenia ze skrzynki." >&2
  exit 2
fi

# sudo resetuje środowisko, więc skrypt ustawia je sam.
export HOME=/home/fabryka
export PATH="/home/fabryka/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
umask 022

if [ "$#" -eq 1 ]; then
  if ! poprawny_id "$1"; then
    echo "start-fabryki.sh: identyfikator polecenia nie pasuje do wzorca RRRRMMDD-GGMMSS-xxxx." >&2
    exit 2
  fi
  # Odmowa przed uruchomieniem czegokolwiek: rodzaj spoza listy, zły format, zły właściciel albo prawa pliku.
  if ! /usr/bin/python3 /usr/local/lib/fabryka-serwer/skrzynka.py sprawdz "$1"; then
    exit 2
  fi
  # Praca w menedżerze użytkownika fabryka, a nie w grupie procesów obserwator.service, z której przychodzi
  # sudo: restart usługi obserwatora jej nie przerywa. Treść polecenia nie przechodzi przez powłokę.
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  if systemd-run --user --quiet --collect --unit="fabryka-polecenie-$1" \
    /usr/bin/python3 /usr/local/lib/fabryka-serwer/skrzynka.py wykonaj "$1"; then
    exit 0
  fi
  echo "start-fabryki.sh: usługa fabryka-polecenie-$1 nie wystartowała." >&2
  exit 1
fi

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
