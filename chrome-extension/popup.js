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
const FIREBASE_PROJECT_ID = "oakwoodstudents-d9495";

// Advisor roster — keep in sync with FirebaseService.swift's advisorList.
const ADVISOR_LIST = ["Mr. Hubbard", "Mrs. Call", "Mr. Willis", "Dr. Pak", "Mr. Clink"];

// TODO: confirm real values via the Lookup Value Lists button before real
// approvals will actually succeed — until then, creates from the Pending
// Approvals flow will fail with these left null (Veracross likely requires
// them). The hardcoded Test Create button below still uses known-good
// values (3 / 50) and is unaffected by these.
const VOLUNTEER_JOB_CATEGORY = null;
const GRADING_PERIOD = null;

const pullBtn = document.getElementById("pullBtn");
const updateBtn = document.getElementById("updateBtn");
const createBtn = document.getElementById("createBtn");
const lookupBtn = document.getElementById("lookupBtn");
const loadPendingBtn = document.getElementById("loadPendingBtn");
const pendingListEl = document.getElementById("pendingList");
const statusEl = document.getElementById("status");
const outputEl = document.getElementById("output");
const advisorSelectContainer = document.getElementById("advisorSelectContainer");

function setStatus(text, kind) {
  statusEl.textContent = text;
  statusEl.className = kind || "";
}

// Same graceful-fallback pattern as the Swift side's advisorList: a plain text input while
// the real roster is empty, a <select> once ADVISOR_LIST is populated. Persists the chosen
// value in localStorage so the advisor doesn't have to re-enter/re-select it every time.
let advisorSelectEl = null;

function initAdvisorSelect() {
  const saved = localStorage.getItem("selectedAdvisor") || "";
  advisorSelectContainer.innerHTML = "";

  if (ADVISOR_LIST.length === 0) {
    const input = document.createElement("input");
    input.type = "text";
    input.id = "advisorSelect";
    input.placeholder = "Your name (as it appears on student forms)";
    input.value = saved;
    input.addEventListener("change", () => {
      localStorage.setItem("selectedAdvisor", input.value);
    });
    advisorSelectContainer.appendChild(input);
    advisorSelectEl = input;
  } else {
    const select = document.createElement("select");
    select.id = "advisorSelect";
    const blankOption = document.createElement("option");
    blankOption.value = "";
    blankOption.textContent = "Select advisor…";
    select.appendChild(blankOption);
    for (const name of ADVISOR_LIST) {
      const option = document.createElement("option");
      option.value = name;
      option.textContent = name;
      select.appendChild(option);
    }
    select.value = ADVISOR_LIST.includes(saved) ? saved : "";
    select.addEventListener("change", () => {
      localStorage.setItem("selectedAdvisor", select.value);
    });
    advisorSelectContainer.appendChild(select);
    advisorSelectEl = select;
  }
}

function getSelectedAdvisor() {
  return advisorSelectEl ? advisorSelectEl.value : "";
}

// Filters pending forms down to just the selected advisor's students — but only once the
// real roster (ADVISOR_LIST) is configured and an advisor is actually selected. Until then,
// this is a no-op so the tool keeps working unfiltered exactly as it does today.
function filterFormsByAdvisor(forms) {
  const selected = getSelectedAdvisor().trim();
  if (ADVISOR_LIST.length === 0 || !selected) return forms;
  const selectedLower = selected.toLowerCase();
  return forms.filter(f => (f.advisorName || "").trim().toLowerCase() === selectedLower);
}

