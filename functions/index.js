// =====================================================
// IMPORTS & INITIALIZATION
// =====================================================
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const axios = require("axios");
const https = require("https");
const twilio = require("twilio");

admin.initializeApp();
const db = admin.firestore();

// =====================================================
// ENV CONFIG
// =====================================================
const BOT_TOKEN = functions.config().telegram?.token;
const TOYYIBPAY_SECRET_KEY = String(
  functions.config().toyyibpay?.secret_key || process.env.TOYYIBPAY_SECRET_KEY || ""
).trim();
const TOYYIBPAY_CATEGORY_CODE = String(
  functions.config().toyyibpay?.category_code ||
    process.env.TOYYIBPAY_CATEGORY_CODE ||
    ""
).trim();
const TOYYIBPAY_SANDBOX =
  String(
    functions.config().toyyibpay?.sandbox ||
      process.env.TOYYIBPAY_SANDBOX ||
      "",
  )
    .trim()
    .toLowerCase() === "true";
const TOYYIBPAY_API_BASE =
  functions.config().toyyibpay?.api_base ||
  process.env.TOYYIBPAY_API_BASE ||
  (TOYYIBPAY_SANDBOX
    ? "https://dev.toyyibpay.com/index.php/api"
    : "https://toyyibpay.com/index.php/api");
const TOYYIBPAY_PAYMENT_BASE =
  functions.config().toyyibpay?.payment_base ||
  process.env.TOYYIBPAY_PAYMENT_BASE ||
  (TOYYIBPAY_SANDBOX ? "https://dev.toyyibpay.com" : "https://toyyibpay.com");
const TOYYIBPAY_RETURN_URL =
  functions.config().toyyibpay?.return_url ||
  process.env.TOYYIBPAY_RETURN_URL ||
  "https://toyyibpay.com/";
const FB_PROJECT_ID = functions.config().fb?.project_id;
const PROJECT_ID =
  FB_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  process.env.GCP_PROJECT ||
  (() => {
    try {
      const raw = process.env.FIREBASE_CONFIG;
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      return parsed.projectId || null;
    } catch (_) {
      return null;
    }
  })();
const SHIFTPDF_API_KEY =
  functions.config().shiftpdf?.key || process.env.SHIFTPDF_API_KEY;
const SHIFTPDF_HTML_TO_PDF_URL =
  functions.config().shiftpdf?.html_to_pdf_url ||
  process.env.SHIFTPDF_HTML_TO_PDF_URL ||
  "https://api.shiftpdf.com/convert/html/pdf";
const SHIFTPDF_ALLOW_SELF_SIGNED =
  String(
    functions.config().shiftpdf?.allow_self_signed ||
      process.env.SHIFTPDF_ALLOW_SELF_SIGNED ||
      "",
  )
    .trim()
    .toLowerCase() === "true";
const IS_EMULATOR = Boolean(
  process.env.FUNCTIONS_EMULATOR || process.env.FIREBASE_EMULATOR_HUB,
);

const PDFREST_API_KEY =
  functions.config().pdfrest?.key || process.env.PDFREST_API_KEY;
const PDFREST_PDF_URL =
  functions.config().pdfrest?.pdf_url ||
  process.env.PDFREST_PDF_URL ||
  "https://api.pdfrest.com/pdf";

function getTwilioConfig() {
  const cfg = functions.config().twilio || {};
  return {
    sid: String(cfg.sid || "").trim(),
    token: String(cfg.token || cfg.auth_token || "").trim(),
    from: String(cfg.from || cfg.from_number || "").trim(),
  };
}

function normalizeE164(phone) {
  const raw = String(phone || "").trim();
  if (!raw) return "";
  const cleaned = raw.replace(/[^\d+]/g, "");
  if (!cleaned.startsWith("+")) return "";
  if (cleaned.length < 8) return "";
  return cleaned;
}

async function sendTwilioSms({ to, body }) {
  const cfg = getTwilioConfig();
  if (!cfg.sid || !cfg.token || !cfg.from) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Twilio not configured. Set functions config: twilio.sid, twilio.token, twilio.from",
    );
  }
  const client = twilio(cfg.sid, cfg.token);
  return await client.messages.create({ from: cfg.from, to, body });
}

function escapeHtml(input) {
  return String(input || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

async function assertAdmin(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated");
  }
  const uid = context.auth.uid;

  // Preferred: admin doc id equals auth uid.
  const directDoc = await db.collection("admin").doc(uid).get();
  if (directDoc.exists) {
    const data = directDoc.data() || {};
    const role = String(data.role || "").toLowerCase().trim();
    if (role && role !== "admin") {
      throw new functions.https.HttpsError("permission-denied", "Not an admin");
    }
    return { uid, admin: data, adminDocId: directDoc.id };
  }

  // Fallback: allow admin lookup by email when admin docs were created manually.
  const email = String(context.auth.token?.email || "").trim().toLowerCase();
  if (!email) {
    throw new functions.https.HttpsError("permission-denied", "Not an admin");
  }
  const byEmailSnap = await db
    .collection("admin")
    .where("email", "==", email)
    .limit(1)
    .get();
  if (byEmailSnap.empty) {
    throw new functions.https.HttpsError("permission-denied", "Not an admin");
  }
  const adminDoc = byEmailSnap.docs[0];
  const data = adminDoc.data() || {};
  const role = String(data.role || "").toLowerCase().trim();
  if (role && role !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Not an admin");
  }
  return { uid, admin: data, adminDocId: adminDoc.id };
}

function monthRangeUtc(year, month) {
  const y = Number(year);
  const m = Number(month);
  if (!Number.isFinite(y) || !Number.isFinite(m) || m < 1 || m > 12) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid month/year");
  }
  const start = new Date(Date.UTC(y, m - 1, 1, 0, 0, 0));
  const end = new Date(Date.UTC(y, m, 1, 0, 0, 0));
  return { start, end };
}

async function callShiftPdfHtmlToPdf({ html, fileName }) {
  if (!SHIFTPDF_API_KEY) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Missing ShiftPDF API key (shiftpdf.key)",
    );
  }

  try {
    const allowInsecureTls = SHIFTPDF_ALLOW_SELF_SIGNED;
    const httpsAgent = allowInsecureTls
      ? new https.Agent({ rejectUnauthorized: false })
      : undefined;

    console.log("ShiftPDF request init", {
      allowInsecureTls,
      isEmulator: IS_EMULATOR,
      nodeEnv: process.env.NODE_ENV || "",
      url: SHIFTPDF_HTML_TO_PDF_URL,
    });
    const res = await axios.post(
      SHIFTPDF_HTML_TO_PDF_URL,
      {
        html,
        format: "A4",
        landscape: false,
        printBackground: true,
      },
      {
        responseType: "arraybuffer",
        // Avoid picking up local machine proxy env vars when developing.
        proxy: false,
        ...(httpsAgent ? { httpsAgent } : {}),
        headers: {
          Authorization: `Bearer ${SHIFTPDF_API_KEY}`,
          "X-Api-Key": SHIFTPDF_API_KEY,
          "x-api-key": SHIFTPDF_API_KEY,
          Accept: "application/pdf, application/json",
          "Content-Type": "application/json",
        },
        timeout: 60_000,
        maxContentLength: 20 * 1024 * 1024,
        maxBodyLength: 20 * 1024 * 1024,
      },
    );

    const contentType = String(res.headers?.["content-type"] || "").toLowerCase();
    const buf = Buffer.from(res.data);
    const looksLikePdf = buf.slice(0, 4).toString("utf8") === "%PDF";
    if (contentType.includes("application/pdf") || looksLikePdf) {
      return {
        pdfBase64: buf.toString("base64"),
        fileName,
      };
    }

    // Fallback: ShiftPDF might return JSON with a URL.
    if (contentType.includes("application/json")) {
      const json = JSON.parse(buf.toString("utf8"));
      const url = json?.url || json?.file || json?.downloadUrl;
      if (!url) {
        throw new Error(`ShiftPDF JSON response missing url: ${buf.toString("utf8")}`);
      }
      const pdfRes = await axios.get(url, {
        responseType: "arraybuffer",
        proxy: false,
        ...(httpsAgent ? { httpsAgent } : {}),
        timeout: 60_000,
      });
      const pdfBuf = Buffer.from(pdfRes.data);
      if (pdfBuf.slice(0, 4).toString("utf8") !== "%PDF") {
        throw new Error("ShiftPDF download did not return a PDF");
      }
      return { pdfBase64: pdfBuf.toString("base64"), fileName };
    }

    throw new Error(`ShiftPDF unexpected response: ${contentType}`);
  } catch (err) {
    const status = err?.response?.status;
    const contentType = String(err?.response?.headers?.["content-type"] || "").toLowerCase();
    const errCode = err?.code ? String(err.code) : "";
    const errMessage = err?.message ? String(err.message) : "";
    let bodyPreview = "";
    try {
      const raw = err?.response?.data;
      if (raw) {
        const buf = Buffer.isBuffer(raw) ? raw : Buffer.from(raw);
        bodyPreview = buf.toString("utf8").slice(0, 700);
      }
    } catch (_) {
      bodyPreview = "";
    }
    console.error("ShiftPDF html->pdf failed", {
      status,
      contentType,
      errCode,
      errMessage,
      url: SHIFTPDF_HTML_TO_PDF_URL,
      bodyPreview,
    });
    const details = [
      errCode ? `code=${errCode}` : null,
      errMessage ? `message=${errMessage}` : null,
      SHIFTPDF_HTML_TO_PDF_URL ? `url=${SHIFTPDF_HTML_TO_PDF_URL}` : null,
      status ? `status=${status}` : null,
      contentType ? `contentType=${contentType}` : null,
      bodyPreview ? `body=${bodyPreview}` : null,
    ]
      .filter(Boolean)
      .join(" | ");
    throw new functions.https.HttpsError(
      "internal",
      details ? `Failed to generate PDF (${details})` : "Failed to generate PDF",
    );
  }
}

async function callPdfRestHtmlToPdf({ html, fileName }) {
  if (!PDFREST_API_KEY) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Missing pdfRest API key (pdfrest.key)",
    );
  }

  // pdfRest /pdf supports HTML as uploaded .html file.
  const form = new FormData();
  const htmlBlob = new Blob([html], { type: "text/html" });
  form.append("file", htmlBlob, "report.html");
  form.append("output", String(fileName || "admin-users-report"));

  let json;
  try {
    const res = await fetch(PDFREST_PDF_URL, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Api-Key": PDFREST_API_KEY,
      },
      body: form,
    });

    const text = await res.text();
    try {
      json = JSON.parse(text);
    } catch (_) {
      throw new Error(`pdfRest non-JSON response (status=${res.status}): ${text.slice(0, 700)}`);
    }

    if (!res.ok) {
      throw new Error(`pdfRest /pdf failed (status=${res.status}): ${JSON.stringify(json).slice(0, 700)}`);
    }
  } catch (err) {
    console.error("pdfRest /pdf failed", err?.message || err);
    throw new functions.https.HttpsError("internal", `Failed to generate PDF (${err?.message || err})`);
  }

  const outputUrl = json?.outputUrl;
  if (!outputUrl) {
    throw new functions.https.HttpsError(
      "internal",
      `pdfRest response missing outputUrl: ${JSON.stringify(json).slice(0, 700)}`,
    );
  }

  try {
    const pdfRes = await fetch(String(outputUrl), {
      headers: { Accept: "application/pdf" },
    });
    const pdfBuf = Buffer.from(await pdfRes.arrayBuffer());
    if (pdfBuf.slice(0, 4).toString("utf8") !== "%PDF") {
      const preview = pdfBuf.toString("utf8").slice(0, 300);
      throw new Error(`pdfRest outputUrl did not return a PDF (status=${pdfRes.status}) body=${preview}`);
    }
    return { pdfBase64: pdfBuf.toString("base64"), fileName };
  } catch (err) {
    console.error("pdfRest download failed", err?.message || err);
    throw new functions.https.HttpsError("internal", `Failed to download PDF (${err?.message || err})`);
  }
}

