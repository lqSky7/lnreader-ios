// AllManga (en), hand port of keiyoushi/extensions-source src/en/allanime.
//
// Catalogue, details and chapters are plain GraphQL over http.post. The page
// list is not: the site wraps `chapterPages` in a client-side crypto handshake,
// so, like upstream, it is read out of the real site running in a web view
// (`webview.capture`, see ExtensionContract).

var BASE = "https://mkissa.to";
var API = "https://api.mkissa.net/api";
var LIMIT = 20;
var THUMBNAIL_CDN = "https://wp.youtube-anime.com/aln.youtube-anime.com/";
var IMAGE_HOST = "https://ytimgf.youtube-anime.com/";
var UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
  "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

var POPULAR_QUERY =
  "query ($type: VaildPopularTypeEnumType!, $size: Int!, $page: Int, $dateRange: Int, " +
  "$allowAdult: Boolean, $allowUnknown: Boolean) { queryPopular(type: $type, size: $size, " +
  "dateRange: $dateRange, page: $page, allowAdult: $allowAdult, allowUnknown: $allowUnknown) " +
  "{ recommendations { anyCard { _id name thumbnail englishName } } } }";

var SEARCH_QUERY =
  "query ($search: SearchInput, $size: Int, $page: Int, " +
  "$translationType: VaildTranslationTypeMangaEnumType, $countryOrigin: VaildCountryOriginEnumType) " +
  "{ mangas(search: $search, limit: $size, page: $page, translationType: $translationType, " +
  "countryOrigin: $countryOrigin) { edges { _id name thumbnail englishName } } }";

var UPDATE_QUERY =
  "query ($id: String!, $showId: String!, $search: SearchInput) { " +
  "manga(_id: $id, search: $search) { _id name thumbnail description authors genres tags status " +
  "altNames englishName malId aniListId relatedMangas availableChaptersDetail } " +
  "episodeInfos(showId: $showId, episodeNumStart: 0, episodeNumEnd: 9999) " +
  "{ episodeIdNum notes uploadDates } }";

// MARK: - Transport

var lastApiCall = 0;

/// One request per second to the API host, as upstream does.
function throttle() {
  var wait = lastApiCall + 1000 - Date.now();
  if (wait > 0) sleep(wait);
  lastApiCall = Date.now();
}

function graphql(query, variables) {
  throttle();
  var response = http.post(API, JSON.stringify({ query: query, variables: variables }), {
    "Content-Type": "application/json",
    "Referer": BASE + "/",
    "Origin": BASE
  });
  if (response.error) throw new Error("AllManga: " + response.error);
  if (response.status !== 200 && !response.body) throw new Error("AllManga: HTTP " + response.status);

  var parsed;
  try {
    parsed = JSON.parse(response.body);
  } catch (e) {
    throw new Error("AllManga: HTTP " + response.status + " (unreadable response)");
  }
  if (parsed.errors && parsed.errors.length > 0 && !parsed.data) {
    var error = new Error(String(parsed.errors[0].message || "GraphQL error"));
    error.graphql = true;
    throw error;
  }
  return parsed.data || {};
}

// MARK: - Mapping

function thumbnailOf(value) {
  if (!value) return null;
  return /^https?:\/\//.test(value) ? value : THUMBNAIL_CDN + value + "?w=250";
}

function statusOf(value) {
  var text = String(value || "").toLowerCase();
  if (text.indexOf("releasing") >= 0) return "ongoing";
  if (text.indexOf("finished") >= 0) return "completed";
  return "unknown";
}

function slugOf(name) {
  return String(name).trim().toLowerCase().replace(/[^a-z0-9]+/g, "-");
}

/// `/manga/{id}/{slug}`: the same shape upstream used before it moved the slug
/// into memo, so entries from older Mihon backups still resolve. The contract
/// passes URLs only, which is why the id has to live in the URL.
function entryOf(item) {
  return {
    url: "/manga/" + item._id + "/" + slugOf(item.name),
    title: item.englishName || item.name,
    thumbnailURL: thumbnailOf(item.thumbnail)
  };
}

function idOf(url) {
  var parts = String(url).split("/");
  var i = parts.indexOf("manga");
  if (i < 0) i = parts.indexOf("read");
  var id = i >= 0 ? parts[i + 1] : parts[parts.length - 1];
  if (!id) throw new Error("AllManga: unsupported URL " + url);
  return id;
}

