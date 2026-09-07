# Pułapki

Spis błędów popełnionych przy budowie tego licznika w pierwszym tygodniu. Każdy jest
tu z ceną, którą zapłaciliśmy, i z sygnałem, który był w danych wcześniej, niż go
zauważyliśmy.

Wspólna cecha wszystkich: **dawały wynik wyglądający wiarygodnie**. Żaden nie zgłosił
się sam, żaden nie wywrócił niczego, przy żadnym nic nie świeciło na czerwono. Licznik
po prostu podawał liczbę, która była nieprawdziwa.

---

## 1. Literówka w nazwie domeny, która przez trzy dni oskarżała cudzą firmę

**Co się stało.** Weryfikacja przez odwrotny DNS sprawdza, czy nazwa hosta kończy się
domeną operatora. Dla Amazonbota mieliśmy wpisane `crawl.amazon.com` — domenę, która
**nie istnieje** (NXDOMAIN). Amazon dokumentuje `crawl.amazonbot.amazon`.

**Skutek.** Każde żądanie prawdziwego Amazonbota odpadało na kroku drugim i lądowało
w tabeli jako podszycie. Przez trzy doby publiczna strona pokazywała Amazonbota jako
**najczęściej podszywanego bota w całym zbiorze** — 24 fałszywe oskarżenia pod adresem
firmy, która robiła dokładnie to, co deklarowała.

**Sygnał był w danych od początku.** Metoda odwrotnego DNS miała bilans **zero
potwierdzeń na dwadzieścia pięć sprawdzeń**. Odnotowaliśmy to dzień wcześniej i opisali
tę metodę jako niesprawdzoną — ale zabrakło wniosku, że skoro jest niesprawdzona, to
jej „nie" też nie nadaje się do publikacji.

**Czego nie dało się naprawić.** Werdyktów nie dało się przeliczyć, bo **celowo nie
zapisujemy adresów IP** — bez adresu nie ma jak ponowić zapytania DNS. Zostały cofnięte
do „niesprawdzone".

**Zasada, która z tego wynika.** Zły sufiks nie powoduje błędu — powoduje, że każdy
prawdziwy bot danego operatora nie przechodzi weryfikacji. **Wpisuj do konfiguracji
wyłącznie domeny sprawdzone pełnym obiegiem**, ręcznie, przed pierwszym użyciem:

```
adres  ->  PTR  ->  nazwa hosta
nazwa  ->  A    ->  ten sam adres
```

Jeśli którykolwiek krok nie wychodzi, metoda dla tego operatora ma dawać
**„niesprawdzone", a nie „fałszywe"**. Brak metody to uczciwa odpowiedź. Zły sufiks to
zarzut wobec cudzej firmy postawiony na podstawie własnej literówki.

---

## 2. Pliki serwowane z pominięciem licznika, czyli zero, które nic nie znaczyło

**Co się stało.** `sitemap.xml` i `llms.txt` leżą fizycznie na dysku. Warstwa serwowania
plików statycznych (u nas Cloudflare Assets, u innych Nginx czy Apache) oddaje takie
pliki **zanim uruchomi się kod aplikacji**. Funkcja zapisująca wizytę nigdy się nie
wykonywała.

**Skutek.** Licznik pokazywał dla obu plików twarde zero. Odczytaliśmy to jako „nikt
tego nie pobiera" i wyciągnęliśmy wniosek, że `llms.txt` jest konwencją bez pokrycia.
**Wniosek był fałszywy — po prostu nie mieliśmy jak zobaczyć.**

**Jak sprawdzić u siebie.** Nie wystarczy wejść przeglądarką (patrz pułapka 4). Trzeba
sprawdzić, czy żądanie o plik statyczny w ogóle **dociera do Twojego kodu** — podglądem
na żywo (`wrangler tail`), logiem dostępowym serwera albo licznikiem w kodzie.

**Zasada.** Zanim uznasz zero za wynik, sprawdź, czy pomiar tego miejsca w ogóle jest
możliwy. Zero z niedziałającego licznika wygląda identycznie jak zero z braku ruchu.

---

## 3. Raport, który odsiewał dokładnie to, czego w nim szukaliśmy

**Co się stało.** Raport „co odwiedzali" filtruje `status = 200` i dwa typy ścieżek —
bo ma pokazywać czytaną treść, nie błędy. Szukaliśmy w nim żądań, które mogły
zakończyć się inaczej niż 200, i żądań o ścieżki spoza tych dwóch typów.

**Skutek.** Trzy razy w ciągu jednego dnia patrzyliśmy na zero i wyciągali wniosek
o braku ruchu — podczas gdy wiersze były w bazie, tylko poza filtrem. Za trzecim razem
mieliśmy próbę kontrolną (osobny licznik) i błąd wyszedł w kilkanaście sekund zamiast
po pół dnia.

