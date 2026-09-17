// Called only from the LockPilot master admin dashboard's "Add shop" form.
// Creates the owner's auth account via Supabase's admin API, emails them
// Supabase's own invite link to set their own password (we never generate
// or see a plaintext password ourselves), then inserts the shop + owner
// staff row itself using the service_role client.
//
// Deliberately does NOT rely on a database trigger keyed off the new
// user's metadata for this — that metadata can be set by anyone calling
// Supabase's public signUp() API directly, which would let a stranger
// create themselves a free shop with no admin involved at all. Doing the
// insert here instead means only a request that passes the platform_admin
// check below can ever create a shop.
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
    { data: { full_name: ownerFullName } },
  );

  if (inviteError || !inviteData.user) {
    return new Response(JSON.stringify({ error: inviteError?.message ?? "Invite failed" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const newUserId = inviteData.user.id;

  const { data: newShop, error: shopError } = await adminClient
    .from("shops")
    .insert({ name: shopName, phone: shopPhone ?? null })
    .select()
    .single();

  if (shopError || !newShop) {
    await adminClient.auth.admin.deleteUser(newUserId);
    return new Response(JSON.stringify({ error: shopError?.message ?? "Could not create shop" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { error: staffError } = await adminClient.from("staff").insert({
    id: newUserId,
    shop_id: newShop.id,
    full_name: ownerFullName,
    email: ownerEmail,
    role: "owner",
  });

  if (staffError) {
    await adminClient.auth.admin.deleteUser(newUserId);
    await adminClient.from("shops").delete().eq("id", newShop.id);
    return new Response(JSON.stringify({ error: staffError.message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ userId: newUserId, shopId: newShop.id }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
