// DB11 Owner-managed Auth invitations.
// The client only sends name/email/role/campus. Admin credentials never
// leave the Edge Function environment.
import { createClient } from "npm:@supabase/supabase-js@2.58.0";

type InvitePayload = {
  school_id: string;
  campus_id: string;
  role: string;
  email: string;
  name: string;
};

const allowed = new Set([
  "principal", "vice_principal", "admin", "accountant", "hr", "teacher",
  "coordinator", "librarian", "transport_manager", "driver", "nurse",
  "store_keeper", "security_guard", "parent", "attendance_staff",
]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
  const token = req.headers.get("authorization")?.match(/^Bearer (\S+)$/i)?.[1];
  if (!token || token.startsWith("sb_")) {
    return reply(401, { error: "Signed-in school Owner required" });
  }
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !secret) {
    return reply(503, { error: "User invitation service is not configured" });
  }
  let payload: InvitePayload;
  try {
    if ((Number(req.headers.get("content-length")) || 0) > 4096) {
      return reply(413, { error: "Request exceeds allowed size" });
    }
    const raw = await req.text();
    if (raw.length > 4096) return reply(413, { error: "Request exceeds allowed size" });
    payload = JSON.parse(raw) as InvitePayload;
    if (!payload || typeof payload !== "object") throw Error("Bad payload");
  } catch {
    return reply(400, { error: "Invalid invitation request" });
  }
  const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : "";
  const name = typeof payload.name === "string" ? payload.name.trim() : "";
  if (!uuid.test(payload.school_id || "") || !uuid.test(payload.campus_id || "") ||
      !allowed.has(payload.role) || name.length < 2 || name.length > 120 ||
      email.length > 254 || !emailPattern.test(email)) {
    return reply(400, { error: "Invalid name, email, campus or role" });
  }

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: "Bearer " + token } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: identity, error: identityError } = await caller.auth.getUser(token);
  if (identityError || !identity.user?.id || !identity.user.email_confirmed_at) {
    return reply(401, { error: "Verified Owner authentication required" });
  }
  const { data: eligible, error: authorizationError } =
    await caller.rpc("owner_user_invite_preflight", {
      p_school: payload.school_id,
      p_campus: payload.campus_id,
      p_role: payload.role,
    });
  if (authorizationError || eligible?.eligible !== true) {
    return reply(403, { error: "Owner role or campus authorization denied" });
  }

  const administrator = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: invitation, error: invitationError } =
    await administrator.auth.admin.inviteUserByEmail(email);
  if (invitationError || !invitation.user?.id) {
    // Avoid disclosing whether another user's email exists.
    return reply(409, {
      error: "Invitation was not accepted. Check email configuration or use another address.",
    });
  }

  // This RPC is service_role-only, and independently rechecks the verified
  // Owner, target Auth email, campus and role in a single SQL transaction.
  const { data: assigned, error: assignmentError } =
    await administrator.rpc("server_register_invited_user", {
      p_actor: identity.user.id,
      p_target: invitation.user.id,
      p_school: payload.school_id,
      p_campus: payload.campus_id,
      p_role: payload.role,
      p_display_name: name,
      p_expected_email: email,
    });
  if (assignmentError || assigned?.status !== "invited") {
    // Never delete the returned Auth identity automatically: inviteUserByEmail
    // does not attest that it was freshly created vs existing; deleting an
    // existing user would be catastrophic. The account has no school role.
    console.error("DB11 role assignment failed", assignmentError?.code || "unexpected result");
    return reply(500, {
      error: "Invitation sent, but school role could not be assigned. Contact administrator.",
    });
  }
  return reply(201, {
    status: "invited",
    role_id: assigned.role_id,
    user_id: assigned.user_id,
    role: assigned.role,
  });
});
