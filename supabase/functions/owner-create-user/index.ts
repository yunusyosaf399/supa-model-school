// DB12: Owner creates staff login credentials; no invitation email.
// The service credential exists only in this Edge Function runtime.
import { createClient } from "npm:@supabase/supabase-js@2.58.0";

const allowedRoles = new Set([
  "principal", "vice_principal", "admin", "accountant", "hr", "teacher",
  "coordinator", "librarian", "transport_manager", "driver", "nurse",
  "store_keeper", "security_guard", "parent", "attendance_staff",
]);
const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") return response(405, { error: "Method not allowed" });
  const token = request.headers.get("authorization")?.match(/^Bearer (\S+)$/i)?.[1];
  if (!token || token.startsWith("sb_")) {
    return response(401, { error: "Verified Owner session required" });
  }
  const url = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serverKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publicKey || !serverKey) {
    return response(503, { error: "Staff account creation unavailable" });
  }

  let data: Record<string, unknown>;
  try {
    if ((Number(request.headers.get("content-length")) || 0) > 8192) {
      return response(413, { error: "Account request is too large" });
    }
    const raw = await request.text();
    if (raw.length > 8192) return response(413, { error: "Account request is too large" });
    const json: unknown = JSON.parse(raw);
    if (!json || typeof json !== "object" || Array.isArray(json)) {
      return response(400, { error: "Invalid account request" });
    }
    data = json as Record<string, unknown>;
  } catch {
    return response(400, { error: "Invalid account request" });
  }

  const school = typeof data.school_id === "string" ? data.school_id : "";
  const campus = typeof data.campus_id === "string" ? data.campus_id : "";
  const role = typeof data.role === "string" ? data.role : "";
  const email = typeof data.email === "string" ? data.email.trim().toLowerCase() : "";
  const name = typeof data.name === "string" ? data.name.trim() : "";
  const password = typeof data.password === "string" ? data.password : "";
  if (!idPattern.test(school) || !idPattern.test(campus) ||
      !allowedRoles.has(role) || name.length < 2 || name.length > 120 ||
      email.length > 254 || !emailPattern.test(email) ||
      password.length < 12 || password.length > 128 ||
      password.trim() !== password ||
      !/[A-Za-z]/.test(password) || !/\d/.test(password)) {
    return response(400, { error: "Invalid school, campus, role, email or initial password" });
  }

  const caller = createClient(url, publicKey, {
    global: { headers: { Authorization: "Bearer " + token } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: identity, error: identityError } = await caller.auth.getUser(token);
  if (identityError || !identity.user?.id || !identity.user.email_confirmed_at) {
    return response(401, { error: "Verified Owner authentication required" });
  }
  const { data: permitted, error: permissionError } =
    await caller.rpc("owner_user_invite_preflight", {
      p_school: school,
      p_campus: campus,
      p_role: role,
    });
  if (permissionError || permitted?.eligible !== true) {
    return response(403, { error: "School Owner or campus authorization denied" });
  }

  const admin = createClient(url, serverKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  // Admin createUser creates this account directly and confirms its email.
  // There is no invite/password email, no client signUp, and no Owner password
  // persistence outside the transient request and Supabase Auth.
  const { data: created, error: creationError } =
    await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
  if (creationError || !created.user?.id) {
    // Account-existence details are intentionally not disclosed.
    return response(409, { error: "Could not create staff account. The email may already be in use." });
  }

  const userId = created.user.id;
  const { data: assigned, error: assignmentError } =
    await admin.rpc("server_register_created_user", {
      p_actor: identity.user.id,
      p_target: userId,
      p_school: school,
      p_campus: campus,
      p_role: role,
      p_display_name: name,
      p_expected_email: email,
    });
  if (assignmentError || assigned?.status !== "created") {
    // This ID is from a successful createUser call (not a lookup/existing
    // account). Remove the just-created credential if school-role registration
    // fails so a partial user does not retain an unassigned login.
    const { error: cleanupError } = await admin.auth.admin.deleteUser(userId);
    if (cleanupError) {
      console.error("DB12 orphaned new Auth identity needs administrator cleanup");
    }
    return response(500, {
      error: "Staff account could not be completed. Contact school administrator.",
    });
  }
  return response(201, {
    status: "created",
    role_id: assigned.role_id,
    user_id: assigned.user_id,
    role: assigned.role,
  });
});
