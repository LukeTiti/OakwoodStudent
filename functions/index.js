/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({maxInstances: 10});

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

// Proxies ICS calendar fetches to Veracross so advisor-portal (served from
// Firebase Hosting) can pull schedule data without hitting browser CORS —
// Veracross's server does not send Access-Control-Allow-Origin for our
// origin, and that isn't something client-side JS can work around. Since
// this fetch happens server-to-server, CORS does not apply here at all.
const ALLOWED_HOSTNAMES = new Set(["api.veracross.com"]);

exports.icsProxy = onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");

  const target = req.query.url;
  if (!target) {
    res.status(400).send("Missing url parameter");
    return;
  }

  let parsed;
  try {
    parsed = new URL(target);
  } catch (err) {
    res.status(400).send("Invalid url");
    return;
  }

  if (!ALLOWED_HOSTNAMES.has(parsed.hostname)) {
    res.status(403).send("Host not allowed");
    return;
  }

  try {
    const upstream = await fetch(parsed.toString());
    const text = await upstream.text();
    res.set("Content-Type", "text/calendar");
    res.status(upstream.status).send(text);
  } catch (err) {
    logger.error("icsProxy upstream fetch failed", err);
    res.status(502).send(`Upstream fetch failed: ${err.message}`);
  }
});
