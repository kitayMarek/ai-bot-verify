# Plan rozwoju

Stan dokumentu: propozycje do przeglądu  
Ostatnia aktualizacja: 12 września 2026

Ten dokument opisuje możliwy dalszy rozwój projektu. Nie oznacza, że wymienione
funkcje są już wdrożone.

Najważniejsza zasada pozostaje bez zmian:

> User-Agent jest deklaracją, a nie dowodem. Projekt weryfikuje prawo do użycia
> deklarowanej tożsamości; nie próbuje zgadywać, czy dowolny klient „jest AI”
> ani w jakim celu pobiera treść.

## Kierunek projektu

Najtrafniejsze pozycjonowanie:

**niezależny audyt tożsamości crawlerów i agentów AI**

Określenie „wykrywacz botów AI” jest zbyt szerokie. Narzędzie potrafi dobrze
odpowiedzieć na pytanie:

> Czy klient podający się za bota X pochodzi z infrastruktury operatora X?

Nie zawsze może natomiast rozstrzygnąć, czy niepodpisany ruch pochodzi od
człowieka, zwykłej automatyzacji czy modelu.

## Co należy zachować

- wynik trójwartościowy: `true`, `false`, `null`;
- oddzielenie deklarowanej nazwy od dowodu;
- zapis metody weryfikacji;
- poprawny, trzyetapowy FCrDNS;
- obsługę IPv4 i IPv6;
- oficjalne listy prefiksów jako podstawowy dowód sieciowy;
- brak trwałego zapisu adresów IP;
- osobne oznaczenie testów właściciela;
- jawne podawanie okresu pomiaru, liczebności próby i obu mianowników;
- opis błędów i pułapek pomiarowych;
- zasadę, że awaria sprawdzenia daje „nie wiadomo”, a nie „fałszywy”.

## P0 — odtwarzalne wdrożenie

### Jedno źródło prawdy

Docelowo repozytorium powinno zawierać albo jednoznacznie wskazywać:

- kompletny punkt wejścia Workera;
- przykładową konfigurację `wrangler.jsonc` bez sekretów i danych konkretnej
  domeny;
- wszystkie migracje SQL wymagane przez aplikację;
- wersję kodu widoczną w logach diagnostycznych;
- jeden opisany proces wdrożenia i wycofania wersji.

Wzorce używane do routingu i klasyfikacji powinny pochodzić ze wspólnego modułu,
aby dwie listy rozpoznawanych botów nie mogły się rozjechać.

Kryterium akceptacji: nowa osoba potrafi sklonować repozytorium, skonfigurować
własne środowisko według dokumentacji i odtworzyć działający licznik.

### Migracje zamiast ręcznych zmian

- Każda zmiana tabeli, funkcji, widoku, indeksu lub uprawnienia powinna otrzymać
  osobną, numerowaną migrację.
- Wdrożonych migracji nie należy przepisywać; poprawki powinny powstawać jako
  kolejne pliki.
- Migracje powinny być testowane na pustej bazie oraz przy ponownym uruchomieniu.
- Warto dodać kontrolę zgodności wymaganych obiektów bazy ze stanem repozytorium.

### Granica uprawnień

Dla publicznych raportów warto stosować wąską i testowalną granicę:

1. kontrolowana funkcja zwraca wyłącznie dozwolone agregaty;
2. funkcja ma ustalony `search_path`, kwalifikowane nazwy obiektów i nie używa
   dynamicznego SQL;
3. `PUBLIC` nie otrzymuje domyślnie prawa wykonania;
4. uprawnienia dostają wyłącznie wymagane role;
5. surowa tabela nie jest dostępna publicznie;
6. testy uruchamiane jako role anonimowa i zalogowana potwierdzają oczekiwany
   dostęp.

Nie należy hurtowo przełączać wszystkich widoków na `security_invoker`.
Widok agregujący prywatną tabelę może wtedy przestać działać dla użytkownika
anonimowego. Każdy przypadek wymaga testu.

### Zamknięte parametry raportów

- Publiczne funkcje raportowe powinny przyjmować tylko udokumentowane wartości.
- Nieznana wartość nie powinna niejawnie uruchamiać najdroższego wariantu.
- Każdy raport powinien mieć ograniczony wynik i korzystać z indeksu po czasie.
- Dla publicznych wywołań warto przewidzieć ograniczenie częstotliwości.

## P1 — mocniejszy dowód tożsamości

### Pełna walidacja Web Bot Auth