function stripHtml(html) {
  return String(html || "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .trim();
}

function descriptionOf(manga) {
  var text = stripHtml(manga.description) + "\n\n";
  if (manga.malId) text += "[MyAnimeList](https://myanimelist.net/manga/" + manga.malId + ")\n";
  if (manga.aniListId) text += "[AniList](https://anilist.co/manga/" + manga.aniListId + ")\n";
  text += "\n\n";
  var alt = manga.altNames || [];
  if (alt.length > 0) {
    text += "Alternative Titles:\n" + alt.map(function (n) { return "- " + n; }).join("\n");
  }
  return text.trim();
}

function searchPage(page, query) {
  var data = graphql(SEARCH_QUERY, {
    search: {
      query: query && query.length > 0 ? query : null,
      sortBy: null,
      genres: null,
      excludeGenres: null,
      isManga: true,
      allowAdult: false,
      allowUnknown: false
    },
    size: LIMIT,
    page: page,
    translationType: "sub",
    countryOrigin: "ALL"
  });
  var edges = (data.mangas && data.mangas.edges) || [];
  return { entries: edges.map(entryOf), hasNextPage: edges.length === LIMIT };
}

/// Upstream retries up to five times: the API answers `manga: null` or a
/// "try again in N seconds" error while it rate limits.
var cache = { id: null, at: 0, data: null };

/// details() and chapters() ask for the same document back to back, and the API
/// allows one call per second, so the second reuses the first for a short while.
function fetchManga(id) {
  if (cache.id === id && Date.now() - cache.at < 30000) return cache.data;
  var data = fetchMangaUncached(id);
  cache = { id: id, at: Date.now(), data: data };
  return data;
}

function fetchMangaUncached(id) {
  var delay = 1000;
  var lastError = null;
  for (var attempt = 0; attempt <= 5; attempt++) {
    if (attempt > 0) sleep(delay);
    try {
      var data = graphql(UPDATE_QUERY, {
        id: id,
        showId: "manga@" + id,
        search: { fromSearch: true, allowAdult: true }
      });
      if (data.manga) return data;
      delay += 1000;
    } catch (e) {
      if (!e.graphql) throw e;
      lastError = e;
      var match = /again in (\d+)\s*second/.exec(e.message);
      delay = match ? Number(match[1]) * 1000 : delay + 1000;
    }
  }
  throw lastError || new Error("AllManga: unable to fetch manga details");
}

// MARK: - Page list (web view)

/// Runs at document start. Surfaces any JSON that carries `chapterPages`,
/// whether the page reads it through `fetch().json()` or `JSON.parse`. Upstream
/// also nulls every iframe's `contentWindow`; that breaks Cloudflare Turnstile,
/// so it is left out and the site's own verification is allowed to run.
var HOOK = "(function () {" +
  "var post = function (s) { if (window.__lnrPost) window.__lnrPost(s); };" +
  "var originalJson = Response.prototype.json;" +
  "Response.prototype.json = function () {" +
  "  return originalJson.call(this).then(function (data) {" +
  "    if (data && data.chapterPages) post(JSON.stringify(data));" +
  "    return data;" +
  "  });" +
  "};" +
  "var originalParse = JSON.parse;" +
  "JSON.parse = new Proxy(originalParse, {" +
  "  apply: function (target, thisArg, args) {" +
  "    var result = Reflect.apply(target, thisArg, args);" +
  "    if (result && result.chapterPages) post(args[0]);" +
  "    return result;" +
  "  }" +
  "});" +
  "})();";

/// Waits for the SPA router, then navigates to the chapter the way a click would.
function navigateScript(chapterPath) {
  return "(function () {" +
    "var go = function () {" +
    "  var a = document.createElement('a');" +
    "  a.href = a.dataset.href = " + JSON.stringify(chapterPath) + ";" +
    "  document.body.append(a); a.click();" +
    "};" +
    "var tries = 0;" +
    "var check = function () {" +
    "  if (document.querySelector('[data-href]')) go();" +
    "  else if (tries++ < 200) setTimeout(check, 50);" +
    "  else go();" +
    "};" +
    "document.addEventListener('DOMContentLoaded', check);" +
    "if (document.readyState !== 'loading') check();" +
    "})();";
}

function resolveImage(value, head) {
  if (/^https?:\/\//.test(value)) return value;
  return head + value.replace(/^\//, "");
}

function pageList(mangaId, chapterSlug) {
  var mangaUrl = BASE + "/manga/" + mangaId + "?fromSearch=1";
  var chapterPath = "/manga/" + mangaId + "/" + chapterSlug;

  var shell = http.get(mangaUrl, { "User-Agent": UA });
  if (shell.error) throw new Error("AllManga: " + shell.error);
  if (shell.status === 403 || shell.status === 503) throw new Error("Solve captcha in WebView and retry");
  if (shell.status !== 200) throw new Error("AllManga: HTTP " + shell.status);

  var captured = webview.capture({
    url: mangaUrl,
    html: shell.body,
    userAgent: UA,
    startScripts: [
      "try { localStorage.clear(); sessionStorage.clear(); } catch (e) {}",
      HOOK,
      navigateScript(chapterPath)
    ],
    timeoutMs: 20000,
    // The site asks for a human check on some requests. When that overlay (or a
    // Cloudflare interstitial) stays up, the host shows the page to the user.
    challengeScript: "document.title.indexOf('Just a moment') >= 0 || " +
      "document.querySelector('.captcha-overlay--visible') != null",
    challengeTitle: "Verify to load this chapter"
  });
  if (captured.error) throw new Error("AllManga: " + captured.error);

  var payload = JSON.parse(captured.message);
  var root = payload.chapterPages ? payload : (payload.data || {});
  var edges = (root.chapterPages && root.chapterPages.edges) || [];
  if (edges.length === 0) return [];

  // Prefer a server whose URLs are usable as they are or that names a host.
  var chosen = null;
  for (var i = 0; i < edges.length && !chosen; i++) {
    var urls = edges[i].pictureUrls || [];
    var sample = urls.length > 0 ? urls[Math.floor(Math.random() * urls.length)].url : null;
    if ((sample && /^https?:\/\//.test(sample)) || edges[i].pictureUrlHead) chosen = edges[i];
  }
  chosen = chosen || edges[0];

  var head = IMAGE_HOST;
  var server = chosen.pictureUrlHead;
  if (server) {
    head = /^https?:\/\//.test(server) ? server.replace(/\/+$/, "") + "/" : "https://" + server.replace(/\/+$/, "") + "/";
  }

  var pages = [];
  (chosen.pictureUrls || []).forEach(function (image) {
    if (!image.url) return;
    pages.push({ url: resolveImage(image.url, head), headers: { "Referer": BASE + "/" } });
  });
  return pages;
}

// MARK: - Extension

var extension = {
  id: "allmanga",
  name: "AllManga",
  lang: "en",
  version: "1.0.0",
  baseUrl: BASE,
  supportsLatest: true,

  popular: function (page) {
    var data = graphql(POPULAR_QUERY, {
      type: "manga",
      size: LIMIT,
      dateRange: 0,
      page: page,
      allowAdult: false,
      allowUnknown: false
    });
    var recommendations = (data.queryPopular && data.queryPopular.recommendations) || [];
    var entries = [];
    recommendations.forEach(function (item) {
      if (item.anyCard) entries.push(entryOf(item.anyCard));
    });
    return { entries: entries, hasNextPage: recommendations.length === LIMIT };
  },

  latest: function (page) {
    return searchPage(page, "");
  },

  search: function (query, page) {
    return searchPage(page, query ? query.trim() : "");
  },

  details: function (url) {
    var manga = fetchManga(idOf(url)).manga;
    var entry = entryOf(manga);
    entry.url = url;
    entry.description = descriptionOf(manga);
    var authors = manga.authors || [];
    if (authors.length > 0) {
      entry.author = authors[0].trim();
      entry.artist = entry.author;
    }
    var seen = {};
    entry.genres = (manga.genres || []).concat(manga.tags || []).map(function (g) { return g.trim(); })
      .filter(function (g) {
        if (!g || seen[g.toLowerCase()]) return false;
        seen[g.toLowerCase()] = true;
        return true;
      });
    entry.status = statusOf(manga.status);
    return entry;
  },

  chapters: function (url) {
    var id = idOf(url);
    var data = fetchManga(id);
    var slug = slugOf(data.manga.name);
    var details = {};
    (data.episodeInfos || []).forEach(function (info) { details[String(info.episodeIdNum)] = info; });

    var available = (data.manga.availableChaptersDetail && data.manga.availableChaptersDetail.sub) || [];
    var out = [];
    available.forEach(function (num) {
      var info = details[String(num)];
      if (!info) return;
      var name = "Chapter " + num;
      if (info.notes && !/\d/.test(info.notes)) name += ": " + info.notes;
      var uploaded = info.uploadDates && info.uploadDates.sub;
      out.push({
        url: "/read/" + id + "/" + slug + "/chapter-" + num + "-sub",
        name: name,
        number: parseFloat(num),
        dateUpload: uploaded || null
      });
    });
    return out;
  },

  pages: function (url) {
    // /read/{mangaId}/{slug}/chapter-{n}-sub
    var parts = String(url).split("/").filter(function (s) { return s.length > 0; });
    if (parts[0] !== "read" || parts.length < 4) throw new Error("Refresh Chapter List");
    return pageList(parts[1], parts[3]);
  }
};
