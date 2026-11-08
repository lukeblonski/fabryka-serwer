#!/usr/bin/env python3
"""Wykonawca rozmowy obserwatora z sesją główną fabryki: sprawdzenie wiadomości i tura claude -p z sygnałem końca.

Instalator kopiuje ten plik do /usr/local/lib/fabryka-serwer/skrzynka.py (root:root, 0755), a woła go
start-fabryki.sh jako konto fabryka:

    python3 skrzynka.py sprawdz <id wiadomości>   kod 0: wiadomość poprawna; kod 2: odmowa, powód na stderr
    python3 skrzynka.py wykonaj <id wiadomości>   tura sesji; zawsze kończy się plikiem WYNIKI/<id>.json

Wiadomość to jeden plik JSON SKRZYNKA/<id>.json, który pisze tylko konto obserwator, z polami folder (LAB albo
PROJEKTY/<projekt> z nazwą według wzorca ZMIANA), tekst (zwykły tekst do sesji) i opcjonalnym rozmowa (UUID
rozmowy do wznowienia). Wykonawca bierze blokadę folderu i uruchamia w nim jedną turę claude -p: tekst idzie na
wejście standardowe, nigdy przez powłokę ani argument. Wiadomość bez pola rozmowa zaczyna nową rozmowę.

Wynik WYNIKI/<id>.json ma pola wiadomosc, folder, rozmowa, kod, tury (tekst, odmowy i blad każdej tury po kolei),
powod, log i koniec. Gdy tura uruchomiła autopilota (autopilot.py --w-tle dopisuje do
.autopilot-local/<id>/wyjscie.log), wykonawca czeka, aż wywołanie zwolni blokadę stan.lock (odczyt /proc/locks),
potem wznawia tę samą rozmowę wiadomością o końcu autopilota i dopisuje kolejną turę do tego samego wyniku.

Foldery i konto są stałymi modułu; testy podmieniają je w procesie. Plik nie czyta zmiennych środowiska
do wyboru folderów.
"""

import datetime
import fcntl
import json
import os
import pwd
import re
import signal
import stat
import subprocess
import sys
import time
import traceback
import uuid

SKRZYNKA = "/var/lib/fabryka-serwer/skrzynka"
WYNIKI = "/var/lib/fabryka-serwer/wyniki"
DOM = "/home/fabryka"
LAB = "/home/fabryka/fabryka"
PROJEKTY = DOM + "/projekty"
OBSERWATOR = "obserwator"

ID = re.compile(r"[0-9]{8}-[0-9]{6}-[a-z0-9]{4}")
ZMIANA = re.compile(r"[a-z][a-z0-9]*(-[a-z0-9]+)*")
ROZMOWA = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

POLA = ("folder", "tekst")
POLA_OPCJONALNE = ("rozmowa",)

MAKS_PLIK = 64 * 1024
MAKS_TRESC = 20000

# Wywołanie tury. Reguła zezwala sesji uruchomić autopilota laboratorium pełną ścieżką (Z6).
REGULA_AUTOPILOTA = "Bash(python3 /home/fabryka/fabryka/scripts/autopilot.py:*)"
SESJA_SERWERA = (
    "Rozmówcą w tej rozmowie jest obserwator, który pisze w imieniu człowieka. Działaj według "
    "/home/fabryka/fabryka/docs/sesja-glowna.md, sekcja „Na serwerze: rozmowa przez obserwatora”."
)
# Zmienna tury: autopilot bez --w-tle przy niej kończy się kodem 2 (scripts/autopilot.py, ROZMOWA_ENV).
ROZMOWA_ENV = "FABRYKA_ROZMOWA"
WZNOWIENIE = (
    "Wywołanie autopilota w tym folderze się skończyło. Przeczytaj jego stan.json i koniec logu {log} "
    "i postępuj według sekcji „Na serwerze: rozmowa przez obserwatora” w "
    "/home/fabryka/fabryka/docs/sesja-glowna.md."
)
LOG_AUTOPILOTA = "wyjscie.log"
BLOKADA_AUTOPILOTA = "stan.lock"
MAKS_WZNOWIEN = 30
# Sekundy: czekanie na start wywołania autopilota, odstęp sprawdzania jego startu i końca, czas na koniec claude.
CZEKANIE_NA_START = 15
ODSTEP_STARTU = 0.5
ODSTEP = 10
CZAS_NA_KONIEC = 5

