// Sends a "go check now" push to a device via Firebase Cloud Messaging.
// Called only by the notify_lock_state_changed() Postgres trigger (see
// migrations/007_push_notifications.sql) — never by the app or website
// directly. Authenticated by a shared secret (not the Supabase service_role
// key) checked against the x-trigger-secret header, since this function is
// deployed with JWT verification off (Postgres triggers can't hold a user
// session to satisfy normal Supabase auth).
//
// Deliberately sends a DATA-ONLY message, no "notification" block: this
// guarantees the app's own code runs on receipt (onMessageReceived) even
// while backgrounded, instead of Android auto-displaying a generic system
// notification. The push carries no lock state of its own — it's purely a
// wake-up signal. The app always re-verifies via the same secure
// get_device_lock_state check the 15-minute background sync already uses,
// so a forged or stale push can't lie about lock state.

import { initializeApp, cert, getApps } from "npm:firebase-admin@12/app";
import { getMessaging } from "npm:firebase-admin@12/messaging";

const TRIGGER_SECRET = Deno.env.get("FCM_TRIGGER_SECRET") ?? "";
const SERVICE_ACCOUNT_JSON = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";

function getMessagingClient() {
  if (getApps().length === 0) {
    initializeApp({ credential: cert(JSON.parse(SERVICE_ACCOUNT_JSON)) });
  }
  return getMessaging();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const incomingSecret = req.headers.get("x-trigger-secret");
  if (!TRIGGER_SECRET || incomingSecret !== TRIGGER_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { fcm_token, device_label, should_be_locked } = await req.json();
  if (!fcm_token) {
    return new Response("Missing fcm_token", { status: 400 });
  }

  try {
    await getMessagingClient().send({
      token: fcm_token,
      data: {
        reason: "sync_now",
        device_label: String(device_label ?? ""),
        should_be_locked: String(should_be_locked ?? ""),
      },
      android: { priority: "high" },
    });
    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error("FCM send failed", err);
    return new Response("FCM send failed", { status: 500 });
  }
});