initAdvisorSelect();

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
function createInPage(personPK, hours, notes, volunteerDate, jobCategory, gradingPeriod, schoolYear) {
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
        { field_alias: "school_year", field_info_fk: 3439, path_fk_list: "", value: schoolYear },
        { field_alias: "grading_period", field_info_fk: 3440, path_fk_list: "", value: gradingPeriod },
        { field_alias: "volunteer_job_category", field_info_fk: 1208, path_fk_list: "", value: jobCategory },
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

// --- Firestore (runs in the popup itself — Firestore's REST API is a
// public Google Cloud endpoint with permissive CORS, unlike Veracross, so
// no injection needed here) ---

function parseFirestoreValue(v) {
  if (!v) return null;
  if (v.stringValue !== undefined) return v.stringValue;
  if (v.integerValue !== undefined) return Number(v.integerValue);
  if (v.doubleValue !== undefined) return v.doubleValue;
  if (v.booleanValue !== undefined) return v.booleanValue;
  if (v.timestampValue !== undefined) return v.timestampValue;
  if (v.nullValue !== undefined) return null;
  if (v.arrayValue !== undefined) return (v.arrayValue.values || []).map(parseFirestoreValue);
  if (v.mapValue !== undefined) return parseFirestoreDoc(v.mapValue.fields || {});
  return null;
}

function parseFirestoreDoc(fields) {
  const obj = {};
  for (const [k, v] of Object.entries(fields || {})) obj[k] = parseFirestoreValue(v);
  return obj;
}

async function fetchPendingForms() {
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/serviceForms`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Firestore fetch failed: HTTP ${response.status}`);
  const data = await response.json();
  const docs = data.documents || [];
  return docs
    .map(doc => ({ id: doc.name.split("/").pop(), ...parseFirestoreDoc(doc.fields) }))
    .filter(f => f.status === "pending");
}

async function markFormApproved(formId) {
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/serviceForms/${formId}?updateMask.fieldPaths=status`;
  const response = await fetch(url, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ fields: { status: { stringValue: "approved" } } })
  });
  if (!response.ok) throw new Error(`Failed to mark approved: HTTP ${response.status}`);
}

// Inverse of parseFirestoreValue — encodes a plain JS value into Firestore's REST wire format.
function toFirestoreValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toFirestoreValue) } };
  if (typeof v === "object") return { mapValue: { fields: toFirestoreFields(v) } };
  throw new Error(`Can't encode value: ${v}`);
}

function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, val] of Object.entries(obj)) fields[k] = toFirestoreValue(val);
  return fields;
}

// Marks a form rejected with a reason. Two separate single-field PATCHes rather than one
// PATCH with two `updateMask.fieldPaths` params — Firestore's REST API does document support
// for repeating that param, but markFormApproved (the only existing precedent in this file)
// only ever does one field at a time, so this stays on the pattern that's proven to work here
// rather than betting on the untested multi-field form.
async function rejectForm(formId, reason) {
  const statusUrl = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/serviceForms/${formId}?updateMask.fieldPaths=status`;
  const statusResponse = await fetch(statusUrl, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ fields: { status: { stringValue: "rejected" } } })
  });
  if (!statusResponse.ok) throw new Error(`Failed to mark rejected: HTTP ${statusResponse.status}`);

  const reasonUrl = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/serviceForms/${formId}?updateMask.fieldPaths=rejectionReason`;
  const reasonResponse = await fetch(reasonUrl, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ fields: { rejectionReason: { stringValue: reason } } })
  });
  if (!reasonResponse.ok) throw new Error(`Failed to write rejection reason: HTTP ${reasonResponse.status}`);
}