KOD_ODMOWA = 2
KOD_ZAJETE = 3
KOD_BLAD = 1


# --- sprawdzenie treści ------------------------------------------------------------------------------------------

def poprawny_id(id_wiadomosci):
    return isinstance(id_wiadomosci, str) and ID.fullmatch(id_wiadomosci) is not None


def nazwa_projektu(folder):
    """Nazwa projektu, gdy folder to PROJEKTY/<nazwa według ZMIANA>; inaczej None."""
    poczatek = PROJEKTY + "/"
    if isinstance(folder, str) and folder.startswith(poczatek):
        nazwa = folder[len(poczatek):]
        if ZMIANA.fullmatch(nazwa):
            return nazwa
    return None


def problemy(dane):
    """Lista problemów wiadomości (pusta: wiadomość poprawna). Funkcja czysta."""
    if not isinstance(dane, dict):
        return ["wiadomość nie jest obiektem JSON"]
    wynik = []
    for pole in sorted(set(dane) - set(POLA) - set(POLA_OPCJONALNE)):
        wynik.append(f"pole spoza listy: {pole}")
    for pole in POLA:
        if pole not in dane:
            wynik.append(f"brak pola {pole}")
    if "folder" in dane:
        folder = dane["folder"]
        if not isinstance(folder, str) or (folder != LAB and nazwa_projektu(folder) is None):
            wynik.append(f"folder to nie {LAB} ani {PROJEKTY}/<projekt> z nazwą według wzorca "
                         f"{ZMIANA.pattern}: {folder!r}")
    if "tekst" in dane:
        tekst = dane["tekst"]
        if not isinstance(tekst, str) or tekst.strip() == "":
            wynik.append("tekst nie jest niepustym napisem")
        elif len(tekst) > MAKS_TRESC:
            wynik.append(f"tekst ma {len(tekst)} znaków, więcej niż {MAKS_TRESC}")
    if "rozmowa" in dane:
        rozmowa = dane["rozmowa"]
        if not isinstance(rozmowa, str) or ROZMOWA.fullmatch(rozmowa) is None:
            wynik.append(f"rozmowa to nie UUID małymi literami: {rozmowa!r}")
    return wynik


def _bez_powtorzen(pary):
    klucze = [k for k, _ in pary]
    if len(klucze) != len(set(klucze)):
        raise ValueError("powtórzone pole w obiekcie JSON")
    return dict(pary)


def _bez_stalych(nazwa):
    raise ValueError(f"niedozwolona stała JSON: {nazwa}")


def wczytaj(bajty):
    """(dane, None) albo (None, powód) dla bajtów pliku wiadomości."""
    try:
        tekst = bajty.decode("utf-8")
        return json.loads(tekst, object_pairs_hook=_bez_powtorzen, parse_constant=_bez_stalych), None
    except (UnicodeDecodeError, ValueError) as blad:
        return None, f"plik nie jest poprawnym JSON-em w UTF-8: {blad}"


# --- sprawdzenie pliku i folderu ---------------------------------------------------------------------------------

def sciezka_wyniku(id_wiadomosci, koncowka):
    return os.path.join(WYNIKI, id_wiadomosci + koncowka)


def problem_wolnego(id_wiadomosci):
    """Powód odmowy, gdy wiadomość już ma plik startu albo wyniku (wykonana albo trwa); inaczej None."""
    for koncowka in (".start", ".json"):
        if os.path.lexists(sciezka_wyniku(id_wiadomosci, koncowka)):
            return f"wiadomość {id_wiadomosci} już wykonana albo trwa: jest {sciezka_wyniku(id_wiadomosci, koncowka)}"
    return None