exports.generateAdminUsersReport = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    await assertAdmin(context);

    const { year, month } = data || {};
    const { start, end } = monthRangeUtc(year, month);
    const startTs = admin.firestore.Timestamp.fromDate(start);
    const endTs = admin.firestore.Timestamp.fromDate(end);

    const [clientsSnap, caregiversSnap] = await Promise.all([
      db
        .collection("users")
        .where("created_at", ">=", startTs)
        .where("created_at", "<", endTs)
        .limit(200)
        .get(),
      db
        .collection("caregivers")
        .where("created_at", ">=", startTs)
        .where("created_at", "<", endTs)
        .limit(200)
        .get(),
    ]);

    const clients = clientsSnap.docs.map((d) => ({ id: d.id, ...(d.data() || {}) }));
    const caregivers = caregiversSnap.docs.map((d) => ({
      id: d.id,
      ...(d.data() || {}),
    }));

    const safeMonth = `${String(month).padStart(2, "0")}/${year}`;
    const fileName = `users-report-${year}-${String(month).padStart(2, "0")}.pdf`;

    function pickText(val) {
      return String(val || "").trim();
    }

    function pickList(val) {
      if (Array.isArray(val)) return val.map((v) => String(v || "").trim()).filter(Boolean);
      const s = String(val || "").trim();
      return s ? [s] : [];
    }

    const clientRows = clients
      .map((u) => {
        const userId = pickText(u.userId) || u.id;
        const name = pickText(u.name) || userId;
        const phone = pickText(u.phone);
        const addr = pickText(u.defaultAddress);
        const prefs = pickList(u.servicePreferences).join(", ");
        return `<tr>
          <td>${escapeHtml(userId)}</td>
          <td>${escapeHtml(name)}</td>
          <td>${escapeHtml(phone)}</td>
          <td>${escapeHtml(addr)}</td>
          <td>${escapeHtml(prefs)}</td>
        </tr>`;
      })
      .join("");

    const caregiverRows = caregivers
      .map((c) => {
        const caregiverId = pickText(c.caregiverId) || c.id;
        const name = pickText(c.name) || caregiverId;
        const phone = pickText(c.phone);
        const addr = pickText(c.defaultAddress);
        const prefs = pickList(c.servicePreferences || c.services).join(", ");
        const availability = c.availability === true ? "true" : "false";
        return `<tr>
          <td>${escapeHtml(caregiverId)}</td>
          <td>${escapeHtml(name)}</td>
          <td>${escapeHtml(phone)}</td>
          <td>${escapeHtml(addr)}</td>
          <td>${escapeHtml(prefs)}</td>
          <td>${escapeHtml(availability)}</td>
        </tr>`;
      })
      .join("");

    const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    body { font-family: Arial, sans-serif; padding: 24px; color: #111; }
    h1 { font-size: 18px; margin: 0 0 8px; }
    .muted { color: #666; font-size: 12px; }
    .stats { margin: 14px 0 18px; display:flex; gap:16px; }
    .stat { border: 1px solid #ddd; border-radius: 10px; padding: 10px 12px; min-width: 140px; }
    .stat .label { font-size: 11px; color:#666; }
    .stat .value { font-size: 18px; font-weight: 700; margin-top: 2px; }
    h2 { font-size: 14px; margin: 18px 0 8px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #e2e2e2; padding: 8px; font-size: 11px; vertical-align: top; }
    th { background: #f6f6f6; text-align: left; }
    .pagebreak { page-break-before: always; }
  </style>
</head>
<body>
  <h1>Admin Users Report</h1>
  <div class="muted">Month: ${escapeHtml(safeMonth)} • Generated at: ${escapeHtml(
      new Date().toISOString(),
    )}</div>
  <div class="stats">
    <div class="stat"><div class="label">Total users</div><div class="value">${
      clients.length + caregivers.length
    }</div></div>
    <div class="stat"><div class="label">Clients</div><div class="value">${clients.length}</div></div>
    <div class="stat"><div class="label">Caregivers</div><div class="value">${caregivers.length}</div></div>
  </div>

  <h2>Clients</h2>
  <table>
    <thead><tr><th>User ID</th><th>Name</th><th>Phone</th><th>Default address</th><th>Service preferences</th></tr></thead>
    <tbody>${clientRows || ""}</tbody>
  </table>

  <div class="pagebreak"></div>
  <h2>Caregivers</h2>
  <table>
    <thead><tr><th>Caregiver ID</th><th>Name</th><th>Phone</th><th>Default address</th><th>Service preferences</th><th>Availability</th></tr></thead>
    <tbody>${caregiverRows || ""}</tbody>
  </table>
</body>
</html>`;

    if (PDFREST_API_KEY) {
      return await callPdfRestHtmlToPdf({ html, fileName });
    }

    return await callShiftPdfHtmlToPdf({ html, fileName });
  });

exports.generateAdminCaregiverVerificationsReport = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    await assertAdmin(context);

    const { year, month } = data || {};
    const { start, end } = monthRangeUtc(year, month);
    const startTs = admin.firestore.Timestamp.fromDate(start);
    const endTs = admin.firestore.Timestamp.fromDate(end);

    const appsSnap = await db
      .collection("waitinglist")
      .where("createdAt", ">=", startTs)
      .where("createdAt", "<", endTs)
      .limit(300)
      .get();

    const applications = appsSnap.docs.map((d) => ({ id: d.id, ...(d.data() || {}) }));

    const verifiedCount = applications.filter((a) => a.verified === true).length;
    const pendingCount = applications.length - verifiedCount;

    const safeMonth = `${String(month).padStart(2, "0")}/${year}`;
    const fileName = `caregiver-verifications-report-${year}-${String(month).padStart(2, "0")}.pdf`;

    function pickText(val) {
      return String(val || "").trim();
    }

    function fmtTs(ts) {
      try {
        if (!ts) return "";
        if (typeof ts.toDate === "function") return ts.toDate().toISOString();
        return "";
      } catch {
        return "";
      }
    }

    const rows = applications
      .map((a) => {
        const status = a.verified === true ? "VERIFIED" : "UNVERIFIED";
        const name = pickText(a.name);
        const email = pickText(a.email);
        const phone = pickText(a.phone);
        const address = pickText(a.defaultAddress || a.address);
        const createdAt = fmtTs(a.createdAt);
        const verifiedAt = fmtTs(a.verifiedAt);

        return `<tr>
          <td>${escapeHtml(String(a.id || ""))}</td>
          <td>${escapeHtml(status)}</td>
          <td>${escapeHtml(name)}</td>
          <td>${escapeHtml(email)}</td>
          <td>${escapeHtml(phone)}</td>
          <td>${escapeHtml(address)}</td>
          <td>${escapeHtml(createdAt)}</td>
          <td>${escapeHtml(verifiedAt)}</td>
        </tr>`;
      })
      .join("");

    const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    body { font-family: Arial, sans-serif; padding: 24px; color: #111; }
    h1 { font-size: 18px; margin: 0 0 8px; }
    .muted { color: #666; font-size: 12px; }
    .stats { margin: 14px 0 18px; display:flex; gap:16px; flex-wrap: wrap; }
    .stat { border: 1px solid #ddd; border-radius: 10px; padding: 10px 12px; min-width: 160px; }
    .stat .label { font-size: 11px; color:#666; }
    .stat .value { font-size: 18px; font-weight: 700; margin-top: 2px; }
    h2 { font-size: 14px; margin: 18px 0 8px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #e2e2e2; padding: 8px; font-size: 11px; vertical-align: top; }
    th { background: #f6f6f6; text-align: left; }
  </style>
</head>
<body>
  <h1>Admin Caregiver Verifications Report</h1>
  <div class="muted">Month: ${escapeHtml(safeMonth)} Â· Generated at: ${escapeHtml(new Date().toISOString())}</div>
  <div class="stats">
    <div class="stat"><div class="label">Total applications</div><div class="value">${applications.length}</div></div>
    <div class="stat"><div class="label">Pending</div><div class="value">${pendingCount}</div></div>
    <div class="stat"><div class="label">Verified</div><div class="value">${verifiedCount}</div></div>
  </div>

  <h2>Applications</h2>
  <table>
    <thead><tr><th>User ID</th><th>Status</th><th>Name</th><th>Email</th><th>Phone</th><th>Address</th><th>Applied at</th><th>Verified at</th></tr></thead>
    <tbody>${rows || ""}</tbody>
  </table>
</body>
</html>`;

    if (PDFREST_API_KEY) {
      return await callPdfRestHtmlToPdf({ html, fileName });
    }

    return await callShiftPdfHtmlToPdf({ html, fileName });
  });

exports.sendSosSmsToEmergencyContacts = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = String(context.auth.uid).trim();
    const sosId = String((data && data.sosId) || "").trim();
    if (!sosId) {
      throw new functions.https.HttpsError("invalid-argument", "Missing sosId.");
    }

    const sosRef = db.collection("sos").doc(sosId);
    const sosSnap = await sosRef.get();
    if (!sosSnap.exists) {
      throw new functions.https.HttpsError("not-found", "SOS request not found.");
    }
    const sos = sosSnap.data() || {};
    const ownerId = String(sos.userId || "").trim();
    if (!ownerId || ownerId !== uid) {
      throw new functions.https.HttpsError("permission-denied", "Not allowed.");
    }

    // Prevent duplicate sends for the same SOS.
    if (sos.smsNotifiedAt) {
      return { ok: true, skipped: true, sent: 0, failed: 0 };
    }

    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const contactsRaw = userData.emergencyContacts;
    const contacts = Array.isArray(contactsRaw) ? contactsRaw : [];
    if (!contacts.length) {
      await sosRef.set(
        {
          smsNotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          smsNotifiedCount: 0,
        },
        { merge: true },
      );
      return { ok: true, skipped: true, reason: "no_contacts", sent: 0, failed: 0 };
    }

    const ownerName = String(sos.userName || userData.name || "Owner").trim();
    const personName = String(sos.selectedPersonName || sos.personName || "selected person").trim();
    const location = String(sos.personAddress || sos.address || sos.addressLabel || "").trim();

    const body = location
      ? `ElderAssist SOS: ${ownerName} activated SOS for ${personName}. Location: ${location}.`
      : `ElderAssist SOS: ${ownerName} activated SOS for ${personName}.`;

    let sent = 0;
    let failed = 0;
    const failures = [];

    for (const c of contacts) {
      const to = normalizeE164(c && c.phone);
      if (!to) {
        failed += 1;
        failures.push({ id: c && c.id, reason: "invalid_phone" });
        continue;
      }
      try {
        await sendTwilioSms({ to, body });
        sent += 1;
      } catch (err) {
        failed += 1;
        failures.push({ to, reason: String(err && err.message ? err.message : err).slice(0, 160) });
      }
    }

    await sosRef.set(
      {
        smsNotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        smsNotifiedCount: sent,
        smsFailedCount: failed,
      },
      { merge: true },
    );

    return { ok: true, sent, failed, failures: failures.slice(0, 5) };
  });

exports.generateAdminBookingsReport = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    await assertAdmin(context);

    const { year, month } = data || {};
    const { start, end } = monthRangeUtc(year, month);
    const startTs = admin.firestore.Timestamp.fromDate(start);
    const endTs = admin.firestore.Timestamp.fromDate(end);

    const bookingsSnap = await db
      .collection("bookings")
      .where("createdAt", ">=", startTs)
      .where("createdAt", "<", endTs)
      .limit(200)
      .get();

    const bookings = bookingsSnap.docs.map((d) => ({ id: d.id, ...(d.data() || {}) }));

    const userIds = Array.from(
      new Set(
        bookings
          .map((b) => String(b.userId || "").trim())
          .filter((id) => id.length > 0),
      ),
    ).slice(0, 200);

    const userNameById = {};
    if (userIds.length) {
      const refs = userIds.map((id) => db.collection("users").doc(id));
      const snaps = await db.getAll(...refs);
      for (const s of snaps) {
        if (!s.exists) continue;
        const data = s.data() || {};
        const name = String(data.name || "").trim();
        if (name) userNameById[s.id] = name;
      }
    }

    const safeMonth = `${String(month).padStart(2, "0")}/${year}`;
    const fileName = `bookings-report-${year}-${String(month).padStart(2, "0")}.pdf`;

    function pickText(val) {
      return String(val || "").trim();
    }

    function fmtTs(ts) {
      try {
        if (!ts) return "";
        if (typeof ts.toDate === "function") return ts.toDate().toISOString();
        return "";
      } catch {
        return "";
      }
    }

    const bookingRows = bookings
      .map((b) => {
        const service = pickText(b.service);
        const scheduled = pickText(b.scheduledDate || b.date);
        const status = pickText(b.status).toUpperCase() || "UNKNOWN";
        const userId = pickText(b.userId);
        const client =
          pickText(userNameById[userId]) ||
          pickText(b.userName) ||
          pickText(b.clientName) ||
          pickText(b.bookedUserName) ||
          pickText(b.userDisplayName) ||
          pickText(b.user) ||
          (userId || "");
        const caregiver = pickText(b.caregiverName) || pickText(b.caregiver) || "";
        const createdAt = fmtTs(b.createdAt);
        return `<tr>
          <td>${escapeHtml(service || "Booking")}</td>
          <td>${escapeHtml(status)}</td>
          <td>${escapeHtml(scheduled)}</td>
          <td>${escapeHtml(client)}</td>
          <td>${escapeHtml(caregiver)}</td>
          <td>${escapeHtml(createdAt)}</td>
        </tr>`;
      })
      .join("");

    const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    body { font-family: Arial, sans-serif; padding: 24px; color: #111; }
    h1 { font-size: 18px; margin: 0 0 8px; }
    .muted { color: #666; font-size: 12px; }
    .stats { margin: 14px 0 18px; display:flex; gap:16px; flex-wrap: wrap; }
    .stat { border: 1px solid #ddd; border-radius: 10px; padding: 10px 12px; min-width: 140px; }
    .stat .label { font-size: 11px; color:#666; }
    .stat .value { font-size: 18px; font-weight: 700; margin-top: 2px; }
    h2 { font-size: 14px; margin: 18px 0 8px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #e2e2e2; padding: 8px; font-size: 11px; vertical-align: top; }
    th { background: #f6f6f6; text-align: left; }
    .pagebreak { page-break-before: always; }
  </style>
</head>
<body>
  <h1>Admin Bookings Report</h1>
  <div class="muted">Month: ${escapeHtml(safeMonth)} · Generated at: ${escapeHtml(
      new Date().toISOString(),
    )}</div>
  <div class="stats">
    <div class="stat"><div class="label">Total bookings</div><div class="value">${bookings.length}</div></div>
    <div class="stat"><div class="label">Bookings</div><div class="value">${bookings.length}</div></div>
  </div>

  <h2>Bookings</h2>
  <table>
    <thead><tr><th>Service</th><th>Status</th><th>Scheduled</th><th>Client</th><th>Caregiver</th><th>Created at</th></tr></thead>
    <tbody>${bookingRows || ""}</tbody>
  </table>
</body>
</html>`;

    if (PDFREST_API_KEY) {
      return await callPdfRestHtmlToPdf({ html, fileName });
    }

    return await callShiftPdfHtmlToPdf({ html, fileName });
  });

exports.generateAdminDocumentsReport = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    await assertAdmin(context);

    const { year, month } = data || {};
    const { start, end } = monthRangeUtc(year, month);
    const startTs = admin.firestore.Timestamp.fromDate(start);
    const endTs = admin.firestore.Timestamp.fromDate(end);

    const docsSnap = await db
      .collection("documents")
      .where("updatedAt", ">=", startTs)
      .where("updatedAt", "<", endTs)
      .limit(300)
      .get();

    const documents = docsSnap.docs.map((d) => ({ id: d.id, ...(d.data() || {}) }));

    const verifiedCount = documents.filter((d) => d.status === true).length;
    const pendingCount = documents.length - verifiedCount;

    const safeMonth = `${String(month).padStart(2, "0")}/${year}`;
    const fileName = `documents-report-${year}-${String(month).padStart(2, "0")}.pdf`;

    function pickText(val) {
      return String(val || "").trim();
    }

    function fmtTs(ts) {
      try {
        if (!ts) return "";
        if (typeof ts.toDate === "function") return ts.toDate().toISOString();
        return "";
      } catch {
        return "";
      }
    }

    const rows = documents
      .map((d) => {
        const status = d.status === true ? "VERIFIED" : "UNVERIFIED";
        const name = pickText(d.name) || "Document";
        const file = pickText(d.fileName) || "PDF";
        const caregiverId = pickText(d.caregiverId);
        const updatedAt = fmtTs(d.updatedAt);
        const verifiedAt = fmtTs(d.verifiedAt);
        return `<tr>
          <td>${escapeHtml(String(d.id || ""))}</td>
          <td>${escapeHtml(status)}</td>
          <td>${escapeHtml(name)}</td>
          <td>${escapeHtml(file)}</td>
          <td>${escapeHtml(caregiverId)}</td>
          <td>${escapeHtml(updatedAt)}</td>
          <td>${escapeHtml(verifiedAt)}</td>
        </tr>`;
      })
      .join("");

    const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    body { font-family: Arial, sans-serif; padding: 24px; color: #111; }
    h1 { font-size: 18px; margin: 0 0 8px; }
    .muted { color: #666; font-size: 12px; }
    .stats { margin: 14px 0 18px; display:flex; gap:16px; flex-wrap: wrap; }
    .stat { border: 1px solid #ddd; border-radius: 10px; padding: 10px 12px; min-width: 140px; }
    .stat .label { font-size: 11px; color:#666; }
    .stat .value { font-size: 18px; font-weight: 700; margin-top: 2px; }
    h2 { font-size: 14px; margin: 18px 0 8px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #e2e2e2; padding: 8px; font-size: 11px; vertical-align: top; }
    th { background: #f6f6f6; text-align: left; }
  </style>
</head>
<body>
  <h1>Admin Documents Report</h1>
  <div class="muted">Month: ${escapeHtml(safeMonth)} · Generated at: ${escapeHtml(
      new Date().toISOString(),
    )}</div>
  <div class="stats">
    <div class="stat"><div class="label">Total documents</div><div class="value">${documents.length}</div></div>
    <div class="stat"><div class="label">Pending</div><div class="value">${pendingCount}</div></div>
    <div class="stat"><div class="label">Verified</div><div class="value">${verifiedCount}</div></div>
  </div>

  <h2>Documents</h2>
  <table>
    <thead><tr><th>Document ID</th><th>Status</th><th>Name</th><th>File name</th><th>Caregiver ID</th><th>Updated at</th><th>Verified at</th></tr></thead>
    <tbody>${rows || ""}</tbody>
  </table>
</body>
</html>`;

    if (PDFREST_API_KEY) {
      return await callPdfRestHtmlToPdf({ html, fileName });
    }

    return await callShiftPdfHtmlToPdf({ html, fileName });
  });

// =====================================================
// HELPER — LINK BOOKED USER BY PAIR CODE (ROLE 2)
// =====================================================
exports.generateAdminSosReport = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    await assertAdmin(context);

    const { year, month } = data || {};
    const { start, end } = monthRangeUtc(year, month);
    const startTs = admin.firestore.Timestamp.fromDate(start);
    const endTs = admin.firestore.Timestamp.fromDate(end);

    const sosSnap = await db
      .collection("sos")
      .where("createdAt", ">=", startTs)
      .where("createdAt", "<", endTs)
      .limit(200)
      .get();

    const sosList = sosSnap.docs.map((d) => ({ id: d.id, ...(d.data() || {}) }));

    const userIds = Array.from(
      new Set(
        sosList
          .map((s) => String(s.userId || "").trim())
          .filter((id) => id.length > 0),
      ),
    ).slice(0, 200);

    const userNameById = {};
    if (userIds.length) {
      const refs = userIds.map((id) => db.collection("users").doc(id));
      const snaps = await db.getAll(...refs);
      for (const s of snaps) {
        if (!s.exists) continue;
        const data = s.data() || {};
        const name = String(data.name || "").trim();
        if (name) userNameById[s.id] = name;
      }
    }

    const safeMonth = `${String(month).padStart(2, "0")}/${year}`;
    const fileName = `sos-report-${year}-${String(month).padStart(2, "0")}.pdf`;

    function pickText(val) {
      return String(val || "").trim();
    }

    function fmtTs(ts) {
      try {
        if (!ts) return "";
        if (typeof ts.toDate === "function") return ts.toDate().toISOString();
        return "";
      } catch {
        return "";
      }
    }

    const sosRows = sosList
      .map((s) => {
        const status = pickText(s.status).toUpperCase() || "UNKNOWN";
        const userId = pickText(s.userId);
        const ownerName = pickText(userNameById[userId]) || pickText(s.userName) || userId;
        const selectedPerson = pickText(s.selectedPersonName) || pickText(s.personName) || ownerName;
        const address = pickText(s.address) || pickText(s.userAddress) || pickText(s.personAddress);
        const caregiver = pickText(s.caregiverName) || pickText(s.caregiverId);
        const reason = pickText(s.reason);
        const createdAt = fmtTs(s.createdAt);
        return `<tr>
          <td>${escapeHtml(String(s.id || ""))}</td>
          <td>${escapeHtml(status)}</td>
          <td>${escapeHtml(selectedPerson)}</td>
          <td>${escapeHtml(ownerName)}</td>
          <td>${escapeHtml(address)}</td>
          <td>${escapeHtml(caregiver)}</td>
          <td>${escapeHtml(reason)}</td>
          <td>${escapeHtml(createdAt)}</td>
        </tr>`;
      })
      .join("");

    const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    body { font-family: Arial, sans-serif; padding: 24px; color: #111; }
    h1 { font-size: 18px; margin: 0 0 8px; }
    .muted { color: #666; font-size: 12px; }
    .stats { margin: 14px 0 18px; display:flex; gap:16px; flex-wrap: wrap; }
    .stat { border: 1px solid #ddd; border-radius: 10px; padding: 10px 12px; min-width: 140px; }
    .stat .label { font-size: 11px; color:#666; }
    .stat .value { font-size: 18px; font-weight: 700; margin-top: 2px; }
    h2 { font-size: 14px; margin: 18px 0 8px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #e2e2e2; padding: 8px; font-size: 11px; vertical-align: top; }
    th { background: #f6f6f6; text-align: left; }
  </style>
</head>
<body>
  <h1>Admin SOS Report</h1>
  <div class="muted">Month: ${escapeHtml(safeMonth)} · Generated at: ${escapeHtml(
      new Date().toISOString(),
    )}</div>
  <div class="stats">
    <div class="stat"><div class="label">Total SOS</div><div class="value">${sosList.length}</div></div>
  </div>

  <h2>SOS</h2>
  <table>
    <thead><tr><th>SOS ID</th><th>Status</th><th>Selected person</th><th>Owner</th><th>Address</th><th>Caregiver</th><th>Reason</th><th>Created at</th></tr></thead>
    <tbody>${sosRows || ""}</tbody>
  </table>
</body>
</html>`;

    if (PDFREST_API_KEY) {
      return await callPdfRestHtmlToPdf({ html, fileName });
    }

    return await callShiftPdfHtmlToPdf({ html, fileName });
  });

async function linkBookedUserByPairCode(pairCode, updateData) {
  const usersSnap = await db.collection("users").get();

  for (const userDoc of usersSnap.docs) {
    const data = userDoc.data() || {};
    const addresses = Array.isArray(data.address) ? [...data.address] : [];

    const index = addresses.findIndex((a) => a.pairCode === pairCode);
    if (index >= 0) {
      addresses[index] = {
        ...addresses[index],
        ...updateData,
        role: "role2",
        telegramLinkedAt: new Date().toISOString(),
      };

      await userDoc.ref.update({ address: addresses });
      return { role: "role2", userId: userDoc.id };
    }
  }

  throw new Error("Pair code not found or expired");
}

// =====================================================
// HELPER — LINK EMERGENCY CONTACT BY PAIR CODE (ROLE 4)
// =====================================================
async function linkEmergencyContactByPairCode(pairCode, updateData) {
  const usersSnap = await db.collection("users").get();

  for (const userDoc of usersSnap.docs) {
    const data = userDoc.data() || {};
    const contacts = Array.isArray(data.emergencyContacts)
      ? [...data.emergencyContacts]
      : [];

    const index = contacts.findIndex((c) => c.pairCode === pairCode);
    if (index >= 0) {
      contacts[index] = {
        ...contacts[index],
        ...updateData,
        role: "role4",
        telegramLinkedAt: new Date().toISOString(),
      };

      await userDoc.ref.update({ emergencyContacts: contacts });
      return { role: "role4", userId: userDoc.id };
    }
  }

  throw new Error("Pair code not found or expired");
}

// =====================================================
// SOS CREATE — APP ONLY (ROLE 1 & ROLE 3)
// =====================================================
exports.handleSOSAlert = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }

    const { lat, lng, reason, notifyContactIds, bookingId } = data || {};
    if (typeof lat !== "number" || typeof lng !== "number") {
      throw new functions.https.HttpsError("invalid-argument");
    }

    const uid = context.auth.uid;

    let triggeredRole = null;
    let triggeredName = "User";
    let ownerUserId = null;

    // PRIMARY USER
    const userDoc = await db.collection("users").doc(uid).get();
    if (userDoc.exists) {
      const user = userDoc.data();
      if (user.role === "user") {
        triggeredRole = "user";
        triggeredName = user.name || "User";
        ownerUserId = uid;
      }
    }

    // CAREGIVER
    if (!triggeredRole) {
      const caregiverDoc = await db.collection("caregivers").doc(uid).get();
      if (caregiverDoc.exists) {
        const caregiver = caregiverDoc.data();
        if (caregiver.role === "caregiver") {
          triggeredRole = "caregiver";
          triggeredName = caregiver.name || "Caregiver";
          ownerUserId = caregiver.userId; // 🔥 linked primary user
        }
      }
    }

    if (!triggeredRole || !ownerUserId) {
      throw new functions.https.HttpsError("permission-denied");
    }

    const bookingIdStr = String(bookingId || "").trim();
    if (bookingIdStr) {
      const bookingSnap = await db.collection("bookings").doc(bookingIdStr).get();
      if (!bookingSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Booking not found");
      }
      const booking = bookingSnap.data() || {};
      const bookingOwner = String(booking.userId || "").trim();
      const bookingCaregiver = String(
        booking.caregiverId || booking.assignedCaregiverId || ""
      ).trim();
      if (!bookingOwner) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Booking owner is missing"
        );
      }
      if (uid !== bookingOwner && uid !== bookingCaregiver) {
        throw new functions.https.HttpsError("permission-denied");
      }
      ownerUserId = bookingOwner;
    }

    const sosRef = db.collection("sos").doc();
    const notifyIds = Array.isArray(notifyContactIds)
      ? notifyContactIds
          .map((id) => String(id || "").trim())
          .filter((id) => id.length > 0)
      : [];

    await sosRef.set({
      sosId: sosRef.id,

      ownerUserId,

      triggeredByUserId: uid,
      triggeredByRole: triggeredRole,
      triggeredByName: triggeredName,
      triggeredVia: "app",

      userLat: lat,
      userLng: lng,
      reason: reason || "Not specified",
      ...(notifyIds.length ? { notifyContactIds: notifyIds } : {}),

      status: "created",
      assignedCaregiverId: null,

      timestamps: {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        acknowledgedAt: null,
        handlingAt: null,
        resolvedAt: null,
      },

      notifyTelegram: true,
      notifyApp: true,
    });

    return { success: true, sosId: sosRef.id };
  });


// =====================================================
// SOS CREATE — FROM TELEGRAM (BOOKED USER / ROLE 2)
// =====================================================
async function createSOSCore({ pairCode, lat, lng, reason }) {
  // =========================
  // VALIDATION
  // =========================
  if (!pairCode) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "pairCode is required"
    );
  }

  if (typeof lat !== "number" || typeof lng !== "number") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "lat and lng must be numbers"
    );
  }

  // =========================
  // FIND OWNER VIA PAIR CODE
  // =========================
  let ownerUserId = null;
  let bookedUserName = "Booked User";

  const usersSnap = await db.collection("users").get();

  for (const userDoc of usersSnap.docs) {
    const userData = userDoc.data() || {};
    const addresses = Array.isArray(userData.address)
      ? userData.address
      : [];

    const matched = addresses.find(a => a.pairCode === pairCode);
    if (matched) {
      ownerUserId = userDoc.id;
      bookedUserName = matched.name || bookedUserName;
      break;
    }
  }

  if (!ownerUserId) {
    throw new functions.https.HttpsError(
      "not-found",
      "Invalid or expired pair code"
    );
  }

  // =========================
  // CREATE SOS
  // =========================
  const sosRef = db.collection("sos").doc();

  await sosRef.set({
    sosId: sosRef.id,

    // 🔑 OWNER
    ownerUserId,

    // 🔎 TRIGGER INFO
    triggeredByUserId: null, // Telegram has no auth UID
    triggeredByRole: "role2",
    triggeredByName: bookedUserName,
    triggeredVia: "telegram",

    // 📍 LOCATION
    userLat: lat,
    userLng: lng,
    reason: reason || "Emergency triggered from Telegram",

    // 🚦 STATUS
    status: "created",
    assignedCaregiverId: null,

    // 🔔 NOTIFY
    notifyTelegram: true,
    notifyApp: true,

    // ⏱ TIMESTAMPS
    timestamps: {
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      acknowledgedAt: null,
      handlingAt: null,
      resolvedAt: null,
    },
  });

  return {
    success: true,
    sosId: sosRef.id,
  };
}

// =====================================================
// 🔔 TELEGRAM NOTIFICATION — SOS CREATED
// =====================================================
exports.sendChatOnCreate = functions.firestore
  .document("sos/{sosId}")
  .onCreate(async (snap) => {
    const sos = snap.data();
    if (!sos.notifyTelegram) return;

    const userSnap = await db
      .collection("users")
      .doc(sos.ownerUserId)
      .get();

    if (!userSnap.exists) return;

    const contacts = userSnap.data().emergencyContacts || [];
    const notifyIds = Array.isArray(sos.notifyContactIds)
      ? sos.notifyContactIds.map((id) => String(id || "").trim()).filter(Boolean)
      : null;

    const message = `🚨 NEW SOS ALERT

👤 User: ${sos.triggeredByName}
📝 Reason: ${sos.reason || "N/A"}

📍 Location:
https://maps.google.com/?q=${sos.userLat},${sos.userLng}

⏳ Status: CREATED`;

    for (const c of contacts) {
      if (!c.telegramChatId) continue;
      if (notifyIds && notifyIds.length) {
        const cid = String(c.id || "").trim();
        if (!cid || !notifyIds.includes(cid)) continue;
      }

      await axios.post(
        `https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`,
        {
          chat_id: c.telegramChatId,
          text: message,
        }
      );
    }

    // ❗ Jangan reset notifyTelegram di sini
    // sebab update status masih perlukan notification
  });


// =====================================================
// 🔔 TELEGRAM NOTIFICATION — STATUS CHANGE
// =====================================================
exports.sendChatNotification = functions.firestore
  .document("sos/{sosId}")
  .onUpdate(async (change) => {
    const after = change.after.data();
    if (!after.notifyTelegram) return;

    const userSnap = await db
      .collection("users")
      .doc(after.ownerUserId)
      .get();

    if (!userSnap.exists) return;

    const contacts = userSnap.data().emergencyContacts || [];
    const notifyIds = Array.isArray(after.notifyContactIds)
      ? after.notifyContactIds
          .map((id) => String(id || "").trim())
          .filter(Boolean)
      : null;

    const message = `📢 SOS STATUS UPDATE

    User: ${after.triggeredByName}
    Status: ${after.status.toUpperCase()}
    Reason: ${after.reason || "N/A"}

    📍 Location:
    https://maps.google.com/?q=${after.userLat},${after.userLng}`;

    for (const c of contacts) {
      if (!c.telegramChatId) continue;
      if (notifyIds && notifyIds.length) {
        const cid = String(c.id || "").trim();
        if (!cid || !notifyIds.includes(cid)) continue;
      }

      await axios.post(
        `https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`,
        {
          chat_id: c.telegramChatId,
          text: message,
        }
      );
    }

    await change.after.ref.update({ notifyTelegram: false });
  });

// =====================================================
// BOOKING STATUS: AUTO-PROMOTE DUE SCHEDULED -> ASSIGNED
// =====================================================
const BOOKING_UPCOMING_STATUSES = ["SCHEDULED", "PENDING", "READY"];
const BOOKING_ASSIGNED_STATUS = "ASSIGNED";
const BOOKING_MISSING_STATUS = "MISSING";
const MALAYSIA_TIMEZONE_OFFSET = "+08:00";

function normalizeBookingStatus(value) {
  return String(value || "")
    .trim()
    .toUpperCase()
    .replace(/[\s-]+/g, "_")
    .replace(/__+/g, "_");
}

function normalizeMalaysiaDateToIso(dateValue) {
  const trimmed = String(dateValue || "").trim();
  if (!trimmed) return null;

  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed;
  if (/^\d{4}\/\d{2}\/\d{2}$/.test(trimmed)) return trimmed.replace(/\//g, "-");

  const slash = trimmed.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (slash) {
    const dd = Number.parseInt(slash[1], 10);
    const mm = Number.parseInt(slash[2], 10);
    const yyyy = Number.parseInt(slash[3], 10);
    if (!Number.isFinite(dd) || !Number.isFinite(mm) || !Number.isFinite(yyyy)) {
      return null;
    }
    if (dd < 1 || dd > 31 || mm < 1 || mm > 12) return null;
    return `${String(yyyy).padStart(4, "0")}-${String(mm).padStart(2, "0")}-${String(dd).padStart(2, "0")}`;
  }

  const dash = trimmed.match(/^(\d{1,2})-(\d{1,2})-(\d{4})$/);
  if (dash) {
    const dd = Number.parseInt(dash[1], 10);
    const mm = Number.parseInt(dash[2], 10);
    const yyyy = Number.parseInt(dash[3], 10);
    if (!Number.isFinite(dd) || !Number.isFinite(mm) || !Number.isFinite(yyyy)) {
      return null;
    }
    if (dd < 1 || dd > 31 || mm < 1 || mm > 12) return null;
    return `${String(yyyy).padStart(4, "0")}-${String(mm).padStart(2, "0")}-${String(dd).padStart(2, "0")}`;
  }

  return null;
}

function normalizeTo24HourTime(timeValue) {
  const raw = String(timeValue || "").trim().toLowerCase();
  if (!raw) return null;

  if (/^\d{2}:\d{2}$/.test(raw)) return raw;
  if (/^\d{1,2}:\d{2}$/.test(raw)) {
    const [h, m] = raw.split(":");
    return `${String(Number.parseInt(h, 10)).padStart(2, "0")}:${m}`;
  }
  if (/^\d{1,2}:\d{2}:\d{2}$/.test(raw)) {
    const [h, m] = raw.split(":");
    return `${String(Number.parseInt(h, 10)).padStart(2, "0")}:${m}`;
  }

  const ampm = raw.match(/^(\d{1,2}):(\d{2})\s*([ap]m)$/);
  if (ampm) {
    let h = Number.parseInt(ampm[1], 10);
    const m = Number.parseInt(ampm[2], 10);
    const period = ampm[3];
    if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
    h = Math.min(Math.max(h, 0), 12);
    const mm = Math.min(Math.max(m, 0), 59);
    if (period === "am") {
      if (h === 12) h = 0;
    } else if (h !== 12) {
      h += 12;
    }
    return `${String(h).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
  }

  return null;
}

function computeScheduledAtTimestamp(bookingData) {
  const dateRaw = bookingData?.scheduledDate ?? bookingData?.date ?? "";
  const timeRaw = bookingData?.startTime ?? bookingData?.time ?? "";
  const dateIso = normalizeMalaysiaDateToIso(dateRaw);
  const time24 = normalizeTo24HourTime(timeRaw);
  if (!dateIso || !time24) return null;

  const iso = `${dateIso}T${time24}:00${MALAYSIA_TIMEZONE_OFFSET}`;
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return null;
  return admin.firestore.Timestamp.fromDate(parsed);
}

// Keeps `scheduledAt` updated so the cron can query efficiently.
exports.syncBookingScheduledAt = functions
  .region("asia-southeast1")
  .firestore.document("bookings/{bookingId}")
  .onWrite(async (change) => {
    const after = change.after.exists ? change.after.data() : null;
    if (!after) return;

    const computed = computeScheduledAtTimestamp(after);
    if (!computed) return;

    const existing = after.scheduledAt;
    const existingSeconds =
      existing && typeof existing.seconds === "number" ? existing.seconds : null;
    if (existingSeconds === computed.seconds) return;

    await change.after.ref.set(
      {
        scheduledAt: computed,
      },
      { merge: true }
    );
  });

// Keeps payment.bookingStatus in sync with bookings.status so client UI can rely
// on payments.bookingStatus without falling back to booking data.
exports.syncPaymentBookingStatus = functions
  .region("asia-southeast1")
  .firestore.document("bookings/{bookingId}")
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() || {} : {};
    const after = change.after.exists ? change.after.data() || {} : null;
    if (!after) return;

    const beforeStatus = String(before.status || "").trim();
    const afterStatus = String(after.status || "").trim();
    if (!afterStatus) return;
    if (beforeStatus === afterStatus && change.before.exists) return;

    const bookingId = String(context.params.bookingId || "").trim();
    if (!bookingId) return;

    const bookingStatus = afterStatus.toUpperCase();
    const billCode = String(after.toyyibBillCode || "").trim();

    const batch = db.batch();
    const payload = {
      bookingStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (billCode) {
      batch.set(db.collection("payments").doc(billCode), payload, { merge: true });
    }

    const paymentsSnap = await db
      .collection("payments")
      .where("bookingId", "==", bookingId)
      .limit(25)
      .get();

    for (const doc of paymentsSnap.docs) {
      batch.set(doc.ref, payload, { merge: true });
    }

    if (billCode || !paymentsSnap.empty) {
      await batch.commit();
    }
  });

// One-time helper: backfill missing payments.bookingStatus using embedded booking
// fields (date/time). Admin only.
exports.backfillPaymentsBookingStatus = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    await assertAdmin(context);
    const limit = Math.min(Math.max(Number(data?.limit) || 200, 1), 500);

    const snap = await db
      .collection("payments")
      .orderBy("updatedAt", "desc")
      .limit(limit)
      .get();

    if (snap.empty) return { updated: 0 };

    const batch = db.batch();
    let updated = 0;
    for (const doc of snap.docs) {
      const p = doc.data() || {};
      const existingBookingStatus = String(p.bookingStatus || "").trim();
      const existingUserId = String(p.userId || "").trim();

      const embedded = p.booking || {};
      let nextBookingStatus = existingBookingStatus;
      if (!nextBookingStatus) {
        const computed = derivePaidBookingStatus(embedded);
        nextBookingStatus = String(computed || "").toUpperCase() || "SCHEDULED";
      }

      let nextUserId = existingUserId;
      if (!nextUserId) {
        const bookingId = String(p.bookingId || "").trim();
        if (bookingId) {
          const bookingSnap = await db.collection("bookings").doc(bookingId).get();
          if (bookingSnap.exists) {
            const booking = bookingSnap.data() || {};
            nextUserId = String(booking.userId || "").trim();
            if (!existingBookingStatus) {
              const statusFromBooking = String(booking.status || "").trim();
              if (statusFromBooking) nextBookingStatus = statusFromBooking.toUpperCase();
            }
          }
        }
      }

      if (!nextBookingStatus && !nextUserId) continue;

      const payload = {
        ...(nextBookingStatus ? { bookingStatus: nextBookingStatus } : null),
        ...(nextUserId ? { userId: nextUserId } : null),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      batch.set(doc.ref, payload, { merge: true });
      updated += 1;
    }

    if (updated > 0) {
      await batch.commit();
    }
    return { updated };
  });

exports.promoteDueBookings = functions
  .region("asia-southeast1")
  .pubsub.schedule("every 1 minutes")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    // Prefer the indexed path (status + scheduledAt).
    // If this needs an index, Firebase will log a URL to create it.
    const query = db
      .collection("bookings")
      .where("status", "in", BOOKING_UPCOMING_STATUSES)
      .where("scheduledAt", "<=", now)
      .limit(200);

    const snapshot = await query.get();
    if (snapshot.empty) return null;

    const batch = db.batch();
    let updated = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const normalized = normalizeBookingStatus(data.status);
      if (!BOOKING_UPCOMING_STATUSES.includes(normalized)) continue;

      const scheduledAt = data.scheduledAt || computeScheduledAtTimestamp(data);
      if (!scheduledAt || scheduledAt.toMillis() > now.toMillis()) continue;

      batch.update(doc.ref, {
        status: BOOKING_ASSIGNED_STATUS,
        assignedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(data.scheduledAt ? null : { scheduledAt }),
      });
      updated += 1;
    }

    if (updated > 0) {
      await batch.commit();
    }

    return { updated };
  });

// =====================================================
// BOOKING STATUS: AUTO-MARK STALE ASSIGNED -> MISSING
// =====================================================
// If a booking stays ASSIGNED for >24h without progressing to ONGOING/COMPLETED,
// mark it as MISSING so it doesn't stay active forever.
exports.markStaleAssignedBookingsMissing = functions
  .region("asia-southeast1")
  .pubsub.schedule("every 1 minutes")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const cutoff = admin.firestore.Timestamp.fromMillis(
      now.toMillis() - 5 * 60 * 60 * 1000,
    );

    // Avoid composite index requirements by querying scheduledAt only, then
    // filtering status in-memory.
    const snapshot = await db
      .collection("bookings")
      .where("scheduledAt", "<=", cutoff)
      .limit(200)
      .get();
    if (snapshot.empty) return null;

    const batch = db.batch();
    let updated = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const normalized = normalizeBookingStatus(data.status);
      if (normalized !== BOOKING_ASSIGNED_STATUS) continue;

      const reference =
        data.assignedAt ||
        data.scheduledAt ||
        computeScheduledAtTimestamp(data) ||
        null;
      if (!reference || reference.toMillis() > cutoff.toMillis()) continue;

      batch.update(doc.ref, {
        status: BOOKING_MISSING_STATUS,
        missingAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        missingReason: "AUTO_EXPIRED",
      });
      updated += 1;
    }

    if (updated > 0) {
      await batch.commit();
    }

    return { updated };
  });

  // =====================================================
// GENERATE TELEGRAM PAIR CODE (ROLE 2 & ROLE 4)
// =====================================================
exports.generateTelegramPairCode = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be logged in"
      );
    }

    const { role, addressId, contactId } = data || {};
    const uid = context.auth.uid;
    console.log(
      "generateTelegramPairCode called",
      { role, addressId, contactId, uid }
    );

    if (!role || !["role2", "role4"].includes(role)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Invalid role"
      );
    }

    // Generate 6-digit pair code
    const pairCode = Math.floor(100000 + Math.random() * 900000).toString();

    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();

    if (!userSnap.exists) {
      throw new functions.https.HttpsError("not-found", "User not found");
    }

    const user = userSnap.data();
    const userAddresses = Array.isArray(user.address)
      ? user.address.map((address) => address.id)
      : [];
    console.log("Existing address IDs for user:", userAddresses);

    // =====================================================
    // ROLE 2 — BOOKED USER (address[])
    // =====================================================
    if (role === "role2") {
      if (!addressId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "addressId is required for role2"
        );
      }

      const addresses = Array.isArray(user.address)
        ? [...user.address]
        : [];

      const index = addresses.findIndex((a) => a.id === addressId);
      if (index === -1) {
        throw new functions.https.HttpsError(
          "not-found",
          "Address not found"
        );
      }

      addresses[index] = {
        ...addresses[index],
        pairCode,
        pairCodeGeneratedAt: Date.now(),         
        telegramChatId: null,
        telegramLinkedAt: null,
      };

      await userRef.update({ address: addresses });

      return {
        success: true,
        role: "role2",
        pairCode,
        telegramLink: `https://t.me/Elder_AssistBot?start=${pairCode}`,
      };
    }

    // =====================================================
    // ROLE 4 — EMERGENCY CONTACT (emergencyContacts[])
    // =====================================================
    if (role === "role4") {
      if (!contactId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "contactId is required for role4"
        );
      }

      const contacts = Array.isArray(user.emergencyContacts)
        ? [...user.emergencyContacts]
        : [];

      const index = contacts.findIndex((c) => c.id === contactId);
      if (index === -1) {
        throw new functions.https.HttpsError(
          "not-found",
          "Emergency contact not found"
        );
      }

      contacts[index] = {
        ...contacts[index],
        pairCode,
        pairCodeGeneratedAt: Date.now(), 
        telegramChatId: null,
        telegramLinkedAt: null,
      };

      await userRef.update({ emergencyContacts: contacts });

      return {
        success: true,
        role: "role4",
        pairCode,
        telegramLink: `https://t.me/Elder_AssistBot?start=${pairCode}`,
      };
    }
  });

// =====================================================
// CHAT NOTIFICATION
// =====================================================
exports.sendChatNotification = functions
  .region("us-central1")
  .firestore.document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot) => {
    const message = snapshot.data();
    if (!message) return null;

    await admin.messaging().send({
      topic: message.receiverId,
      notification: {
        title: "New Message",
        body: message.text?.slice(0, 50) || "",
      },
    });

    return null;
  });

const qs = require("qs");

async function createToyyibBill({
  billName,
  billDescription,
  amount,
  name,
  email,
  phone,
}) {
  if (!TOYYIBPAY_SECRET_KEY || !TOYYIBPAY_CATEGORY_CODE) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "ToyyibPay is not configured (missing secret_key/category_code).",
    );
  }
  if (!PROJECT_ID) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Firebase project id is not configured (missing fb.project_id).",
    );
  }

  const normalizedAmount = Number(amount) || 0;
  if (!Number.isFinite(normalizedAmount) || normalizedAmount <= 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Invalid payment amount.",
    );
  }

  const payload = {
    userSecretKey: TOYYIBPAY_SECRET_KEY,
    categoryCode: TOYYIBPAY_CATEGORY_CODE,

    billName,
    billDescription,

    billPriceSetting: 1,
    billPayorInfo: 1,

    // RM + SEN
    billAmount: Math.round(normalizedAmount * 100),

    billTo: name || "ElderAssist User",
    billEmail: email || "noreply@elderassist.com",
    billPhone: phone || "0123456789",

    // ToyyibPay expects a valid http(s) URL. The app already checks payment
    // status when it resumes, so deep-link return URL is optional.
    billReturnUrl: TOYYIBPAY_RETURN_URL,

    // ToyyibPay akan panggil function ni
    billCallbackUrl: `https://asia-southeast1-${PROJECT_ID}.cloudfunctions.net/toyyibpayCallback`,
  };

  let response;
  try {
    console.log("ToyyibPay createBill config:", {
      sandbox: TOYYIBPAY_SANDBOX,
      apiBase: TOYYIBPAY_API_BASE,
      paymentBase: TOYYIBPAY_PAYMENT_BASE,
      categoryCode: TOYYIBPAY_CATEGORY_CODE,
      secretKeyTail: TOYYIBPAY_SECRET_KEY.slice(-6),
      billNameLength: String(billName || "").length,
    });
    response = await axios.post(
      `${TOYYIBPAY_API_BASE.replace(/\/+$/, "")}/createBill`,
      qs.stringify(payload),
      {
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
        },
        timeout: 15000,
      }
    );
  } catch (err) {
    const status = err?.response?.status;
    const body = err?.response?.data;
    console.error("ToyyibPay createBill request failed:", {
      status,
      body: typeof body === "string" ? body.slice(0, 500) : body,
      message: err?.message,
    });
    throw new functions.https.HttpsError(
      "internal",
      "ToyyibPay create bill request failed.",
    );
  }

  const billCode = response?.data?.[0]?.BillCode;
  const responseData = response?.data;
  const extractedBillCode =
    billCode ||
    (Array.isArray(responseData)
      ? responseData?.[0]?.billCode || responseData?.[0]?.Billcode
      : null) ||
    (responseData && typeof responseData === "object"
      ? responseData.BillCode || responseData.billCode || null
      : null);

  if (!extractedBillCode) {
    const snippet =
      typeof responseData === "string"
        ? responseData.slice(0, 300)
        : JSON.stringify(responseData).slice(0, 300);
    console.error("ToyyibPay createBill unexpected response:", {
      data: responseData,
    });
    throw new functions.https.HttpsError(
      "internal",
      `ToyyibPay did not return a BillCode. Response: ${snippet}`,
    );
  }

  return {
    billCode: extractedBillCode,
    paymentUrl: `${TOYYIBPAY_PAYMENT_BASE.replace(/\/+$/, "")}/${extractedBillCode}`,
  };
}

