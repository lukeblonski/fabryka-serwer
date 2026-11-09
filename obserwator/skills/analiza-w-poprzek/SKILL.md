---
name: analiza-w-poprzek
description: Stała procedura analizy w poprzek zmian laboratorium fabryki, którą obserwator robi z człowiekiem co kilka zmian albo co tydzień - wsad od ostatniej analizy, liczby z scripts/pomiar.py przez sesję fabryki, status każdej sprawy z listy, stałe miary ze strategii, raport według wzoru i jedna wiadomość do zapisu w repo. Trigger phrases - "analiza w poprzek", "analiza zmian", "zrób analizę", "przegląd zmian laboratorium", "co wyszło z ostatnich zmian".
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
- Warunki „Kiedy wrócić” w `context/foundation/limitations.md`: które z nich spełniły się w zmianach od ostatniej analizy.
- Stałe miary i zakłady z `context/foundation/strategia.md`.

Analiza nie czyta backlogu (`context/foundation/backlog.md`). Pomysł zapisany tylko w backlogu nie trafia do raportu.

## Liczby

- Jedyne źródło liczb to `scripts/pomiar.py`. Obserwator nie uruchamia programów laboratorium i nie liczy liczb własnym skryptem; ten skill nie ma skryptu.
- Obserwator prosi sesję fabryki wiadomością do folderu `/home/fabryka/fabryka`, wysłaną narzędziem `/home/obserwator/obserwator/narzedzia/wyslij.sh` jak w umowie („Rozmowa z sesją główną”), o dwie rzeczy:
  - pełną tabelę z polecenia `python3 scripts/pomiar.py`;
  - listę folderów `context/archive/<RRRR-MM-DD>-<id>/` z datą od daty ostatniej analizy.
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
- Koszt: USD na zmianę i na oddaną aplikację, z nieudanymi podejściami.
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
## 5. Zakłady i ich miary
## 6. Zabezpieczenia i warunki „Kiedy wrócić”
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

1. Obserwator pokazuje człowiekowi wnioski i propozycje. Decyzje o propozycjach podejmuje człowiek; obserwator nie zapisuje decyzji za niego.
2. Po decyzjach obserwator wysyła sesji fabryki jedną wiadomość do folderu `/home/fabryka/fabryka` z:
   - raportem `poprzek-<RRRR-MM-DD>.md` w całości;
   - zmianami statusów spraw `lista-spraw.md` (numer sprawy, nowy status, dowód) i nowymi sprawami;
   - nową linią `spis.md`;
   - pozycjami backlogu albo roadmapy, które człowiek kazał dopisać albo zmienić (tylko te pozycje, nie całe pliki);
   - decyzjami człowieka jego słowami w cudzysłowie.
3. Cała wiadomość mieści się poniżej limitu tekstu skrzynki, 20 000 znaków (umowa, „Rozmowa z sesją główną”). Gdy się nie mieści, obserwator skraca raport, a nie dzieli wiadomość na kilka.
4. Zapis w repo robi sesja fabryki według sekcji „Zapis analizy w poprzek” w `docs/sesja-glowna.md`; obserwator nie pisze w repo fabryki. Sesji wolno zapisać tylko `context/analizy/`, `context/foundation/backlog.md` i `context/foundation/roadmap.md`; poprawka fabryki z analizy (instrukcje, skille, kod) idzie zwykłą zmianą po decyzji człowieka.
5. Gdy sesja odmówi zapisu, bo jej warunek nie jest spełniony, obserwator zachowuje wiadomość w swoich notatkach razem z nazwą zmiany albo przebiegu z odpowiedzi sesji. Wysyła ją ponownie, gdy ta zmiana zostanie scalona albo porzucona, i mówi człowiekowi, na co zapis czeka.
