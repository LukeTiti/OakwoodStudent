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
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

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

// Notifies a student by push when their community service form moves through
// the signing/approval pipeline (signed by supervisor, approved, or
// rejected) — so they don't have to keep reopening the app to check. Reuses
// the same userTokens/{email} FCM token store that PushNotificationManager
// .swift already maintains for grade/club notifications.
const STATUS_MESSAGES = {
  pending: (data) => ({
    title: "Supervisor signed your form",
    body: `${data.supervisorSignature || "Your supervisor"} signed ` +
      `"${data.title}". It's now with your advisor for approval.`,
  }),
  approved: (data) => ({
    title: "Service hours approved",
    body: `"${data.title}" (${data.totalHours || 0} hrs) was approved.`,
  }),
  rejected: (data) => ({
    title: "Service hours rejected",
    body: data.rejectionReason ?
      `"${data.title}" was rejected: ${data.rejectionReason}` :
      `"${data.title}" was rejected.`,
  }),
};

exports.onServiceFormStatusChange = onDocumentUpdated(
    "serviceForms/{formId}",
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      if (!before || !after || before.status === after.status) return;

      // Only notify on the pending_signature -> pending transition (signed),
      // not every write that touches status — resubmission also passes
      // through "pending_signature" but that's the student's own action,
      // not news to push to them.
      const messageBuilder = after.status === "pending" ?
        (before.status === "pending_signature" ?
          STATUS_MESSAGES.pending : null) :
        STATUS_MESSAGES[after.status];
      if (!messageBuilder) return;

      const studentId = after.studentId;
      if (!studentId) return;

      const tokenDoc = await admin.firestore()
          .collection("userTokens").doc(studentId).get();
      const tokenData = tokenDoc.data();
      const token = tokenData && tokenData.fcmToken;
      if (!token) return;

      const {title, body} = messageBuilder(after);
      try {
        await admin.messaging().send({
          token,
          notification: {title, body},
          apns: {payload: {aps: {sound: "default"}}},
        });
      } catch (err) {
        logger.error("Failed to send service form status notification", err);
      }
    },
);