function parseMultipartFormFields(bodyText) {
  const result = {};
  if (!bodyText) return result;
  const lines = bodyText.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(/Content-Disposition: form-data; name="([^"]+)"/);
    if (!match) continue;
    let valueIndex = i + 1;
    while (valueIndex < lines.length && lines[valueIndex].trim() === "") {
      valueIndex++;
    }
    if (valueIndex >= lines.length) break;
    result[match[1]] = lines[valueIndex].trim();
  }
  return result;
}

exports.cancelBooking = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }
    const bookingId = (data?.bookingId ?? '').toString();
    const reason = (data?.reason ?? '').toString().trim();
    const otherDetails = (data?.details ?? '').toString().trim();

    if (bookingId.isEmpty || reason.isEmpty) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "bookingId and reason are required",
      );
    }

    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingSnap = await bookingRef.get();
    if (!bookingSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Booking not found");
    }

    const booking = bookingSnap.data() || {};
    const batch = db.batch();
    batch.update(bookingRef, {
      status: "CANCELLED",
      cancellationReason: reason,
      cancellationDetails: otherDetails,
      cancellationRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      cancellationRequestedBy: context.auth.uid,
      notifyApp: true,
    });

    const billCode = booking.toyyibBillCode;
    if (billCode) {
      const paymentRef = db.collection("payments").doc(billCode);
      batch.set(
        paymentRef,
        {
          paymentStatus: "REFUND_REQUESTED",
          bookingStatus: "CANCELLED",
          refundRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
          refundRequestedBy: context.auth.uid,
          refundReason: reason,
        },
        { merge: true },
      );
    }

    await batch.commit();
    return { success: true };
  });

