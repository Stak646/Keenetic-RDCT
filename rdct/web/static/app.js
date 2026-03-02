async function loadJSON(url) {
  const r = await fetch(url, { cache: "no-cache" });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return await r.json();
}

function getToken() {
  return localStorage.getItem("rdct_token") || "";
}

function setToken(t) {
  localStorage.setItem("rdct_token", t);
}

function authHeaders() {
  const t = getToken();
  const h = {};
  if (t) h["X-RDCT-Token"] = t;
  return h;
}

async function apiGET(path) {
  const r = await fetch(path, { headers: authHeaders(), cache: "no-cache" });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || ("HTTP " + r.status));
  return j;
}

async function apiPOST(path, obj) {
  const r = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(obj || {}),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || ("HTTP " + r.status));
  return j;
}

function pretty(obj) {
  return JSON.stringify(obj, null, 2);
}

// i18n
let STR = {};
async function setLang(lang) {
  STR = await loadJSON("/i18n/" + lang + ".json");
  localStorage.setItem("rdct_lang", lang);
  applyStrings();
}

function applyStrings() {
  const map = [
    ["lbl-lang", "lang"],
    ["h-auth", "auth_title"],
    ["btn-save-token", "save"],
    ["p-token-hint", "token_hint"],
    ["h-status", "status_title"],
    ["btn-refresh", "refresh"],
    ["btn-stop", "stop"],
    ["h-run", "run_title"],
    ["lbl-mode", "mode"],
    ["lbl-perf", "perf"],
    ["lbl-baseline", "baseline"],
    ["btn-start", "start"],
    ["h-reports", "reports_title"],
    ["btn-load-reports", "load"],
  ];
  for (const [id, key] of map) {
    const el = document.getElementById(id);
    if (el && STR[key]) el.textContent = STR[key];
  }
}

async function refreshStatus() {
  const el = document.getElementById("status");
  el.textContent = STR.loading || "Loading...";
  try {
    const j = await apiGET("/api/v1/status");
    el.textContent = pretty(j.status);
  } catch (e) {
    el.textContent = "ERROR: " + e.message;
  }
}

async function startRun() {
  const el = document.getElementById("run-result");
  el.textContent = STR.loading || "Loading...";
  try {
    const mode = document.getElementById("mode").value;
    const perf = document.getElementById("perf").value;
    const baseline = document.getElementById("baseline").checked;
    const j = await apiPOST("/api/v1/run/start", { research_mode: mode, performance_mode: perf, baseline });
    el.textContent = pretty(j);
    await refreshStatus();
  } catch (e) {
    el.textContent = "ERROR: " + e.message;
  }
}

async function stopRun() {
  const el = document.getElementById("status");
  try {
    const j = await apiPOST("/api/v1/run/stop", {});
    await refreshStatus();
  } catch (e) {
    el.textContent = "ERROR: " + e.message;
  }
}

async function loadReports() {
  const root = document.getElementById("reports");
  root.innerHTML = "";
  try {
    const j = await apiGET("/api/v1/reports");
    const items = (j.reports && j.reports.items) || [];
    if (!items.length) {
      root.textContent = STR.no_reports || "No reports yet.";
      return;
    }
    for (const it of items) {
      const div = document.createElement("div");
      div.className = "report-item";
      const title = document.createElement("div");
      title.textContent = it.run_id;
      div.appendChild(title);

      const links = document.createElement("div");
      if (it.archive) {
        const a = document.createElement("a");
        a.href = "/api/v1/reports/" + it.run_id + "/download";
        a.textContent = STR.download || "Download archive";
        links.appendChild(a);
      } else {
        links.textContent = STR.no_archive || "No archive";
      }
      div.appendChild(links);

      root.appendChild(div);
    }
  } catch (e) {
    root.textContent = "ERROR: " + e.message;
  }
}

function init() {
  const t = getToken();
  document.getElementById("token").value = t;

  document.getElementById("btn-save-token").addEventListener("click", () => {
    setToken(document.getElementById("token").value.trim());
    refreshStatus();
  });
  document.getElementById("btn-refresh").addEventListener("click", refreshStatus);
  document.getElementById("btn-start").addEventListener("click", startRun);
  document.getElementById("btn-stop").addEventListener("click", stopRun);
  document.getElementById("btn-load-reports").addEventListener("click", loadReports);

  const langEl = document.getElementById("lang");
  const savedLang = localStorage.getItem("rdct_lang") || "ru";
  langEl.value = savedLang;
  langEl.addEventListener("change", async () => {
    await setLang(langEl.value);
  });

  setLang(savedLang).then(() => refreshStatus());
}

init();
