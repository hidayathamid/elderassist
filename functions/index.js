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

    const { lat, lng, reason } = data || {};
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

    const message = `🚨 NEW SOS ALERT

👤 User: ${sos.triggeredByName}
📝 Reason: ${sos.reason || "N/A"}

📍 Location:
https://maps.google.com/?q=${sos.userLat},${sos.userLng}

⏳ Status: CREATED`;

    for (const c of contacts) {
      if (!c.telegramChatId) continue;

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

    const message = `📢 SOS STATUS UPDATE

    User: ${after.triggeredByName}
    Status: ${after.status.toUpperCase()}
    Reason: ${after.reason || "N/A"}

    📍 Location:
    https://maps.google.com/?q=${after.userLat},${after.userLng}`;

    for (const c of contacts) {
      if (!c.telegramChatId) continue;

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
exports.createToyyibPayBill = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated");
    }

    const payload = {
      userSecretKey: TOYYIBPAY_SECRET_KEY,
      categoryCode: TOYYIBPAY_CATEGORY_CODE,
      billName: data.billName,
      billDescription: data.billDescription,
      billPriceSetting: 1,
      billPayorInfo: 1,
      billAmount: (data.amount * 100).toString(),
      billReturnUrl: "https://elderassist.com/payment-success",
      billCallbackUrl: `https://us-central1-${FB_PROJECT_ID}.cloudfunctions.net/toyyibpayCallback`,
    };

    const res = await axios.post(
      "https://toyyibpay.com/index.php/api/createBill",
      payload
    );

    return {
      success: true,
      paymentUrl: `https://toyyibpay.com/${res.data[0].BillCode}`,
    };
  });

// =====================================================
// TOYYIBPAY CALLBACK
// =====================================================
exports.toyyibpayCallback = functions
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      await db.collection("payments").doc(req.query.billcode).set(
        {
          status: parseInt(req.query.status),
          updatedAt: Date.now(),
        },
        { merge: true }
      );
      res.send("OK");
    } catch (err) {
      console.error(err);
      res.status(500).send("ERROR");
    }
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
