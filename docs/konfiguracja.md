# Konfiguracja

Trzy rzeczy trzeba ustawić pod siebie i jedna z nich traci sens, jeśli zostawisz
naszą wartość. Wszystkie są w `sql/02-klasyfikacja.sql`, oznaczone jako
`>>> USTAW POD SIEBIE`.

---

## 1. Ścieżka pułapki

```sql
WHEN _sciezka LIKE '/ZMIEN-MNIE-NA-WLASNA-SCIEZKE/%' THEN 'kanarek'
```

Wymyśl adres, którego **nie ma nigdzie**: ani w mapie serwisu, ani w żadnym linku,
ani w treści, ani w `llms.txt`. Wpisz go wyłącznie do `robots.txt` jako `Disallow`.

```
User-agent: *
Disallow: /twoja-wymyslona-sciezka/
```

Od tej pory każde żądanie o ten adres jest **potwierdzonym zignorowaniem
`robots.txt`** — nie poszlaką, tylko dowodem. Nikt nie mógł na niego trafić inaczej
niż czytając plik, w którym stoi zakaz.

To najtańszy sygnał w całym liczniku: nie kosztuje ani jednego zapytania sieciowego
i nie da się go podrobić. Ale **cała jego wartość polega na tym, że jest nieznany** —
zostawienie naszej ścieżki czyni go bezużytecznym, bo ta jest opisana w publicznym
repozytorium.

Nie publikuj swojej nigdzie. Także w komunikatach o wynikach: pisz „ścieżka
kanarkowa", nie jej adres.

> U nas przez cztery dni pomiaru: **zero wejść**. Wszystkie boty, które przychodzą,
> respektują zakaz. To dobra wiadomość, ale rozstrzyga tylko połowę pytania —
> `robots.txt` kontroluje dostęp, nie wykorzystanie. Model czytający z indeksu
> wyszukiwarki nie puka do Twoich drzwi, więc zakaz go nie dotyczy, a treść i tak ma.

---

## 2. Wzorzec własnej treści

```sql
WHEN _sciezka = '/' OR _sciezka ~* '\.html$'
  OR _sciezka ~* '^/(artykuly|blog|produkty)'
  THEN 'tresc'
```

Dopisz prefiksy swoich działów. Bez tego Twoja treść wyląduje w koszu `inne`
i wypadnie z raportów — a Ty zobaczysz zero tam, gdzie ruch był.

Sprawdź po dobie:

```sql
SELECT sciezka_typ, count(*) FROM bot_visits GROUP BY 1 ORDER BY 2 DESC;
```

Jeśli `inne` jest największą kategorią, wzorzec jest niekompletny.

---

## 3. Numer sieci i znacznik testowy

```sql
SELECT COALESCE(_asn = 0, false)
    OR COALESCE(_ua ILIKE '%ZMIEN-MNIE-ZNACZNIK%', false);
```

**Numer sieci (ASN)** swojego łącza sprawdzisz na bgp.tools albo prościej — jeśli
masz workera, wypisz `request.cf.asn` przy własnym żądaniu.

**Znacznik** to dowolny ciąg, który wstawiasz w `User-Agent` podczas testów:

```bash
curl -A "GPTBot/1.2 moj-znacznik-testowy" https://twoja-domena.pl/
```

Potrzebne są oba, bo żaden sam nie wystarcza: znacznik działa też z sieci
komórkowej, gdzie ASN jest inny; numer sieci łapie testy sprzed wprowadzenia
znacznika.

> U nas w pierwszym pomiarze **24 z 33 „fałszywych ClaudeBotów" to były własne
> sprawdzenia**. Bez tego odsiewu licznik pokazywałby, że ktoś masowo podszywa się
> pod Anthropic — a to byliśmy my.

---

## Zmienne środowiskowe workera

```
SUPABASE_URL          adres bazy — jawny, nie jest sekretem
SUPABASE_SERVICE_KEY  klucz do zapisu — SEKRET
```

```bash
wrangler secret put SUPABASE_SERVICE_KEY
```

Bez nich moduł nic nie robi i nie rzuca błędem. To celowe: pozwala wdrożyć kod
przed skonfigurowaniem bazy, bez wywracania serwisu.

---

## Pliki statyczne — krok, o którym łatwo zapomnieć

Jeśli chcesz mierzyć żądania o `sitemap.xml`, `robots.txt` czy `llms.txt`, musisz
**wymusić, żeby dotarły do Twojego kodu**. Serwery i CDN-y oddają pliki leżące na
dysku, zanim uruchomi się cokolwiek Twojego.

W Cloudflare służy do tego `run_worker_first` w `wrangler.jsonc`:

```jsonc
"assets": {
  "run_worker_first": ["/robots.txt", "/sitemap.xml", "/llms.txt"]
}
```

⚠ **Uwaga: sama ta zmiana nie wystarczy.** Skoro worker dostaje żądanie pierwszy,
musi też umieć te pliki oddać — inaczej wpadną w Twoją regułę 404 i zaczniesz
serwować błędy zamiast mapy serwisu. Potrzebna jest jawna obsługa, która pobierze
plik z warstwy assetów i go zwróci (przykład: `PLIKI_MIERZONE` w naszym workerze).

Bez tego kroku dostaniesz dla tych plików twarde zero i uznasz, że nikt ich nie
pobiera. My tak uznaliśmy i opublikowaliśmy fałszywy wniosek.

---

## Pierwsze sprawdzenie po uruchomieniu

Licznik nie powie Ci, że nie działa. Sprawdź sam, testem różnicowym:

```sql
-- 1. odczyt PRZED
SELECT testy_wlasciciela FROM pub_bot_podsumowanie;
```

```bash
# 2. trzy żądania z własnego łącza, ze znacznikiem
for i in 1 2 3; do
  curl -s -o /dev/null -A "GPTBot/1.2 moj-znacznik-testowy" https://twoja-domena.pl/
done
```

```sql
-- 3. odczyt PO — musi wzrosnąć dokładnie o 3
SELECT testy_wlasciciela FROM pub_bot_podsumowanie;
```

**Użyj `testy_wlasciciela`, nie zwykłych raportów.** Twój ruch jest oznaczany jako
własny i odsiewany ze wszystkich widoków publicznych — więc w nich testu nie
zobaczysz i uznasz, że zapis nie działa. Zajęło nam to pół godziny szukania błędu,
którego nie było.
