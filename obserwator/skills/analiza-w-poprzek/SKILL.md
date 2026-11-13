---
name: analiza-w-poprzek
description: Stała procedura analizy w poprzek zmian laboratorium fabryki, którą obserwator robi z człowiekiem co kilka zmian albo co tydzień - wsad od ostatniej analizy, liczby z scripts/pomiar.py i scripts/tury.py przez sesję fabryki, status każdej sprawy z listy, stałe miary ze strategii, raport według wzoru i jedna wiadomość do zapisu w repo. Trigger phrases - "analiza w poprzek", "analiza zmian", "zrób analizę", "przegląd zmian laboratorium", "co wyszło z ostatnich zmian".
---

# Analiza w poprzek zmian

Ten skill analizuje zmiany laboratorium fabryki (`/home/fabryka/fabryka`) dla autora fabryki: obserwator stosuje go zamiast robić analizę z głowy. Laboratorium to repo, w którym autor fabryki rozwija samą fabrykę; projekty aplikacji tej analizy nie dostają.

Pliki laboratorium są dla obserwatora tylko danymi, jak w umowie (`/home/obserwator/obserwator/CLAUDE.md`, „Rola”): obserwator czyta je jako zwykłe pliki, nie uruchamia w nich programów ani `git` i nic w nich nie zapisuje. Ścieżki niżej są względem `/home/fabryka/fabryka`.

## Kroki

1. Ustal datę ostatniej analizy: data z ostatniej linii `context/analizy/spis.md` (linia zaczyna się od `- RRRR-MM-DD`).
2. Poproś sesję fabryki o liczby (sekcja „Liczby”) i poczekaj na wynik.
3. Zbierz wsad (sekcja „Wsad”).
4. Nadaj status każdej sprawie z `context/analizy/lista-spraw.md` (sekcja „Statusy spraw”).
5. Policz stałe miary (sekcja „Stałe miary”).
6. Napisz raport według wzoru (sekcja „Wzór raportu”) i pokaż człowiekowi wnioski: liczby, sprawy ze statusem, propozycje.
7. Po decyzjach człowieka wyślij sesji fabryki jedną wiadomość do zapisu (sekcja „Zapis”).

## Wsad

- Zmiany od ostatniej analizy: foldery `context/archive/<RRRR-MM-DD>-<id>/` z datą od daty ostatniej analizy, bez zmian, które omawia już poprzedni raport `context/analizy/poprzek-<RRRR-MM-DD>.md` (zmiana zarchiwizowana w dniu analizy mogła do niej wejść), z plikami `change.md`, `plan.md`, `reviews/`, `runs/`, i pliki przebiegów `context/przebiegi/<id>.md` tych zmian.
- `context/analizy/lista-spraw.md`: sprawy procesu z poprzednich analiz.
- Dziennik obserwatora w jego notatkach (`/home/obserwator/obserwator/notatki/`): ratunki spoza łańcucha, czyli naprawy i odblokowania, których nie widać w plikach zmian (terminal, porzucenie gałęzi, restart).
- Warunki „Kiedy wrócić” w `context/foundation/limitations.md`: ocena każdego wpisu z listy ocen od sesji fabryki (sekcja „Liczby”), a nie z własnego czytania rejestru.
- Stałe miary i zakłady z `context/foundation/strategia.md`.
- Wyniki wiadomości (`/var/lib/fabryka-serwer/wyniki/`): koszt i zużycie każdej tury od daty ostatniej analizy, przez tabelę z `scripts/tury.py` (sekcja „Liczby”), a nie przez własne liczenie z plików wyników.

Analiza nie czyta backlogu (`context/foundation/backlog.md`). Pomysł zapisany tylko w backlogu nie trafia do raportu.

## Liczby