Obecność nagłówków podpisu nie jest dowodem poprawności podpisu. Bieżące pole
informujące o ich obecności warto zachować jako sygnał historyczny, ale nie należy
wliczać go do zweryfikowanych żądań.

Docelowa implementacja powinna:

- bezpiecznie parsować `Signature-Agent`, `Signature-Input` i `Signature`;
- akceptować wyłącznie katalog kluczy dostępny przez HTTPS;
- pobierać i sprawdzać katalog/JWKS;
- weryfikować kryptograficzny podpis żądania;
- sprawdzać `created`, `expires`, `keyid`, algorytm oraz
  `tag="web-bot-auth"`;
- obsługiwać rotację kluczy i ograniczony czas cache;
- traktować błąd sieci jako `unknown`, nie `false`;
- zabezpieczać pobieranie katalogu przed SSRF, nadmiernymi przekierowaniami,
  dużą odpowiedzią i przekroczeniem czasu;
- ograniczać ryzyko powtórzenia żądania krótkim czasem `expires`.

Implementację lepiej oprzeć na utrzymywanej bibliotece niż pisać własny parser
podpisów HTTP. Aktualny opis integracji i wskazanie biblioteki TypeScript:
https://developers.cloudflare.com/bots/reference/bot-verification/web-bot-auth/

Minimalne testy akceptacyjne:

- poprawny podpis;
- zły podpis;
- nieznany klucz;
- podpis wygasły;
- zmieniona ścieżka lub authority;
- błędny katalog kluczy;
- próba SSRF;
- timeout;
- rotacja klucza.

### Siła dowodu

Obecny wynik logiczny warto zachować dla kompatybilności, ale uzupełnić go
o siłę i pochodzenie dowodu.

| Poziom | Dowód | Znaczenie |
|---|---|---|
| A | zweryfikowany Web Bot Auth | dowód kryptograficzny |
| B | oficjalna lista adresów operatora | silny dowód sieciowy |
| C | pełny FCrDNS | potwierdzona delegacja DNS |
| D | ASN operatora | szerszy i słabszy sygnał sieciowy |
| E | tylko User-Agent | niepotwierdzona deklaracja |
| ? | błąd lub brak metody | brak podstaw do werdyktu |

Proponowane pola:

- `evidence_type`;
- `assurance_level`;
- `evidence_source`;
- `verifier_version`;
- `verified_at`;
- `source_fetched_at`.

Poziom dowodu nie zastępuje wyniku. Silny dowód może potwierdzić lub zaprzeczyć
deklaracji, natomiast brak kompletnego źródła powinien nadal dawać `null`.

### Wersjonowanie reguł i źródeł

- Każdy zestaw reguł klasyfikacji powinien mieć wersję.
- Należy zapisywać czas ostatniego poprawnego pobrania źródła.
- Pusta, nieosiągalna lub zmieniona formatem lista powinna generować sygnał
  diagnostyczny.
- Warto zachować ostatni poprawny snapshot zamiast zastępować go pustą listą.
- Musi istnieć możliwość cofnięcia wyników konkretnej wadliwej metody lub wersji
  do `null`.
- Awaria źródła nigdy nie może automatycznie oznaczać podszycia.

## P1 — testy i jakość

### Macierz testów regresyjnych

#### IPv4

- początek i koniec prefiksu;
- adres tuż poza prefiksem;
- maski `/0` i `/32`;
- błędny adres i CIDR.

#### IPv6

- zapis pełny i skrócony;
- adres mieszany IPv4;
- maski `/0` i `/128`;
- brak listy IPv6 dla operatora;
- błędny adres.

#### Źródła operatorów

- poprawna odpowiedź;
- częściowa awaria kilku źródeł;
- wszystkie źródła puste;
- niepoprawny JSON;
- timeout;
- przekierowanie;
- zmiana formatu.

#### FCrDNS

- poprawny PTR oraz A/AAAA;
- PTR bez potwierdzenia w przód;
- nieprawidłowy sufiks;
- wiele odpowiedzi;
- końcowa kropka w nazwie;
- timeout DNS.

#### Klasyfikacja i prywatność

- kolejność nakładających się User-Agentów;
- różna wielkość liter;
- pusty i przeglądarkowy User-Agent;
- zgodny, niezgodny i brakujący ASN;
- payload zapisu nie zawiera IP ani sekretów;
- publiczne raporty nie ujawniają surowych ścieżek;
- test kontrolny zwiększa właściwy licznik dokładnie o oczekiwaną wartość.

