-- ===========================================================================
--  Raporty — funkcje wywoływane z parametrem okresu
-- ===========================================================================
--
--  Widoki z 03 podają stan narastający. Te funkcje pozwalają pytać o wycinek
--  czasu: '24h', '7d', '30d', 'all'.
--
--  ⚠ NIGDY nie buduj interfejsu, w którym użytkownik wpisuje SQL — ani
--  publicznie, ani za logowaniem, ani „tylko dla admina". Okres jest tu
--  ZAMKNIĘTĄ LISTĄ wartości, a nie fragmentem zapytania. Funkcja z nieznanym
--  okresem ma zwrócić dane z całej historii, a nie błąd — bo błąd bywa
--  zaproszeniem do dalszego próbowania.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.okres_od(okres TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE okres
    WHEN '24h' THEN now() - INTERVAL '24 hours'
    WHEN '7d'  THEN now() - INTERVAL '7 days'
    WHEN '30d' THEN now() - INTERVAL '30 days'
    ELSE '-infinity'::TIMESTAMPTZ
  END;
$$;


-- ---------------------------------------------------------------------------
--  1. CO ODWIEDZALI — treść, którą boty faktycznie czytały
-- ---------------------------------------------------------------------------
--  ⚠ Ten raport FILTRUJE: tylko `status = 200` i tylko dwa typy ścieżek.
--  Tak ma być, bo pokazuje czytaną treść, a nie błędy. Ale zapamiętaj ten filtr
--  — trzy razy szukaliśmy w nim rzeczy, które z definicji odsiewa
--  (docs/pulapki.md, pułapka 3). Do szukania czegokolwiek innego użyj
--  raportu diagnostycznego z punktu 3 niżej.

CREATE OR REPLACE FUNCTION public.pub_raport_co_odwiedzali(okres TEXT DEFAULT '7d')
RETURNS TABLE (sciezka TEXT, zadan BIGINT, roznych_botow BIGINT,
               czy_mirror BOOLEAN, ostatnio TIMESTAMPTZ)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp STABLE
AS $$
  SELECT v.sciezka, count(*), count(DISTINCT v.bot), bool_or(v.mirror), max(v.odwiedzono)
  FROM public.bot_visits v
  WHERE NOT v.wlasne
    AND v.odwiedzono >= public.okres_od(okres)
    AND v.sciezka_typ IN ('tresc', 'techniczna')
    AND v.status = 200
  GROUP BY v.sciezka
  ORDER BY count(*) DESC
  LIMIT 200;
$$;


-- ---------------------------------------------------------------------------
--  2. CZEGO NIE BYŁO — prawdziwe braki, nie skany
-- ---------------------------------------------------------------------------
--  Bot pytał o treść i dostał 404. To są najcenniejsze wiersze w całym
--  liczniku: pokazują, czego ktoś u Ciebie szukał i nie znalazł.
--
--  Ograniczone do `sciezka_typ = 'tresc'`, bo inaczej raport zaleją żądania
--  skanerów o pliki konfiguracyjne — i prawdziwy brak utonie wśród nich.
--  U nas ten raport znalazł jeden autentyczny błędny link i to wystarczyło,
--  żeby się obronił.

CREATE OR REPLACE FUNCTION public.pub_raport_czego_nie_bylo(okres TEXT DEFAULT '30d')
RETURNS TABLE (sciezka TEXT, prob BIGINT, boty TEXT[], ostatnio TIMESTAMPTZ)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp STABLE
AS $$
  SELECT v.sciezka, count(*), array_agg(DISTINCT v.bot), max(v.odwiedzono)
  FROM public.bot_visits v
  WHERE NOT v.wlasne
    AND v.odwiedzono >= public.okres_od(okres)
    AND v.sciezka_typ = 'tresc'
    AND v.status = 404
  GROUP BY v.sciezka
  ORDER BY count(*) DESC
  LIMIT 100;
$$;


-- ---------------------------------------------------------------------------
--  3. DIAGNOSTYKA — jedyny raport BEZ ŻADNYCH FILTRÓW
-- ---------------------------------------------------------------------------
--  ⚠ TEN NIE JEST DLA ANONIMA. Pokazuje pełne ścieżki, więc trzymaj go dla
--  siebie (patrz GRANT na końcu pliku — celowo tylko `authenticated`).
--
--  PO CO ISTNIEJE: trzy razy w ciągu jednego dnia szukaliśmy żądań w raportach,
--  które je odsiewały — raz przez filtr statusu, raz przez typ ścieżki, raz
--  przez odsiew ruchu własnego. Za każdym razem widzieliśmy zero i wyciągali
--  wniosek o braku ruchu, choć wiersze były w bazie.
--
--  Ten raport nie filtruje NICZEGO: pokazuje ścieżkę, status, bota, ruch własny
--  i godzinę. Gdy jakaś liczba Cię zaskoczy — zaczynaj tutaj, nie w raportach
--  publicznych.

CREATE OR REPLACE FUNCTION public.raport_diagnostyczny(okres TEXT DEFAULT '24h')
RETURNS TABLE (odwiedzono TIMESTAMPTZ, bot TEXT, sciezka TEXT, sciezka_typ TEXT,
               status SMALLINT, zweryfikowany BOOLEAN, metoda TEXT, wlasne BOOLEAN)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp STABLE
AS $$
  SELECT v.odwiedzono, v.bot, v.sciezka, v.sciezka_typ, v.status,
         v.zweryfikowany, v.metoda_weryfikacji, v.wlasne
  FROM public.bot_visits v
  WHERE v.odwiedzono >= public.okres_od(okres)
  ORDER BY v.odwiedzono DESC
  LIMIT 500;
$$;


-- ---------------------------------------------------------------------------
--  UPRAWNIENIA
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.pub_raport_co_odwiedzali(TEXT)  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pub_raport_czego_nie_bylo(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.raport_diagnostyczny(TEXT)      FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.pub_raport_co_odwiedzali(TEXT)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pub_raport_czego_nie_bylo(TEXT) TO anon, authenticated;

-- Diagnostyka pokazuje pełne ścieżki — NIE dla anonima.
GRANT EXECUTE ON FUNCTION public.raport_diagnostyczny(TEXT) TO authenticated;