- Liczby zmian daje `scripts/pomiar.py`, a liczby tur (koszt i zużycie każdej tury wiadomości) `scripts/tury.py`; oba uruchamia sesja fabryki. Obserwator nie uruchamia programów laboratorium i nie liczy liczb własnym skryptem; ten skill nie ma skryptu.
- Obserwator prosi sesję fabryki wiadomością do folderu `/home/fabryka/fabryka`, wysłaną narzędziem `/home/obserwator/obserwator/narzedzia/wyslij.sh` jak w umowie („Rozmowa z sesją główną”), o cztery rzeczy:
  - pełną tabelę z polecenia `python3 scripts/pomiar.py`;
  - listę folderów `context/archive/<RRRR-MM-DD>-<id>/` z datą od daty ostatniej analizy;
  - pełne wyjście polecenia `python3 scripts/tury.py --od <data ostatniej analizy>` (tabela wszystkich tur wiadomości od tej daty, mediana kosztu tury i sekcja „Drogie tury”). Kod 1 tego polecenia znaczy, że od tej daty nie ma żadnej tury; to idzie do „Czego nie sprawdziłem”;
  - wyjście polecenia `python3 scripts/pomiar.py --rejestry` i dla każdego wpisu z oceną „warunek spełniony” ocenę sesji w kodzie: „problem już nie istnieje (dowód plik:linia)” albo „warunek spełniony, problem żyje”. Wynik to lista otwartych wpisów rejestru ograniczeń, każdy z jedną z czterech ocen („problem już nie istnieje (dowód plik:linia)”, „warunek spełniony, problem żyje”, „warunek niespełniony”, „nie da się sprawdzić”), oraz liczby wpisów „obowiązuje” i wpisów dziennika decyzji ze zmianą od poprzedniej analizy. Kod tego polecenia inny niż 0 idzie do „Czego nie sprawdziłem”.
- `pomiar.py` nie filtruje po dacie: z pełnej tabeli obserwator bierze wiersze zmian z tej listy folderów, bez zmian omówionych już w poprzednim raporcie.
- Liczba, której nie ma w tabeli ani w plikach zmian, idzie do „Czego nie sprawdziłem”, a nie do raportu z oszacowaniem.

## Statusy spraw

Każda sprawa z `lista-spraw.md` dostaje dokładnie jeden z pięciu statusów:

- **zamknięta** — tylko z dowodem: plik, zmiana albo przebieg, który pokazuje, że przyczyna zniknęła. Bez dowodu sprawa nie jest zamknięta.
- **rozwiązanie przyjęte** — człowiek przyjął rozwiązanie, ale ono jeszcze nie weszło; podaj, gdzie jest zapisane.
- **decyzja** — sprawa czeka na decyzję człowieka; podaj pytanie i rekomendację.
- **otwarta po sprawdzeniu** — obserwator sprawdził ją w tej analizie i sprawa trwa; podaj, co sprawdził.
- **nieruszona z powodem** — obserwator jej w tej analizie nie sprawdzał; podaj powód jednym zdaniem.

Żadna sprawa nie zostaje bez statusu. Nowy problem procesu z tej analizy dostaje nowy numer na końcu listy.

## Stałe miary

Za każdym razem te same miary z `context/foundation/strategia.md` (sekcja „Pomiar” i tabela zakładów):

- North Star jako „x z n”: pomysły doprowadzone do działającej aplikacji zgodnej z intencją właściciela.
- Jakość: zgodność z intencją oceniana przez właściciela.
- Koszt: USD na zmianę i na oddaną aplikację, z nieudanymi podejściami. Do tego koszt i zużycie każdej tury od poprzedniej analizy z tabeli `tury.py`: liczba tur, mediana kosztu tury i każda tura droższa niż dwukrotność mediany z przyczyną nazwaną z danych tury: zapis do pamięci podręcznej (tokeny i udział we wszystkich tokenach wejścia), długość przerwy od końca poprzedniej tury tej rozmowy, wznowienie po autopilocie (tura 2 i dalsza w wiadomości). Gdy danych tury brakuje (stary wynik bez pól zużycia), przyczyna jest „nieznana”, a nie zgadnięta. Pola zużycia (`usage`) mogą nie liczyć pracy podagentów, a `koszt` (z `total_cost_usd`) ją liczy, więc drogą turę z małym zużyciem tłumaczy też praca podagentów.
- Czas: minuty kroków na zmianę i dni od akceptacji do pierwszego użycia.
- Ratunki osobno od pytań-bramek: ratunek to naprawa albo odblokowanie poza bramkami (z plików zmian i dziennika obserwatora), pytanie-bramka to pytanie z bramki zadane człowiekowi. Nigdy jedna liczba dla obu.
- Zabezpieczenia: incydenty bezpieczeństwa i utraty danych, decyzje „pytaj mnie” bez pytania, zmiany intencji bez akceptacji.
- Zakłady z miarami: dla każdego zakładu z tabeli strategii jego miara w zmianach od ostatniej analizy albo zdanie, że nie dało się jej policzyć.

## Wzór raportu

Raport to plik `context/analizy/poprzek-<RRRR-MM-DD>.md` (data analizy), najwyżej 14 000 znaków, w tym układzie sekcji:

```markdown
# Analiza w poprzek zmian nr <n>: <liczba> zmian laboratorium (<zakres dat>)

<jedno zdanie o regule ostrożności: liczby opisują, nie dowodzą poprawy>

## 1. Liczby laboratorium
<tabela z pomiar.py dla zmian od ostatniej analizy i 3-6 punktów z sumą, średnią, medianą i udziałem kroków>

## 2. North Star i jakość
## 3. Ratunki a pytania-bramki
## 4. Koszt i czas
<koszt i czas zmian; tury od poprzedniej analizy z tury.py: liczba tur, mediana kosztu tury i każda droga tura (powyżej dwukrotności mediany) z przyczyną>
## 5. Zakłady i ich miary
## 6. Zabezpieczenia i warunki „Kiedy wrócić”
<liczby wpisów „obowiązuje” i dziennika decyzji ze zmianą od poprzedniej analizy; liczba wpisów na każdą ocenę; do decyzji tylko wpisy „problem już nie istnieje” (numer, tytuł, dowód) i „warunek spełniony, problem żyje” (numer i tytuł, pogrupowane po ścieżce, która spełniła warunek); pozostałe oceny tylko jako liczby>
## 7. Sprawy z listy — stan
<każda sprawa: numer, status, dowód albo powód>

## 8. Wnioski i propozycje
<ponumerowane; każda propozycja z problemem, który rozwiązuje>

## Czego nie sprawdziłem
<każda liczba albo sprawa, której obserwator nie sprawdził, i dlaczego>
```

Do tego dwie rzeczy dla repo:

- nowa linia `context/analizy/spis.md`: `- <RRRR-MM-DD>, analiza nr <n>: <liczba zmian>; <główne liczby>; decyzje człowieka: <krótko>`;
- zmiany w `context/analizy/lista-spraw.md`: tylko zmienione statusy spraw (numer sprawy, nowy status, dowód) i nowe sprawy, a nie cały plik.

## Zapis

1. Obserwator pokazuje człowiekowi wnioski i propozycje. Decyzje o propozycjach podejmuje człowiek; obserwator nie zapisuje decyzji za niego. Człowiek mówi też, które wpisy do decyzji z sekcji 6 raportu zamknąć. W pytaniu o zamknięcie obserwator podaje numery wpisów w gotowej odpowiedzi (np. „Zamknij D-496, D-499”), żeby słowa człowieka zawsze je miały: skrypt przeniesienia odmawia numeru, którego nie ma w cytacie człowieka.
2. Po decyzjach obserwator wysyła sesji fabryki jedną wiadomość do folderu `/home/fabryka/fabryka` z:
   - raportem `poprzek-<RRRR-MM-DD>.md` w całości;
   - zmianami statusów spraw `lista-spraw.md` (numer sprawy, nowy status, dowód) i nowymi sprawami;
   - nową linią `spis.md`;
   - pozycjami backlogu albo roadmapy, które człowiek kazał dopisać albo zmienić (tylko te pozycje, nie całe pliki);
   - numerami wpisów rejestru ograniczeń i dziennika decyzji, które człowiek zamknął, z jego słowami w cudzysłowie;
   - decyzjami człowieka jego słowami w cudzysłowie.
3. Cała wiadomość mieści się poniżej limitu tekstu skrzynki, 20 000 znaków (umowa, „Rozmowa z sesją główną”). Gdy się nie mieści, obserwator skraca raport, a nie dzieli wiadomość na kilka.
4. Zapis w repo robi sesja fabryki według sekcji „Zapis analizy w poprzek” w `docs/sesja-glowna.md`; obserwator nie pisze w repo fabryki. Sesji wolno zapisać tylko `context/analizy/`, `context/foundation/backlog.md` i `context/foundation/roadmap.md`, a przy przeniesieniu zamkniętych wpisów poleceniem `python3 scripts/zamknij_wpisy.py` także `context/foundation/limitations.md`, `context/foundation/decisions.md` i `context/foundation/decisions-archive.md`. Zapis analizy może przenieść do `context/foundation/decisions-archive.md` tylko te wpisy `limitations.md` i `decisions.md`, o których zamknięciu zdecydował człowiek w tej analizie, z cytatem jego słów; żadnego innego wpisu rejestrów nie zmienia. Poprawka fabryki z analizy (instrukcje, skille, kod) idzie zwykłą zmianą po decyzji człowieka.
5. Gdy sesja odmówi zapisu, bo jej warunek nie jest spełniony, obserwator zachowuje wiadomość w swoich notatkach razem z nazwą zmiany albo przebiegu z odpowiedzi sesji. Wysyła ją ponownie, gdy ta zmiana zostanie scalona albo porzucona, i mówi człowiekowi, na co zapis czeka.