Testy jednostkowe powinny używać mockowanych odpowiedzi sieciowych. Niewielki,
osobny zestaw testów integracyjnych może okresowo kontrolować prawdziwe źródła,
ale chwilowa awaria cudzej strony nie powinna blokować każdego commita.

### Automatyczna kontrola przed scaleniem

CI powinno uruchamiać:

- testy Node;
- lint i formatowanie;
- test migracji SQL;
- test uprawnień publicznych;
- skan sekretów;
- kontrolę, że kod nie zapisuje i nie loguje adresu IP;
- kontrolę wspólnego źródła wzorców routingu i klasyfikacji.

## P2 — obserwowalność

Logi powinny pozwalać przypisać operację do jednej wersji kodu bez ujawniania
sekretów lub danych osobowych.

Przydatne pola:

- losowy `request_id`;
- `deployment_id` albo `app_version`;
- nazwa operacji;
- status usługi zewnętrznej;
- metoda weryfikacji;
- czas wykonania;
- liczba prób;
- kategoria błędu.

Nie logować pełnego klucza, jego początku/końca, adresu IP ani tajnej ścieżki
kanarkowej. Jeżeli potrzebny jest identyfikator konfiguracji, powinien być
nieodwracalny i niewystarczający do odtworzenia sekretu.

Warto dodać alerty na:

- nagły wzrost odrzuconych zapisów;
- wielokrotny zapis jednego `request_id`;
- długo nieodświeżane źródło;
- pustą listę operatora;
- metodę mającą wiele zaprzeczeń i zero potwierdzeń;
- nietypowy wzrost kategorii `unknown`.

## P2 — uczciwe raportowanie

Każdy publiczny wynik powinien pokazywać razem:

- okres pomiaru i czas aktualizacji;
- liczebność próby;
- potwierdzone, zaprzeczone i nierozstrzygalne;
- procent wśród rozstrzygniętych oraz procent całości;
- użyte metody i wersję klasyfikatora;
- informację, że próbka jednej witryny nie reprezentuje internetu;
- informację, że „zweryfikowany” nie oznacza „bezpieczny” ani nie ujawnia celu
  pobrania treści.

Nie publikować pełnych ścieżek skanowanych zasobów ani tajnej ścieżki
kanarkowej.

## P2 — projekt gotowy do użycia przez innych

- Dodać kompletny, minimalny Worker, nie tylko fragment integracji.
- Dostarczyć przykładową konfigurację bez domen i sekretów.
- Dodać checklistę instalacji, aktualizacji i usuwania.
- Opisać limity oraz spodziewane koszty zapytań.
- Określić publiczne API modułu i zasady kompatybilności.
- Publikację paczki rozważyć dopiero po ustabilizowaniu API i testów.

## Proponowana kolejność

1. Odtwarzalne wdrożenie i migracje.
2. Testy granicy uprawnień.
3. Wspólne źródło konfiguracji botów.
4. Wersjonowanie reguł i źródeł.
5. Model siły dowodu.
6. Walidacja Web Bot Auth.
7. Automatyczne CI.
8. Kompletne wdrożenie przykładowe.
9. Dopiero potem nowe raporty i kolejni operatorzy.

## Czego nie robić automatycznie

- Nie zmieniać `null` na `false` po błędzie sprawdzenia.
- Nie uznawać obecności nagłówka za poprawny podpis.
- Nie przypisywać całego ASN dostawcy chmurowego do jednego operatora.
- Nie przełączać wszystkich widoków na `security_invoker` bez testów ról.
- Nie umieszczać klucza serwisowego w kodzie klienta ani repozytorium.
- Nie dodawać trwałego IP wyłącznie dla łatwiejszego debugowania.
- Nie rozbudowywać raportów przed zapewnieniem odtwarzalności metodologii.

## Definicja ukończenia najbliższego etapu

Etap można uznać za zakończony, gdy:

- kod i schemat dają się odtworzyć z repozytorium;
- jedno kontrolowane żądanie daje jeden oczekiwany zapis;
- użytkownik publiczny widzi agregaty, ale nie surowe dane;
- klasyfikacja przechowuje wynik, metodę, wersję i czas;
- awaria źródła daje `unknown`;
- testy obejmują IPv4, IPv6, FCrDNS, uprawnienia oraz prywatność;
- README nadal jasno odróżnia deklarację, dowód i brak wiedzy.
