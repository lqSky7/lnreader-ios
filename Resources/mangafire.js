// MangaFire — port of keiyoushi/extensions-source src/all/mangafire.
//
// The upstream extension is Kotlin against OkHttp + kotlinx.serialization. This
// is a direct port of its request builders, DTO mapping and VRF signer; no
// behaviour was reverse-engineered, only translated.
//
// Host contract (see lnreader-ios Services/Extensions/ExtensionContract.swift):
//   http.get(url, headers) -> { status, url, body } | { error }
//
// MangaFire signs every /api/ request with a `vrf` query parameter computed by
// VrfSigner.kt: three substitution stages over the *sorted* query string.

var BASE = "https://mangafire.to";
var LANG = "en";

// MARK: - Base64 (JavaScriptCore has no atob)

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function b64decode(text) {
  var clean = String(text).replace(/[^A-Za-z0-9+/=]/g, "");
  var out = [];
  for (var i = 0; i < clean.length; i += 4) {
    var c1 = B64.indexOf(clean.charAt(i));
    var c2 = B64.indexOf(clean.charAt(i + 1));
    var c3 = B64.indexOf(clean.charAt(i + 2));
    var c4 = B64.indexOf(clean.charAt(i + 3));
    if (c1 < 0 || c2 < 0) break;
    out.push(((c1 << 2) | (c2 >> 4)) & 0xff);
    if (c3 >= 0) out.push(((c2 << 4) | (c3 >> 2)) & 0xff);
    if (c4 >= 0) out.push(((c3 << 6) | c4) & 0xff);
  }
  return out;
}

function b64urlencode(bytes) {
  var out = "";
  for (var i = 0; i < bytes.length; i += 3) {
    var b0 = bytes[i];
    var b1 = i + 1 < bytes.length ? bytes[i + 1] : -1;
    var b2 = i + 2 < bytes.length ? bytes[i + 2] : -1;
    out += B64.charAt(b0 >> 2);
    out += B64.charAt(((b0 & 3) << 4) | ((b1 < 0 ? 0 : b1) >> 4));
    if (b1 >= 0) out += B64.charAt(((b1 & 15) << 2) | ((b2 < 0 ? 0 : b2) >> 6));
    if (b2 >= 0) out += B64.charAt(b2 & 63);
  }
  return out.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function utf8(text) {
  var bytes = [];
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code < 0xd800 || code >= 0xe000) {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    } else {
      // Surrogate pair.
      var next = text.charCodeAt(++i);
      var point = 0x10000 + (((code & 0x3ff) << 10) | (next & 0x3ff));
      bytes.push(
        0xf0 | (point >> 18),
        0x80 | ((point >> 12) & 0x3f),
        0x80 | ((point >> 6) & 0x3f),
        0x80 | (point & 0x3f)
      );
    }
  }
  return bytes;
}

// MARK: - VRF signer (VrfSigner.kt)

var STAGES = [
  {
    table: b64decode("yINlmUNho8VYJT+ibTIP+9ESiULpVEtMOoD6U6lRE0R/xwXo/Xp9NrUgC4cw/Lmo33vUyjUE40kUoEWIr/fxfNNcq2s79ShQ5NhNrFnJ4hXPwOu/SuXzIbuTQKGFvfm08E9jvCfqAtoDqvQq3dVWPQFmJjgvkISBeXY3BgANR+yVnjGbcxZ47d6kLNfZPIayTq3/YGySb1KuVZodWp/WGNAO5pfMcpaK53Hhs0allBszaMaxuouOwdxbwgxIw6YunSsXjI05Yi0j9j4eHKfSXR8Ifo/Od+8iamRfCXTyvm7NGRGYdcQ0ywcK/u6RXhrbcCm4t2eCtrDgQVecJGkQ+A=="),
    key: b64decode("0Ec58JOY3uBzJK9m3zqIOpdlF7UFiax9DmA="),
    iv: 0x5a
  },
  {
    table: b64decode("IUFltCxD3Oc2cwCgkJffthaOg9cgPUb0LgW6H/VtfcF0kc5F25t+aWj6JH9VOhOaY0rAFdUxlDnl5BLNvwEJvQtP5qcw7vdb/K+chnbwnspSHT8mz5lqwz41TezG0hkO06FTjJZhsyNuFLDpD2ZZxQj/QIRcF90zpmQ7Byu483WsQqUE0C342HL+JXngRB6fRzxRyVTaKu83h7UYTJ0QMt6ixFh6S3F8gqkKwrGTL3jHNBsD45UnifK8+RGtishQV2K3rujLKEkiZxpr2dYcudFW4oFsDKhad3CLBvuyTqsCo4B7mL5IKQ1vXo/MOOvq1I1d8ar9X6Ttu5KF4fZgiA=="),
    key: b64decode("AAdjb1iPY8CiDmq9H34tKTBF8a3oDQ=="),
    iv: 0x35
  },
  {
    table: b64decode("NQHlu1/wVO5EmkwQymF810qqY2xG1k2obcas4Z9mCsPEIFl9pRIjFxbJ7ybMHbBckT5Ton85E0FOeHezbh/mjlEYpmpnlXOS8dgrqeq2KfxImTh1YK9y0PeMNhzA1OQzSY9brYOJq/l2QnE/hwOeZIhPixVSKIUlDb5vLcH6RWKxkIEMuP0bDwIqQ71AJJaEaMJL7A6YtyIwoRT+L5v4aZzodN/0+3nOGsfblFjgxSfPzVDjNFeNl5P26+kEC/8AHgdrpAbt3hHz3HrRN1Y6e+JHgF7ncFWnoF0y3THL1S71WgWGCa6KtSzTCCG58n68nTyj2T3Sshk7utqCtMi/ZQ=="),
    key: b64decode("DELOJgPsVaCcblDtTGMdHzM="),
    iv: 0xba
  }
];

