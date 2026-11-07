#!/usr/bin/env python3
"""Skrzynka poleceń obserwatora po stronie fabryki: sprawdzenie polecenia i wykonanie z sygnałem końca.

Instalator kopiuje ten plik do /usr/local/lib/fabryka-serwer/skrzynka.py (root:root, 0755), a woła go
start-fabryki.sh jako konto fabryka:

    python3 skrzynka.py sprawdz <id polecenia>   kod 0: polecenie poprawne; kod 2: odmowa, powód na stderr
    python3 skrzynka.py wykonaj <id polecenia>   praca polecenia; zawsze kończy się plikiem WYNIKI/<id>.json

Polecenie to jeden plik JSON SKRZYNKA/<id>.json, który pisze tylko konto obserwator. Rodzaje: intencja,
autopilot, odpowiedz, przyjecie, start. Pole zmiana wskazuje zmianę laboratorium; pole projekt wskazuje projekt
aplikacji w folderze PROJEKTY: start go rozpoczyna, a autopilot, odpowiedz i przyjecie z polem projekt działają
na przebiegu startu tego projektu. Treść polecenia przechodzi do wykonawcy laboratorium tylko jako dane:
kopia sprawdzonych bajtów w WYNIKI/<id>.polecenie.json i lista argumentów, bez powłoki.

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
import traceback

SKRZYNKA = "/var/lib/fabryka-serwer/skrzynka"
WYNIKI = "/var/lib/fabryka-serwer/wyniki"
DOM = "/home/fabryka"
LAB = "/home/fabryka/fabryka"
PROJEKTY = DOM + "/projekty"
WYKONAWCA = LAB + "/scripts/wykonaj_polecenie.py"
OBSERWATOR = "obserwator"

RODZAJE = ("intencja", "autopilot", "odpowiedz", "przyjecie", "start")
# Sześć rodzajów pytań z docs/zasady-budowy.md, punkt 6.
RODZAJE_PYTAN = ("spór recenzenta z autorem", "eskalacja", "płatny przebieg", "zakres", "kryterium", "inne")
ROZSTRZYGNAL = ("człowiek", "obserwator")
POLA_PYTANIA = ("rodzaj", "pytanie", "rekomendacja", "wybor")

ID = re.compile(r"[0-9]{8}-[0-9]{6}-[a-z0-9]{4}")
ZMIANA = re.compile(r"[a-z][a-z0-9]*(-[a-z0-9]+)*")

MAKS_PLIK = 64 * 1024
MAKS_TRESC = 20000

# rodzaj -> (pola wymagane, pola opcjonalne) poza "rodzaj" i polami z CEL
POLA = {
    "intencja": ({"tresc"}, set()),
    "autopilot": (set(), set()),
    "odpowiedz": ({"tresc", "rozstrzygnal", "pytania"}, set()),
    "przyjecie": ({"rozstrzygnal"}, {"tresc", "pytania"}),
    "start": ({"projekt", "tresc"}, set()),
}
# rodzaj -> pola, z których polecenie ma dokładnie jedno: zmiana (laboratorium) albo projekt (przebieg startu
# projektu). Para projekt + zmiana to zmiany w repo aplikacji, które przyjdą w kroku 2.
CEL = {
    "intencja": ("zmiana",),
    "autopilot": ("zmiana", "projekt"),
    "odpowiedz": ("zmiana", "projekt"),
    "przyjecie": ("zmiana", "projekt"),
    "start": (),
}

KOD_ODMOWA = 2
KOD_ZAJETE = 3
KOD_BLAD = 1


# --- sprawdzenie treści ------------------------------------------------------------------------------------------

def poprawny_id(id_polecenia):
    return isinstance(id_polecenia, str) and ID.fullmatch(id_polecenia) is not None


def _napis_linii(wartosc):
    """Niepusty napis bez nowej linii i bez separatora ` · ` linii pytań."""
    return (isinstance(wartosc, str) and wartosc.strip() != "" and "\n" not in wartosc and "\r" not in wartosc
            and " · " not in wartosc)


def problemy_pytania(nr, pytanie, rozstrzygnal):
    if not isinstance(pytanie, dict):
        return [f"pytania[{nr}] nie jest obiektem"]
    problemy = []
    for pole in sorted(set(pytanie) - set(POLA_PYTANIA)):
        problemy.append(f"pytania[{nr}]: pole spoza listy: {pole}")
    for pole in POLA_PYTANIA:
        if pole not in pytanie:
            problemy.append(f"pytania[{nr}]: brak pola {pole}")
        elif not _napis_linii(pytanie[pole]):
            problemy.append(f"pytania[{nr}].{pole}: pusty, nie jest napisem, ma nową linię albo ' · '")
    rodzaj = pytanie.get("rodzaj")
    if isinstance(rodzaj, str) and rodzaj not in RODZAJE_PYTAN:
        problemy.append(f"pytania[{nr}].rodzaj spoza listy: {rodzaj}")
    wybor = pytanie.get("wybor")
    if isinstance(wybor, str):
        if wybor != "rekomendacja" and not (wybor.startswith("inny: ") and wybor[len("inny: "):].strip()):
            problemy.append(f"pytania[{nr}].wybor to nie 'rekomendacja' ani 'inny: …'")
        elif rozstrzygnal == "obserwator" and wybor != "rekomendacja":
            problemy.append(f"pytania[{nr}].wybor: obserwator rozstrzyga tylko rekomendacją")
    return problemy


def problemy(dane):
    """Lista problemów polecenia (pusta: polecenie poprawne). Funkcja czysta."""
    if not isinstance(dane, dict):
        return ["polecenie nie jest obiektem JSON"]
    rodzaj = dane.get("rodzaj")
    if not isinstance(rodzaj, str) or rodzaj not in RODZAJE:
        return [f"rodzaj spoza listy {', '.join(RODZAJE)}: {rodzaj!r}"]
    wymagane, opcjonalne = POLA[rodzaj]
    wymagane = wymagane | {"rodzaj"}
    cele = CEL[rodzaj]
    wynik = []
    for pole in sorted(set(dane) - wymagane - opcjonalne - set(cele)):
        wynik.append(f"pole spoza listy dla rodzaju {rodzaj}: {pole}")
    for pole in sorted(wymagane - set(dane)):
        wynik.append(f"brak pola {pole} dla rodzaju {rodzaj}")
    obecne = [pole for pole in cele if pole in dane]
    if cele and not obecne:
        wynik.append(f"brak pola {cele[0]} dla rodzaju {rodzaj}")
    elif len(obecne) > 1:
        wynik.append(f"pola {' i '.join(obecne)} razem: zmiany w projekcie przyjdą w kroku 2")

    for pole in ("zmiana", "projekt"):
        wartosc = dane.get(pole)
        if pole in dane and not (isinstance(wartosc, str) and ZMIANA.fullmatch(wartosc)):
            wynik.append(f"{pole} nie pasuje do wzorca {ZMIANA.pattern}: {wartosc!r}")
    if "tresc" in dane:
        tresc = dane["tresc"]
        if not isinstance(tresc, str) or tresc.strip() == "":
            wynik.append("tresc nie jest niepustym napisem")
        elif len(tresc) > MAKS_TRESC:
            wynik.append(f"tresc ma {len(tresc)} znaków, więcej niż {MAKS_TRESC}")
    rozstrzygnal = dane.get("rozstrzygnal")
    if "rozstrzygnal" in dane and rozstrzygnal not in ROZSTRZYGNAL:
        wynik.append(f"rozstrzygnal to nie {' ani '.join(ROZSTRZYGNAL)}: {rozstrzygnal!r}")
    if "pytania" in dane:
        pytania = dane["pytania"]
        if not isinstance(pytania, list) or not pytania:
            wynik.append("pytania nie są niepustą listą")
        else:
            for nr, pytanie in enumerate(pytania):
                wynik.extend(problemy_pytania(nr, pytanie, rozstrzygnal))
    return wynik


def _bez_powtorzen(pary):
    klucze = [k for k, _ in pary]
    if len(klucze) != len(set(klucze)):
        raise ValueError("powtórzone pole w obiekcie JSON")
    return dict(pary)


def _bez_stalych(nazwa):
    raise ValueError(f"niedozwolona stała JSON: {nazwa}")


def wczytaj(bajty):
    """(dane, None) albo (None, powód) dla bajtów pliku polecenia."""
    try:
        tekst = bajty.decode("utf-8")
        return json.loads(tekst, object_pairs_hook=_bez_powtorzen, parse_constant=_bez_stalych), None
    except (UnicodeDecodeError, ValueError) as blad:
        return None, f"plik nie jest poprawnym JSON-em w UTF-8: {blad}"


# --- sprawdzenie pliku -------------------------------------------------------------------------------------------

def sciezka_wyniku(id_polecenia, koncowka):
    return os.path.join(WYNIKI, id_polecenia + koncowka)


def problem_wolnego(id_polecenia):
    """Powód odmowy, gdy polecenie już ma plik startu albo wyniku (wykonane albo trwa); inaczej None."""
    for koncowka in (".start", ".json"):
        if os.path.lexists(sciezka_wyniku(id_polecenia, koncowka)):
            return f"polecenie {id_polecenia} już wykonane albo trwa: jest {sciezka_wyniku(id_polecenia, koncowka)}"
    return None


def problem_projektu(dane):
    """Powód odmowy dla folderu projektu poprawnego polecenia z polem projekt; inaczej None.

    start: odmowa, gdy PROJEKTY jest dowiązaniem albo PROJEKTY/<projekt> już istnieje (także jako dowiązanie).
    Inny rodzaj: odmowa, gdy PROJEKTY/<projekt> jest dowiązaniem albo nie jest folderem."""
    if "projekt" not in dane:
        return None
    folder = os.path.join(PROJEKTY, dane["projekt"])
    if dane["rodzaj"] == "start":
        if os.path.islink(PROJEKTY):
            return f"folder projektów {PROJEKTY} jest dowiązaniem"
        if os.path.lexists(folder):
            return f"projekt {dane['projekt']} już istnieje: jest {folder}"
        return None
    if os.path.islink(folder) or not os.path.isdir(folder):
        return f"nie ma folderu projektu {folder} (albo jest dowiązaniem)"
    return None


def przeczytaj_polecenie(id_polecenia):
    """(bajty, dane, None) dla poprawnego pliku SKRZYNKA/<id>.json albo (None, None, powód)."""
    sciezka = os.path.join(SKRZYNKA, id_polecenia + ".json")
    try:
        konto = pwd.getpwnam(OBSERWATOR)
    except KeyError:
        return None, None, f"nie ma konta {OBSERWATOR}"
    try:
        fd = os.open(sciezka, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None, None, f"nie ma pliku {sciezka}"
    except OSError as blad:
        return None, None, f"nie otwieram {sciezka} (dowiązanie albo brak dostępu): {blad}"
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            return None, None, f"{sciezka} nie jest zwykłym plikiem"
        if info.st_uid != konto.pw_uid:
            return None, None, f"{sciezka} nie należy do konta {OBSERWATOR}"
        if info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            return None, None, f"{sciezka} ma prawo zapisu dla grupy albo innych ({stat.filemode(info.st_mode)})"
        if info.st_size > MAKS_PLIK:
            return None, None, f"{sciezka} ma {info.st_size} bajtów, więcej niż {MAKS_PLIK}"
        bajty = os.read(fd, MAKS_PLIK + 1)
    finally:
        os.close(fd)
    if len(bajty) > MAKS_PLIK:
        return None, None, f"{sciezka} ma więcej niż {MAKS_PLIK} bajtów"
    dane, powod = wczytaj(bajty)
    if powod:
        return None, None, powod
    lista = problemy(dane)
    if lista:
        return None, None, "; ".join(lista)
    return bajty, dane, None


def sprawdz(id_polecenia):
    """Kod 0 albo 2 (powód na stderr) dla polecenia <id>, zanim cokolwiek zostanie uruchomione."""
    if not poprawny_id(id_polecenia):
        print(f"skrzynka.py: identyfikator nie pasuje do wzorca {ID.pattern}: {id_polecenia!r}", file=sys.stderr)
        return KOD_ODMOWA
    _bajty, dane, powod = przeczytaj_polecenie(id_polecenia)
    if powod is None:
        powod = problem_projektu(dane)
    if powod is None:
        powod = problem_wolnego(id_polecenia)
    if powod:
        print(f"skrzynka.py: odmowa: {powod}", file=sys.stderr)
        return KOD_ODMOWA
    return 0


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


def wykonaj(id_polecenia):
    """Praca polecenia <id>. Po sprawdzeniu identyfikatora i braku startu/wyniku każde zakończenie (odmowa,
    zajęte, kod wykonawcy, wyjątek, SIGTERM, SIGHUP) zostawia atomowo zapisany WYNIKI/<id>.json."""
    if not poprawny_id(id_polecenia):
        print(f"skrzynka.py: identyfikator nie pasuje do wzorca {ID.pattern}: {id_polecenia!r}", file=sys.stderr)
        return KOD_ODMOWA
    powod = problem_wolnego(id_polecenia)
    if powod:
        # Nie nadpisuje wyniku ani nie wchodzi w pracę, która trwa.
        print(f"skrzynka.py: odmowa: {powod}", file=sys.stderr)
        return KOD_ODMOWA

    stara_maska = os.umask(0o022)
    stare_sygnaly = {numer: signal.signal(numer, _na_sygnal) for numer in (signal.SIGTERM, signal.SIGHUP)}
    wynik = {"polecenie": id_polecenia, "rodzaj": None, "zmiana": None, "kod": KOD_BLAD, "odmowa": None,
             "log": None, "koniec": None}
    blokada = None
    log = sciezka_wyniku(id_polecenia, ".log")
    try:
        bajty, dane, powod = przeczytaj_polecenie(id_polecenia)
        if powod:
            wynik.update(kod=KOD_ODMOWA, odmowa=powod)
            return KOD_ODMOWA
        wynik.update(rodzaj=dane["rodzaj"], zmiana=dane.get("zmiana"))
        if "projekt" in dane:
            wynik["projekt"] = dane["projekt"]
        powod = problem_projektu(dane)
        if powod:
            wynik.update(kod=KOD_ODMOWA, odmowa=powod)
            return KOD_ODMOWA

        blokada = os.open(os.path.join(WYNIKI, ".zajete"), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o640)
        try:
            fcntl.flock(blokada, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            wynik.update(kod=KOD_ZAJETE, odmowa="zajęte: fabryka wykonuje inne polecenie")
            return KOD_ZAJETE

        kopia = sciezka_wyniku(id_polecenia, ".polecenie.json")
        zapisz_nowy(kopia, bajty)
        zapisz_nowy(sciezka_wyniku(id_polecenia, ".start"),
                    (json.dumps({"pid": os.getpid(), "poczatek": teraz()}) + "\n").encode("utf-8"))
        wynik["log"] = log
        with open(log, "ab") as wyjscie:
            proces = subprocess.run([sys.executable, WYKONAWCA, kopia], cwd=LAB, env=srodowisko(),
                                    stdin=subprocess.DEVNULL, stdout=wyjscie, stderr=subprocess.STDOUT)
        kod = proces.returncode if proces.returncode >= 0 else 128 - proces.returncode
        wynik["kod"] = kod
        return kod
    except Przerwanie as przerwanie:
        wynik["kod"] = 128 + przerwanie.numer
        dopisz_do_logu(log, f"\nskrzynka.py: praca przerwana: {przerwanie}\n")
        wynik["log"] = log
        return wynik["kod"]
    except Exception:  # noqa: BLE001 — każdy błąd kończy się plikiem wyniku z kodem 1
        wynik["kod"] = KOD_BLAD
        dopisz_do_logu(log, "\nskrzynka.py: błąd:\n" + traceback.format_exc())
        wynik["log"] = log
        return KOD_BLAD
    finally:
        # Drugi sygnał w trakcie zapisu nie może przerwać zapisu pliku wyniku.
        for numer in stare_sygnaly:
            signal.signal(numer, signal.SIG_IGN)
        wynik["koniec"] = teraz()
        try:
            zapisz_atomowo(sciezka_wyniku(id_polecenia, ".json"), wynik)
        finally:
            if blokada is not None:
                os.close(blokada)
            for numer, obsluga in stare_sygnaly.items():
                signal.signal(numer, obsluga)
            os.umask(stara_maska)


def main(argv):
    if len(argv) != 2 or argv[0] not in ("sprawdz", "wykonaj"):
        print("użycie: skrzynka.py sprawdz|wykonaj <id polecenia>", file=sys.stderr)
        return KOD_ODMOWA
    if argv[0] == "sprawdz":
        return sprawdz(argv[1])
    return wykonaj(argv[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