exports.savePaymentDetails = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }
    const uid = context.auth.uid;
    const userRef = db.collection('users').doc(uid);
    const caregiverRef = db.collection('caregivers').doc(uid);
    const paymentDetails = {
      bankName: (data.bankName ?? '').trim(),
      accountName: (data.accountName ?? '').trim(),
      accountNumber: (data.accountNumber ?? '').trim(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
   if (
      paymentDetails.bankName.length === 0 ||
      paymentDetails.accountName.length === 0 ||
      paymentDetails.accountNumber.length === 0
    ) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Please fill in the required fields.',
      );
    }
    const targetRaw = (data?.target ?? 'auto').toString().toLowerCase();
    const target = ['caregiver', 'user', 'auto'].includes(targetRaw)
      ? targetRaw
      : 'auto';
    const caregiverSnap = await caregiverRef.get();
    const batch = db.batch();
    const shouldWriteCaregiver =
      target === 'caregiver' || (target === 'auto' && caregiverSnap.exists);
    const shouldWriteUser =
      target === 'user' || (target === 'auto' && !caregiverSnap.exists);
    if (shouldWriteCaregiver) {
      batch.set(caregiverRef, { paymentDetails }, { merge: true });
    }
    if (shouldWriteUser) {
      batch.set(userRef, { paymentDetails }, { merge: true });
    }
    await batch.commit();
    return { success: true };
  });

