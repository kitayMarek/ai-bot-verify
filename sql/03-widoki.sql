-- ===========================================================================
--  Widoki publiczne — jedyne, co wolno wystawić na zewnątrz
-- ===========================================================================
--
--  Surowa tabela zawiera pełne ścieżki i User-Agenty. Te widoki agregują ją do
--  postaci, w której nie da się odtworzyć pojedynczego żądania.
--
--  ⚠ CELOWO BEZ `security_invoker`. Widok bez tej opcji wykonuje się
--  z uprawnieniami właściciela, więc anonim czyta agregaty, choć do tabeli
--  dostępu nie ma. Z `security_invoker = on` zapytanie anonima wykonałoby się
--  Z JEGO uprawnieniami i dostałby zero wierszy — bez błędu, bez ostrzeżenia,
--  po prostu pustą stronę. Sprawdziliśmy to na sobie.
--
--  ⚠ WSZYSTKIE ODSIEWAJĄ RUCH WŁASNY (`NOT wlasne`). To znaczy, że własnego
--  testu tutaj NIE ZOBACZYSZ. Do testów służy kolumna `testy_wlasciciela`.
-- ===========================================================================


-- ---------------------------------------------------------------------------
--  1. PODSUMOWANIE — stąd bierze się liczba nagłówkowa
-- ---------------------------------------------------------------------------
--  Widok podaje OBA mianowniki, bo „61% ruchu AI jest prawdziwe" bez
--  powiedzenia, procent czego, jest dokładnie tym rodzajem liczby, który ten
--  projekt krytykuje.
--
--    proc_wsrod_rozstrzygnietych — spośród żądań, które dało się rozstrzygnąć
--    proc_calosci                — licząc też te, których rozstrzygnąć się nie da
--
--  Pierwszy jest metodologicznie uczciwszy (nie zgadujemy o operatorach, którzy
--  nic nie publikują), drugi ostrożniejszy. Publikuj oba w jednym zdaniu.

DROP VIEW IF EXISTS public.pub_bot_podsumowanie;
CREATE VIEW public.pub_bot_podsumowanie AS
WITH z_deklaracja AS (
  -- Ruch bez podpisu NIE WCHODZI do procentów. Liczba nagłówkowa mówi „ile
  -- ruchu PODAJĄCEGO SIĘ za bota AI jest prawdziwe" — wrzucenie do mianownika
  -- czegoś, co nigdy takiej deklaracji nie złożyło, zmieniłoby to, co ta liczba
  -- mierzy, i to z dnia na dzień, bez ostrzeżenia dla czytelnika.
  SELECT * FROM public.bot_visits WHERE bot <> '(bez podpisu)'
)
SELECT
  (SELECT min(odwiedzono)::DATE FROM public.bot_visits)            AS pomiar_od,
  now()                                                            AS stan_na,
  greatest(1, (now()::DATE - (SELECT min(odwiedzono)::DATE FROM public.bot_visits)))
                                                                   AS dni_pomiaru,

  count(*) FILTER (WHERE NOT wlasne)                               AS zadan_ogolem,
  count(*) FILTER (WHERE NOT wlasne AND zweryfikowany IS TRUE)     AS oryginalne,
  count(*) FILTER (WHERE NOT wlasne AND zweryfikowany IS FALSE)    AS falszowane,
  count(*) FILTER (WHERE NOT wlasne AND zweryfikowany IS NULL)     AS niesprawdzone,
  count(*) FILTER (WHERE NOT wlasne AND zweryfikowany IS NOT NULL) AS rozstrzygniete,

  -- Ten licznik NIE odsiewa ruchu własnego — i tylko po nim poznasz, że Twój
  -- test w ogóle się zapisał. Reszta widoku go nie pokaże.
  count(*) FILTER (WHERE wlasne)                                   AS testy_wlasciciela,

  round(100.0 * count(*) FILTER (WHERE NOT wlasne AND zweryfikowany IS TRUE)
        / NULLIF(count(*) FILTER (WHERE NOT wlasne AND zweryfikowany IS NOT NULL), 0), 1)
                                                                   AS proc_wsrod_rozstrzygnietych,
  round(100.0 * count(*) FILTER (WHERE NOT wlasne AND zweryfikowany IS TRUE)
        / NULLIF(count(*) FILTER (WHERE NOT wlasne), 0), 1)        AS proc_calosci,

  count(DISTINCT bot) FILTER (WHERE NOT wlasne)                    AS roznych_tozsamosci,
  count(DISTINCT asn) FILTER (WHERE NOT wlasne)                    AS roznych_sieci,

  -- Ruch, który nie przedstawił się żadną nazwą. POZA powyższymi liczbami.
  (SELECT count(*) FROM public.bot_visits
    WHERE bot = '(bez podpisu)' AND NOT wlasne)                    AS bez_podpisu
FROM z_deklaracja;


