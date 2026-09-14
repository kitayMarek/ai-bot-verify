-- ===========================================================================
--  Klasyfikacja wizyt: kategoria bota, typ ścieżki, ruch własny
-- ===========================================================================
--
--  ⚠ TEN PLIK WYMAGA KONFIGURACJI. Trzy miejsca oznaczone jako
--    „>>> USTAW POD SIEBIE" mają wartości zaślepkowe, które celowo nie zadziałają
--    przypadkiem. Bez ich zmiany licznik będzie działał, ale dwie rzeczy będą
--    bezużyteczne: odsiew ruchu własnego i pułapka na boty ignorujące robots.txt.
--
--  DLACZEGO KLASYFIKACJA SIEDZI W BAZIE, A NIE W KODZIE: przy każdej zmianie
--  reguł trzeba przeliczyć stare wiersze. Gdyby logika była w dwóch miejscach —
--  w triggerze dla nowych i w skrypcie dla starych — rozjechałyby się przy
--  pierwszej poprawce. Jedna implementacja, dwa zastosowania.
-- ===========================================================================


-- ---------------------------------------------------------------------------
--  1. KATEGORIA BOTA
-- ---------------------------------------------------------------------------
--  Rozróżnienie ai_crawler / ai_uzytkownik jest tu najważniejsze i większość
--  narzędzi go nie robi. Pierwszy zbiera treść do przyszłego indeksu modelu,
--  wedle własnego harmonogramu. Drugi znaczy, że KONKRETNY CZŁOWIEK zadał
--  pytanie w czacie, a model poszedł po tę stronę, żeby odpowiedzieć.
--  To dwa zupełnie różne zdarzenia i wrzucanie ich do jednej sumy zaciera
--  jedyny sygnał, na którym właścicielowi strony naprawdę zależy.