// =====================================================
// PAYMENT RECEIPT PDF (USER/CAREGIVER)
// =====================================================
exports.generatePaymentReceiptPdf = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }

    const uid = context.auth.uid;
    const paymentId = String(data?.paymentId || "").trim();
    if (!paymentId) {
      throw new functions.https.HttpsError("invalid-argument", "Missing paymentId");
    }

    let isAdmin = false;
    try {
      await assertAdmin(context);
      isAdmin = true;
    } catch (_) {
      isAdmin = false;
    }

    const paymentSnap = await db.collection("payments").doc(paymentId).get();
    if (!paymentSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Payment not found");
    }
    const payment = paymentSnap.data() || {};
    const bookingPayload = (payment.booking && typeof payment.booking === "object")
      ? payment.booking
      : {};

    const ownerUserId = String(payment.userId || bookingPayload.userId || "").trim();
    const caregiverId = String(payment.caregiverId || bookingPayload.caregiverId || "").trim();
    if (!isAdmin && uid !== ownerUserId && uid !== caregiverId) {
      throw new functions.https.HttpsError("permission-denied", "Not allowed");
    }

    const bookingId = String(payment.bookingId || bookingPayload.bookingId || "").trim();
    let booking = {};
    if (bookingId) {
      const bookingSnap = await db.collection("bookings").doc(bookingId).get();
      if (bookingSnap.exists) {
        booking = bookingSnap.data() || {};
      }
    }

    const merged = { ...(bookingPayload || {}), ...(booking || {}) };
    const service = String(
      merged.service ||
        (Array.isArray(merged.servicePreferences) ? merged.servicePreferences[0] : "") ||
        "",
    ).trim();
    const caregiverName = String(merged.caregiverName || "").trim();
    const personName = String(merged.personName || "").trim();
    const personAddress = String(merged.personAddress || "").trim();
    const date = String(merged.date || "").trim();
    const time = String(merged.time || "").trim();
    const startTime = String(merged.startTime || "").trim();
    const endTime = String(merged.endTime || "").trim();
    const paymentMethod = String(payment.paymentMethod || merged.paymentMethod || "ToyyibPay").trim();
    const paymentStatus = String(payment.paymentStatus || merged.paymentStatus || "").trim().toUpperCase();
    const bookingStatus = String(payment.bookingStatus || merged.status || "").trim().toUpperCase();
    const billCode = String(payment.billCode || merged.toyyibBillCode || paymentId).trim();

    const servicePrice = Number(merged.servicePrice) || 0;
    const distanceKm = Number(merged.distanceKm) || 0;
    const distanceCharge = Number(merged.distanceCharge) || 0;
    const amount = Number(payment.amount) || 0;
    const total = amount > 0 ? amount : servicePrice + distanceCharge;

    const personNotes = String(merged.personNotes || merged.notes || "").trim();
    const bookingNotes = String(merged.bookingNotes || "").trim();

    function fmtMoney(n) {
      const v = Number(n) || 0;
      return v.toFixed(2);
    }

    function scheduleLine() {
      const parts = [];
      if (date) parts.push(date);
      if (time) parts.push(time);
      if (startTime && endTime) parts.push(`${startTime} - ${endTime}`);
      return parts.join(" · ");
    }

    const safeId = String(bookingId || billCode || paymentId || "receipt")
      .replace(/[^a-zA-Z0-9_-]/g, "")
      .slice(0, 24);
    const fileName = `receipt-${safeId || "payment"}.pdf`;

    const statusUpper = String(paymentStatus || "").trim().toUpperCase();
    const statusTone =
      statusUpper === "PAID" || statusUpper === "SUCCESS"
        ? "paid"
        : statusUpper === "FAILED" || statusUpper === "CANCELLED"
          ? "failed"
          : "pending";
    const generatedAtIso = new Date().toISOString();
    const computedServiceValue = servicePrice || Math.max(0, total - distanceCharge);

    const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    :root{
      --text:#111827;
      --muted:#6B7280;
      --border:#D1D5DB;
      --border-strong:#E1E4EA;
      --bg:#F9FAFB;
      --gold:#F4B63D;
      --shadow: rgba(17,24,39,.10);
      --green:#2BB673;
      --red:#F25C54;
    }
    @page { margin: 22mm; }
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
      color: var(--text);
      background: #fff;
      font-size: 12px;
      line-height: 1.35;
    }
    .header {
      display:flex;
      align-items:flex-start;
      justify-content: space-between;
      gap: 18px;
      padding-bottom: 12px;
      border-bottom: 3px solid var(--gold);
      margin-bottom: 14px;
    }
    .brand {
      font-weight: 900;
      font-size: 16px;
      letter-spacing: -0.2px;
    }
    .title {
      margin-top: 4px;
      font-weight: 900;
      font-size: 18px;
      letter-spacing: -0.25px;
    }
    .subtitle {
      margin-top: 4px;
      color: var(--muted);
      font-size: 11px;
      font-weight: 600;
    }
    .pill {
      display:inline-block;
      padding: 6px 10px;
      border-radius: 999px;
      font-size: 10px;
      font-weight: 900;
      letter-spacing: 0.3px;
      text-transform: uppercase;
      border: 1px solid var(--border);
      background: var(--bg);
      color: var(--text);
      white-space: nowrap;
    }
    .pill.paid { border-color: rgba(43,182,115,.35); background: rgba(43,182,115,.10); color: var(--green); }
    .pill.failed { border-color: rgba(242,92,84,.35); background: rgba(242,92,84,.10); color: var(--red); }
    .pill.pending { border-color: rgba(244,182,61,.40); background: rgba(244,182,61,.14); color: #7A4C00; }
    .grid {
      display:grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }
    .card {
      border: 1px solid var(--border-strong);
      border-radius: 14px;
      padding: 12px 12px;
      box-shadow: 0 10px 22px var(--shadow);
    }
    .card h2{
      margin: 0 0 10px;
      font-size: 12px;
      font-weight: 900;
      letter-spacing: -0.15px;
    }
    .table{
      width: 100%;
      border-collapse: separate;
      border-spacing: 0;
      overflow: hidden;
      border: 1.35px solid var(--border);
      border-radius: 12px;
      box-shadow: inset 0 0 0 1px var(--border);
    }
    .table td{
      border-bottom: 1.2px solid var(--border);
      padding: 9px 10px;
      vertical-align: top;
    }
    .table tr:last-child td{ border-bottom: none; }
    .table td:first-child{
      width: 42%;
      background: var(--bg);
      color: var(--muted);
      font-weight: 900;
      font-size: 11px;
    }
    .table td:last-child{
      font-weight: 900;
      color: var(--text);
      overflow-wrap: anywhere;
      white-space: pre-wrap;
      font-size: 12px;
    }
    .icon{
      display:inline-flex;
      align-items:center;
      justify-content:center;
      width: 18px;
      height: 18px;
      border-radius: 6px;
      background: rgba(244,182,61,.20);
      border: 1px solid rgba(244,182,61,.35);
      color: #7A4C00;
      font-size: 11px;
      margin-right: 8px;
      flex: 0 0 auto;
    }
    .mono{
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      font-weight: 900;
      font-size: 11px;
      background: rgba(17,24,39,.04);
      border: 1px solid rgba(17,24,39,.08);
      border-radius: 10px;
      padding: 2px 8px;
      display: inline-block;
    }
    .divider{ height: 1px; background: var(--border); margin: 10px 0; }
    .total{
      display:flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 12px;
      margin-top: 10px;
      padding-top: 10px;
      border-top: 1px dashed var(--border);
    }
    .amount{
      font-weight: 950;
      font-size: 22px;
      letter-spacing: -0.3px;
    }
    .note{
      margin-top: 10px;
      padding: 10px 10px;
      border: 1px solid var(--border);
      border-radius: 12px;
      background: var(--bg);
    }
    .note .label{ margin-bottom: 6px; display:block; }
    .footer{
      margin-top: 14px;
      color: var(--muted);
      font-size: 10px;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="header">
    <div>
      <div class="brand">ElderAssist</div>
      <div class="title">Payment Receipt</div>
      <div class="subtitle">Generated: ${escapeHtml(generatedAtIso)}</div>
    </div>
    <div>
      <div class="pill ${escapeHtml(statusTone)}">${escapeHtml(paymentStatus || "-")}</div>
    </div>
  </div>

  <div class="grid">
    <div class="card">
      <h2>Booking</h2>
      <table class="table">
        <tr><td><span class="icon">#</span>Booking ID</td><td><span class="mono">${escapeHtml(bookingId || "-")}</span></td></tr>
        <tr><td><span class="icon">≡</span>Bill code</td><td><span class="mono">${escapeHtml(billCode || "-")}</span></td></tr>
        <tr><td><span class="icon">▣</span>Service</td><td>${escapeHtml(service || "-")}</td></tr>
        <tr><td><span class="icon">⏱</span>Schedule</td><td>${escapeHtml(scheduleLine() || "-")}</td></tr>
        <tr><td><span class="icon">👤</span>Caregiver</td><td>${escapeHtml(caregiverName || "-")}</td></tr>
        <tr><td><span class="icon">👥</span>Selected person</td><td>${escapeHtml(personName || "-")}</td></tr>
        <tr><td><span class="icon">⌂</span>Address</td><td>${escapeHtml(personAddress || "-")}</td></tr>
        <tr><td><span class="icon">✓</span>Booking status</td><td>${escapeHtml(bookingStatus || "-")}</td></tr>
      </table>
      ${
        bookingNotes
          ? `<div class="note"><span class="label">Booking notes</span><div class="value">${escapeHtml(
              bookingNotes,
            )}</div></div>`
          : ""
      }
      ${
        personNotes
          ? `<div class="note"><span class="label">Person notes</span><div class="value">${escapeHtml(
              personNotes,
            )}</div></div>`
          : ""
      }
    </div>

    <div class="card">
      <h2>Payment</h2>
      <table class="table">
        <tr><td><span class="icon">✓</span>Payment status</td><td>${escapeHtml(paymentStatus || "-")}</td></tr>
        <tr><td><span class="icon">☰</span>Payment method</td><td>${escapeHtml(paymentMethod || "-")}</td></tr>
        <tr><td><span class="icon">RM</span>Service price</td><td>RM ${escapeHtml(fmtMoney(computedServiceValue))}</td></tr>
        <tr><td><span class="icon">⇄</span>Distance</td><td>${escapeHtml(distanceKm ? distanceKm.toFixed(1) : "0.0")} km</td></tr>
        <tr><td><span class="icon">＋</span>Distance charge</td><td>RM ${escapeHtml(fmtMoney(distanceCharge))}</td></tr>
      </table>
      <div class="total">
        <div class="label">Total paid</div>
        <div class="amount">RM ${escapeHtml(fmtMoney(total))}</div>
      </div>
      <div class="footer">Payment ID: ${escapeHtml(paymentId)} • Receipt file: ${escapeHtml(
        fileName,
      )}</div>
    </div>
  </div>
</body>
</html>`;

    if (PDFREST_API_KEY) {
      return await callPdfRestHtmlToPdf({ html, fileName });
    }
    return await callShiftPdfHtmlToPdf({ html, fileName });
  });

exports.createToyyibPayBill = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }

    let result;
    try {
      result = await createToyyibBill({
        billName: data.billName,
        billDescription: data.billDescription,
        amount: Number(data.amount) || 0,
        name: data.name,
        email: data.email,
        phone: data.phone,
      });
    } catch (err) {
      if (err instanceof functions.https.HttpsError) throw err;
      console.error("createToyyibPayBill failed:", err);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to create ToyyibPay bill.",
      );
    }

    return {
      success: true,
      ...result,
    };
  });

exports.createBookingAndPay = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }

    const normalizeDateString = (value) => String(value || "").trim();
    const minutesFrom24h = (hhmm) => {
      const raw = String(hhmm || "").trim();
      const m = raw.match(/^(\d{2}):(\d{2})$/);
      if (!m) return Number.NaN;
      const h = parseInt(m[1], 10);
      const min = parseInt(m[2], 10);
      if (!Number.isFinite(h) || !Number.isFinite(min)) return Number.NaN;
      if (h < 0 || h > 23 || min < 0 || min > 59) return Number.NaN;
      return h * 60 + min;
    };

    const uid = context.auth.uid;
    const amount = Number(data.amount) || Number(data.servicePrice) || 0;
    let paymentResult;
    try {
      paymentResult = await createToyyibBill({
        billName: data.billName,
        billDescription: data.billDescription,
        amount,
        name: data.name,
        email: data.email,
        phone: data.phone,
      });
    } catch (err) {
      if (err instanceof functions.https.HttpsError) throw err;
      console.error("createBookingAndPay failed to create bill:", err);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to create ToyyibPay bill.",
      );
    }

    const normalizeServicePreferences = (raw) => {
      if (Array.isArray(raw)) {
        return raw.map((value) => String(value).trim()).filter(Boolean);
      }
      if (typeof raw === "string" && raw.trim()) {
        return [raw.trim()];
      }
      return [];
    };

    const servicePreferences = normalizeServicePreferences(
      data.servicePreferences ?? data.service ?? data.services,
    );
    const serviceLabel = servicePreferences.join(", ");

    const bookingId = db.collection("bookings").doc().id;
    const startTime = String(data.startTime || "").trim();
    const endTime = String(data.endTime || "").trim();
    const time = String(data.time || "").trim();
    const hasTimeRange = Boolean(startTime && endTime);

    // Prevent redundant scheduled bookings (server-side lock).
    if (hasTimeRange) {
      const caregiverId = String(data.caregiverId || "").trim();
      const date = normalizeDateString(data.date);
      if (!caregiverId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Missing caregiverId.",
        );
      }
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Invalid date format. Expected yyyy-MM-dd.",
        );
      }

      const start24 = normalizeTo24HourTime(startTime);
      const end24 = normalizeTo24HourTime(endTime);
      const startMin = minutesFrom24h(start24);
      const endMin = minutesFrom24h(end24);
      if (!Number.isFinite(startMin) || !Number.isFinite(endMin) || endMin <= startMin) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Invalid start/end time.",
        );
      }

      const existingSnap = await db
        .collection("bookings")
        .where("caregiverId", "==", caregiverId)
        .where("date", "==", date)
        .where("paymentStatus", "==", "PAID")
        .where("status", "in", ["ASSIGNED", "SCHEDULED", "EMERGENCY_ALERT"])
        .get();

      const overlaps = (aStart, aEnd, bStart, bEnd) =>
        aStart < bEnd && aEnd > bStart;

      for (const doc of existingSnap.docs) {
        const b = doc.data() || {};
        const s = String(b.startTime || "").trim();
        const e = String(b.endTime || "").trim();
        if (!s || !e) continue;
        const s24 = normalizeTo24HourTime(s);
        const e24 = normalizeTo24HourTime(e);
        const sMin = minutesFrom24h(s24);
        const eMin = minutesFrom24h(e24);
        if (!Number.isFinite(sMin) || !Number.isFinite(eMin) || eMin <= sMin) continue;
        if (overlaps(startMin, endMin, sMin, eMin)) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Selected time is no longer available. Please choose another time.",
          );
        }
      }
    }

    const bookingPayload = {
      caregiverId: data.caregiverId || "",
      caregiverName: data.caregiverName || "",
      caregiverPhoto: data.caregiverPhoto || data.photoUrl || "",
      servicePreferences,
      service: serviceLabel,
      personId: data.personId || "",
      personName: data.personName || "",
      personAddress: data.personAddress || "",
      addressId: data.addressId || "",
      addressLabel: data.addressLabel || "",
      date: data.date || "",
      ...(hasTimeRange ? { startTime, endTime } : { time }),
      personNotes: String(data.personNotes || data.notes || "").trim(),
      bookingNotes: String(data.bookingNotes || "").trim(),
      distanceKm: Number(data.distanceKm) || 0,
      distanceCharge: Number(data.distanceCharge) || 0,
      servicePrice: Number(data.servicePrice) || 0,
    };
    const initialBookingStatus = derivePaidBookingStatus(bookingPayload);

    await db.collection("payments").doc(paymentResult.billCode).set(
      {
        userId: uid,
        bookingId,
        billCode: paymentResult.billCode,
        paymentUrl: paymentResult.paymentUrl,
        paymentMethod: data.paymentMethod || "ToyyibPay",
        amount,
        currency: "MYR",
        paymentStatus: "PENDING",
        status: 2, // 1=paid,2=pending,3=failed (ToyyibPay conventions)
        bookingStatus: initialBookingStatus,
        hidden: false,
        booking: bookingPayload,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      success: true,
      bookingId,
      billCode: paymentResult.billCode,
      paymentUrl: paymentResult.paymentUrl,
    };
  });

// =====================================================
// TOYYIBPAY CALLBACK (SERVER → SERVER)
// =====================================================
exports.toyyibpayCallback = functions
  .region("asia-southeast1")
  .https.onRequest(async (req, res) => {
    try {
      console.log("Toyyib callback query:", req.query, req.body);

      const rawBody = req.body;
      let parsedBody = {};
      let bodyText = "";
      if (rawBody) {
        if (Buffer.isBuffer(rawBody)) {
          bodyText = rawBody.toString("utf8");
          parsedBody = qs.parse(bodyText);
        } else if (typeof rawBody === "string") {
          bodyText = rawBody;
          parsedBody = qs.parse(bodyText);
        } else if (typeof rawBody === "object") {
          parsedBody = rawBody;
          bodyText = JSON.stringify(rawBody);
        }
      }
      console.log("Toyyib callback bodyText:", bodyText.slice(0, 400));

      const extractFromText = (key) => {
        const regex = new RegExp(`${key}=([^\\r\\n&]+)`);
        const match = bodyText.match(regex);
        return match ? match[1] : undefined;
      };

      const multipartFields = parseMultipartFormFields(bodyText);
      const billCode =
        parsedBody.billcode ||
        multipartFields.billcode ||
        multipartFields.billcod ||
        req.query?.billcode;
      const statusValue =
        parsedBody.status ||
        multipartFields.status ||
        multipartFields.stat ||
        req.query?.status;
      const fallbackBillCode = extractFromText("billcode");
      const fallbackStatus = extractFromText("status");
      const finalBillCode =
        billCode ||
        multipartFields.billcode ||
        multipartFields.billcod ||
        multipartFields.billCode ||
        multipartFields.billcodex ||
        fallbackBillCode;
      const finalStatusValue =
        statusValue ||
        multipartFields.status ||
        multipartFields.status_id ||
        multipartFields.stat ||
        fallbackStatus;
      const status = finalStatusValue ? parseInt(finalStatusValue, 10) : null;

      if (!finalBillCode) {
        console.warn("Toyyib callback missing billcode", req.query, req.body);
        return res.status(400).send("Missing billcode");
      }

      if (!finalStatusValue) {
        console.warn("Toyyib callback missing status", req.query, req.body);
        return res.status(400).send("Missing status");
      }

      await db.collection("payments").doc(finalBillCode).set(
        {
          status,          // 1 = success, 2 = pending, 3 = failed
          paidAt: Date.now(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      const paymentRef = db.collection("payments").doc(finalBillCode);
      const paymentSnap = await paymentRef.get();
      const paymentData = paymentSnap.data() || {};
      const bookingId = String(paymentData.bookingId || "").trim();
      const bookingPayload = paymentData.booking || {};
      const userId = String(paymentData.userId || "").trim();
      const paymentMethod = String(paymentData.paymentMethod || "ToyyibPay");
      const amountValue = Number(paymentData.amount) || 0;

      if (status === 1) {
        const computedStatus = derivePaidBookingStatus(bookingPayload);
        const bookingRef = db.collection("bookings").doc(bookingId || undefined);
        const hasTimeRange = Boolean(
          bookingPayload.startTime && bookingPayload.endTime,
        );
        const bookingData = {
          bookingId: bookingRef.id,
          userId,
          caregiverId: bookingPayload.caregiverId || "",
          caregiverName: bookingPayload.caregiverName || "",
          caregiverPhoto: bookingPayload.caregiverPhoto || "",
          servicePreferences: bookingPayload.servicePreferences || [],
          service: bookingPayload.service || "",
          personId: bookingPayload.personId || "",
          personName: bookingPayload.personName || "",
          personAddress: bookingPayload.personAddress || "",
          addressId: bookingPayload.addressId || "",
          addressLabel: bookingPayload.addressLabel || "",
          date: bookingPayload.date || "",
          ...(hasTimeRange
            ? {
                startTime: bookingPayload.startTime || "",
                endTime: bookingPayload.endTime || "",
              }
            : { time: bookingPayload.time || "" }),
          paymentMethod,
          servicePrice: Number(bookingPayload.servicePrice) || amountValue,
          distanceKm: Number(bookingPayload.distanceKm) || 0,
          distanceCharge: Number(bookingPayload.distanceCharge) || 0,
          bookingNotes: String(bookingPayload.bookingNotes || "").trim(),
          personNotes: String(
            bookingPayload.personNotes || bookingPayload.notes || "",
          ).trim(),
          status: computedStatus,
          paymentStatus: "PAID",
          paidAt: Date.now(),
          toyyibBillCode: finalBillCode,
          toyyibPaymentUrl: paymentData.paymentUrl || null,
          notifyApp: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await bookingRef.set(bookingData, { merge: true });
        await paymentRef.set(
          {
            bookingId: bookingRef.id,
            paymentStatus: "PAID",
            bookingStatus: computedStatus,
            status: 1,
            paidAt: Date.now(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      } else if (status === 3) {
        await paymentRef.set(
          {
            paymentStatus: "FAILED",
            bookingStatus: "PAYMENT_FAILED",
            status: 3,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        if (bookingId) {
          await db.collection("bookings").doc(bookingId).delete().catch(() => {});
        }
      } else {
        await paymentRef.set(
          {
            paymentStatus: "PENDING",
            status: 2,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      res.status(200).send("OK");
    } catch (err) {
      console.error("Toyyib callback error:", err);
      res.status(500).send("ERROR");
    }
  });

function derivePaidBookingStatus(bookingData) {
  const date = String(bookingData.date || "").trim(); // expected yyyy-MM-dd
  const time = String(bookingData.startTime || bookingData.time || "").trim(); // expected HH:mm

  const nowEpoch = Date.now();
  const scheduledEpoch = parseMalaysiaEpoch(date, time);
  if (Number.isFinite(scheduledEpoch)) {
    return scheduledEpoch > nowEpoch ? "SCHEDULED" : "ASSIGNED";
  }

  if (/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    const todayMalaysia = malaysiaTodayString();
    if (date > todayMalaysia) return "SCHEDULED";
  }

  return "ASSIGNED";
}

function parseMalaysiaEpoch(date, time) {
  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return Number.NaN;
  const safeTime = normalizeTo24HourTime(time);
  const iso = `${date}T${safeTime}:00+08:00`;
  const epoch = Date.parse(iso);
  return Number.isNaN(epoch) ? Number.NaN : epoch;
}

function normalizeTo24HourTime(time) {
  const raw = String(time || "").trim().toLowerCase();
  if (/^\d{2}:\d{2}$/.test(raw)) return raw; // already HH:mm

  // Accept "hh:mm am/pm" (Flutter currently stores this format in bookings)
  const m = raw.match(/^(\d{1,2}):(\d{2})\s*([ap]m)$/);
  if (m) {
    let h = parseInt(m[1], 10);
    const minute = parseInt(m[2], 10);
    const period = m[3];
    if (!Number.isFinite(h) || !Number.isFinite(minute)) return "00:00";
    h = Math.max(0, Math.min(12, h));
    const mm = Math.max(0, Math.min(59, minute));
    if (period === "am") {
      if (h === 12) h = 0;
    } else {
      if (h !== 12) h += 12;
    }
    return `${String(h).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
  }

  return "00:00";
}

function malaysiaTodayString() {
  // Malaysia is UTC+8 and does not observe DST.
  const malaysiaEpoch = Date.now() + 8 * 60 * 60 * 1000;
  return new Date(malaysiaEpoch).toISOString().slice(0, 10);
}

// =====================================================
// BOOKING AUTO-STATUS — SCHEDULED -> ASSIGNED WHEN DUE
// =====================================================
exports.autoAssignDueBookings = functions.pubsub
  .schedule("every 5 minutes")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async () => {
    const nowEpoch = Date.now();
    const todayMalaysia = malaysiaTodayString();
    const bookingsRef = db.collection("bookings");

    let lastDoc = null;
    let processed = 0;
    let updated = 0;

    while (processed < 1500) {
      let query = bookingsRef
        .where("status", "==", "SCHEDULED")
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(300);
      if (lastDoc) query = query.startAfter(lastDoc);

      const snap = await query.get();
      if (snap.empty) break;
      lastDoc = snap.docs[snap.docs.length - 1];
      processed += snap.size;

      const batch = db.batch();
      let writes = 0;

      for (const doc of snap.docs) {
        const data = doc.data() || {};

        const paymentStatus = String(data.paymentStatus || "").toUpperCase();
        if (paymentStatus && paymentStatus !== "PAID") continue;

        const date = String(data.date || data.scheduledDate || "").trim();
        const time = String(data.startTime || data.time || "").trim();

        const scheduledEpoch = parseMalaysiaEpoch(date, time);
        let shouldAssign = false;
        if (Number.isFinite(scheduledEpoch)) {
          shouldAssign = scheduledEpoch <= nowEpoch;
        } else if (/^\d{4}-\d{2}-\d{2}$/.test(date)) {
          shouldAssign = date <= todayMalaysia;
        }

        if (!shouldAssign) continue;

        batch.update(doc.ref, {
          status: "ASSIGNED",
          notifyApp: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        writes += 1;
        updated += 1;

        const billCode = String(data.toyyibBillCode || "").trim();
        if (billCode) {
          batch.set(
            db.collection("payments").doc(billCode),
            {
              bookingId: doc.id,
              bookingStatus: "ASSIGNED",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          writes += 1;
        }

        if (writes >= 450) break;
      }

      if (writes > 0) {
        await batch.commit();
      }

      if (snap.size < 300) break;
    }

    console.log("autoAssignDueBookings", { processed, updated });
    return null;
  });


// =====================================================
// HELPER: DISTANCE CALCULATION
// =====================================================
function toRad(x) {
  return (x * Math.PI) / 180;
}

function haversine(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);

  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) ** 2;

  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// =====================================================
// SOS: MATCH BEST AVAILABLE CAREGIVER (RULES-BASED)
// =====================================================
function malaysiaNowParts() {
  // Malaysia is UTC+8 and does not observe DST.
  const ms = Date.now() + 8 * 60 * 60 * 1000;
  const d = new Date(ms);
  const weekday = d.getUTCDay(); // 0=Sun..6=Sat
  const hours = d.getUTCHours();
  const minutes = d.getUTCMinutes();
  const isoDate = d.toISOString().slice(0, 10);
  return { weekday, hours, minutes, isoDate };
}

function weekdayNameFromMalaysiaWeekday(weekday) {
  // 0=Sun..6=Sat -> stored names use Monday..Sunday
  const map = {
    0: "Sunday",
    1: "Monday",
    2: "Tuesday",
    3: "Wednesday",
    4: "Thursday",
    5: "Friday",
    6: "Saturday",
  };
  return map[weekday] || "Monday";
}

function parseHHmmToMinutes(value, fallback) {
  const raw = String(value || "").trim();
  const m = raw.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return fallback;
  const h = parseInt(m[1], 10);
  const mm = parseInt(m[2], 10);
  if (!Number.isFinite(h) || !Number.isFinite(mm)) return fallback;
  if (h < 0 || h > 23 || mm < 0 || mm > 59) return fallback;
  return h * 60 + mm;
}

function isBlockedToday(blockedDates, todayIso) {
  if (!Array.isArray(blockedDates) || !todayIso) return false;
  for (const entry of blockedDates) {
    if (!entry || typeof entry !== "object") continue;
    const startRaw = String(entry.start || "").slice(0, 10);
    const endRaw = String(entry.end || "").slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(startRaw)) continue;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(endRaw)) continue;
    if (todayIso >= startRaw && todayIso <= endRaw) return true;
  }
  return false;
}

function isWorkingNowFromAvailabilityDoc(data, parts) {
  if (!data) return true;
  if (isBlockedToday(data.blockedDates, parts.isoDate)) return false;

  const weekly = data.weeklySchedule;
  if (!Array.isArray(weekly) || weekly.length === 0) return true;
  const dayName = weekdayNameFromMalaysiaWeekday(parts.weekday);
  const entry = weekly.find((e) => e && String(e.day || "") === dayName);
  if (!entry) return true;
  const available = entry.available !== false;
  if (!available) return false;

  const startMin = parseHHmmToMinutes(entry.start, 8 * 60);
  const endMin = parseHHmmToMinutes(entry.end, 18 * 60);
  const nowMin = parts.hours * 60 + parts.minutes;
  if (endMin <= startMin) return true;
  return nowMin >= startMin && nowMin <= endMin;
}

function normalizeStringList(value) {
  if (Array.isArray(value)) {
    return value
      .map((v) => String(v || "").trim())
      .filter(Boolean);
  }
  if (typeof value === "string" && value.trim()) return [value.trim()];
  return [];
}

function toFiniteNumber(value) {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

function caregiverLatLng(caregiver) {
  const loc = caregiver && caregiver.location;
  if (
    loc &&
    typeof loc.latitude === "number" &&
    typeof loc.longitude === "number" &&
    Number.isFinite(loc.latitude) &&
    Number.isFinite(loc.longitude)
  ) {
    return { lat: loc.latitude, lng: loc.longitude };
  }

  const nested =
    (caregiver && caregiver.currentLocation) ||
    (caregiver && caregiver.currentLatLng) ||
    (caregiver && caregiver.latLng) ||
    (caregiver && caregiver.coordinates) ||
    null;

  const lat =
    toFiniteNumber(caregiver && caregiver.lat) ??
    toFiniteNumber(caregiver && caregiver.latitude) ??
    toFiniteNumber(nested && (nested.lat ?? nested.latitude));
  const lng =
    toFiniteNumber(caregiver && caregiver.lng) ??
    toFiniteNumber(caregiver && caregiver.longitude) ??
    toFiniteNumber(caregiver && caregiver.long) ??
    toFiniteNumber(nested && (nested.lng ?? nested.longitude ?? nested.long));

  if (lat == null || lng == null) return null;
  return { lat, lng };
}

function buildRules(raw) {
  const defaults = {
    maxRuleDistanceKm: 12.0,
    preferredDistanceKm: 6.0,
    minAcceptableRating: 3.0,
    ratingPenaltyThreshold: 3.5,
    ratingPenaltyValue: -10.0,
    recommendationTier1MinScore: 2600.0,
    recommendationTier2MinScore: 2200.0,
    distanceScoreMultiplier: 8.0,
    ratingScoreMultiplier: 15.0,
    matchScoreMultiplier: 1200.0,
    serviceScoreMultiplier: 3.0,
    serviceScoreCap: 6,
    priceScoreMultiplier: -6.0,
    distancePenaltyMultiplier: -2.0,
  };

  const data = raw && typeof raw === "object" ? raw : {};
  const d = (k, cur) => {
    const v = data[k];
    if (typeof v === "number") return v;
    if (typeof v === "string") {
      const n = Number(v.trim());
      return Number.isFinite(n) ? n : cur;
    }
    return cur;
  };
  const i = (k, cur) => {
    const v = data[k];
    if (typeof v === "number") return Math.trunc(v);
    if (typeof v === "string") {
      const n = parseInt(v.trim(), 10);
      return Number.isFinite(n) ? n : cur;
    }
    return cur;
  };

  return {
    maxRuleDistanceKm: d("maxRuleDistanceKm", defaults.maxRuleDistanceKm),
    preferredDistanceKm: d("preferredDistanceKm", defaults.preferredDistanceKm),
    minAcceptableRating: d("minAcceptableRating", defaults.minAcceptableRating),
    ratingPenaltyThreshold: d(
      "ratingPenaltyThreshold",
      defaults.ratingPenaltyThreshold,
    ),
    ratingPenaltyValue: d("ratingPenaltyValue", defaults.ratingPenaltyValue),
    recommendationTier1MinScore: d(
      "recommendationTier1MinScore",
      defaults.recommendationTier1MinScore,
    ),
    recommendationTier2MinScore: d(
      "recommendationTier2MinScore",
      defaults.recommendationTier2MinScore,
    ),
    distanceScoreMultiplier: d(
      "distanceScoreMultiplier",
      defaults.distanceScoreMultiplier,
    ),
    ratingScoreMultiplier: d("ratingScoreMultiplier", defaults.ratingScoreMultiplier),
    matchScoreMultiplier: d("matchScoreMultiplier", defaults.matchScoreMultiplier),
    serviceScoreMultiplier: d(
      "serviceScoreMultiplier",
      defaults.serviceScoreMultiplier,
    ),
    serviceScoreCap: i("serviceScoreCap", defaults.serviceScoreCap),
    priceScoreMultiplier: d("priceScoreMultiplier", defaults.priceScoreMultiplier),
    distancePenaltyMultiplier: d(
      "distancePenaltyMultiplier",
      defaults.distancePenaltyMultiplier,
    ),
  };
}

function priceValue(distanceKm, available) {
  const base = 6.0 + distanceKm * 1.6 - (available ? 0 : -2);
  return Math.max(0, base);
}

function scoreWithRules(rules, distanceKm, rating, serviceCount, price, matchCount) {
  const normalizedDistance = Math.max(
    0,
    rules.preferredDistanceKm - Math.min(distanceKm, rules.preferredDistanceKm),
  );
  const distanceScore = normalizedDistance * rules.distanceScoreMultiplier;
  const ratingScore = rating * rules.ratingScoreMultiplier;
  const matchScore = matchCount * rules.matchScoreMultiplier;
  const serviceScore =
    Math.min(serviceCount, rules.serviceScoreCap) * rules.serviceScoreMultiplier;
  const priceScore = price * rules.priceScoreMultiplier;
  const ratingPenalty = rating < rules.ratingPenaltyThreshold ? rules.ratingPenaltyValue : 0;
  const distancePenalty =
    distanceKm > rules.preferredDistanceKm
      ? (distanceKm - rules.preferredDistanceKm) * rules.distancePenaltyMultiplier
      : 0;
  return (
    distanceScore +
    ratingScore +
    serviceScore +
    priceScore +
    matchScore +
    ratingPenalty +
    distancePenalty
  );
}

function isBusyBookingNow(data, nowEpoch) {
  const status = String(data.status || "").toUpperCase().trim();
  if (status === "ONGOING" || status === "IN_PROGRESS") return true;
  if (status !== "ASSIGNED") return false;

  const date = String(data.date || data.scheduledDate || "").trim();
  const start = String(data.startTime || data.time || "").trim();
  const end = String(data.endTime || "").trim();
  const startEpoch = parseMalaysiaEpoch(date, start);
  if (!Number.isFinite(startEpoch)) return true;
  const endEpoch = end ? parseMalaysiaEpoch(date, end) : startEpoch + 60 * 60 * 1000;
  const early = startEpoch - 10 * 60 * 1000;
  const late = endEpoch + 15 * 60 * 1000;
  return nowEpoch >= early && nowEpoch <= late;
}

async function busyCaregiverIds(caregiverIds, nowEpoch) {
  const busy = new Set();
  const ids = Array.isArray(caregiverIds) ? caregiverIds.filter(Boolean) : [];
  const chunkSize = 30;
  for (let i = 0; i < ids.length; i += chunkSize) {
    const chunk = ids.slice(i, i + chunkSize);
    const snap = await db.collection("bookings").where("caregiverId", "in", chunk).get();
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      if (isBusyBookingNow(data, nowEpoch)) {
        const id = String(data.caregiverId || "").trim();
        if (id) busy.add(id);
      }
    }
  }
  return busy;
}

exports.matchSosCaregiver = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated");
      }

      const sosId = String((data && data.sosId) || "").trim();
      if (!sosId) {
        throw new functions.https.HttpsError("invalid-argument", "sosId required");
      }
      const inputLat = toFiniteNumber((data && (data.userLat ?? data.lat)) ?? null);
      const inputLng = toFiniteNumber((data && (data.userLng ?? data.lng)) ?? null);

      const uid = context.auth.uid;
      const sosRef = db.collection("sos").doc(sosId);
      const sosSnap = await sosRef.get();
      if (!sosSnap.exists) {
        throw new functions.https.HttpsError("not-found", "SOS not found");
      }
      const sos = sosSnap.data() || {};
      const bookingId = String(sos.bookingId || "").trim();
      const meta =
        sos.addressMeta && typeof sos.addressMeta === "object" ? sos.addressMeta : {};
      const sosLat =
        toFiniteNumber(sos.userLat) ??
        toFiniteNumber(meta.lat) ??
        toFiniteNumber(meta.latitude) ??
        toFiniteNumber(meta.deviceLat) ??
        toFiniteNumber(meta.currentLat);
      const sosLng =
        toFiniteNumber(sos.userLng) ??
        toFiniteNumber(meta.lng) ??
        toFiniteNumber(meta.longitude) ??
        toFiniteNumber(meta.long) ??
        toFiniteNumber(meta.deviceLng) ??
        toFiniteNumber(meta.currentLng);
      const lat = sosLat ?? inputLat;
      const lng = sosLng ?? inputLng;
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        return { success: false, caregiverId: null, sosId, reason: "NO_USER_LOCATION" };
      }
      const sosUserId = String(sos.userId || sos.ownerUserId || "").trim();
      if (sosUserId && sosUserId !== uid) {
        throw new functions.https.HttpsError("permission-denied");
      }
      const existingCaregiver = String(
        sos.caregiverId || sos.assignedCaregiverId || "",
      ).trim();
      if (existingCaregiver) {
        return { success: true, caregiverId: existingCaregiver, sosId };
      }
      const status = String(sos.status || "").toUpperCase().trim();
      if (status === "RESOLVED" || status === "CANCELLED") {
        return { success: false, caregiverId: null, sosId };
      }

      const nowEpoch = Date.now();
      const nowParts = malaysiaNowParts();
      const sosMaxDistanceKm = 15.0;

      const [userSnap, rulesSnap] = await Promise.all([
        db.collection("users").doc(uid).get(),
        db.collection("recommendationRules").doc("current").get(),
      ]);

      const prefs = normalizeStringList(userSnap.data()?.servicePreferences).map((s) =>
        s.toLowerCase(),
      );
      const prefsSet = new Set(prefs);
      const rules = buildRules(rulesSnap.data());

      // Candidate caregivers (availability must be true)
      const caregiverSnap = await db
        .collection("caregivers")
        .where("availability", "==", true)
        .limit(220)
        .get();

      const candidates = [];
      const nearbyFallback = [];
      const outsideRadiusFallback = [];
      for (const doc of caregiverSnap.docs) {
        const c = doc.data() || {};
        const caregiverId = doc.id;
        const coords = caregiverLatLng(c);
        if (!coords) continue;
        const rating = Number(c.rating) || 0;
        const services = normalizeStringList(c.servicePreferences ?? c.services);
        const serviceCount = services.length;
        const distanceKm = haversine(lat, lng, coords.lat, coords.lng);
        if (!Number.isFinite(distanceKm)) continue;

        const withinRadius = distanceKm <= sosMaxDistanceKm;

        let matchCount = 0;
        if (prefsSet.size > 0) {
          for (const s of services) {
            const key = String(s || "").toLowerCase().trim();
            if (key && prefsSet.has(key)) matchCount += 1;
          }
        }

        const price = priceValue(distanceKm, true);
        const score = scoreWithRules(rules, distanceKm, rating, serviceCount, price, matchCount);

        if (withinRadius) {
          // Ranked candidates must pass base rules.
          if (rating >= rules.minAcceptableRating && distanceKm <= rules.maxRuleDistanceKm) {
            candidates.push({
              caregiverId,
              distanceKm,
              rating,
              serviceCount,
              matchCount,
              score,
            });
          }

          // Fallback candidates ignore rating/rules thresholds (still within SOS radius).
          nearbyFallback.push({
            caregiverId,
            distanceKm,
            rating,
            serviceCount,
            matchCount,
            score,
          });
        } else {
          // Last-resort: allow offering outside radius if no one is available within 15km.
          outsideRadiusFallback.push({
            caregiverId,
            distanceKm,
            rating,
            serviceCount,
            matchCount,
            score,
          });
        }
      }

      candidates.sort((a, b) => b.score - a.score);
      nearbyFallback.sort((a, b) => a.distanceKm - b.distanceKm);
      outsideRadiusFallback.sort((a, b) => a.distanceKm - b.distanceKm);

      const availabilityRefs = (ids) =>
        ids.map((id) => db.collection("availability").doc(id).get());

      const batchSize = 30;

      async function buildEligibleQueue(ordered, maxCount, requireWorkingNow = true) {
        const out = [];
        const selected = new Set();
        for (let i = 0; i < ordered.length && out.length < maxCount; i += batchSize) {
          const slice = ordered.slice(i, i + batchSize);
          const ids = slice.map((c) => c.caregiverId);
          const busy = await busyCaregiverIds(ids, nowEpoch);
          const availabilitySnaps = await Promise.all(availabilityRefs(ids));
          const availabilityById = new Map();
          for (let j = 0; j < ids.length; j += 1) {
            availabilityById.set(ids[j], availabilitySnaps[j]?.data() || null);
          }

          for (const item of slice) {
            const id = item && item.caregiverId;
            if (!id) continue;
            if (selected.has(id)) continue;
            if (busy.has(id)) continue;
            if (requireWorkingNow) {
              const availData = availabilityById.get(id);
              if (!isWorkingNowFromAvailabilityDoc(availData, nowParts)) continue;
            }
            out.push(id);
            selected.add(id);
            if (out.length >= maxCount) break;
          }
        }
        return out;
      }

      let offerQueue = await buildEligibleQueue(candidates, 10, true);
      if (offerQueue.length < 10) {
        const more = await buildEligibleQueue(nearbyFallback, 10 - offerQueue.length, true);
        offerQueue = [...offerQueue, ...more];
      }
      if (offerQueue.length === 0) {
        // Last resort: outside-radius caregivers that are available & free now.
        offerQueue = await buildEligibleQueue(outsideRadiusFallback, 10, true);
      }

      // Emergency override: if schedule filters out everyone, allow offering caregivers that are free now.
      if (offerQueue.length === 0) {
        offerQueue = await buildEligibleQueue(candidates, 10, false);
        if (offerQueue.length < 10) {
          const more = await buildEligibleQueue(nearbyFallback, 10 - offerQueue.length, false);
          offerQueue = [...offerQueue, ...more];
        }
        if (offerQueue.length === 0) {
          offerQueue = await buildEligibleQueue(outsideRadiusFallback, 10, false);
        }
      }

      if (offerQueue.length === 0) {
        await sosRef.set(
          {
            status: "NO_MATCH",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        return { success: false, caregiverId: null, sosId, reason: "NO_MATCH_WITHIN_RADIUS" };
      }

      const selectedId = offerQueue[0];

      // Offer to multiple caregivers at once so a responder can accept even if the
      // requesting client app is closed/logged-out (one-phone testing, backgrounded app, etc).
      const offeredCaregiverIds = offerQueue.slice(0, 10).filter(Boolean);

      await db.runTransaction(async (tx) => {
        const snap = await tx.get(sosRef);
        if (!snap.exists) return;
        const current = snap.data() || {};
        const already = String(
          current.caregiverId || current.assignedCaregiverId || "",
        ).trim();
        const st = String(current.status || "").toUpperCase().trim();
        if (already) return;
        if (st === "RESOLVED" || st === "CANCELLED") return;
        tx.set(
          sosRef,
          {
            status: "OFFERING",
            offerQueue,
            offerIndex: 0,
            offeredCaregiverId: selectedId,
            offeredCaregiverIds,
            offeredAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            tracking: admin.firestore.FieldValue.arrayUnion({
              label: "Caregiver offered",
              description: selectedId,
              timestamp: new Date().toISOString(),
              status: "OFFERING",
            }),
          },
          { merge: true },
        );
      });

      const writeTasks = [];
      for (const caregiverId of offeredCaregiverIds) {
        const responderRef = sosRef.collection("responders").doc(caregiverId);
        writeTasks.push(
          responderRef.set(
            {
              caregiverId,
              status: "OFFERED",
              offeredAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          ),
        );

        // Also write to caregiver-owned inbox for reliable reads under restrictive rules.
        writeTasks.push(
          db
            .collection("caregivers")
            .doc(caregiverId)
            .collection("sosOffers")
            .doc(sosId)
            .set(
              {
                sosId,
                bookingId: bookingId || null,
                status: "OFFERED",
                offeredAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                userLat: Number.isFinite(lat) ? lat : null,
                userLng: Number.isFinite(lng) ? lng : null,
                address: String(sos.address || sos.userAddress || "").trim() || null,
                selectedPersonName: String(
                  sos.selectedPersonName || sos.userName || "Client",
                ).trim(),
              },
              { merge: true },
            ),
        );
      }
      await Promise.allSettled(writeTasks);

      return { success: true, caregiverId: null, sosId, offeredCaregiverId: selectedId };
    } catch (err) {
      console.error("matchSosCaregiver failed", err);
      if (err instanceof functions.https.HttpsError) throw err;
      const message =
        (err && typeof err === "object" && String(err.message || "").trim()) ||
        String(err || "").trim() ||
        "Internal error";
      throw new functions.https.HttpsError("internal", message);
    }
  });

