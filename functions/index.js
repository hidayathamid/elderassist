// =====================================================
// IMPORTS & INITIALIZATION
// =====================================================
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();
const db = admin.firestore();

// =====================================================
// ENV CONFIG
// =====================================================
const BOT_TOKEN = functions.config().telegram?.token;
const TOYYIBPAY_SECRET_KEY = functions.config().toyyibpay?.secret_key;
const TOYYIBPAY_CATEGORY_CODE = functions.config().toyyibpay?.category_code;
const FB_PROJECT_ID = functions.config().fb?.project_id;

// =====================================================
// HELPER — LINK BOOKED USER BY PAIR CODE (ROLE 2)
// =====================================================
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
// TELEGRAM HTTPS ENDPOINT — PAIRING (ROLE 2 & ROLE 4)
// =====================================================
exports.telegramLinkContact = functions.https.onRequest(async (req, res) => {
  try {
    const { pairCode, name, phone, chatId } = req.body || {};
    if (!pairCode || !name || !phone || !chatId) {
      return res.status(400).send("Missing required fields.");
    }

    // Try ROLE 2 first
    try {
      await linkBookedUserByPairCode(pairCode, {
        name,
        phone,
        telegramChatId: chatId,
      });

      await axios.post(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
        chat_id: chatId,
        text: "✅ You are now registered as a booked user.",
      });

      return res.send("OK");
    } catch (_) {
      // fallback to ROLE 4
    }

    await linkEmergencyContactByPairCode(pairCode, {
      name,
      phone,
      telegramChatId: chatId,
    });

    await axios.post(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
      chat_id: chatId,
      text: "✅ You are now registered as an emergency contact.",
    });

    res.send("OK");
  } catch (err) {
    console.error(err);
    res.status(500).send("Invalid or expired pairing code.");
  }
});

// =====================================================
// SOS CREATE — APP ONLY (ROLE 1 & ROLE 3)
// =====================================================
exports.handleSOSAlert = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }

    const { lat, lng, reason, notifyContactIds } = data || {};
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
// 📱 APP / FIREBASE SDK (onCall)
// =====================================================
exports.createSOSFromTelegram = functions
  .region("us-central1")
  .https.onCall(async (data) => {
    try {
      return await createSOSCore(data);
    } catch (err) {
      console.error("createSOSFromTelegram ERROR:", err);

      if (err instanceof functions.https.HttpsError) {
        throw err;
      }

      throw new functions.https.HttpsError(
        "internal",
        "Failed to create SOS"
      );
    }
  });

// =====================================================
// 🤖 TELEGRAM / HTTP (onRequest)
// =====================================================
exports.createSOSFromTelegramHttp = functions
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      const result = await createSOSCore(req.body);
      return res.status(200).json(result);
    } catch (err) {
      console.error("HTTP SOS ERROR:", err);

      if (err instanceof functions.https.HttpsError) {
        return res.status(400).json({ error: err.message });
      }

      return res.status(500).json({
        error: "Internal server error",
      });
    }
  });

// =====================================================
// SOS STATUS UPDATE — ROLE 3 ONLY
// =====================================================
exports.updateSOSStatus = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }

    const { sosId, status } = data || {};
    if (!sosId || !status) {
      throw new functions.https.HttpsError("invalid-argument");
    }

    const uid = context.auth.uid;
   const caregiverDoc = await db.collection("caregivers").doc(uid).get();
    if (!caregiverDoc.exists || caregiverDoc.data().role !== "caregiver") {
      throw new functions.https.HttpsError("permission-denied");
    }


    const sosRef = db.collection("sos").doc(sosId);
    const update = { status, notifyTelegram: true };

    if (status === "acknowledged") {
      update.assignedCaregiverId = uid;
      update["timestamps.acknowledgedAt"] =
        admin.firestore.FieldValue.serverTimestamp();
    }
    if (status === "handling") {
      update["timestamps.handlingAt"] =
        admin.firestore.FieldValue.serverTimestamp();
    }
    if (status === "resolved") {
      update["timestamps.resolvedAt"] =
        admin.firestore.FieldValue.serverTimestamp();
    }

    await sosRef.update(update);
    return { success: true };
  });

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
// SOS UPDATE — LIVE LOCATION (FROM TELEGRAM ROLE 2)
// =====================================================
exports.updateSOSLocationFromTelegram = functions
  .region("us-central1")
  .https.onCall(async (data) => {
    const { sosId, lat, lng } = data || {};

    // =========================
    // VALIDATION
    // =========================
    if (!sosId || typeof lat !== "number" || typeof lng !== "number") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "sosId, lat and lng are required"
      );
    }

    const sosRef = db.collection("sos").doc(sosId);
    const sosSnap = await sosRef.get();

    if (!sosSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "SOS not found"
      );
    }

    // =========================
    // UPDATE LOCATION ONLY
    // =========================
    await sosRef.update({
      userLat: lat,
      userLng: lng,
      "timestamps.updatedAt": admin.firestore.FieldValue.serverTimestamp(),

      // 🔔 App boleh refresh map
      notifyApp: true,
    });

    return { success: true };
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

// =====================================================
// TOYYIBPAY BILL (CALLABLE)
// =====================================================
// =====================================================
// TOYYIBPAY CREATE BILL (CALLABLE - FROM APP)
// =====================================================
const qs = require("qs");

async function createToyyibBill({
  billName,
  billDescription,
  amount,
  name,
  email,
  phone,
}) {
  const payload = {
    userSecretKey: TOYYIBPAY_SECRET_KEY,
    categoryCode: TOYYIBPAY_CATEGORY_CODE,

    billName,
    billDescription,

    billPriceSetting: 1,
    billPayorInfo: 1,

    // RM + SEN
    billAmount: Math.round((amount || 0) * 100),

    billTo: name || "ElderAssist User",
    billEmail: email || "noreply@elderassist.com",
    billPhone: phone || "0123456789",

    billReturnUrl: "elderassist://payment-success",

    // ToyyibPay akan panggil function ni
    billCallbackUrl: `https://asia-southeast1-${FB_PROJECT_ID}.cloudfunctions.net/toyyibpayCallback`,
  };

  const response = await axios.post(
    "https://toyyibpay.com/index.php/api/createBill",
    qs.stringify(payload),
    {
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      timeout: 15000,
    }
  );

  return {
    billCode: response.data[0].BillCode,
    paymentUrl: `https://toyyibpay.com/${response.data[0].BillCode}`,
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

exports.createToyyibPayBill = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }

    const result = await createToyyibBill({
      billName: data.billName,
      billDescription: data.billDescription,
      amount: Number(data.amount) || 0,
      name: data.name,
      email: data.email,
      phone: data.phone,
    });

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

    const uid = context.auth.uid;
    const amount = Number(data.amount) || Number(data.servicePrice) || 0;
    const paymentResult = await createToyyibBill({
      billName: data.billName,
      billDescription: data.billDescription,
      amount,
      name: data.name,
      email: data.email,
      phone: data.phone,
    });

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
      notes: data.notes || "",
      servicePrice: Number(data.servicePrice) || 0,
    };

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
// TOYYIBPAY CALLBACK
// =====================================================
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
          notes: bookingPayload.notes || "",
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
      const status = String(sos.status || "").toUpperCase().trim();
      if (status !== "OFFERING") {
        throw new functions.https.HttpsError("failed-precondition", "No active offer for this SOS");
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
          const [snap, offerSnap] = await Promise.all([
            tx.get(sosRef),
            tx.get(caregiverOfferRef),
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
