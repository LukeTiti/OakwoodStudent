// v0.1: read-only proof of concept. Confirms the extension can make an
// authenticated request to axiom.veracross.com using whatever session
// cookies already exist in the browser from the advisor's own normal
// Veracross login — no login flow of our own, no stored credentials.
//
// "801" is the detail-category id for volunteer hours (matches the
// "#/detail/student-us/{personPK}/801-vol-hours" URL fragment seen while
// inspecting the real Veracross admin page).

const personPKInput = document.getElementById("personPK");
const pullBtn = document.getElementById("pullBtn");
const statusEl = document.getElementById("status");
const outputEl = document.getElementById("output");

function setStatus(text, kind) {
  statusEl.textContent = text;
  statusEl.className = kind || "";
}

pullBtn.addEventListener("click", async () => {
  const personPK = personPKInput.value.trim();
  if (!personPK || !/^\d+$/.test(personPK)) {
    setStatus("Enter a numeric person PK first.", "error");
    return;
  }

  pullBtn.disabled = true;
  setStatus("Pulling…");
  outputEl.textContent = "";

  const url = `https://axiom.veracross.com/oakwood/detail_category/801/data/${personPK}.json`;

  try {
    const response = await fetch(url, {
      method: "GET",
      credentials: "include",
      headers: {
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "X-Requested-With": "XMLHttpRequest"
      }
    });

    const contentType = response.headers.get("content-type") || "";
    const bodyText = await response.text();

    if (!response.ok) {
      setStatus(`Request failed: HTTP ${response.status}. Are you logged into Veracross in this browser?`, "error");
      outputEl.textContent = bodyText.slice(0, 2000);
      return;
    }

    if (!contentType.includes("json")) {
      // Most likely got redirected to an HTML login page instead of real data.
      setStatus("Got a non-JSON response — you're probably not logged into Veracross (axiom.veracross.com) in this browser.", "error");
      outputEl.textContent = bodyText.slice(0, 2000);
      return;
    }

    const data = JSON.parse(bodyText);
    setStatus(`Success — ${Array.isArray(data) ? data.length : "?"} record(s).`, "ok");
    outputEl.textContent = JSON.stringify(data, null, 2);
  } catch (err) {
    setStatus(`Network/CORS error: ${err.message}`, "error");
  } finally {
    pullBtn.disabled = false;
  }
});
