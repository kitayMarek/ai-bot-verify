# Licznik botów AI z weryfikacją tożsamości

Nagłówek `User-Agent` to **deklaracja, nie dowód tożsamości**. Każdy może napisać, że
jest GPTBotem — zajmuje to jedną linijkę i nie wymaga żadnych uprawnień. Mimo to
większość liczników „ruchu AI" zlicza właśnie tę deklarację, bez sprawdzania.

Ten licznik sprawdza. Każde żądanie porównuje z listami adresów, które operatorzy
publikują właśnie po to, żeby dało się ich odróżnić od podszywek — i zapisuje wynik
razem z informacją, **którą metodą** go ustalono.

## Po co, skoro panel hostingu już to pokazuje

Bo panel liczy deklaracje. 3 września 2026 sprawdziliśmy, ile taki licznik jest wart:
dwa żądania wysłane zwykłym `curl` z domowego łącza, z nagłówkiem podającym się za
PerplexityBota, podniosły w panelu Cloudflare licznik „AI Answer retrievals" z 16 na 18.
**Żadne z nich nie przyszło od Perplexity.**

To nie jest zarzut o nieuczciwość — sprawdzenie tożsamości kosztuje zapytania sieciowe
przy każdym żądaniu, a przyjęcie deklaracji jest darmowe. Skutek jest jednak taki, że
licznik mierzy, co bot o sobie napisał, a nie kto naprawdę przyszedł.

## Co ten licznik robi inaczej niż inne

**Ma kategorię „nie wiem".** To jest najważniejsza różnica i jednocześnie
najtrudniejsza do sprzedania. Część operatorów nie publikuje ani list adresów, ani
niczego, co pozwoliłoby ich potwierdzić. Wrzucenie tych żądań do „prawdziwych"
zawyżyłoby wynik, a do „podrobionych" — byłoby oskarżeniem bez dowodu. Zostają osobno.
Bez tej kolumny pozostałe liczby nic nie znaczą.

**Zapisuje metodę rozstrzygnięcia.** Nie tylko „prawdziwy / fałszywy", ale też czym to
ustalono: listą adresów operatora, numerem sieci, odwrotnym DNS-em. Dzięki temu da się
później wycofać werdykty jednej metody, gdy okaże się błędna — a okaże się (patrz
[docs/pulapki.md](docs/pulapki.md), sekcja o Amazonie).

**Liczy ruch, który nie przedstawia się wcale.** Puste pole `User-Agent` albo nazwa
spoza wszystkich list. Stoi osobno, poza procentami — bo nigdy nie złożył deklaracji,
której można by nie uwierzyć. Bez tego nie zobaczylibyśmy, że jeden z dużych modeli
chodzi po sieci bez rozpoznawalnego podpisu.

**Nie zapisuje adresów IP.** Do rozpoznania podszywacza wystarczy numer sieci i kraj —
jedno i drugie opisuje serwerownię, nie człowieka. Adres służy wyłącznie do porównania
z listą i nigdzie nie trafia. Kosztuje to jedną rzecz: błędnych werdyktów nie da się
potem przeliczyć, bo nie ma po czym. Uznaliśmy to za cenę wartą zapłacenia.

## Wyniki z jednej niewielkiej strony

Portal o serowarstwie domowym, cztery dni pomiaru:

| | |
|---|---|
| żądań ogółem | 1025 |
| prawdziwych | 457 |
| podrobionych | 288 |
| nierozstrzygalnych | 280 |
| **prawdziwych wśród rozstrzygniętych** | **61,3%** |
| **prawdziwych licząc wszystko** | **44,6%** |
| różnych tożsamości botów | 20 |
| różnych sieci | 16 |
| ruch bez żadnej deklaracji | 18 |

**To nie jest próba reprezentatywna dla internetu** i nie udajemy, że jest. Wartość tych
danych bierze się z czegoś innego: każde żądanie sprawdzono tą samą, opisaną metodą,
a wynik — łącznie z tym, czego nie umieliśmy rozstrzygnąć — podano w całości.

