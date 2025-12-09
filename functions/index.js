const functions = require("firebase-functions");
const admin = require("firebase-admin");
require("dotenv").config();
const axios = require("axios");

admin.initializeApp();

// =====================================================
// 3. SOS ALERT (USER SENDS SOS)
// =====================================================
exports.handleSOSAlert = functions.https.onCall(async (data) => {
  const userId = data?.userId;
  const lat = data?.lat;
  const lng = data?.lng;

  if (!userId || typeof lat !== "number" || typeof lng !== "number") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing or invalid userId / lat / lng"
    );
  }

  let userName = "User";
  let userPhone = "";

  try {
    const userDoc = await admin.firestore().collection("users").doc(userId).get();
    if (userDoc.exists) {
      const u = userDoc.data() || {};
      userName = u.name || userName;
      userPhone = u.phone || "";
    }
  } catch (e) {
    console.warn("handleSOSAlert: failed to read user profile", e);
  }

  const sosRef = admin.firestore().collection("sos").doc();
  const sosData = {
    sosId: sosRef.id,
    userId,
    userName,
    userPhone,
    userLat: lat,
    userLng: lng,
    status: "FINDING",
    requestedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await sosRef.set(sosData);

  return { success: true, sosId: sosRef.id };
});


// =====================================================
// HELPER: DISTANCE
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
// 4. AUTO DISPATCH SOS
// =====================================================
exports.autoDispatchSOS = functions.firestore
  .document("sos/{sosId}")
  .onCreate(async (snap, context) => {
    const sos = snap.data();
    const sosId = context.params.sosId;

    if (!sos) return null;

    const { userLat, userLng, userName, userId } = sos;

    const caregiversSnap = await admin
      .firestore()
      .collection("caregivers")
      .where("availability", "==", true)
      .get();

    if (caregiversSnap.empty) {
      await snap.ref.update({ status: "NO_RESPONDER" });
      return null;
    }

    const responders = caregiversSnap.docs.map((doc) => {
      const data = doc.data() || {};
      const lat = data.lat;
      const lng = data.lng;

      return {
        caregiverId: doc.id,
        caregiverName: data.name || "Caregiver",
        caregiverPhoto: data.photoUrl || "",
        distanceKm:
          typeof lat === "number" && typeof lng === "number"
            ? haversine(userLat, userLng, lat, lng)
            : null,
      };
    });

    responders.sort((a, b) => {
      if (a.distanceKm === null) return 1;
      if (b.distanceKm === null) return -1;
      return a.distanceKm - b.distanceKm;
    });

    const batch = admin.firestore().batch();
    const responderIds = [];

    for (const responder of responders) {
      const responderRef = snap.ref
        .collection("responders")
        .doc(responder.caregiverId);

      batch.set(responderRef, {
        ...responder,
        status: "PENDING",
        assignedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      responderIds.push(responder.caregiverId);

      await admin.messaging().send({
        topic: responder.caregiverId,
        notification: {
          title: "Emergency Alert",
          body: `${userName} needs urgent assistance.`,
        },
        data: {
          type: "SOS",
          sosId,
          userId,
        },
      });
    }

    batch.update(snap.ref, {
      status: "ALERT_SENT",
      responders: responderIds,
    });

    await batch.commit();
    return null;
  });


// =====================================================
// 5. CHAT NOTIFICATIONS
// =====================================================
exports.sendChatNotification = functions
  .region("us-central1")
  .firestore.document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot) => {
    const message = snapshot.data();
    if (!message) return null;

    const body = (message.text || "").toString().slice(0, 50);

    await admin.messaging().send({
      topic: message.receiverId,
      notification: {
        title: "New Message",
        body,
      },
    });

    return null;
  });


// =====================================================
// 6. AUTO ASSIGN CAREGIVER (BOOKING)
// =====================================================
exports.autoAssignCaregiver = functions.firestore
  .document("bookings/{bookingId}")
  .onCreate(async (snap, context) => {
    const booking = snap.data();
    if (!booking) return null;

    const userId = booking.userId;

    const caregiverSnap = await admin
      .firestore()
      .collection("caregivers")
      .where("availability", "==", true)
      .limit(1)
      .get();

    if (caregiverSnap.empty) return null;

    const caregiverDoc = caregiverSnap.docs[0];
    const caregiverId = caregiverDoc.id;
    const c = caregiverDoc.data() || {};

    const updates = {
      caregiverId,
      caregiverName: c.name || "Caregiver",
      caregiverPhoto: c.photoUrl || "",
      caregiverPhone: c.phone || "",
      status: "ASSIGNED",
    };

    const batch = admin.firestore().batch();

    batch.update(snap.ref, updates);

    batch.set(
      admin.firestore().collection("users").doc(userId).collection("bookings").doc(context.params.bookingId),
      { ...booking, ...updates }
    );

    batch.set(
      admin.firestore().collection("caregivers").doc(caregiverId).collection("assignedBookings").doc(context.params.bookingId),
      { ...booking, ...updates }
    );

    await batch.commit();

    await admin.messaging().send({
      topic: caregiverId,
      notification: {
        title: "New Job Assigned",
        body: "You have a new care assignment",
      },
    });

    return null;
  });


// =====================================================
// 7. TOYYIBPAY — CREATE BILL
// =====================================================
exports.createToyyibPayBill = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be logged in to create a payment."
      );
    }

    const secretKey = process.env.TOYYIBPAY_SECRET_KEY;
    const categoryCode = process.env.TOYYIBPAY_CATEGORY_CODE;

    const payload = {
      userSecretKey: secretKey,
      categoryCode,
      billName: data.billName || "ElderAssist Payment",
      billDescription: data.billDescription || "Service Payment",
      billPriceSetting: 1,
      billPayorInfo: 1,
      billAmount: (data.amount * 100).toString(),
      billReturnUrl: "https://elderassist.com/payment-success",
      billCallbackUrl: `https://us-central1-${process.env.FB_PROJECT_ID}.cloudfunctions.net/toyyibpayCallback`,
    };

    const res = await axios.post(
      "https://toyyibpay.com/index.php/api/createBill",
      payload
    );

    const billCode = res.data[0].BillCode;

    return {
      success: true,
      paymentUrl: `https://toyyibpay.com/${billCode}`,
      billCode,
      userId: context.auth.uid,
    };

  } catch (err) {
    console.error("ToyyibPay error:", err);
    throw new functions.https.HttpsError("unknown", err.message);
  }
});




// =====================================================
// 8. TOYYIBPAY CALLBACK
// =====================================================
exports.toyyibpayCallback = functions.https.onRequest(async (req, res) => {
  try {
    const billcode = req.query.billcode;
    const status = parseInt(req.query.status);

    await admin.firestore().collection("payments").doc(billcode).set(
      {
        status,
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
