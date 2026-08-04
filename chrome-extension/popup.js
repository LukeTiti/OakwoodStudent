// v0.6: hardcoded to one test student PK (39950). Instead of fetching from
// the popup (cross-origin from chrome-extension://…, which Veracross's
// backend rejects with a 401 — confirmed) or relying on an auto-injected
// content script (silently failed to attach, cause unknown), this injects
// the exact request — proven working when run in the page's own DevTools
// console — directly into the active Veracross tab via
// chrome.scripting.executeScript. That runs in the page's real origin, so
// cookies/CSRF/Origin all line up the same way they do for the page's own
// JavaScript.

const PERSON_PK = 39950;
const TEST_RECORD_PK = 11261;

const pullBtn = document.getElementById("pullBtn");
const updateBtn = document.getElementById("updateBtn");
const createBtn = document.getElementById("createBtn");
const lookupBtn = document.getElementById("lookupBtn");
const statusEl = document.getElementById("status");
const outputEl = document.getElementById("output");

function setStatus(text, kind) {
  statusEl.textContent = text;
  statusEl.className = kind || "";
}

// Runs INSIDE the Veracross tab, not in the popup — no imports/closures
// from this file are available in there, only its own arguments.
function pullInPage(personPK) {
  return (async () => {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    if (!token) {
      return { ok: false, status: 0, body: "No csrf-token meta tag found — are you logged in on this tab?" };
    }

    const response = await fetch("https://axiom.veracross.com/oakwood/query/2154/result_data.json", {
      method: "POST",
      credentials: "include",
      cache: "no-store",
      headers: {
        "Accept": "*/*",
        "Content-Type": "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "X-CSRF-Token": token
      },
      body: JSON.stringify({
        query_criteria_field_data: JSON.stringify({
          record_fk: personPK,
          criteria_values: [{ field_info_fk: "188", criteria_value_1: personPK }]
        }),
        activity_log_data: JSON.stringify({
          query_type: "detail-category-query",
          page_url: location.href
        })
      })
    });

    const text = await response.text();
    return { ok: response.ok, status: response.status, body: text };
  })();
}

// Runs INSIDE the Veracross tab. Mirrors the exact PUT captured from a real
// manual edit in Veracross's own grid (records is a JSON-encoded array of
// per-field edits; person_volunteer_hours_id is the "which row" identifier,
// not a value being set).
function updateInPage(recordPk, notes, hours) {
  return (async () => {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    if (!token) {
      return { ok: false, status: 0, body: "No csrf-token meta tag found — are you logged in on this tab?" };
    }

    const records = [{
      guid: String(Date.now()),
      record_pk: recordPk,
      table_info_fk: 122,
      fields: [
        { field_alias: "notes", field_info_fk: 1210, path_fk_list: "", value: notes },
        { field_alias: "volunteer_hours", field_info_fk: 1209, path_fk_list: "", value: hours },
        { field_alias: "person_volunteer_hours_id", field_info_fk: 1205, path_fk_list: "", criteria_operator: 1, criteria_value_1: recordPk }
      ],
      activity_log_data: { query_type: "input-grid", record_fk: recordPk }
    }];

    const response = await fetch("https://axiom.veracross.com/oakwood/results/2154.json", {
      method: "PUT",
      credentials: "include",
      cache: "no-store",
      headers: {
        "Accept": "*/*",
        "Content-Type": "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "X-CSRF-Token": token
      },
      body: JSON.stringify({
        records: JSON.stringify(records),
        activity_log_data: JSON.stringify({
          query_type: "detail-category-query",
          page_url: location.href
        })
      })
    });

    const text = await response.text();
    return { ok: response.ok, status: response.status, body: text };
  })();
}

// Runs INSIDE the Veracross tab. Mirrors the exact POST captured from
// manually adding a brand-new row in Veracross's grid. record_pk: null
// signals "create"; the response's completed[0].record_pk is the new id.
// field_alias "26269" (field_info_fk 1206) is the odd one — that's the
// field that actually ties the new row to a student.
function createInPage(personPK, hours, notes, volunteerDate) {
  return (async () => {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    if (!token) {
      return { ok: false, status: 0, body: "No csrf-token meta tag found — are you logged in on this tab?" };
    }

    const records = [{
      guid: String(Date.now()),
      record_pk: null,
      table_info_fk: 122,
      fields: [
        { field_alias: "26269", field_info_fk: 1206, path_fk_list: "", value: personPK },
        { field_alias: "school_year", field_info_fk: 3439, path_fk_list: "", value: 2026 },
        { field_alias: "grading_period", field_info_fk: 3440, path_fk_list: "", value: 50 },
        { field_alias: "volunteer_job_category", field_info_fk: 1208, path_fk_list: "", value: 3 },
        { field_alias: "volunteer_hours", field_info_fk: 1209, path_fk_list: "", value: hours },
        { field_alias: "approved", field_info_fk: 11945, path_fk_list: "", value: true },
        { field_alias: "organization_key", field_info_fk: 12261, path_fk_list: "", value: 0 },
        { field_alias: "volunteer_date", field_info_fk: 1207, path_fk_list: "", value: volunteerDate },
        { field_alias: "notes", field_info_fk: 1210, path_fk_list: "", value: notes }
      ],
      activity_log_data: { query_type: "input-grid", record_fk: null }
    }];

    const response = await fetch("https://axiom.veracross.com/oakwood/results.json", {
      method: "POST",
      credentials: "include",
      cache: "no-store",
      headers: {
        "Accept": "*/*",
        "Content-Type": "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "X-CSRF-Token": token
      },
      body: JSON.stringify({
        records: JSON.stringify(records),
        activity_log_data: JSON.stringify({
          query_type: "detail-category-query",
          page_url: location.href
        })
      })
    });

    const text = await response.text();
    return { ok: response.ok, status: response.status, body: text };
  })();
}

