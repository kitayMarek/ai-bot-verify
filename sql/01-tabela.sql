-- ===========================================================================
--  Licznik botów AI — tabela wizyt
-- ===========================================================================
--
--  Jeden wiersz = jedno żądanie od czegoś, co przedstawiło się nazwą bota
--  (albo nie przedstawiło się wcale — patrz `bot = '(bez podpisu)'`).
--
--  CZEGO TU CELOWO NIE MA: adresu IP. Do rozpoznania podszywacza wystarczy
--  numer sieci i kraj — jedno i drugie opisuje serwerownię, nie człowieka.
--  Adres służy wyłącznie do porównania z listą operatora i nigdzie nie trafia.
--
--  Ta decyzja ma cenę i lepiej znać ją z góry: gdy wyjdzie na jaw, że któraś
--  metoda weryfikacji była błędna, jej werdyktów NIE DA SIĘ przeliczyć, bo nie
--  ma po czym powtórzyć zapytania DNS. Zostaje cofnięcie ich do „niesprawdzone".
--  Zdarzyło nam się to po trzech dniach (docs/pulapki.md, pułapka 1).
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.bot_visits (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  odwiedzono    TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Kto TWIERDZI, że przyszedł
  operator      TEXT NOT NULL,
  bot           TEXT NOT NULL,

  -- Czy to prawda.
  --   TRUE  — adres mieści się w zakresach publikowanych przez operatora
  --   FALSE — nie mieści się, a nazwa jest tego operatora → podszycie
  --   NULL  — NIE DA SIĘ ROZSTRZYGNĄĆ (operator nic nie publikuje, albo lista
  --           była chwilowo nieosiągalna). To NIE znaczy „podejrzany".
  zweryfikowany BOOLEAN,

  -- Czym rozstrzygnięto: 'ip_lista' | 'asn_operatora' | 'fcrdns'
  --                    | 'brak_metody' | 'blad_sprawdzenia'
  --
  -- Ta kolumna wygląda na formalność, a jest ratunkiem. Gdy okaże się, że jedna
  -- z metod dawała błędne wyniki, pozwala wycofać DOKŁADNIE jej werdykty,
  -- zamiast unieważniać cały pomiar.
  metoda_weryfikacji TEXT,

  -- Gdzie był i co dostał
  sciezka       TEXT NOT NULL,
  sciezka_typ   TEXT,              -- wypełnia trigger, patrz 02-klasyfikacja.sql
  status        SMALLINT NOT NULL,
  rozmiar       INTEGER,           -- bajty; odróżnia treść od pustej skorupy JS
  mirror        BOOLEAN NOT NULL DEFAULT false,

  -- Skąd — na tyle ogólnie, żeby nie były to dane osobowe
  asn           INTEGER,
  kraj          TEXT,
  ua            TEXT,

  -- Wypełniane przez trigger
  kategoria     TEXT,
  wlasne        BOOLEAN NOT NULL DEFAULT false,

  -- Web Bot Auth: TYLKO obecność nagłówków podpisu, bez walidacji.
  -- Dlatego nie jest to weryfikacja i nie liczy się jako taka. Zapisujemy,
  -- żeby mieć dane historyczne, gdy standard się przyjmie.
  ma_podpis     BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS bot_visits_odwiedzono_idx ON public.bot_visits (odwiedzono DESC);
CREATE INDEX IF NOT EXISTS bot_visits_bot_idx        ON public.bot_visits (bot);
CREATE INDEX IF NOT EXISTS bot_visits_kategoria_idx  ON public.bot_visits (kategoria) WHERE NOT wlasne;

COMMENT ON COLUMN public.bot_visits.zweryfikowany IS
  'TRUE = adres z listy operatora. FALSE = nie z listy, a nazwa jego → podszycie. NULL = nie da się rozstrzygnąć. NULL to NIE jest podejrzenie.';

-- ---------------------------------------------------------------------------
--  UPRAWNIENIA
-- ---------------------------------------------------------------------------
--  Surowa tabela zawiera pełne ścieżki i User-Agenty. Nie publikuj jej.
--  Na zewnątrz wystawiaj wyłącznie widoki agregujące z 03-widoki.sql.
--
--  RLS tutaj NIE WYSTARCZY: polityka filtruje wiersze, więc anonim dostałby
--  pustą odpowiedź zamiast błędu i nie wiedziałby, że coś jest nie tak.
--  Jawne REVOKE daje uczciwy błąd uprawnień.
REVOKE ALL ON public.bot_visits FROM anon;