function encryptStage(data, stage) {
  var out = new Array(data.length);
  var prev = stage.iv;
  for (var i = 0; i < data.length; i++) {
    prev = stage.table[(data[i] ^ stage.key[i % stage.key.length] ^ prev) & 0xff] & 0xff;
    out[i] = prev;
  }
  return out;
}

function vrfSign(path) {
  var data = utf8(path);
  for (var i = 0; i < STAGES.length; i++) {
    data = encryptStage(data, STAGES[i]);
  }
  return b64urlencode(data);
}

// MARK: - API

function encode(value) {
  return encodeURIComponent(String(value)).replace(/%5B/g, "[").replace(/%5D/g, "]");
}

/// GET an /api/ path. `params` is a list of [key, value]; they are sorted for
/// signing exactly as the upstream interceptor does, and encoded only on the wire.
function api(path, params) {
  var sorted = params.slice().sort(function (a, b) {
    return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
  });

  var signed = sorted.map(function (p) { return p[0] + "=" + p[1]; }).join("&");
  var wire = sorted.map(function (p) { return encode(p[0]) + "=" + encode(p[1]); }).join("&");

  var pathWithQuery = path + (signed ? "?" + signed : "");
  var url = BASE + "/api" + path +
    (wire ? "?" + wire : "") +
    (wire ? "&" : "?") + "vrf=" + vrfSign(pathWithQuery);

  var response = http.get(url, { "Accept": "application/json", "Referer": BASE + "/" });
  if (response.error) { throw new Error("MangaFire: " + response.error); }
  if (response.status !== 200) {
    throw new Error("MangaFire: HTTP " + response.status + " for " + path);
  }
  return JSON.parse(response.body);
}

// MARK: - Mapping

function statusOf(value) {
  switch (String(value || "").toLowerCase()) {
    case "releasing": return "ongoing";
    case "finished": return "completed";
    case "discontinued": return "cancelled";
    case "on_hiatus": return "onHiatus";
    default: return "unknown";
  }
}

function posterOf(poster) {
  if (!poster) return null;
  return poster.large || poster.medium || poster.small || null;
}

function plainText(html) {
  if (!html) return "";
  return String(html)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li)>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function entryOf(item) {
  return {
    url: item.url,
    title: item.title,
    thumbnailURL: posterOf(item.poster),
    status: statusOf(item.status)
  };
}

function pageOf(response, page) {
  var items = response.items || [];
  var meta = response.meta || {};
  return {
    entries: items.map(entryOf),
    hasNextPage: meta.hasNext === true || (typeof meta.lastPage === "number" && page < meta.lastPage)
  };
}

/// `/title/728q1-overgeared` -> `728q1`
function hidOf(url) {
  var last = String(url).split("/").filter(function (s) { return s.length > 0; }).pop() || "";
  return last.split("-")[0];
}

// MARK: - Extension

var extension = {
  id: "mangafire",
  name: "MangaFire",
  lang: LANG,
  version: "1.0.0",
  baseUrl: BASE,
  supportsLatest: true,

  popular: function (page) {
    return pageOf(api("/titles", [
      ["limit", "50"],
      ["order[views_30d]", "desc"],
      ["page", String(page)]
    ]), page);
  },

  latest: function (page) {
    return pageOf(api("/titles", [
      ["limit", "50"],
      ["order[chapter_updated_at]", "desc"],
      ["page", String(page)]
    ]), page);
  },

  search: function (query, page) {
    var params = [["limit", "50"], ["page", String(page)]];
    if (query && query.trim().length > 0) {
      params.push(["keyword", query.trim()]);
    }
    return pageOf(api("/titles", params), page);
  },

  details: function (url) {
    var data = api("/titles/" + hidOf(url), []).data || {};
    var genres = (data.genres || []).map(function (g) { return g.title; });
    return {
      url: url,
      title: data.title,
      thumbnailURL: posterOf(data.poster),
      description: plainText(data.synopsisHtml),
      genres: genres,
      status: statusOf(data.status)
    };
  },

  chapters: function (url) {
    var hid = hidOf(url);
    var out = [];
    var page = 1;
    var lastPage = 1;

    do {
      var response = api("/titles/" + hid + "/chapters", [
        ["language", LANG],
        ["limit", "200"],
        ["order", "desc"],
        ["page", String(page)],
        ["sort", "number"]
      ]);
      var items = response.items || [];
      for (var i = 0; i < items.length; i++) {
        var item = items[i];
        out.push({
          url: "/chapter/" + item.id,
          name: item.name && item.name.length > 0 ? item.name : ("Chapter " + item.number),
          number: item.number,
          scanlator: item.type,
          dateUpload: item.createdAt ? new Date(item.createdAt * 1000).toISOString() : null
        });
      }
      lastPage = (response.meta && response.meta.lastPage) || 1;
      page += 1;
    } while (page <= lastPage && page <= 20);

    return out;
  },

  pages: function (url) {
    var id = String(url).split("/").pop().split("-")[0];
    var data = api("/chapters/" + id, []).data || {};
    return (data.pages || []).map(function (page) {
      return { url: page.url, headers: { "Referer": BASE + "/" } };
    });
  }
};