exports.respondSosOffer = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated");
      }
      const sosId = String((data && data.sosId) || "").trim();
      const action = String((data && data.action) || "").toUpperCase().trim();
      if (!sosId) {
        throw new functions.https.HttpsError("invalid-argument", "sosId required");
      }
      if (action !== "ACCEPT" && action !== "REJECT") {
        throw new functions.https.HttpsError("invalid-argument", "action must be ACCEPT or REJECT");
      }

      const caregiverId = context.auth.uid;
      const sosRef = db.collection("sos").doc(sosId);
      const sosSnap = await sosRef.get();
      if (!sosSnap.exists) {
        throw new functions.https.HttpsError("not-found", "SOS not found");
      }
      const sos = sosSnap.data() || {};
      const bookingId = String(sos.bookingId || "").trim();
      const status = String(sos.status || "").toUpperCase().trim();
      const finalized = new Set([
        "RESOLVED",
        "CANCELLED",
        "TIMEOUT",
        "NO_RESPONDER",
        "NO_MATCH",
      ]);
      if (finalized.has(status)) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "This SOS is no longer active.",
        );
      }

      const responderRef = sosRef.collection("responders").doc(caregiverId);
      const caregiverOfferRef = db
        .collection("caregivers")
        .doc(caregiverId)
        .collection("sosOffers")
        .doc(sosId);

      if (action === "ACCEPT") {
        const queue = Array.isArray(sos.offerQueue) ? sos.offerQueue.map(String) : [];
        await db.runTransaction(async (tx) => {
          const caregiverDocRef = db.collection("caregivers").doc(caregiverId);
          const bookingRef = bookingId ? db.collection("bookings").doc(bookingId) : db.collection("bookings").doc();
          const [snap, offerSnap, caregiverSnap] = await Promise.all([
            tx.get(sosRef),
            tx.get(caregiverOfferRef),
            tx.get(caregiverDocRef),
          ]);
          if (!snap.exists) return;
          if (!offerSnap.exists) {
            throw new functions.https.HttpsError(
              "failed-precondition",
              "No active offer for this caregiver",
            );
          }
          const offerData = offerSnap.data() || {};
          const offerStatus = String(offerData.status || "").toUpperCase().trim();
          if (offerStatus !== "OFFERED") {
            throw new functions.https.HttpsError(
              "failed-precondition",
              "No active offer for this caregiver",
            );
          }

          const current = snap.data() || {};
          const already = String(
            current.caregiverId || current.assignedCaregiverId || "",
          ).trim();
          if (already) {
            tx.set(
              caregiverOfferRef,
              {
                status: "EXPIRED",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
            return;
          }

          const caregiverData = caregiverSnap.data() || {};
          const caregiverName = String(
            caregiverData.name || caregiverData.fullName || "",
          ).trim();

          const personId = String(current.personId || current.addressId || "").trim();
          const personName = String(
            current.personName || current.selectedPersonName || current.userName || "Client",
          ).trim();
          const personAddress = String(
            current.personAddress || current.address || current.userAddress || "",
          ).trim();
          const addressId = String(current.addressId || current.personId || "").trim();
          const addressLabel = String(
            current.addressLabel || current.addressLabelText || "",
          ).trim();
          const service = String(current.service || "Emergency Alert").trim();
          const date = String(current.date || current.scheduledDate || "").trim();
          const scheduledDate = String(current.scheduledDate || current.date || date).trim();
          const time = String(current.time || "").trim();
          const startTime = String(current.startTime || "").trim();
          const endTime = String(current.endTime || "").trim();

          tx.set(
            responderRef,
            {
              caregiverId,
              status: "ACCEPTED",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              respondedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          tx.set(
            caregiverOfferRef,
            {
              status: "ACCEPTED",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              respondedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          tx.set(
            sosRef,
            {
              caregiverId,
              assignedCaregiverId: caregiverId,
              status: "RESPONDER_ASSIGNED",
              responderId: caregiverId,
              offeredCaregiverId: admin.firestore.FieldValue.delete(),
              offeredCaregiverIds: admin.firestore.FieldValue.delete(),
              offerQueue: queue,
              assignedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              tracking: admin.firestore.FieldValue.arrayUnion({
                label: "Caregiver accepted",
                description: caregiverId,
                timestamp: new Date().toISOString(),
                status: "RESPONDER_ASSIGNED",
              }),
            },
            { merge: true },
          );

          tx.set(
            db.collection("caregivers").doc(caregiverId),
            {
              activeSosId: sosId,
              activeSosUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );

          // Create (or update if already existed) booking record once a caregiver accepts.
          tx.set(
            bookingRef,
            {
              sosId,
              userId: String(current.userId || "").trim(),
              caregiverId,
              caregiverName,
              personId,
              personName,
              personAddress,
              lat: Number.isFinite(current.userLat) ? current.userLat : null,
              lng: Number.isFinite(current.userLng) ? current.userLng : null,
              personLat: Number.isFinite(current.userLat) ? current.userLat : null,
              personLng: Number.isFinite(current.userLng) ? current.userLng : null,
              addressId,
              addressLabel,
              service,
              date,
              scheduledDate,
              time,
              startTime,
              endTime,
              paymentMethod: String(current.paymentMethod || "").trim(),
              servicePrice: current.servicePrice ?? "",
              status: "EMERGENCY_ALERT",
              personNotes: String(current.notes || "").trim(),
              cancellationReason: String(current.cancellationReason || "").trim(),
              createdAt: current.createdAt || admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              assignedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );

          // Backlink the booking into the sos doc (and keep a bookingStatus mirror for UI).
          tx.set(
            sosRef,
            {
              bookingId: bookingRef.id,
              bookingStatus: "EMERGENCY_ALERT",
              caregiverName,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        });

        // Best-effort: expire any remaining caregiver inbox offers so they stop showing incoming screens.
        const expireTargets = Array.isArray(sos.offerQueue) ? sos.offerQueue.map(String) : [];
        const expireTasks = [];
        for (const id of expireTargets) {
          const otherId = String(id || "").trim();
          if (!otherId || otherId === caregiverId) continue;
          expireTasks.push(
            db
              .collection("caregivers")
              .doc(otherId)
              .collection("sosOffers")
              .doc(sosId)
              .set(
                {
                  status: "EXPIRED",
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true },
              ),
          );
          expireTasks.push(
            sosRef.collection("responders").doc(otherId).set(
              {
                caregiverId: otherId,
                status: "EXPIRED",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            ),
          );
        }
        await Promise.allSettled(expireTasks);
        return { success: true, sosId, status: "RESPONDER_ASSIGNED" };
      }

      // REJECT: mark this caregiver declined. Another caregiver may still accept.
      await responderRef.set(
        {
          caregiverId,
          status: "DECLINED",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await caregiverOfferRef.set(
        {
          status: "DECLINED",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await sosRef.set(
        {
          tracking: admin.firestore.FieldValue.arrayUnion({
            label: "Caregiver declined",
            description: caregiverId,
            timestamp: new Date().toISOString(),
            status: "DECLINED",
          }),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      // If this SOS was offered to multiple caregivers at once (broadcast mode),
      // and everyone has declined/expired, finalize immediately so the client UI
      // doesn't wait for its own timeout.
      try {
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(sosRef);
          if (!snap.exists) return;
          const current = snap.data() || {};
          const assigned = String(
            current.caregiverId || current.assignedCaregiverId || "",
          ).trim();
          if (assigned) return;

          const st = String(current.status || "").toUpperCase().trim();
          const finalized = new Set([
            "RESOLVED",
            "CANCELLED",
            "TIMEOUT",
            "NO_RESPONDER",
            "NO_MATCH",
          ]);
          if (finalized.has(st)) return;

          const offered = Array.isArray(current.offeredCaregiverIds)
            ? current.offeredCaregiverIds.map(String).filter(Boolean)
            : [];
          if (offered.length === 0) return;

          const offerDocs = offered.map((id) =>
            db.collection("caregivers").doc(String(id).trim()).collection("sosOffers").doc(sosId),
          );
          const offerSnaps = await Promise.all(offerDocs.map((ref) => tx.get(ref)));
          let stillOffered = false;
          for (const offerSnap of offerSnaps) {
            if (!offerSnap.exists) continue;
            const offerData = offerSnap.data() || {};
            const offerStatus = String(offerData.status || "").toUpperCase().trim();
            if (offerStatus === "OFFERED") {
              stillOffered = true;
              break;
            }
          }
          if (stillOffered) return;

          tx.set(
            sosRef,
            {
              status: "NO_RESPONDER",
              offeredCaregiverId: admin.firestore.FieldValue.delete(),
              offeredCaregiverIds: admin.firestore.FieldValue.delete(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              tracking: admin.firestore.FieldValue.arrayUnion({
                label: "No responders available",
                description: "All offered caregivers declined.",
                timestamp: new Date().toISOString(),
                status: "NO_RESPONDER",
              }),
            },
            { merge: true },
          );
        });
      } catch (err) {
        console.error("respondSosOffer finalize NO_RESPONDER failed", sosId, err);
      }

      return { success: true, sosId, status: "OFFERING" };
    } catch (err) {
      console.error("respondSosOffer failed", err);
      if (err instanceof functions.https.HttpsError) throw err;
      const message =
        (err && typeof err === "object" && String(err.message || "").trim()) ||
        String(err || "").trim() ||
        "Internal error";
      throw new functions.https.HttpsError("internal", message);
    }
  });

exports.advanceSosOffer = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated");
      }

      const sosId = String((data && data.sosId) || "").trim();
      if (!sosId) {
        throw new functions.https.HttpsError("invalid-argument", "sosId required");
      }

      const uid = context.auth.uid;
      const sosRef = db.collection("sos").doc(sosId);
      const snap = await sosRef.get();
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "SOS not found");
      }
      const sos = snap.data() || {};
      const sosUserId = String(sos.userId || sos.ownerUserId || "").trim();
      if (sosUserId && sosUserId !== uid) {
        throw new functions.https.HttpsError("permission-denied");
      }

      const assigned = String(sos.caregiverId || sos.assignedCaregiverId || "").trim();
      if (assigned) {
        return { success: true, sosId, status: "RESPONDER_ASSIGNED", caregiverId: assigned };
      }

      const status = String(sos.status || "").toUpperCase().trim();
      if (status !== "OFFERING") {
        return { success: true, sosId, status, offeredCaregiverId: sos.offeredCaregiverId || null };
      }

      // Broadcast-offer mode: offers are written to multiple caregivers at once.
      // No need to advance a single "current" offer. Client uses its own timeout UI.
      const broadcastList = Array.isArray(sos.offeredCaregiverIds) ? sos.offeredCaregiverIds : null;
      if (broadcastList && broadcastList.length > 0) {
        return { success: true, sosId, status: "OFFERING", mode: "BROADCAST" };
      }

      const queue = Array.isArray(sos.offerQueue) ? sos.offerQueue.map(String) : [];
      const idxRaw = typeof sos.offerIndex === "number" ? sos.offerIndex : Number(sos.offerIndex);
      const currentIndex = Number.isFinite(idxRaw) ? Math.max(0, Math.trunc(idxRaw)) : 0;
      const offeredCaregiverId = String(sos.offeredCaregiverId || "").trim();
      const offeredAt = sos.offeredAt && typeof sos.offeredAt.toMillis === "function"
        ? sos.offeredAt.toMillis()
        : null;

      // Only advance if the current offer has been pending long enough.
      const now = Date.now();
      const offerTimeoutMs = 22 * 1000;
      if (offeredAt != null && now - offeredAt < offerTimeoutMs) {
        return {
          success: true,
          sosId,
          status: "OFFERING",
          offeredCaregiverId: offeredCaregiverId || null,
          offerIndex: currentIndex,
        };
      }

      const nextIndex = currentIndex + 1;
      const nextCaregiverId = queue[nextIndex] ? String(queue[nextIndex]).trim() : "";

      if (!nextCaregiverId) {
        await sosRef.set(
          {
            status: "NO_RESPONDER",
            offeredCaregiverId: admin.firestore.FieldValue.delete(),
            offerIndex: nextIndex,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            tracking: admin.firestore.FieldValue.arrayUnion({
              label: "No responders available",
              description: "Offer timed out.",
              timestamp: new Date().toISOString(),
              status: "NO_RESPONDER",
            }),
          },
          { merge: true },
        );
        return { success: false, sosId, status: "NO_RESPONDER" };
      }

      // Mark previous offer as timed out (best-effort).
      if (offeredCaregiverId) {
        await Promise.allSettled([
          sosRef.collection("responders").doc(offeredCaregiverId).set(
            {
              caregiverId: offeredCaregiverId,
              status: "TIMED_OUT",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          ),
          db
            .collection("caregivers")
            .doc(offeredCaregiverId)
            .collection("sosOffers")
            .doc(sosId)
            .set(
              {
                sosId,
                status: "TIMED_OUT",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            ),
        ]);
      }

      await sosRef.set(
        {
          status: "OFFERING",
          offeredCaregiverId: nextCaregiverId,
          offerIndex: nextIndex,
          offeredAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          tracking: admin.firestore.FieldValue.arrayUnion({
            label: "Caregiver offered",
            description: nextCaregiverId,
            timestamp: new Date().toISOString(),
            status: "OFFERING",
          }),
        },
        { merge: true },
      );

      await sosRef.collection("responders").doc(nextCaregiverId).set(
        {
          caregiverId: nextCaregiverId,
          status: "OFFERED",
          offeredAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      await db
        .collection("caregivers")
        .doc(nextCaregiverId)
        .collection("sosOffers")
        .doc(sosId)
        .set(
          {
            sosId,
            status: "OFFERED",
            offeredAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            userLat: toFiniteNumber(sos.userLat) ?? null,
            userLng: toFiniteNumber(sos.userLng) ?? null,
            address: String(sos.address || sos.userAddress || "").trim() || null,
            selectedPersonName: String(
              sos.selectedPersonName || sos.userName || "Client",
            ).trim(),
          },
          { merge: true },
        );

      return { success: true, sosId, status: "OFFERING", offeredCaregiverId: nextCaregiverId, offerIndex: nextIndex };
    } catch (err) {
      console.error("advanceSosOffer failed", err);
      if (err instanceof functions.https.HttpsError) throw err;
      const message =
        (err && typeof err === "object" && String(err.message || "").trim()) ||
        String(err || "").trim() ||
        "Internal error";
      throw new functions.https.HttpsError("internal", message);
    }
  });

async function advanceSosOfferByTimeout({ sosId, sos, offerTimeoutMs = 22 * 1000 }) {
  const sosRef = db.collection("sos").doc(sosId);
  const assigned = String(sos.caregiverId || sos.assignedCaregiverId || "").trim();
  if (assigned) {
    return { advanced: false, status: "RESPONDER_ASSIGNED", caregiverId: assigned };
  }

  const status = String(sos.status || "").toUpperCase().trim();
  if (status !== "OFFERING") {
    return { advanced: false, status };
  }

  // Broadcast-offer mode: do not advance. UI handles timeout; responders can accept anytime.
  const offeredCaregiverIds = Array.isArray(sos.offeredCaregiverIds) ? sos.offeredCaregiverIds : null;
  if (offeredCaregiverIds && offeredCaregiverIds.length > 0) {
    return { advanced: false, status: "OFFERING", mode: "BROADCAST" };
  }

  const queue = Array.isArray(sos.offerQueue) ? sos.offerQueue.map(String) : [];
  const idxRaw = typeof sos.offerIndex === "number" ? sos.offerIndex : Number(sos.offerIndex);
  const currentIndex = Number.isFinite(idxRaw) ? Math.max(0, Math.trunc(idxRaw)) : 0;
  const offeredCaregiverId = String(sos.offeredCaregiverId || "").trim();

  const offeredAtMs =
    sos.offeredAt && typeof sos.offeredAt.toMillis === "function" ? sos.offeredAt.toMillis() : null;
  const now = Date.now();
  if (offeredAtMs != null && now - offeredAtMs < offerTimeoutMs) {
    return { advanced: false, status: "OFFERING", offeredCaregiverId, offerIndex: currentIndex };
  }

  const nextIndex = currentIndex + 1;
  const nextCaregiverId = queue[nextIndex] ? String(queue[nextIndex]).trim() : "";

  if (!nextCaregiverId) {
    await sosRef.set(
      {
        status: "NO_RESPONDER",
        offeredCaregiverId: admin.firestore.FieldValue.delete(),
        offerIndex: nextIndex,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        tracking: admin.firestore.FieldValue.arrayUnion({
          label: "No responders available",
          description: "Offer timed out.",
          timestamp: new Date().toISOString(),
          status: "NO_RESPONDER",
        }),
      },
      { merge: true },
    );
    return { advanced: true, status: "NO_RESPONDER" };
  }

  if (offeredCaregiverId) {
    await Promise.allSettled([
      sosRef.collection("responders").doc(offeredCaregiverId).set(
        {
          caregiverId: offeredCaregiverId,
          status: "TIMED_OUT",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      ),
      db
        .collection("caregivers")
        .doc(offeredCaregiverId)
        .collection("sosOffers")
        .doc(sosId)
        .set(
          {
            sosId,
            status: "TIMED_OUT",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        ),
    ]);
  }

  await sosRef.set(
    {
      status: "OFFERING",
      offeredCaregiverId: nextCaregiverId,
      offerIndex: nextIndex,
      offeredAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      tracking: admin.firestore.FieldValue.arrayUnion({
        label: "Caregiver offered",
        description: nextCaregiverId,
        timestamp: new Date().toISOString(),
        status: "OFFERING",
      }),
    },
    { merge: true },
  );

  await sosRef.collection("responders").doc(nextCaregiverId).set(
    {
      caregiverId: nextCaregiverId,
      status: "OFFERED",
      offeredAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await db
    .collection("caregivers")
    .doc(nextCaregiverId)
    .collection("sosOffers")
    .doc(sosId)
    .set(
      {
        sosId,
        status: "OFFERED",
        offeredAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        userLat: toFiniteNumber(sos.userLat) ?? null,
        userLng: toFiniteNumber(sos.userLng) ?? null,
        address: String(sos.address || sos.userAddress || "").trim() || null,
        selectedPersonName: String(sos.selectedPersonName || sos.userName || "Client").trim(),
      },
      { merge: true },
    );

  return { advanced: true, status: "OFFERING", offeredCaregiverId: nextCaregiverId, offerIndex: nextIndex };
}

exports.tickSosOffers = functions.pubsub
  .schedule("every 1 minutes")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async () => {
    const snap = await db.collection("sos").where("status", "==", "OFFERING").limit(120).get();
    if (snap.empty) return null;

    const tasks = [];
    for (const doc of snap.docs) {
      const sos = doc.data() || {};
      tasks.push(
        advanceSosOfferByTimeout({ sosId: doc.id, sos }).catch((err) => {
          console.error("tickSosOffers advance failed", doc.id, err);
          return null;
        }),
      );
    }

    await Promise.allSettled(tasks);
    return null;
  });

// =====================================================
// SOS FINALIZE → EXPIRE CAREGIVER INBOX OFFERS
// =====================================================
exports.syncSosFinalStateToInbox = functions
  .region("asia-southeast1")
  .firestore.document("sos/{sosId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const beforeStatus = String(before.status || "").toUpperCase().trim();
    const afterStatus = String(after.status || "").toUpperCase().trim();
    if (beforeStatus === afterStatus) return null;

    const finalized = new Set([
      "RESOLVED",
      "CANCELLED",
      "TIMEOUT",
      "NO_RESPONDER",
      "NO_MATCH",
    ]);
    if (!finalized.has(afterStatus)) return null;

    const sosId = String(context.params.sosId || "").trim();
    if (!sosId) return null;

    const caregiverIds = new Set();
    const offered = Array.isArray(after.offeredCaregiverIds)
      ? after.offeredCaregiverIds.map(String)
      : [];
    const queue = Array.isArray(after.offerQueue) ? after.offerQueue.map(String) : [];
    const assigned = String(after.caregiverId || after.assignedCaregiverId || "").trim();
    for (const id of [...offered, ...queue]) {
      const s = String(id || "").trim();
      if (s) caregiverIds.add(s);
    }
    if (assigned) caregiverIds.add(assigned);

    const userId = String(after.userId || after.ownerUserId || "").trim();
    const inboxStatus = afterStatus === "RESOLVED" ? "CLOSED" : "EXPIRED";

    const batch = db.batch();
    for (const id of caregiverIds) {
      batch.set(
        db.collection("caregivers").doc(id).collection("sosOffers").doc(sosId),
        {
          sosId,
          status: inboxStatus,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    // Clear "active" pointers so SOS tabs resume cleanly.
    if (assigned) {
      batch.set(
        db.collection("caregivers").doc(assigned),
        {
          activeSosId: admin.firestore.FieldValue.delete(),
          activeSosUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    if (userId) {
      batch.set(
        db.collection("users").doc(userId),
        {
          activeSosId: admin.firestore.FieldValue.delete(),
          activeSosUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    await batch.commit();
    return null;
  });

async function deleteCollectionPaged(collectionRef, batchSize = 180) {
  let snap = await collectionRef.limit(batchSize).get();
  while (!snap.empty) {
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    snap = await collectionRef.limit(batchSize).get();
  }
}

async function recursiveDeleteDoc(docRef) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(docRef);
    return;
  }

  const subcols = await docRef.listCollections();
  for (const col of subcols) {
    await deleteCollectionPaged(col);
  }
  await docRef.delete();
}

// =====================================================
// SOS CLEANUP — REMOVE EXPIRED SOS DOCS
// =====================================================
exports.cleanupExpiredSos = functions
  .region("asia-southeast1")
  .firestore.document("sos/{sosId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const beforeStatus = String(before.status || "").toUpperCase().trim();
    const afterStatus = String(after.status || "").toUpperCase().trim();
    if (!afterStatus || beforeStatus === afterStatus) return null;

    // "Expired" = SOS finished without a successful resolution/assignment.
    // Keep RESOLVED records for history; delete expired/timeout/no-responder records.
    const expiredStatuses = new Set([
      "TIMEOUT",
      "NO_RESPONDER",
      "NO_MATCH",
      "CANCELLED",
    ]);
    if (!expiredStatuses.has(afterStatus)) return null;

    const sosId = String((context.params && context.params.sosId) || "").trim();
    if (!sosId) return null;

    try {
      // Mark for purge (do not delete immediately) so the client can still read
      // the final status and show the right message.
      if (after.purgeAt) return null;
      await db.collection("sos").doc(sosId).set(
        {
          purgeAt: admin.firestore.FieldValue.serverTimestamp(),
          purgeReason: afterStatus,
        },
        { merge: true },
      );
    } catch (err) {
      console.error("cleanupExpiredSos mark failed", sosId, err);
    }
    return null;
  });

exports.purgeExpiredSos = functions.pubsub
  .schedule("every 1 minutes")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async () => {
    const snap = await db
      .collection("sos")
      .where("purgeAt", "<=", admin.firestore.Timestamp.now())
      .limit(120)
      .get();

    if (snap.empty) return null;

    const tasks = [];
    for (const doc of snap.docs) {
      const sosRef = db.collection("sos").doc(doc.id);
      tasks.push(
        recursiveDeleteDoc(sosRef).catch((err) => {
          console.error("purgeExpiredSos delete failed", doc.id, err);
          return null;
        }),
      );
    }
    await Promise.allSettled(tasks);
    return null;
  });

// =====================================================
// CAREGIVER LIVE LOCATION UPDATE (TRACKING)
// =====================================================
exports.updateCaregiverLocation = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated");
      }

      const { lat, lng, bookingId } = data || {};
      if (typeof lat !== "number" || typeof lng !== "number") {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "lat and lng are required numbers",
        );
      }

      const caregiverId = context.auth.uid;
      const geoPoint = new admin.firestore.GeoPoint(lat, lng);

      await db.collection("caregivers").doc(caregiverId).set(
        {
          lat,
          lng,
          location: geoPoint,
          locationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      if (typeof bookingId === "string" && bookingId.trim()) {
        await db.collection("bookings").doc(bookingId.trim()).set(
          {
            caregiverLastLocation: geoPoint,
            trackingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      return { ok: true };
    } catch (err) {
      console.error("updateCaregiverLocation failed", err);
      if (err instanceof functions.https.HttpsError) throw err;
      throw new functions.https.HttpsError("internal", "Internal error");
    }
  });

// =====================================================
// RECOMMENDATION RULES (SEED) - DEV/ADMIN ONLY
// =====================================================
exports.seedRecommendationRules = functions
  .region("asia-southeast1")
  .https.onRequest(async (req, res) => {
    try {
      const secret = String(
        functions.config().seed?.secret || process.env.SEED_SECRET || "",
      ).trim();
      if (!secret) {
        return res
          .status(400)
          .json({ ok: false, error: "Missing SEED_SECRET (functions config or env)" });
      }

      const provided = String(req.query.secret || "").trim();
      if (!provided || provided !== secret) {
        return res.status(403).json({ ok: false, error: "Forbidden" });
      }

      const mode = String(req.query.mode || "merge").trim().toLowerCase();
      const density = String(req.query.density || "lite")
        .trim()
        .toLowerCase();

      // NOTE: This is intentionally opinionated and aligned with the app-side
      // `_RecommendationMatrixFeatures.from(...)` bucketing in Flutter.
      const ratingLevels = density === "full" ? [1, 2, 3, 4, 5] : [1, 3, 5];
      const matchLevels = density === "full" ? [1, 2, 3, 4, 5] : [1, 3, 5];
      const priceGapLevels = density === "full" ? [1, 2, 3, 4, 5] : [1, 3, 5];
      const serviceCountLevels =
        density === "full" ? [1, 2, 3, 4, 5] : [1, 3, 5];
      const distanceLevels = density === "full" ? [1, 2, 3, 4, 5] : [1, 2];

      function recommendationClassFor({
        ratingLevel,
        distanceLevel,
        matchLevel,
        priceGapLevel,
        serviceCountLevel,
      }) {
        // App caps usable distance at ~15km (distanceLevel 1..2). Anything beyond that is
        // treated as "Not ideal" to keep recommendations predictable.
        if (distanceLevel >= 3) return 3;

        // Best match (Class 1):
        // - High rating + close + strong match + within budget + decent service variety.
        if (
          ratingLevel <= 2 &&
          matchLevel <= 2 &&
          priceGapLevel <= 2 &&
          distanceLevel <= 2 &&
          serviceCountLevel <= 3
        ) {
          return 1;
        }

        // Recommended (Class 2):
        // - Still close and acceptable rating, but allow some flexibility in match/price/service variety.
        if (
          ratingLevel <= 3 &&
          matchLevel <= 3 &&
          priceGapLevel <= 3 &&
          distanceLevel <= 2 &&
          serviceCountLevel <= 4
        ) {
          return 2;
        }

        // Not ideal (Class 3): everything else.
        return 3;
      }

      const rules = [];
      for (const rating_level of ratingLevels) {
        for (const distance_level of distanceLevels) {
          for (const match_level of matchLevels) {
            for (const price_gap_level of priceGapLevels) {
              for (const service_count_level of serviceCountLevels) {
                const recommendation_class = recommendationClassFor({
                  ratingLevel: rating_level,
                  distanceLevel: distance_level,
                  matchLevel: match_level,
                  priceGapLevel: price_gap_level,
                  serviceCountLevel: service_count_level,
                });

                rules.push({
                  id: `r${rating_level}d${distance_level}m${match_level}p${price_gap_level}s${service_count_level}`,
                  data: {
                    rating_level,
                    distance_level,
                    match_level,
                    price_gap_level,
                    service_count_level,
                    recommendation_class,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                  },
                });
              }
            }
          }
        }
      }

      // Optional cleanup (do not touch `recommendationRules/current`).
      if (mode === "replace") {
        const snap = await db.collection("recommendationRules").get();
        const toDelete = snap.docs.filter((d) => d.id !== "current");
        for (let i = 0; i < toDelete.length; i += 450) {
          const batch = db.batch();
          for (const doc of toDelete.slice(i, i + 450)) {
            batch.delete(doc.ref);
          }
          await batch.commit();
        }
      }

      // Ensure "current" exists with sane defaults (app can override from Firestore).
      await db.collection("recommendationRules").doc("current").set(
        {
          maxRuleDistanceKm: 15.0,
          preferredDistanceKm: 6.0,
          minAcceptableRating: 3.0,
        },
        { merge: true },
      );

      // Write rules in batches.
      for (let i = 0; i < rules.length; i += 450) {
        const batch = db.batch();
        for (const rule of rules.slice(i, i + 450)) {
          const ref = db.collection("recommendationRules").doc(rule.id);
          batch.set(ref, rule.data, { merge: true });
        }
        await batch.commit();
      }

      return res.status(200).json({
        ok: true,
        mode,
        density,
        count: rules.length,
        note: "Seeded recommendationRules/* (matrix) and ensured recommendationRules/current exists",
      });
    } catch (err) {
      console.error("seedRecommendationRules failed", err);
      return res.status(500).json({ ok: false, error: String(err?.message || err) });
    }
  });