// Writes back whichever services actually got a Veracross record_pk, so the app can later
// link its "Completed hours from Veracross" rows back to this form. Independent of
// markFormApproved — call regardless of whether every entry succeeded.
async function writeBackServices(formId, updatedServices) {
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/serviceForms/${formId}?updateMask.fieldPaths=services`;
  const response = await fetch(url, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ fields: { services: toFirestoreValue(updatedServices) } })
  });
  if (!response.ok) throw new Error(`Failed to write back services: HTTP ${response.status}`);
}

// Heuristic inferred from real read data (Aug 2024 entries -> school_year
// 2024; May 2025 onward -> 2025) and confirmed by today's live create
// (Aug 2026 -> school_year 2026): the school year is named for the
// calendar year it starts in, with a rollover around July.
function computeSchoolYear(dateStr) {
  const d = new Date(dateStr);
  if (isNaN(d)) return null;
  const month = d.getUTCMonth() + 1; // 1-12
  return month >= 7 ? d.getUTCFullYear() : d.getUTCFullYear() - 1;
}

function normalizeDate(dateStr) {
  const d = new Date(dateStr);
  if (isNaN(d)) return dateStr; // pass through as-is, better than crashing
  return d.toISOString().slice(0, 10);
}

// Parses a createInPage result to determine REAL success — HTTP 200 alone
// isn't enough proof (e.g. a logged-out session gets redirected to a login
// page that still returns 200), so this requires an actual record_pk back.
function parseCreateResult(result) {
  if (!result.ok) return { success: false, recordPk: null };
  let parsed;
  try {
    parsed = JSON.parse(result.body);
  } catch {
    return { success: false, recordPk: null };
  }
  const recordPk = parsed?.completed?.[0]?.record_pk ?? null;
  const failed = Array.isArray(parsed?.failed) ? parsed.failed : [];
  return { success: recordPk != null && failed.length === 0, recordPk };
}

// Builds the (initially hidden) detail panel for a pending item: supervisor
// info, the signature image (if present), signer/signed info, tax ID,
// advisor name, and the full per-entry services list. Fields that are
// missing/empty are simply omitted rather than shown as blank/"undefined".
function buildDetailPanel(form) {
  const detail = document.createElement("div");
  detail.className = "pending-item-detail";
  detail.style.display = "none";

  const addLine = (label, value) => {
    if (value === undefined || value === null || value === "") return;
    const line = document.createElement("div");
    line.textContent = `${label}: ${value}`;
    detail.appendChild(line);
  };

  addLine("Supervisor", form.supervisorName);
  addLine("Supervisor email", form.supervisorEmail);
  addLine("Signer email", form.signerEmail);
  addLine("Signed at", form.signedAt);
  addLine("Tax ID", form.taxID);
  addLine("Advisor", form.advisorName);

  if (form.signatureImageBase64) {
    const src = form.signatureImageBase64.startsWith("data:")
      ? form.signatureImageBase64
      : `data:image/png;base64,${form.signatureImageBase64}`;
    const img = document.createElement("img");
    img.className = "signature-img";
    img.src = src;
    img.alt = "Supervisor signature";
    detail.appendChild(img);
  }

  if (form.services && form.services.length > 0) {
    const title = document.createElement("div");
    title.className = "detail-section-title";
    title.textContent = "Service entries:";
    detail.appendChild(title);

    for (const service of form.services) {
      const row = document.createElement("div");
      row.className = "service-entry";
      const parts = [];
      if (service.date) parts.push(service.date);
      if (service.hours !== undefined && service.hours !== null && service.hours !== "") parts.push(`${service.hours} hrs`);
      if (service.description) parts.push(service.description);
      if (service.notes) parts.push(service.notes);
      row.textContent = parts.length > 0 ? parts.join(" — ") : "(no details)";
      detail.appendChild(row);
    }
  }

  return detail;
}

function renderPendingList(forms) {
  pendingListEl.innerHTML = "";
  if (forms.length === 0) {
    pendingListEl.textContent = "No pending submissions.";
    return;
  }

  for (const form of forms) {
    const div = document.createElement("div");
    div.className = "pending-item";

    const meta = document.createElement("div");
    meta.className = "meta";
    meta.textContent =
      `${form.studentName || form.studentId || "(unknown student)"} — ${form.title || "Untitled"}\n` +
      `${form.totalHours || 0} hrs, ${form.organization || "no org"}, personPK: ${form.personPK ?? "MISSING"}`;
    div.appendChild(meta);

    const detail = buildDetailPanel(form);

    const moreInfoBtn = document.createElement("button");
    moreInfoBtn.className = "more-info-btn";
    moreInfoBtn.textContent = "More Info";
    moreInfoBtn.addEventListener("click", () => {
      const isHidden = detail.style.display === "none";
      detail.style.display = isHidden ? "block" : "none";
      moreInfoBtn.textContent = isHidden ? "Hide Info" : "More Info";
    });
    div.appendChild(moreInfoBtn);

    if (!form.personPK) {
      const warn = document.createElement("div");
      warn.className = "warn";
      warn.textContent = "No personPK on this submission — can't post to Veracross.";
      div.appendChild(warn);
    } else {
      const btn = document.createElement("button");
      btn.textContent = "Approve & Post to Veracross";
      btn.addEventListener("click", () => approveForm(form, btn));
      div.appendChild(btn);
    }

    const rejectBtn = document.createElement("button");
    rejectBtn.className = "reject-btn";
    rejectBtn.textContent = "Reject";
    rejectBtn.addEventListener("click", () => handleRejectClick(form, rejectBtn));
    div.appendChild(rejectBtn);

    div.appendChild(detail);

    pendingListEl.appendChild(div);
  }
}

async function approveForm(form, btn) {
  btn.disabled = true;
  setStatus(`Posting ${form.services?.length || 0} entr${form.services?.length === 1 ? "y" : "ies"} for ${form.studentName || form.personPK}…`);
  outputEl.textContent = "";

  try {
    const tab = await findVeracrossTab();
    if (!tab) {
      setStatus("Open axiom.veracross.com in a tab, log in, then try again.", "error");
      return;
    }

    const results = [];
    const successFlags = [];
    const updatedServices = [];
    let anyNewIds = false;
    for (const service of form.services || []) {
      const notes = [service.description, service.notes].filter(Boolean).join(" — ");
      const [{ result }] = await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: createInPage,
        args: [
          form.personPK,
          service.hours,
          notes,
          normalizeDate(service.date),
          VOLUNTEER_JOB_CATEGORY,
          GRADING_PERIOD,
          computeSchoolYear(service.date)
        ]
      });
      const { success, recordPk } = parseCreateResult(result);
      results.push(result);
      successFlags.push(success);

      if (recordPk != null) {
        anyNewIds = true;
        updatedServices.push({ ...service, veracrossRecordId: recordPk });
      } else {
        updatedServices.push(service);
      }
    }

    outputEl.textContent = JSON.stringify(results, null, 2);

    // Record whichever entries actually got a Veracross id, independent of whether every
    // entry succeeded — this is what lets the app later link its "Completed hours from
    // Veracross" rows back to this form.
    if (anyNewIds) {
      try {
        await writeBackServices(form.id, updatedServices);
      } catch (err) {
        outputEl.textContent += `\n\nWarning: failed to write back Veracross record ids: ${err.message}`;
      }
    }

    const allOk = successFlags.length > 0 && successFlags.every(Boolean);
    if (!allOk) {
      setStatus(
        `${successFlags.filter(Boolean).length}/${results.length} entries actually created in Veracross — NOT marking approved. Check you're logged into axiom.veracross.com, and that VOLUNTEER_JOB_CATEGORY/GRADING_PERIOD (still null placeholders) are filled in. See output for details.`,
        "error"
      );
      return;
    }

    await markFormApproved(form.id);
    setStatus(`Posted all ${results.length} entries and marked "${form.title}" approved.`, "ok");
    const pending = await fetchPendingForms();
    renderPendingList(filterFormsByAdvisor(pending));
  } catch (err) {
    setStatus(`Error: ${err.message}`, "error");
  } finally {
    btn.disabled = false;
  }
}

