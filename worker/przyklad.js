/**
 * Minimalny przykład wpięcia licznika w Cloudflare Worker.
 *
 * Całość sprowadza się do trzech rzeczy:
 *   1. obsłuż żądanie tak, jak obsługiwałeś je do tej pory,
 *   2. zmierz rozmiar odpowiedzi z KLONU, nie z nagłówka,
 *   3. zapisz wizytę przez ctx.waitUntil(), czyli PO odesłaniu odpowiedzi.
 *
 * Punkt trzeci jest ważniejszy, niż wygląda: bez niego bot czeka na zapis do bazy,
 * a awaria bazy przewraca serwowanie stron. Z nim licznik jest dodatkiem, który
 * nie może zaszkodzić — i taki ma być.
 */
import { zapiszWizyteBota } from './wizyty-botow.js';

export default {
  async fetch(request, env, ctx) {
    // 1. Twoja dotychczasowa obsługa żądania. Tu najprostsza z możliwych.
    const odpowiedz = await env.ASSETS.fetch(request);

    // 2. Rozmiar liczony z klonu, a NIE z nagłówka content-length.
    //
    //    Dlaczego: warstwy serwujące pliki często strumieniują odpowiedź i tego
    //    nagłówka po prostu nie ustawiają — u nas kolumna wychodziła w całości
    //    pusta, zanim to zauważyliśmy. A rozmiar jest tu istotny, bo odróżnia
    //    pełną treść od pustej skorupy aplikacji JavaScript: bot dostający 40 kB
    //    dostał artykuł, bot dostający 14 kB dostał sam szkielet.
    const klon = odpowiedz.clone();

    // 3. Zapis w tle. Bot dostaje odpowiedź natychmiast i nie czeka na bazę.
    ctx.waitUntil((async () => {
      let rozmiar = null;
      try {
        rozmiar = (await klon.arrayBuffer()).byteLength;
      } catch {
        // trudno — wizyta zapisze się bez rozmiaru
      }
      await zapiszWizyteBota(
        request,
        {
          status: odpowiedz.status,
          rozmiar,
          // `mirror` to informacja, czy oddałeś botowi osobną, statyczną wersję
          // strony. Jeśli nie masz dwóch warstw treści — zostaw false.
          mirror: false,
        },
        env
      );
    })());

    return odpowiedz;
  },
};

/**
 * WYMAGANE ZMIENNE ŚRODOWISKOWE
 *
 *   SUPABASE_URL          adres bazy (jawny, nie jest sekretem)
 *   SUPABASE_SERVICE_KEY  klucz do zapisu — SEKRET, ustaw przez
 *                         `wrangler secret put SUPABASE_SERVICE_KEY`
 *
 * Bez nich moduł po prostu nic nie robi i nie rzuca błędem. To celowe: pozwala
 * wdrożyć kod przed skonfigurowaniem bazy, bez wywracania serwisu.
 *
 * ⚠ PLIKI STATYCZNE OMIJAJĄ TEN KOD. Jeśli chcesz mierzyć żądania o sitemap.xml,
 * robots.txt czy llms.txt, musisz wymusić przejście przez workera — w Cloudflare
 * służy do tego `run_worker_first` w wrangler.jsonc. Bez tego dostaniesz dla nich
 * twarde zero i uznasz, że nikt ich nie pobiera. My tak uznaliśmy.
 * Szczegóły: docs/pulapki.md, pułapka 2.
 */
