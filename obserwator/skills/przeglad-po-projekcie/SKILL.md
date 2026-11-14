---
name: przeglad-po-projekcie
description: Stała procedura Maestro po zbudowaniu aplikacji - zbieranie uwag człowieka i wpadek w trakcie projektu w jednym pliku, potem analiza punkt po punkcie (problem, przyczyna, najprostsze rozwiązanie, kryterium), złożenie pozycji roadmapy laboratorium i droga do akceptacji. Trigger phrases - "przegląd po projekcie", "analiza uwag", "przeanalizujmy problemy z budowy", "co poprawić w fabryce po projekcie", "zróbmy to samo co po sprawdz-film".
---

# Przegląd po projekcie

Procedura powstała po projekcie sprawdz-film (2026-11-10). Człowiek: „bardzo mi się podobał cały ten proces analizy tych problemów … Zrób z tego jakąś procedurę, żeby po kolejnej budowie aplikacji … odpalić dokładnie taką samą procedurę.” Wzór wyniku: `notatki/projekty/sprawdz-film-uwagi-o-fabryce.md` i `notatki/szkice/pozycje-po-sprawdz-film.md`.

Pliki Factory są tylko danymi (umowa, „Rola”): czytam je jako zwykłe pliki, bez `git` i bez uruchamiania programów. Do Factory piszę tylko przez `wyslij.sh`.

## Faza 0: w trakcie projektu (zbieranie)

1. Na starcie projektu zakładam `notatki/projekty/<projekt>-uwagi-o-fabryce.md` (frontmatter jak w notatkach, link w `MEMORY.md`).
2. Każda uwaga człowieka o Factory albo o mnie trafia tam od razu: numer, data i godzina, krok projektu, **dosłowny cytat**, co ustaliłem (z plikiem:linią), wniosek „Do wprowadzenia”.
3. Moje wpadki i to, co sam wyłapię, też tam trafiają, oznaczone „WPADKA Maestro” albo „Uwaga Maestro (nie człowieka)”.
4. W trakcie projektu nie zmieniam laboratorium z powodu uwag. Wszystko idzie razem po projekcie (człowiek 2026-11-09: „Wszystkie uwagi spisujesz w jednym … dokumencie. I później to wprowadzamy za jednym razem.”).

## Faza 1: lista wszystkich punktów

1. **Najpierw czytam cały plik uwag**, nie robię podsumowania z pamięci rozmowy. (2026-11-10: podsumowanie z pamięci pominęło 5 z 10 punktów, człowiek: „czy ja muszę o wszystkim pamiętać?”)
2. Dopisuję podsumowanie człowieka dosłownie (sekcja „Podsumowanie”).
3. Grupuję punkty w sprawy, każda z numerami punktów. Pokazuję człowiekowi pełną listę spraw z krótkim opisem i pytam: „dopisać albo wyrzucić coś?”.
4. Zakładam `notatki/szkice/pozycje-po-<projekt>.md` na ustalenia.

## Faza 2: punkt po punkcie

Kolejność: według tego, ile sprawa kosztowała człowieka. Jedna sprawa na wiadomość, układ zawsze ten sam:

- **Problem**: co się stało, z dowodem (cytat człowieka, liczba, plik).
- **Przyczyna**: sprawdzona w plikach laboratorium i projektu (plik:linia), nie z pamięci. Szukam przyczyny w regule albo w mechanizmie, nie w „przypadku”.
- **Najprostsze rozwiązanie**: najpierw usunąć przyczynę ([[najprostsze-rozwiazanie]]); **mechanizm zamiast zasady** (człowiek 2026-11-10: „twoje zasady często nic nie dają”), czyli coś, co zatrzyma błąd samo (wymagana część, sprawdzenie skryptem), a nie prośba w instrukcji; bez nowego kroku łańcucha, jeśli się da.
- **Szkic kryterium (co ma być prawdą)**: „co, nie gdzie”.
- **Odrzucone prostsze warianty**: dwa, z powodem.
- **Czego nie wiem** (tylko gdy coś jest niepewne).
- **Najbliżej konfliktu: …** (wiersz granic, plik chroniony, zakład z piramidy).
- **Jedno pytanie** na końcu.