Proporcje zależą mocno od tego, jaką masz stronę. Na domenie, którą prawdziwe crawlery
odwiedzają od miesięcy, podszywki topią się w masie autentycznego ruchu; na małej i
młodej — dominują. Niezależne badanie
[Jakuba Sawy](https://www.jakubsawa.pl/twoj-raport-ruchu-z-ai-klamie-sprawdzilem-ile-z-botow-perplexity-to-naprawde-perplexity/)
(28 sierpnia 2026, ta sama metoda, 80 dni pomiaru) dało ten sam mechanizm i inne
proporcje. Obie liczby są prawdziwe — różni je mianownik.

## Jak to działa

Trzy drogi weryfikacji, w kolejności pewności:

1. **Lista adresów operatora.** Najpewniejsza. OpenAI, Anthropic, Perplexity, Google
   i Microsoft publikują pliki z zakresami, z których wychodzą ich boty. Wynik jest
   jednoznaczny w obie strony.
2. **Numer sieci (ASN).** Dla operatorów, którzy listy nie publikują, ale mają własną,
   znaną sieć. Słabsze, bo sieć bywa duża — wciąż rozstrzygające przy nazwach, których
   nikt inny nie ma prawa używać.
3. **Odwrotny DNS w trzech krokach (FCrDNS).** Dla reszty. **Pominięcie któregokolwiek
   z trzech kroków czyni metodę bezwartościową** — szczegóły i nasz kosztowny błąd
   w [docs/pulapki.md](docs/pulapki.md).

Wszystkie trzy odpowiadają na pytanie **czyja to maszyna** — i na żadne inne.
Nie mówią, kto o to poprosił ani po co: z tego samego potwierdzonego zakresu
przychodzi crawler budujący indeks i agent robiący to, co ktoś obcy wpisał w okno
czatu. `zweryfikowany = true` znaczy „nie podszywa się", nigdy „bezpieczny".

Osobno odnotowywana jest obecność nagłówków podpisu kryptograficznego (Web Bot Auth).
Na razie **tylko odnotowywana, bez walidacji** — więc to nie jest weryfikacja i nie
liczy się jako taka.

## Uruchomienie

Wymaga: Cloudflare Workers i bazy PostgreSQL (u nas Supabase, ale liczy się tylko
dostęp REST-owy).

```bash
# 1. baza
psql < sql/01-tabela.sql
psql < sql/02-klasyfikacja.sql   # <- najpierw przeczytaj, wymaga konfiguracji
psql < sql/03-widoki.sql
psql < sql/04-raporty.sql

# 2. worker
cp worker/wizyty-botow.js  <twoj-projekt>/worker/
# wywołaj zapiszWizyteBota() z ctx.waitUntil() — przykład w worker/przyklad.js

# 3. testy
node test/test.mjs
```

**Zanim uruchomisz, przeczytaj [docs/konfiguracja.md](docs/konfiguracja.md).** Trzy
rzeczy trzeba ustawić pod siebie, a jedna z nich (ścieżka pułapki) traci sens, jeśli
zostawisz naszą.

## Zanim uwierzysz własnym liczbom

[docs/pulapki.md](docs/pulapki.md) to spis naszych błędów z pierwszego tygodnia, każdy
z ceną, którą zapłaciliśmy. Nie jest to ozdobnik — **żadna z nich nie zgłosiła się
sama, a większość dawała wynik wyglądający całkowicie wiarygodnie**:

- weryfikacja z literówką w nazwie domeny, przez trzy dni publicznie oskarżająca cudzą
  firmę o podszywanie się pod samą siebie,
- pliki serwowane z pominięciem licznika, dające twarde zero odczytane jako „nikt tego
  nie pobiera",
- raport filtrujący `status = 200`, w którym szukaliśmy żądań zakończonych inaczej,
- ruch własny odsiewany z raportów — i test, który przez to wyglądał na nieudany,
- test przez model, który **zafałszował mierzony wynik**: zapytaliśmy trzy modele
  o zawartość `llms.txt`, każdy po niego poszedł, i trzy z czterech pobrań tego pliku
  okazały się nasze własne. Odsiew ruchu własnego tego nie łapie, bo model przychodzi
  ze swojej sieci — im więcej testujesz, tym bardziej dane potwierdzają to, co testujesz.
- filtr chroniący prywatność („nie logujemy ludzi"), który ukrył **całą klasę
  ruchu**: model w trybie agenta dosłownie używa przeglądarki, więc wysyłał nagłówki
  przeglądarki i wypadał z licznika, zanim cokolwiek sprawdziło, skąd przyszedł.

Jeśli masz wziąć z tego repozytorium jedną rzecz, weź tę: **każdy pomiar botów wymaga
próby kontrolnej**, bo inaczej nie odróżnisz „nie przyszli" od „nie umiemy zobaczyć".

## Licencja

MIT. Dane, które sam zbierzesz, są Twoje.

Jeśli opublikujesz wyniki, podaj okres pomiaru i wielkość próby razem z liczbą — bez
tego procent jest nie do odtworzenia, a w tej dziedzinie to jest cały problem.