CREATE OR REPLACE FUNCTION public.kategoria_bota(_bot TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN _bot IN ('ChatGPT-User', 'Claude-User', 'Perplexity-User', 'DuckAssistBot')
      THEN 'ai_uzytkownik'
    WHEN _bot IN ('Googlebot', 'Googlebot-Image', 'Bingbot', 'Applebot',
                  'Seznam-Bot', 'YandexBot', 'Yandex', 'Baiduspider', 'Naverbot')
      THEN 'wyszukiwarka'
    WHEN _bot IN ('GPTBot', 'OAI-SearchBot', 'ClaudeBot', 'Claude-SearchBot',
                  'anthropic-ai', 'PerplexityBot', 'CCBot', 'Bytespider',
                  'Meta-ExternalAgent', 'Amazonbot', 'Google-Extended',
                  'cohere-ai', 'MistralAI-User', 'YouBot', 'Diffbot')
      THEN 'ai_crawler'
    WHEN _bot IN ('AhrefsBot', 'SemrushBot', 'DotBot', 'MJ12bot')
      THEN 'narzedzie_seo'
    ELSE 'inne'
  END;
$$;


-- ---------------------------------------------------------------------------
--  2. TYP ŻĄDANEJ ŚCIEŻKI
-- ---------------------------------------------------------------------------
--  Po co: intencję widać w celach, nie w narzędziu. Prawdziwy crawler prosi
--  o treść. Skaner prosi o pliki konfiguracyjne i kopie zapasowe. Zbiory tych
--  celów prawie się nie przecinają i to jest najostrzejsze rozróżnienie, jakie
--  udało nam się znaleźć — mocniejsze niż weryfikacja adresu.
--
--  ⚠ KOLEJNOŚĆ WARUNKÓW MA ZNACZENIE. Pułapka musi stać przed resztą, sekrety
--  przed kodem, treść na końcu — inaczej /pulapka/cos.html trafi do „tresc".

CREATE OR REPLACE FUNCTION public.typ_sciezki(_sciezka TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    -- >>> USTAW POD SIEBIE (1 z 3): ŚCIEŻKA PUŁAPKI
    --
    -- Adres, którego NIE MA nigdzie: ani w mapie serwisu, ani w żadnym linku,
    -- ani w treści. Wpisany wyłącznie do robots.txt jako `Disallow`.
    -- Żądanie o niego to potwierdzone zignorowanie robots.txt — sygnał czystszy
    -- niż weryfikacja adresu i nie kosztuje ani jednego zapytania sieciowego.
    --
    -- CAŁA JEGO WARTOŚĆ POLEGA NA TYM, ŻE JEST NIEZNANY. Zostawienie naszej
    -- ścieżki czyni go bezużytecznym. Wymyśl własną i nie publikuj jej nigdzie
    -- poza robots.txt.
    WHEN _sciezka LIKE '/ZMIEN-MNIE-NA-WLASNA-SCIEZKE/%' THEN 'kanarek'

    -- Pliki, o które pyta wyłącznie skaner podatności. To wiedza powszechna
    -- (te listy są w każdym narzędziu pentesterskim), więc publikowanie jej
    -- nikomu nie pomaga ani nie szkodzi. Czym innym jest publikowanie, o które
    -- z nich pytano NA TWOJEJ STRONIE — tego nie rób, bo to gotowa mapa.
    --
    -- Ostatnie cztery dopisane 14.09.2026 po obserwacji Krzysztofa Balickiego
    -- (Web Systems) z logów serwerów hostingowych: /@fs/ to odczyt plików przez
    -- serwer deweloperski Vite (licznik zapisuje ścieżkę bez ?raw??, więc łapiemy
    -- prefiks), dalej klucze AWS, pliki gcloud i zmienne środowiskowe procesu.
    WHEN _sciezka ~* '(\.env|\.git/|/config\.(json|ya?ml|php)|token\.json|-adminsdk\.json|local_settings\.py|appsettings\.json|\.npmrc|wp-login\.php|/wp-includes/|/wp-admin/|^/@fs/|\.aws/|gcloud|/proc/self/)'
      THEN 'sekret'

    WHEN _sciezka ~* '(\.(js|ts|css)\.map$|^/assets/.*\.map$)' THEN 'kod'

    WHEN _sciezka ~* '^/(robots\.txt|llms\.txt|sitemap.*\.xml|favicon|humans\.txt|\.well-known/)'
      THEN 'techniczna'

    -- Paczki JS, style, grafiki. Publiczne z założenia, NIE są wrażliwe.
    -- U prawdziwych botów zajmują sporą część ruchu z prozaicznego powodu:
    -- każde wdrożenie zmienia im adresy, więc crawler wraca po wersję,
    -- której już nie ma. Bez tej kategorii lądowały w koszu „inne" i zawyżały
    -- podejrzenia wobec Googlebota.
    WHEN _sciezka ~* '^/assets/|\.(js|mjs|css|png|jpe?g|gif|svg|webp|ico|woff2?|ttf)$'
      THEN 'zasob'

    -- >>> USTAW POD SIEBIE (2 z 3): WZORZEC WŁASNEJ TREŚCI
    -- Dopisz tu prefiksy swoich działów, żeby treść nie wpadała do „inne".
    WHEN _sciezka = '/' OR _sciezka ~* '\.html$'
      OR _sciezka ~* '^/(artykuly|blog|produkty)'
      THEN 'tresc'

    ELSE 'inne'
  END;
$$;


-- ---------------------------------------------------------------------------
--  3. RUCH WŁASNY
-- ---------------------------------------------------------------------------
--  Testujesz własną stronę, podszywając się pod boty — i masz rację, że tak
--  robisz. Ale ten ruch MUSI być odliczony, inaczej zawyży Twoje statystyki.
--  U nas w pierwszym pomiarze 24 z 33 „fałszywych ClaudeBotów" to były nasze
--  własne sprawdzenia.
--
--  Dwa sygnały, bo żaden sam nie wystarcza:
--   • znacznik w User-Agencie działa też z sieci komórkowej, gdzie ASN jest inny,
--   • numer sieci łapie testy sprzed wprowadzenia znacznika.
--
--  ⚠ PAMIĘTAJ PRZY TESTOWANIU: ruch oznaczony jako własny jest odsiewany ze
--  WSZYSTKICH raportów publicznych. Twój test będzie więc niewidzialny w tym
--  samym raporcie, który miał go pokazać — i będzie to wyglądało na awarię.
--  Do testów używaj licznika `testy_wlasciciela` z 03-widoki.sql.

CREATE OR REPLACE FUNCTION public.ruch_wlasny(_asn INTEGER, _ua TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  -- >>> USTAW POD SIEBIE (3 z 3): TWÓJ NUMER SIECI I ZNACZNIK TESTOWY
  --
  -- ASN sprawdzisz na przykład na bgp.tools albo w request.cf.asn we własnym
  -- workerze. Znacznik to dowolny ciąg, który wstawiasz w User-Agent podczas
  -- testów: curl -A "GPTBot moj-znacznik-testowy" ...
  --
  -- COALESCE nie jest tu kosmetyką: `asn` bywa puste, a (NULL = 12345) daje
  -- NULL, po czym NULL OR false daje NULL — czyli próbę zapisania NULL do
  -- kolumny NOT NULL i wywrócenie całego insertu.
  SELECT COALESCE(_asn = 0, false)                              -- <- wpisz swój ASN
      OR COALESCE(_ua ILIKE '%ZMIEN-MNIE-ZNACZNIK%', false);    -- <- wpisz swój znacznik
$$;


-- ---------------------------------------------------------------------------
--  4. TRIGGER — wypełnia trzy kolumny naraz przy każdym zapisie
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.oznacz_wizyte_bota()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.kategoria   := public.kategoria_bota(NEW.bot);
  NEW.sciezka_typ := public.typ_sciezki(NEW.sciezka);
  NEW.wlasne      := public.ruch_wlasny(NEW.asn, NEW.ua);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS oznacz_wizyte_bota_trg ON public.bot_visits;
CREATE TRIGGER oznacz_wizyte_bota_trg
  BEFORE INSERT ON public.bot_visits
  FOR EACH ROW EXECUTE FUNCTION public.oznacz_wizyte_bota();


-- ---------------------------------------------------------------------------
--  5. PRZELICZENIE ISTNIEJĄCYCH WIERSZY
-- ---------------------------------------------------------------------------
--  Uruchom po KAŻDEJ zmianie reguł wyżej. Ta sama implementacja co w triggerze,
--  więc nie ma jak się rozjechać.

UPDATE public.bot_visits
SET kategoria   = public.kategoria_bota(bot),
    sciezka_typ = public.typ_sciezki(sciezka),
    wlasne      = public.ruch_wlasny(asn, ua);