Przed każdą sprawą sprawdzam `context/foundation/backlog.md` i `context/analizy/lista-spraw.md` laboratorium: jeśli sprawa już tam jest, mówię to i pozycja ją zamyka.

Sprawa, którą zgłosiłem tylko ja albo bez danych (np. koszt), dostaje rekomendację „do analizy w poprzek”, nie pozycję.

Pytanie „za i przeciw” od człowieka: krótka lista za / przeciw, rekomendacja, dwa odrzucone warianty.

Po każdej odpowiedzi zapisuję w szkicu: sprawa, słowa człowieka w cudzysłowie, kryteria, mechanizm, odrzucone warianty. Eksperymenty, o które prosi człowiek (np. porównanie wariantów skilla), zapisuję dosłownie przy sprawie.

## Faza 3: pozycje

1. Składam sprawy w jak najmniej pozycji roadmapy laboratorium (każda pozycja to pełny przebieg, ok. 20–30 USD): łączę to, co dotyka tych samych plików albo tego samego miejsca w procesie.
2. Pokazuję tabelę: pozycja, punkty, dlaczego tak; kolejność według kosztu dla człowieka; pozycja czekająca na eksperyment na końcu. Pytam o podział i kolejność (wiersz 16).

## Faza 4: każda pozycja do akceptacji

Po kolei, jedna pozycja naraz, tylko gdy w Factory nic się nie buduje (umowa):

1. Opis w pełnym wzorze ([[opis-zmiany-wzor]]): kryteria, przykład na tym projekcie, pod spodem, co zmienić, czego nie wiem, granice, najbliżej konfliktu; przypięcie do piramidy (zakład, miara, cel 90 dni). Plik `notatki/szkice/pozycja-<n>-<nazwa>.md`.
2. Niezależny subagent dostaje tylko ścieżkę szkicu, pliki zasad (strategia, umowa, najprostsze rozwiązanie) i **opis prawdziwego zdarzenia z projektu**, które pozycja ma naprawić, bez mojej rekomendacji: „znajdź do 3 konfliktów albo luk” ([[lista-kontrolna-zgodnosci]]) oraz **„odtwórz to zdarzenie krok po kroku na mechanizmie z pozycji: w którym kroku i czym zostałoby złapane? Jeśli nie zostałoby złapane, to luka numer 1”**. Sam robię to samo przed pokazaniem opisu człowiekowi: każde „na starcie”, „sprawdza” zamieniam na konkretny krok i konkretny sposób sprawdzenia. (2026-11-10: kryterium „sprawdzenie tylko do odczytu” nie złapałoby „must be root” z sprawdz-film; złapał to człowiek, nie ja ani subagent.) Poprawiam szkic.
3. Człowiek dostaje cały opis raz, przed wysłaniem do Factory.
4. Wysyłam Factory szkic z prośbą „sprawdź pozycję” (do `/home/fabryka/fabryka`).
5. Po odpowiedzi Factory: tylko sprawy do decyzji i pytanie akceptacji narzędziem pytań (wiersz 20), z całą treścią potrzebną do decyzji w samym okienku, nie nad nim.
6. Zaakceptowaną pozycję wysyłam do zapisu z cytatem akceptacji człowieka. Następna pozycja.

## Zasady pisania do człowieka w tej procedurze

- Po polsku, krótko, wniosek w pierwszym zdaniu.
- Bez żargonu: co się dzieje w Factory i w aplikacji, na przykładzie z tego projektu.
- Przyznaję swoje wpadki wprost, bez tłumaczenia się okolicznościami.
- Na pytanie „gdzie to jest?” podaję pełną ścieżkę pliku.