def problem_folderu(dane):
    """Powód odmowy dla folderu poprawnej wiadomości; inaczej None.

    Odmowa, gdy folder albo (dla projektu) PROJEKTY jest dowiązaniem albo istnieje, a nie jest folderem.
    Brak folderu projektu (i PROJEKTY) jest dozwolony: wykonawca go założy. Laboratorium musi istnieć."""
    folder = dane["folder"]
    sciezki = [folder] if folder == LAB else [PROJEKTY, folder]
    for sciezka in sciezki:
        if os.path.islink(sciezka):
            return f"{sciezka} jest dowiązaniem"
        if os.path.lexists(sciezka) and not os.path.isdir(sciezka):
            return f"{sciezka} nie jest folderem"
    if folder == LAB and not os.path.isdir(LAB):
        return f"nie ma folderu laboratorium {LAB}"
    return None


def przeczytaj_polecenie(id_wiadomosci):
    """(dane, None) dla poprawnego pliku SKRZYNKA/<id>.json albo (None, powód)."""
    sciezka = os.path.join(SKRZYNKA, id_wiadomosci + ".json")
    try:
        konto = pwd.getpwnam(OBSERWATOR)
    except KeyError:
        return None, f"nie ma konta {OBSERWATOR}"
    try:
        fd = os.open(sciezka, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None, f"nie ma pliku {sciezka}"
    except OSError as blad:
        return None, f"nie otwieram {sciezka} (dowiązanie albo brak dostępu): {blad}"
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            return None, f"{sciezka} nie jest zwykłym plikiem"
        if info.st_uid != konto.pw_uid:
            return None, f"{sciezka} nie należy do konta {OBSERWATOR}"
        if info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            return None, f"{sciezka} ma prawo zapisu dla grupy albo innych ({stat.filemode(info.st_mode)})"
        if info.st_size > MAKS_PLIK:
            return None, f"{sciezka} ma {info.st_size} bajtów, więcej niż {MAKS_PLIK}"
        bajty = os.read(fd, MAKS_PLIK + 1)
    finally:
        os.close(fd)
    if len(bajty) > MAKS_PLIK:
        return None, f"{sciezka} ma więcej niż {MAKS_PLIK} bajtów"
    dane, powod = wczytaj(bajty)
    if powod:
        return None, powod
    lista = problemy(dane)
    if lista:
        return None, "; ".join(lista)
    return dane, None


def sprawdz_wiadomosc(id_wiadomosci):
    """(dane, None) albo (None, powód): plik, treść i folder wiadomości."""
    dane, powod = przeczytaj_polecenie(id_wiadomosci)
    if powod is None:
        powod = problem_folderu(dane)
    return (None, powod) if powod else (dane, None)


def sprawdz(id_wiadomosci):
    """Kod 0 albo 2 (powód na stderr) dla wiadomości <id>, zanim cokolwiek zostanie uruchomione."""
    if not poprawny_id(id_wiadomosci):
        print(f"skrzynka.py: identyfikator nie pasuje do wzorca {ID.pattern}: {id_wiadomosci!r}", file=sys.stderr)
        return KOD_ODMOWA
    _dane, powod = sprawdz_wiadomosc(id_wiadomosci)
    if powod is None:
        powod = problem_wolnego(id_wiadomosci)
    if powod:
        print(f"skrzynka.py: odmowa: {powod}", file=sys.stderr)
        return KOD_ODMOWA
    return 0


# --- autopilot w folderze ----------------------------------------------------------------------------------------

def _foldery_autopilota(folder):
    """Foldery <folder>/.autopilot-local/<id>/ bez dowiązań."""
    korzen = os.path.join(folder, ".autopilot-local")
    if os.path.islink(korzen) or not os.path.isdir(korzen):
        return []
    try:
        wpisy = list(os.scandir(korzen))
    except OSError:
        return []
    return sorted(wpis.path for wpis in wpisy if wpis.is_dir(follow_symlinks=False))


def _zwykly_plik(sciezka):
    try:
        info = os.lstat(sciezka)
    except OSError:
        return None
    return info if stat.S_ISREG(info.st_mode) else None


def stan_logow(folder):
    """Ścieżka -> (rozmiar, st_mtime_ns) każdego <folder>/.autopilot-local/*/wyjscie.log, bez dowiązań."""
    stan = {}
    for podfolder in _foldery_autopilota(folder):
        sciezka = os.path.join(podfolder, LOG_AUTOPILOTA)
        info = _zwykly_plik(sciezka)
        if info is not None:
            stan[sciezka] = (info.st_size, info.st_mtime_ns)
    return stan


def _blokady_flock():
    """Zbiór (major, minor, i-węzeł) blokad FLOCK z /proc/locks, bez linii oczekujących (->)."""
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


def autopilot_trwa(folder):
    """Prawda, gdy /proc/locks ma blokadę FLOCK na którymś <folder>/.autopilot-local/*/stan.lock.

    Bez własnego flock (nie przeszkadza startowi autopilota) i bez czytania pid ze stan.json."""
    wezly = set()
    for podfolder in _foldery_autopilota(folder):
        info = _zwykly_plik(os.path.join(podfolder, BLOKADA_AUTOPILOTA))
        if info is not None:
            wezly.add((os.major(info.st_dev), os.minor(info.st_dev), info.st_ino))
    return bool(wezly and wezly & _blokady_flock())


def czekaj_na_autopilota(folder):
    """Do CZEKANIE_NA_START s na start wywołania autopilota, potem co ODSTEP s na jego koniec."""
    termin = time.monotonic() + CZEKANIE_NA_START
    while not autopilot_trwa(folder):
        if time.monotonic() >= termin:
            return
        time.sleep(ODSTEP_STARTU)
    while autopilot_trwa(folder):
        time.sleep(ODSTEP)


# --- wykonanie ---------------------------------------------------------------------------------------------------

class Przerwanie(Exception):
    def __init__(self, numer):
        super().__init__(f"sygnał {signal.Signals(numer).name}")
        self.numer = numer


def _na_sygnal(numer, _ramka):
    raise Przerwanie(numer)


def teraz():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def srodowisko():
    """Środowisko pracy jak w start-fabryki.sh: usługa systemd-run --user nie dziedziczy go z sudo."""
    env = dict(os.environ)
    runtime = f"/run/user/{os.getuid()}"
    env.update({
        "HOME": DOM,
        "PATH": f"{DOM}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "XDG_RUNTIME_DIR": runtime,
        "DBUS_SESSION_BUS_ADDRESS": f"unix:path={runtime}/bus",
    })
    return env


def srodowisko_tury():
    """Środowisko tury: bez AUTOPILOT_KROK (sesja może uruchomić autopilota), z ROZMOWA_ENV=1."""
    env = srodowisko()
    env.pop("AUTOPILOT_KROK", None)
    env[ROZMOWA_ENV] = "1"
    return env


def zapisz_atomowo(sciezka, dane):
    tymczasowy = os.path.join(os.path.dirname(sciezka), "." + os.path.basename(sciezka) + ".tmp")
    with open(tymczasowy, "w", encoding="utf-8") as plik:
        json.dump(dane, plik, ensure_ascii=False, indent=2)
        plik.write("\n")
        plik.flush()
        os.fsync(plik.fileno())
    os.replace(tymczasowy, sciezka)


def zapisz_nowy(sciezka, bajty):
    fd = os.open(sciezka, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o640)
    with os.fdopen(fd, "wb") as plik:
        plik.write(bajty)


def dopisz_do_logu(sciezka, tekst):
    try:
        with open(sciezka, "a", encoding="utf-8") as plik:
            plik.write(tekst)
    except OSError:
        pass


def plik_blokady(folder):
    """Blokada folderu w WYNIKI: jedna tura albo czekanie naraz na folder."""
    nazwa = nazwa_projektu(folder)
    return os.path.join(WYNIKI, ".zajete-fabryka" if nazwa is None else f".zajete-projekt-{nazwa}")


def przygotuj_folder(folder):
    """Zakłada brakujący PROJEKTY i folder projektu (0755), bez podążania za dowiązaniem."""
    if folder == LAB:
        return
    for sciezka in (PROJEKTY, folder):
        if os.path.islink(sciezka):
            raise RuntimeError(f"{sciezka} jest dowiązaniem")
        if not os.path.lexists(sciezka):
            os.mkdir(sciezka, 0o755)


def polecenie_tury(rozmowa, nowa):
    return ["claude", "-p", "--output-format", "json", "--permission-mode", "auto",
            "--allowedTools", REGULA_AUTOPILOTA, "--disallowedTools", "AskUserQuestion",
            "--append-system-prompt", SESJA_SERWERA, "--session-id" if nowa else "--resume", rozmowa]


def zakoncz(proces):
    """Kończy proces claude: terminate, a po CZAS_NA_KONIEC s kill."""
    if proces is None or proces.poll() is not None:
        return
    proces.terminate()
    try:
        proces.wait(timeout=CZAS_NA_KONIEC)
    except subprocess.TimeoutExpired:
        proces.kill()
        proces.wait()


def tura(folder, tekst, rozmowa, nowa, log, biezacy):
    """Jedna tura claude -p w folderze; tekst na stdin. (tura do wyniku, session_id albo None, powód błędu albo
    None). biezacy["proces"] trzyma proces, żeby sygnał mógł go zakończyć."""
    with open(log, "ab") as bledy:
        proces = subprocess.Popen(polecenie_tury(rozmowa, nowa), cwd=folder, env=srodowisko_tury(),
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=bledy)
        biezacy["proces"] = proces
        wyjscie, _ = proces.communicate(tekst.encode("utf-8"))
        biezacy["proces"] = None
    try:
        dane = json.loads(wyjscie.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        dane = None
    if not isinstance(dane, dict):
        dopisz_do_logu(log, "\nskrzynka.py: wyjście claude bez poprawnego JSON:\n"
                       + wyjscie.decode("utf-8", errors="replace") + "\n")
        return ({"tekst": None, "odmowy": [], "blad": True}, None,
                f"claude zakończył się kodem {proces.returncode} bez poprawnego JSON")
    odmowy = dane.get("permission_denials")
    wpis = {"tekst": dane.get("result"), "odmowy": odmowy if isinstance(odmowy, list) else [],
            "blad": bool(dane.get("is_error"))}
    sesja = dane.get("session_id")
    sesja = sesja if isinstance(sesja, str) and ROZMOWA.fullmatch(sesja) else None
    if proces.returncode != 0 or wpis["blad"]:
        return wpis, sesja, f"błąd claude: kod {proces.returncode}"
    return wpis, sesja, None


def wykonaj(id_wiadomosci):
    """Praca wiadomości <id>. Po sprawdzeniu identyfikatora i braku startu/wyniku każde zakończenie (odmowa,
    zajęty folder, błąd claude, wyjątek, SIGTERM, SIGHUP) zostawia atomowo zapisany WYNIKI/<id>.json."""
    if not poprawny_id(id_wiadomosci):
        print(f"skrzynka.py: identyfikator nie pasuje do wzorca {ID.pattern}: {id_wiadomosci!r}", file=sys.stderr)
        return KOD_ODMOWA
    powod = problem_wolnego(id_wiadomosci)
    if powod:
        # Nie nadpisuje wyniku ani nie wchodzi w pracę, która trwa.
        print(f"skrzynka.py: odmowa: {powod}", file=sys.stderr)
        return KOD_ODMOWA

    stara_maska = os.umask(0o022)
    stare_sygnaly = {numer: signal.signal(numer, _na_sygnal) for numer in (signal.SIGTERM, signal.SIGHUP)}
    wynik = {"wiadomosc": id_wiadomosci, "folder": None, "rozmowa": None, "kod": KOD_BLAD, "tury": [],
             "powod": None, "log": None, "koniec": None}
    blokada = None
    biezacy = {"proces": None}
    log = sciezka_wyniku(id_wiadomosci, ".log")
    try:
        dane, powod = sprawdz_wiadomosc(id_wiadomosci)
        if powod:
            wynik.update(kod=KOD_ODMOWA, powod=powod)
            return KOD_ODMOWA
        folder = dane["folder"]
        wynik["folder"] = folder

        blokada = os.open(plik_blokady(folder), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o640)
        try:
            fcntl.flock(blokada, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            wynik.update(kod=KOD_ZAJETE, powod=f"folder zajęty: {folder} (trwa tura albo czekanie na autopilota)")
            return KOD_ZAJETE

        zapisz_nowy(sciezka_wyniku(id_wiadomosci, ".start"),
                    (json.dumps({"pid": os.getpid(), "poczatek": teraz()}) + "\n").encode("utf-8"))
        wynik["log"] = log
        przygotuj_folder(folder)

        rozmowa = dane.get("rozmowa")
        nowa = rozmowa is None
        if nowa:
            rozmowa = str(uuid.uuid4())
        wynik["rozmowa"] = rozmowa
        tekst = dane["tekst"]
        for numer in range(MAKS_WZNOWIEN + 1):
            przed = stan_logow(folder)
            wpis, sesja, blad = tura(folder, tekst, rozmowa, nowa and numer == 0, log, biezacy)
            wynik["tury"].append(wpis)
            if sesja:
                rozmowa = wynik["rozmowa"] = sesja
            if blad:
                wynik.update(kod=KOD_BLAD, powod=blad)
                return KOD_BLAD
            zmienione = sorted(s for s, v in stan_logow(folder).items() if przed.get(s) != v)
            if not zmienione:
                wynik["kod"] = 0
                return 0
            if numer == MAKS_WZNOWIEN:
                break
            czekaj_na_autopilota(folder)
            tekst = WZNOWIENIE.format(log=", ".join(zmienione))
        wynik.update(kod=KOD_BLAD, powod=f"limit {MAKS_WZNOWIEN} wznowień po autopilocie")
        return KOD_BLAD
    except Przerwanie as przerwanie:
        wynik["kod"] = 128 + przerwanie.numer
        wynik["powod"] = f"praca przerwana: {przerwanie}"
        dopisz_do_logu(log, f"\nskrzynka.py: praca przerwana: {przerwanie}\n")
        wynik["log"] = log
        return wynik["kod"]
    except Exception:  # noqa: BLE001 — każdy błąd kończy się plikiem wyniku z kodem 1
        wynik["kod"] = KOD_BLAD
        wynik["powod"] = "błąd wykonawcy (szczegóły w logu)"
        dopisz_do_logu(log, "\nskrzynka.py: błąd:\n" + traceback.format_exc())
        wynik["log"] = log
        return KOD_BLAD
    finally:
        # Drugi sygnał w trakcie zapisu nie może przerwać zakończenia claude ani zapisu pliku wyniku.
        for numer in stare_sygnaly:
            signal.signal(numer, signal.SIG_IGN)
        try:
            zakoncz(biezacy["proces"])
        except Exception:  # noqa: BLE001 — wynik powstaje także wtedy
            dopisz_do_logu(log, "\nskrzynka.py: błąd kończenia claude:\n" + traceback.format_exc())
        wynik["koniec"] = teraz()
        try:
            zapisz_atomowo(sciezka_wyniku(id_wiadomosci, ".json"), wynik)
        finally:
            if blokada is not None:
                os.close(blokada)
            for numer, obsluga in stare_sygnaly.items():
                signal.signal(numer, obsluga)
            os.umask(stara_maska)


def main(argv):
    if len(argv) != 2 or argv[0] not in ("sprawdz", "wykonaj"):
        print("użycie: skrzynka.py sprawdz|wykonaj <id wiadomości>", file=sys.stderr)
        return KOD_ODMOWA
    if argv[0] == "sprawdz":
        return sprawdz(argv[1])
    return wykonaj(argv[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
