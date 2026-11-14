# Instalator fabryki i obserwatora na serwer Ubuntu

Jeden skrypt stawia na czystym serwerze Ubuntu wszystko, czego potrzebują fabryka i obserwator. Ty wklejasz jedno polecenie i logujesz trzy konta przez przeglądarkę. Resztę robi skrypt.

## Co skrypt robi

1. Instaluje pakiety systemu, GitHub CLI i Dockera.
2. Zakłada dwa konta: `obserwator` i `fabryka`. Fabryka nie widzi plików obserwatora. Obserwator czyta pliki fabryki i ma jedną regułę sudo: uruchomienie skryptu startowego fabryki jako `fabryka`.
3. Instaluje Claude Code na obu kontach i dopisuje jego folder do ścieżki.
4. Uruchamia Dockera bez roota na koncie `fabryka` i pobiera raz obraz przeglądarki do testów aplikacji (ok. 1 GB pobierania, 3,6 GB na dysku).
5. Prowadzi logowania: Claude obserwatora, Claude fabryki, GitHub fabryki.
6. Zakłada folder obserwatora z umową i granicami, notatkami i archiwum oraz ustawia Claude Code obserwatora (365 dni historii, pamięć w folderze obserwatora, powiadomienia na telefon, Remote Control).
7. Włącza usługę systemu, która uruchamia sesję obserwatora przy starcie serwera i po każdym jej zakończeniu.
8. Włącza codzienne zadanie, które usuwa pliki archiwum obserwatora starsze niż 365 dni. Notatki zostają.
9. Klonuje laboratorium fabryki na konto `fabryka`.
10. Na końcu pokazuje listę sprawdzeń: każdy punkt „działa” albo „nie działa” z podpowiedzią, co sprawdzić.

Ponowne uruchomienie jest bezpieczne. Skrypt pomija to, co już działa, i nie prosi ponownie o ważne logowania.

## Czego potrzebujesz

- Serwer Hostinger KVM 2 z Ubuntu LTS (sprawdzone wersje: 24.04 i 26.04).
- Subskrypcję Claude z Remote Control: skrypt loguje nią konto obserwatora i konto fabryki.
- Konto GitHub z repozytorium laboratorium fabryki.
- Claude Desktop albo aplikację Claude na telefonie, żeby rozmawiać z obserwatorem.

## Instalacja

Otwórz terminal w przeglądarce w panelu Hostingera (konto `root`) i wklej jedno polecenie:

```bash
f=$(mktemp) && curl -fsSL https://raw.githubusercontent.com/lukeblonski/fabryka-serwer/v1.0.15/instaluj.sh -o "$f" && echo "f63a8d42844972a411ec19aac221dced3a6035d4931f398b43dddb875273485c  $f" | sha256sum -c - && bash "$f"
```

Polecenie pobiera oznaczoną wersję `v1.0.15`, a nie główną gałąź, i uruchamia skrypt dopiero wtedy, gdy jego suma SHA-256 zgadza się z sumą w poleceniu. Polecenie do wklejenia weź od osoby, która dała Ci tę wersję; nie kopiuj go ze strony głównej repozytorium.

## Logowania

Skrypt prosi o trzy logowania po kolei: Claude obserwatora, Claude fabryki i GitHub fabryki. Oba logowania Claude pokazują adres do otwarcia w przeglądarce. Po zalogowaniu strona pokazuje kod; wklej go w terminal i naciśnij Enter. Logowanie GitHub działa odwrotnie: terminal pokazuje kod, który wpisujesz na stronie github.com/login/device. Kody i tokeny nie trafiają do dziennika instalatora (`/var/log/fabryka-instalator.log`) ani do historii poleceń.

Przy pierwszym starcie sesja obserwatora może raz zapytać o Remote Control. Skrypt wtedy pokaże ekran sesji i polecenie `sudo -u obserwator tmux attach -t obserwator`. Wpisz `y` i Enter, a potem naciśnij Ctrl-b i d, żeby wrócić do instalatora.

## Po instalacji

Otwórz Claude Desktop, zakładka Code, sesja „obserwator”. Ta sama sesja jest w aplikacji na telefonie.

## Gdy coś „nie działa”

Przy każdym punkcie „nie działa” lista sprawdzeń mówi, co sprawdzić. Popraw to i uruchom polecenie instalacji jeszcze raz. Skrypt kończy się kodem 0 tylko wtedy, gdy wszystkie punkty działają.

## Odnowienie logowania Claude

Logowanie Claude wygasa po około 30 dniach. Obserwator ostrzega powiadomieniem z wyprzedzeniem. Odnowienie robisz Ty: zaloguj się w terminalu serwera poleceniem `sudo -u obserwator /home/obserwator/.local/bin/claude auth login` (dla fabryki: `sudo -u fabryka /home/fabryka/.local/bin/claude auth login`).