// Runs INSIDE the Veracross tab. value_list/gkc:<id> is the endpoint the
// page's own dropdowns use to populate their options — reading it tells us
// the human-readable labels behind the numeric codes we've been guessing
// at (volunteer_job_category, school_year, grading_period).
function fetchValueListInPage(gkcId) {
  return (async () => {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    if (!token) {
      return { ok: false, status: 0, body: "No csrf-token meta tag found — are you logged in on this tab?" };
    }

    const response = await fetch(`https://axiom.veracross.com/oakwood/value_list/gkc:${gkcId}`, {
      method: "GET",
      credentials: "include",
      cache: "no-store",
      headers: {
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "X-Requested-With": "XMLHttpRequest",
        "X-CSRF-Token": token
      }
    });

    const text = await response.text();
    return { ok: response.ok, status: response.status, body: text };
  })();
}

async function findVeracrossTab() {
  const [tab] = await chrome.tabs.query({ url: "https://axiom.veracross.com/*" });
  return tab;
}

pullBtn.addEventListener("click", async () => {
  pullBtn.disabled = true;
  setStatus("Pulling…");
  outputEl.textContent = "";

  try {
    const tab = await findVeracrossTab();
    if (!tab) {
      setStatus("Open axiom.veracross.com in a tab, log in, then try again.", "error");
      return;
    }

    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: pullInPage,
      args: [PERSON_PK]
    });

    if (!result.ok) {
      setStatus(`HTTP ${result.status}`, "error");
      outputEl.textContent = result.body || "";
      return;
    }

    try {
      const data = JSON.parse(result.body);
      setStatus(`Success — ${Array.isArray(data) ? data.length : "?"} record(s).`, "ok");
      outputEl.textContent = JSON.stringify(data, null, 2);
    } catch {
      setStatus(`HTTP ${result.status} — non-JSON response`, "error");
      outputEl.textContent = result.body.slice(0, 5000);
    }
  } catch (err) {
    setStatus(`Error: ${err.message}`, "error");
  } finally {
    pullBtn.disabled = false;
  }
});

updateBtn.addEventListener("click", async () => {
  updateBtn.disabled = true;
  setStatus("Updating…");
  outputEl.textContent = "";

  const notes = `updated via extension ${new Date().toLocaleTimeString()}`;
  const hours = Math.round(Math.random() * 10 * 4) / 4; // random quarter-hour, easy to eyeball as "it changed"

  try {
    const tab = await findVeracrossTab();
    if (!tab) {
      setStatus("Open axiom.veracross.com in a tab, log in, then try again.", "error");
      return;
    }

    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: updateInPage,
      args: [TEST_RECORD_PK, notes, hours]
    });

    if (!result.ok) {
      setStatus(`HTTP ${result.status}`, "error");
      outputEl.textContent = result.body || "";
      return;
    }

    setStatus(`HTTP ${result.status} — sent notes="${notes}", hours=${hours}. Check the grid in Veracross to confirm.`, "ok");
    try {
      outputEl.textContent = JSON.stringify(JSON.parse(result.body), null, 2);
    } catch {
      outputEl.textContent = result.body.slice(0, 5000);
    }
  } catch (err) {
    setStatus(`Error: ${err.message}`, "error");
  } finally {
    updateBtn.disabled = false;
  }
});

createBtn.addEventListener("click", async () => {
  createBtn.disabled = true;
  setStatus("Creating…");
  outputEl.textContent = "";

  const notes = `created via extension ${new Date().toLocaleTimeString()}`;
  const hours = Math.round(Math.random() * 10 * 4) / 4;
  const today = new Date().toISOString().slice(0, 10);

  try {
    const tab = await findVeracrossTab();
    if (!tab) {
      setStatus("Open axiom.veracross.com in a tab, log in, then try again.", "error");
      return;
    }

    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: createInPage,
      args: [PERSON_PK, hours, notes, today]
    });

    if (!result.ok) {
      setStatus(`HTTP ${result.status}`, "error");
      outputEl.textContent = result.body || "";
      return;
    }

    setStatus(`HTTP ${result.status} — created notes="${notes}", hours=${hours}. Check the grid in Veracross to confirm.`, "ok");
    try {
      outputEl.textContent = JSON.stringify(JSON.parse(result.body), null, 2);
    } catch {
      outputEl.textContent = result.body.slice(0, 5000);
    }
  } catch (err) {
    setStatus(`Error: ${err.message}`, "error");
  } finally {
    createBtn.disabled = false;
  }
});

lookupBtn.addEventListener("click", async () => {
  lookupBtn.disabled = true;
  setStatus("Looking up value lists…");
  outputEl.textContent = "";

  const lists = [
    { id: 1208, label: "volunteer_job_category" },
    { id: 3439, label: "school_year" },
    { id: 3440, label: "grading_period" }
  ];

  try {
    const tab = await findVeracrossTab();
    if (!tab) {
      setStatus("Open axiom.veracross.com in a tab, log in, then try again.", "error");
      return;
    }

    const sections = [];
    for (const { id, label } of lists) {
      const [{ result }] = await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: fetchValueListInPage,
        args: [id]
      });

      let body = result.body;
      try { body = JSON.stringify(JSON.parse(result.body), null, 2); } catch { /* leave as raw text */ }
      sections.push(`=== ${label} (gkc:${id}) — HTTP ${result.status} ===\n${body}`);
    }

    setStatus("Done — see output below.", "ok");
    outputEl.textContent = sections.join("\n\n");
  } catch (err) {
    setStatus(`Error: ${err.message}`, "error");
  } finally {
    lookupBtn.disabled = false;
  }
});
