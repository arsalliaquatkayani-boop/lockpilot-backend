// Called only from the LockPilot master admin dashboard's "Add shop" form.
// Creates the owner's auth account via Supabase's admin API and emails them
// Supabase's own invite link to set their own password — we never generate
// or see a plaintext password ourselves. The handle_new_shop_signup trigger
// (migrations/011) then provisions the shop + owner staff row automatically
// once the invited user's auth.users row lands.
//
// Requires the CALLER to already be signed in as a platform_admin — the
// service_role key below only ever runs inside this function, never in the
// browser, and Supabase injects it automatically (no manual secret setup).

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const callerToken = authHeader.replace("Bearer ", "");
  if (!callerToken) {
    return new Response("Missing authorization", { status: 401 });
  }

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: callerData, error: callerError } = await adminClient.auth.getUser(callerToken);
  if (callerError || !callerData.user) {
    return new Response("Invalid session", { status: 401 });
  }

  const { data: adminRow } = await adminClient
    .from("platform_admins")
    .select("id")
    .eq("id", callerData.user.id)
    .maybeSingle();

  if (!adminRow) {
    return new Response("Forbidden — not a platform admin", { status: 403 });
  }

  const { shopName, shopPhone, ownerFullName, ownerEmail } = await req.json();
  if (!shopName || !ownerFullName || !ownerEmail) {
    return new Response("Missing required fields", { status: 400 });
  }

  const { data: inviteData, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
    ownerEmail,
    {
      data: {
        shop_name: shopName,
        shop_phone: shopPhone ?? "",
        full_name: ownerFullName,
      },
    },
  );

  if (inviteError) {
    return new Response(JSON.stringify({ error: inviteError.message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ userId: inviteData.user?.id }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