-- ---------------------------------------------------------------------------
--  2. KTO PRZYCHODZI
-- ---------------------------------------------------------------------------
--  Wysoka liczba w kolumnie „falszowane" NIE jest zarzutem wobec operatora.
--  Jest odwrotnie: znaczy, że jego nazwa jest na tyle warta, że ktoś obcy ją
--  ukradł. Im bardziej rozpoznawalny bot, tym częściej ktoś się pod niego
--  podszywa — bo strony przepuszczają znane nazwy.

DROP VIEW IF EXISTS public.pub_bot_wg_bota;
CREATE VIEW public.pub_bot_wg_bota AS
SELECT operator, bot, kategoria,
       count(*)                                       AS zadan,
       count(*) FILTER (WHERE zweryfikowany IS TRUE)  AS oryginalne,
       count(*) FILTER (WHERE zweryfikowany IS FALSE) AS falszowane,
       count(*) FILTER (WHERE zweryfikowany IS NULL)  AS niesprawdzone
FROM public.bot_visits
WHERE NOT wlasne
GROUP BY operator, bot, kategoria
-- Przy jednym trafieniu nazwa w zestawieniu to szum, nie dana.
HAVING count(*) >= 3
ORDER BY count(*) FILTER (WHERE zweryfikowany IS TRUE) DESC, count(*) DESC;


-- ---------------------------------------------------------------------------
--  3. KATEGORIE — crawler czy pytanie konkretnego człowieka
-- ---------------------------------------------------------------------------

DROP VIEW IF EXISTS public.pub_bot_kategorie;
CREATE VIEW public.pub_bot_kategorie AS
SELECT kategoria,
       count(*)                                       AS zadan,
       count(*) FILTER (WHERE zweryfikowany IS TRUE)  AS oryginalne,
       count(*) FILTER (WHERE zweryfikowany IS FALSE) AS falszowane,
       count(DISTINCT bot)                            AS roznych_tozsamosci,
       count(*) FILTER (WHERE mirror)                 AS obsluzonych_mirrorem
FROM public.bot_visits
WHERE NOT wlasne
GROUP BY kategoria
ORDER BY count(*) DESC;


-- ---------------------------------------------------------------------------
--  4. METODY WERYFIKACJI — kontrola jakości własnego pomiaru
-- ---------------------------------------------------------------------------
--  NAJWAŻNIEJSZY WIDOK DIAGNOSTYCZNY, choć wygląda najnudniej.
--
--  Metoda, która ma dużo „zaprzeczonych" i zero „potwierdzonych", jest niemal
--  na pewno zepsuta — a nie odkryła spisku. Tak wygląda literówka w konfiguracji.
--  U nas odwrotny DNS miał bilans 0/25 przez trzy dni, zanim to zauważyliśmy;
--  przez ten czas publicznie oskarżaliśmy cudzą firmę (docs/pulapki.md).
--
--  Zaglądaj tu za każdym razem, gdy jakaś liczba Cię zaskoczy.

DROP VIEW IF EXISTS public.pub_bot_metody;
CREATE VIEW public.pub_bot_metody AS
SELECT metoda_weryfikacji                             AS metoda,
       count(*)                                       AS zadan,
       count(*) FILTER (WHERE zweryfikowany IS TRUE)  AS potwierdzone,
       count(*) FILTER (WHERE zweryfikowany IS FALSE) AS zaprzeczone
FROM public.bot_visits
WHERE NOT wlasne AND metoda_weryfikacji IS NOT NULL
GROUP BY metoda_weryfikacji
ORDER BY count(*) DESC;


-- ---------------------------------------------------------------------------
--  5. CZEGO SZUKAJĄ — najostrzejsze rozróżnienie w całym zbiorze
-- ---------------------------------------------------------------------------
--  ⚠ Wyłącznie TYPY ścieżek, nigdy same ścieżki. Opublikowana lista adresów,
--  o które pytał skaner, to gotowa mapa dla następnego.

DROP VIEW IF EXISTS public.pub_bot_cele;
CREATE VIEW public.pub_bot_cele AS
SELECT CASE zweryfikowany WHEN TRUE THEN 'oryginalne'
                          WHEN FALSE THEN 'falszowane' END AS grupa,
       sciezka_typ,
       count(*) AS zadan,
       round(100.0 * count(*) / NULLIF(sum(count(*)) OVER (
         PARTITION BY CASE zweryfikowany WHEN TRUE THEN 'oryginalne'
                                         WHEN FALSE THEN 'falszowane' END), 0), 1) AS proc_grupy
FROM public.bot_visits
WHERE NOT wlasne AND zweryfikowany IS NOT NULL
GROUP BY 1, sciezka_typ
ORDER BY 1, count(*) DESC;


-- ---------------------------------------------------------------------------
--  UPRAWNIENIA
-- ---------------------------------------------------------------------------
GRANT SELECT ON public.pub_bot_podsumowanie, public.pub_bot_wg_bota,
                public.pub_bot_kategorie, public.pub_bot_metody,
                public.pub_bot_cele
  TO anon, authenticated;