// Same UX as advisor-portal's rejectForm: native prompt, cancel (null) is a no-op, an empty
// string is a valid "no reason given" submission — matches the "(optional)" prompt copy.
async function handleRejectClick(form, btn) {
  const reason = prompt("Reason for rejection (optional):");
  if (reason === null) return;

  btn.disabled = true;
  setStatus(`Rejecting "${form.title || "Untitled"}" for ${form.studentName || form.personPK}…`);

  try {
    await rejectForm(form.id, reason);
    setStatus(`Rejected "${form.title || "Untitled"}".`, "ok");
    const pending = await fetchPendingForms();
    renderPendingList(filterFormsByAdvisor(pending));
  } catch (err) {
    setStatus(`Error: ${err.message}`, "error");
    btn.disabled = false;
  }
}

loadPendingBtn.addEventListener("click", async () => {
  loadPendingBtn.disabled = true;
  setStatus("Loading pending approvals…");
  try {
    const forms = filterFormsByAdvisor(await fetchPendingForms());
    renderPendingList(forms);
    setStatus(`${forms.length} pending submission(s).`, "ok");
  } catch (err) {
    setStatus(`Error: ${err.message}`, "error");
  } finally {
    loadPendingBtn.disabled = false;
  }
});

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
      args: [PERSON_PK, hours, notes, today, 3, 50, 2026]
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
