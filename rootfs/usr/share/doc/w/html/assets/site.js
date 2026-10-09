// W Linux documentation site — the only script: search, the narrow-window menu
// and the "On this page" highlight.
//
// A classic script on purpose, with no fetch() and no ES modules: the same files
// open from file:///usr/share/doc/w/html in the Help window, and Firefox gives
// every file:// document its own origin — a fetch of the neighbouring index or a
// module import fails there. The search index is a plain <script> that sets
// window.W_SEARCH = [{t: page, h: section, u: url, x: text}, …], with URLs
// relative to the language root it was loaded from.
(function () {
  "use strict";
  const $ = (s) => document.querySelector(s);

  // ── Menu (narrow windows) ──────────────────────────────────────────────────
  $(".menu").addEventListener("click", () => document.body.classList.toggle("nav-open"));

  // ── Search ─────────────────────────────────────────────────────────────────
  const q = $("#q"), hits = $("#hits");
  const idx = document.querySelector('script[src$="search-index.js"]');
  const base = idx ? idx.src.replace(/search-index\.js$/, "") : "";
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  let sel = -1;

  function score(e, terms) {
    const t = e.t.toLowerCase(), h = e.h.toLowerCase(), x = e.x.toLowerCase();
    let s = 0;
    for (const w of terms) {
      const k = (t.includes(w) ? 8 : 0) + (h.includes(w) ? 5 : 0) + (x.includes(w) ? 1 : 0);
      if (!k) return 0;
      s += k;
    }
    return s;
  }

  function snippet(x, terms) {
    const i = Math.max(0, x.toLowerCase().indexOf(terms[0]));
    const from = Math.max(0, i - 40);
    return (from ? "…" : "") + x.slice(from, from + 120) + (from + 120 < x.length ? "…" : "");
  }

  function render() {
    const terms = q.value.toLowerCase().split(/\s+/).filter(Boolean);
    sel = -1;
    if (!terms.length) { hits.hidden = true; return; }
    const found = (window.W_SEARCH || [])
      .map((e) => [score(e, terms), e]).filter((p) => p[0])
      .sort((a, b) => b[0] - a[0]).slice(0, 12);
    hits.innerHTML = found.length
      ? found.map(([, e]) => `<li><a href="${base}${e.u}"><b>${esc(e.h ? e.t + " › " + e.h : e.t)}</b>` +
          `<small>${esc(snippet(e.x, terms))}</small></a></li>`).join("")
      : `<li class="none">${esc(q.dataset.empty)}</li>`;
    hits.hidden = false;
  }

  function move(d) {
    const items = hits.querySelectorAll("li a");
    if (!items.length) return;
    sel = (sel + d + items.length) % items.length;
    items.forEach((a, i) => a.parentNode.classList.toggle("on", i === sel));
    items[sel].scrollIntoView({ block: "nearest" });
  }

  q.addEventListener("input", render);
  q.addEventListener("keydown", (ev) => {
    if (ev.key === "ArrowDown") { move(1); ev.preventDefault(); }
    else if (ev.key === "ArrowUp") { move(-1); ev.preventDefault(); }
    else if (ev.key === "Enter") {
      const a = hits.querySelectorAll("li a")[Math.max(sel, 0)];
      if (a) location.href = a.href;
    } else if (ev.key === "Escape") { q.value = ""; render(); q.blur(); }
  });
  q.addEventListener("blur", () => setTimeout(() => { hits.hidden = true; }, 150));
  q.addEventListener("focus", render);
  // ?q=… opens the page with the search already run (w-help --search).
  const pre = new URLSearchParams(location.search).get("q");
  if (pre) { q.value = pre; q.focus(); }
  document.addEventListener("keydown", (ev) => {
    const typing = /^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName);
    if (!typing && (ev.key === "/" || (ev.key === "k" && (ev.ctrlKey || ev.metaKey)))) {
      q.focus(); q.select(); ev.preventDefault();
    }
  });

  // ── "On this page": highlight the section being read ───────────────────────
  const links = [...document.querySelectorAll(".toc a")];
  if (links.length) {
    const heads = links.map((a) => document.getElementById(decodeURIComponent(a.hash.slice(1))));
    const spy = () => {
      let cur = 0;
      heads.forEach((h, i) => { if (h && h.getBoundingClientRect().top < 120) cur = i; });
      links.forEach((a, i) => a.classList.toggle("on", i === cur));
    };
    addEventListener("scroll", spy, { passive: true });
    spy();
  }
})();
