// Oakwood Sports Signups — Google Apps Script Web App, bound directly to the volleyball/
// basketball job-signup Google Sheet. Not deployed via Firebase — this file is tracked here
// for version control/reference only. To deploy or update it, copy this file's contents into
// the Sheet's own script editor (Extensions > Apps Script) and paste over whatever's there.
//
// Runs with the script's own implicit access to the sheet it's bound to — no service account,
// no private key, no Cloud Functions, no Firebase billing plan required. Deploy as a Web App
// (Deploy > New deployment > Web app, "Execute as: Me", "Who has access: Anyone") to get an
// HTTPS URL the app calls directly, the same way it already calls the Firestore REST API with
// no embedded secret — the sheet is the only thing this URL can touch.
//
// Sheet layout assumed: header row, then one row per game. First four columns are fixed
// (Date, Start time, Oakwood Team, Opponent); every column after that is a job, dynamically
// read from the header row — add/rename/remove job columns in the sheet and the app picks it
// up automatically, no code change needed. An empty job cell means that slot is open; any
// other value means it's filled by whoever's name is there.

const SHEET_NAME = 'Sheet1';
const FIXED_COLUMNS = ['Date', 'Start time', 'Oakwood Team', 'Opponent'];

// GET: returns every game and its job columns, open slots as "".
function doGet(e) {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
  const values = sheet.getDataRange().getValues();
  const headers = values[0];
  const jobColumns = headers.slice(FIXED_COLUMNS.length);

  // jobs is an array, not an object keyed by job name — JSON objects don't guarantee key
  // order on the Swift decoding side, and the app needs to show jobs in the same left-to-right
  // column order ADs see in the sheet.
  const games = values.slice(1)
    .filter(row => row[0] instanceof Date)
    .map(row => ({
      gameTime: combinedISOString(row[0], row[1]),
      team: String(row[2] || ''),
      opponent: String(row[3] || ''),
      jobs: jobColumns.map((job, i) => ({
        name: String(job),
        filledBy: String(row[FIXED_COLUMNS.length + i] || '')
      }))
    }));

  return jsonResponse({ games: games });
}

// POST body: { gameTime (ISO string, exactly as returned by GET), team, opponent, job, name,
// action: "signup" | "cancel" }. A lock guards the read-check-write so two people signing up
// for the same open slot at the same moment can't both succeed.
function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const body = JSON.parse(e.postData.contents);
    const gameTime = body.gameTime;
    const team = body.team;
    const opponent = body.opponent;
    const job = body.job;
    const name = body.name || '';
    const action = body.action;

    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
    const values = sheet.getDataRange().getValues();
    const headers = values[0];
    const jobColIndex = headers.indexOf(job);
    if (jobColIndex === -1) return jsonResponse({ ok: false, error: 'Unknown job column' });

    for (let r = 1; r < values.length; r++) {
      const row = values[r];
      if (!(row[0] instanceof Date)) continue;
      if (combinedISOString(row[0], row[1]) === gameTime &&
          String(row[2]) === team && String(row[3]) === opponent) {
        const cell = sheet.getRange(r + 1, jobColIndex + 1);
        const current = String(cell.getValue() || '');
        if (action === 'signup') {
          if (current) return jsonResponse({ ok: false, error: 'Slot already taken' });
          cell.setValue(name);
        } else if (action === 'cancel') {
          if (current !== name) return jsonResponse({ ok: false, error: 'Not your slot' });
          cell.setValue('');
        } else {
          return jsonResponse({ ok: false, error: 'Unknown action' });
        }
        return jsonResponse({ ok: true });
      }
    }
    return jsonResponse({ ok: false, error: 'Game not found' });
  } finally {
    lock.releaseLock();
  }
}

// Combines a Date-formatted cell and a separate Time-formatted cell into one ISO 8601
// timestamp string (with timezone offset) — easy for Swift's ISO8601DateFormatter to parse,
// and used as the exact-match key between what GET returns and what POST is told to update,
// so edits to row order/insertions in the sheet never break a pending signup/cancel request.
function combinedISOString(dateValue, timeValue) {
  const t = timeValue instanceof Date ? timeValue : new Date(timeValue);
  const combined = new Date(dateValue.getFullYear(), dateValue.getMonth(), dateValue.getDate(), t.getHours(), t.getMinutes(), 0);
  return Utilities.formatDate(combined, Session.getScriptTimeZone(), "yyyy-MM-dd'T'HH:mm:ssXXX");
}

function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