**Zasada.** Do diagnostyki potrzebny jest **jeden widok bez żadnych filtrów**: ścieżka,
status, bot, godzina. Raporty publiczne mogą i powinny filtrować. Ten jeden nie.

---

## 4. Własny ruch odsiewany z raportów, czyli test, który wyglądał na nieudany

**Co się stało.** Licznik oznacza ruch właściciela (po numerze sieci i po znaczniku
w `User-Agent`) i **wszystkie raporty publiczne go odsiewają** — słusznie, bo inaczej
własne testy zawyżałyby statystyki.

**Skutek.** Sprawdzaliśmy działanie nowej funkcji, wysyłając żądanie z własnego łącza,
i szukali go w raporcie. Nie było. Wyglądało to na awarię zapisu; w rzeczywistości
zapis działał, a wiersz wypadał z raportu z definicji.

**Jak testować poprawnie.** Test różnicowy na liczniku, który **nie odsiewa** ruchu
własnego — u nas jest to osobna kolumna „testy właściciela". Odczyt przed, żądanie,
odczyt po. Przyrost o tyle, ile wysłano, dowodzi, że zapis działa.

---

## 5. Przekierowanie, które po cichu wyłączało treść dla botów

**Co się stało.** Reguły `301` przekierowywały `/x.html` na `/x` — sensownie, bo modele
budują adres z wzorca serwisu i pytały o nieistniejące pliki. Ale warstwa serwowania
plików stosuje przekierowania **przed** kodem aplikacji. Reguła serwująca botom pełną
treść pytała o `/x.html`, dostawała `301` zamiast `200` i po cichu rezygnowała.

**Skutek.** Piętnaście stron oddawało botom pustą skorupę aplikacji zamiast treści —
mimo że pliki z treścią istniały. Dodanie pliku nie pomagało; dopiero usunięcie reguły
przekierowania.

**Dodatkowo, pętla samopodtrzymująca się.** Skrypt audytujący sprawdzał, czy strona ma
wersję dla botów, **stosując najpierw przekierowania** — więc reguła `301` ukrywała
plik przed audytem, a audyt utrzymywał regułę.

**Zasada.** Kolejność warstw decyduje o wszystkim: przekierowania i pliki statyczne
działają przed Twoim kodem. Sprawdzaj efekt końcowy na produkcji, żądaniem
z zewnątrz — nie obecnością pliku na dysku.

---

## 6. Wnioski wyciągane z okna krótszego, niż się wydaje

**Co się stało.** Trzykrotnie odczytaliśmy zero jako „nie ma", gdy w rzeczywistości
oznaczało „mierzymy od dwóch godzin, a to zdarza się raz na dobę".

Skrajny przypadek: mapa serwisu. Google pobiera ją mniej więcej raz dziennie. Nasz
pomiar tego pliku działał od 2,7 godziny. Prawdopodobieństwo trafienia w to okno
wynosiło jakieś 11% — a zero traktowaliśmy jako informację.

**Zasada.** Zanim odczytasz zero, policz: **jak często to zdarzenie w ogóle zachodzi
i jak długi jest Twój pomiar**. Jeśli okno jest krótsze niż typowy odstęp między
zdarzeniami, zero nie znaczy nic.

To dotyczy także cudzych liczb. Wskaźnik z 80 dni i wskaźnik z 4 dni to nie są dwa
pomiary tej samej rzeczy.

---

## 7. Rzecz, której licznik nie zmierzy nigdy

Na koniec ograniczenie, które nie jest błędem, tylko granicą metody — i lepiej wiedzieć
o niej wcześnie.

**Jedno pobranie obsługuje wiele cytowań.** Zmierzyliśmy to: strona pobrana raz o 09:49
została zacytowana w trzech różnych rozmowach, dwóch ponad godzinę później, bez ani
jednego nowego żądania do serwera. Odpowiedzi podawały liczby zamrożone dokładnie na
godzinie pobrania.

**Więc liczba żądań w logu nie jest liczbą cytowań, tylko jej dolnym ograniczeniem** —
i to ograniczeniem nieznanej ostrości. Cytowanie zdarza się po stronie operatora modelu
i nie zostawia u Ciebie żadnego śladu.

Co gorsza, **część modeli w ogóle nie pobiera** — czyta z indeksu wyszukiwarki.
Sprawdziliśmy to bezpośrednio: cztery pliki wystawione pod publicznymi adresami,
i model, który nie wysłał po nie ani jednego żądania, tłumacząc to własnymi słowami:
„cache miss, wyszukiwarka nie ma jego kopii". Dla takiego modelu Twoja treść istnieje
tylko wtedy, gdy jest w indeksie — a Twój licznik nie zobaczy go nigdy.

**Ten licznik mierzy tych, którzy przychodzą.** O tych, którzy nie przychodzą, a mimo
to cytują, nie wie nic i wiedzieć nie może. Warto to napisać przy każdej publikowanej
liczbie, zanim ktoś zrobi to za Ciebie.
