---
name: porzadki-notatek
description: Stała procedura Maestro, gdy plik jego notatek ma ponad 20 KB - co przenieść do archiwum notatek, co zostawić, dokąd i jak wyjąć z powrotem, bez pytania człowieka i z jednym zdaniem po fakcie. Uruchamia ją wyjście narzędzia porzadki-notatek.sh przy starcie sesji i raz w miesiącu albo duży plik zauważony przez Maestro. Trigger phrases - "porządki notatek", "notatki ponad 20 KB", "Pliki notatek wyżej mają ponad 20 KB", "uporządkuj notatki", "za duży plik notatek".
---

# Porządki notatek

Notatki Maestro (`/home/obserwator/obserwator/notatki/`) Maestro czyta na starcie każdej rozmowy, więc plik większy niż 20 KB porządkuje od razu (umowa, „Pamięć”). Sprawdzenie robi narzędzie `/home/obserwator/obserwator/narzedzia/porzadki-notatek.sh`: hak startu sesji uruchamia je przy starcie, wznowieniu i kompaktowaniu sesji, a hak wiadomości raz w miesiącu kalendarzowym. Narzędzie wypisuje każdy plik ponad 20 KB ze ścieżką i rozmiarem; bez takiego pliku nic nie wypisuje.

Przeniesienie idzie bez pytania człowieka. Notatek nie kasuję: każdy fragment trafia do archiwum notatek i da się go wyjąć z powrotem.

## Kroki

1. Powtórne zgłoszenie. Czytam `notatki/porzadki-notatek.md` (linia na plik: ścieżka, data, rozmiar w KB). Gdy zgłoszony plik ma tam linię z tego samego miesiąca, a urósł od niej o nie więcej niż 20 KB, nic nie przenoszę i nic nie piszę człowiekowi. Sprawdzenie rusza przy każdym starcie i kompaktowaniu sesji, a człowiek dostaje jedno zdanie na plik i miesiąc.
2. Czytam zgłoszony plik w całości i dzielę go na to, co przenieść, i to, co zostaje (sekcje niżej).
3. Przenoszę według sekcji „Dokąd i jak”.
4. Uruchamiam narzędzie jeszcze raz: `/home/obserwator/obserwator/narzedzia/porzadki-notatek.sh`.
5. Daję człowiekowi jedno zdanie po fakcie (sekcja „Zdanie dla człowieka”).

## Co przenieść

- Z dziennika (`notatki/dziennik/<RRRR-MM>.md`): zamknięte tematy, czyli sprawy, które się skończyły i nic w nich nie czeka na człowieka, Factory ani na mnie. Plik dawnego miesiąca, w którym wszystkie tematy są zamknięte, przenoszę w całości.
- Z pamięci (np. `notatki/obserwator-pamiec.md`): to, co już stoi w umowie (`/home/obserwator/obserwator/CLAUDE.md`) albo w mechanizmach Factory i serwera (skill, narzędzie, hak, test). Takiej notatki nie potrzebuję, bo umowę i mechanizm mam bez niej.

## Co zostawić

- Otwarte tematy: sprawy w toku i wszystko, na co ktoś jeszcze czeka.
- Prośby „nie zależy” z listy końcowej, w pełnej treści, aż do wysłania listy końcowej (umowa, „Lista końcowa”).
- Sumy SHA-256 plików bloków roota, zanim człowiek wkleił blok i zanim porównałem sumy po wklejeniu (umowa, „Polecenia roota”).
- Adresy makiet przy nazwie projektu albo zmiany.
- Poprzedni stan zmian w panelach usług (umowa, „Panele usług”).
- `MEMORY.md` (indeks notatek) i `notatki/porzadki-notatek.md`.
- Wszystko, czego jeszcze potrzebuję do pracy. Przy wątpliwości notatka zostaje.

## Dokąd i jak

- Archiwum notatek to `/home/obserwator/obserwator/archiwum-notatek/`. Roczna retencja go nie czyści: zadanie systemu usuwa tylko pliki z `/home/obserwator/obserwator/archiwum/`.
- Fragment trafia do pliku o tej samej ścieżce względnej co plik notatek, np. z `notatki/dziennik/2026-11.md` do `archiwum-notatek/dziennik/2026-11.md`. Brakujące foldery zakładam.
- W pliku archiwum dopisuję fragment na końcu, pod nagłówkiem `## Przeniesione <RRRR-MM-DD> z notatki/<ścieżka>`. Niczego w archiwum nie nadpisuję: nigdy `mv` ani zapis narzędziem Write na plik archiwum, który już jest.
- Z pliku notatek usuwam tylko to, co już stoi w archiwum. Plik dawnego miesiąca przenoszę w całości tak samo: całą jego treść dopisuję na końcu pliku archiwum o tej samej ścieżce, pod tym samym nagłówkiem, bo mogą tam już leżeć fragmenty przeniesione wcześniej. Dopiero potem usuwam plik notatek.
- Zapisuję i poprawiam pliki narzędziami plikowymi (Edit, Write na nowy plik), nie poleceniami powłoki.
- Wpis w `MEMORY.md`, który wskazuje przeniesiony plik albo temat, poprawiam: mówi, że treść jest w `archiwum-notatek/<ścieżka>`. Indeks nie może wskazywać pliku, którego nie ma.
- Wyjęcie z powrotem: kopiuję fragment z `archiwum-notatek/<ścieżka>` do `notatki/<ścieżka>`, w archiwum pod jego nagłówkiem dopisuję `Wyjęte z powrotem <RRRR-MM-DD>` i poprawiam wpis w `MEMORY.md`. Tak samo robię, gdy człowiek prosi o przywrócenie notatki.
- Notatek nie kasuję i nie kopiuję poza serwer.

## Zdanie dla człowieka

- Po przeniesieniu daję człowiekowi jedno zdanie: co przeniosłem, z którego pliku i dokąd. Przykład: „Przeniosłem do archiwum notatek zamknięte tematy z dziennika listopada (`notatki/dziennik/2026-11.md` → `/home/obserwator/obserwator/archiwum-notatek/dziennik/2026-11.md`); każdą notatkę mogę wyjąć z powrotem.”
- Przed przeniesieniem o nic nie pytam.
- Gdy narzędzie po przeniesieniu dalej zgłasza ten plik (np. bieżący dziennik z samymi otwartymi tematami), mówię to w tym samym zdaniu, z rozmiarem pliku. W `notatki/porzadki-notatek.md` zapisuję wtedy linię z tą ścieżką, dzisiejszą datą i rozmiarem w KB, zastępując poprzednią linię tego pliku. Krok 1 bierze ją przy następnym zgłoszeniu.
