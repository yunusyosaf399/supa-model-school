// D03-T03 — authenticated admission API. REVIEW DRAFT: NOT DEPLOYED.
// Requires DB01, DB02, DB02_WORKFLOW_SCHEMA, DB02_ADMISSION_OPERATIONS.
// Auth identity comes ONLY from Supabase Auth getUser(jwt), not request JSON.
// SUPABASE_DB_URL must remain a server-side secret. Never expose app_private.
import { createClient } from "jsr:@supabase/supabase-js@2.119.0";
import { Pool } from "jsr:@db/postgres@0.19.5";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const publicKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
  Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const databaseUrl = Deno.env.get("SUPABASE_DB_URL") ?? "";
if (!url || !publicKey || !databaseUrl) {
  throw new Error("Missing server-side admission environment");
}
const authClient = createClient(url, publicKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});
const pool = new Pool(databaseUrl, 1, true);
type Input = Record<string, unknown>;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function getUuid(v: unknown, required = true): string | null {
  if (v === undefined || v === null) {
    if (required) throw new Error("Missing UUID");
    return null;
  }
  if (typeof v !== "string" || !uuidPattern.test(v)) throw new Error("Invalid UUID");
  return v;
}
function getText(v: unknown, max = 200): string | null {
  if (v === null || v === undefined) return null;
  if (typeof v !== "string" || v.length > max) throw new Error("Invalid text");
  return v.trim() || null;
}
function getDate(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) {
    throw new Error("Invalid date");
  }
  return v; // PostgreSQL checks real calendar dates.
}
function getRevision(v: unknown, required = true): number | null {
  if (v === null || v === undefined) {
    if (required) throw new Error("Missing revision");
    return null;
  }
  if (typeof v !== "number" || !Number.isSafeInteger(v) || v < 1) {
    throw new Error("Invalid revision");
  }
  return v;
}
function getGuardians(v: unknown): string {
  if (!Array.isArray(v) || v.length > 8) throw new Error("Invalid guardians");
  const clean = v.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error("Invalid guardian");
    }
    const g = item as Input;
    const name = getText(g.full_name, 200);
    const relationship = getText(g.relationship, 20);
    if (!name || name.length < 2 ||
      !["father", "mother", "guardian", "other"].includes(relationship ?? "") ||
      typeof g.is_primary !== "boolean" ||
      (g.is_legal_guardian !== undefined && typeof g.is_legal_guardian !== "boolean")) {
      throw new Error("Invalid guardian details");
    }
    return {
      full_name: name, relationship,
      phone: getText(g.phone, 80),
      is_primary: g.is_primary,
      is_legal_guardian: g.is_legal_guardian ?? false,
      existing_guardian_id: getUuid(g.existing_guardian_id, false),
    };
  });
  return JSON.stringify(clean);
}
function respond(status: number, body: Record<string, unknown>): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
  });
}
export default {
  fetch: async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return respond(405, { error: "POST required" });
    const auth = request.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ") || auth.length > 9000) {
      return respond(401, { error: "Authentication required" });
    }
    // Fresh Auth API check: a decoded JWT is not sufficient.
    const { data, error } = await authClient.auth.getUser(auth.slice(7).trim());
    if (error || !data.user?.id) return respond(401, { error: "Invalid session" });
    const actor = data.user.id;

    let input: Input;
    try {
      const raw = await request.text();
      if (raw.length > 50000) return respond(413, { error: "Payload too large" });
      const parsed: unknown = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        throw new Error("Invalid request");
      }
      input = parsed as Input;
    } catch {
      return respond(400, { error: "Invalid JSON object" });
    }
    let conn;
    try {
      const action = input.action;
      if (!["save_draft", "submit", "review"].includes(String(action))) {
        return respond(400, { error: "Unknown action" });
      }
      conn = await pool.connect();
      if (action === "save_draft") {
        const updating = input.application_id !== null && input.application_id !== undefined;
        const r = await conn.queryObject<{ result: string }>(
          "select app_private.admission_save_draft($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::bigint,$7::uuid,$8::text,$9::date,$10::text,$11::uuid,$12::uuid,$13::jsonb) as result",
          [actor, getUuid(input.school_id), getUuid(input.campus_id),
           getUuid(input.academic_year_id), getUuid(input.application_id, false),
           getRevision(input.expected_revision, updating), getUuid(input.operation_id),
           getText(input.name), getDate(input.date_of_birth),
           getText(input.previous_school), getUuid(input.class_id, false),
           getUuid(input.section_id, false), getGuardians(input.guardians)],
        );
        return respond(200, { application_id: r.rows[0]?.result });
      }
      if (action === "submit") {
        const r = await conn.queryObject<{ result: unknown }>(
          "select app_private.admission_submit($1::uuid,$2::uuid,$3::bigint,$4::uuid,$5::date,$6::text) as result",
          [actor, getUuid(input.application_id), getRevision(input.expected_revision),
           getUuid(input.operation_id), getDate(input.conditional_due_on),
           getText(input.conditional_reason, 2000)],
        );
        return respond(200, { data: r.rows[0]?.result });
      }
      const decision = getText(input.decision, 20);
      if (!["approve", "return", "reject"].includes(decision ?? "")) {
        return respond(400, { error: "Invalid decision" });
      }
      const r = await conn.queryObject<{ result: unknown }>(
        "select app_private.admission_review($1::uuid,$2::uuid,$3::bigint,$4::uuid,$5::text,$6::text) as result",
        [actor, getUuid(input.application_id), getRevision(input.expected_revision),
         getUuid(input.operation_id), decision, getText(input.reason, 2000)],
      );
      return respond(200, { data: r.rows[0]?.result });
    } catch (e) {
      // Never expose child data, user details, JWT, or database connection data.
      const code = e && typeof e === "object" && "code" in e ? String(e.code) : "";
      if (code === "42501") return respond(403, { error: "Not authorized" });
      if (["40001", "23505"].includes(code)) {
        return respond(409, { error: "Conflict or possible duplicate" });
      }
      if (["23503", "23514", "22023", "22P02"].includes(code)) {
        return respond(422, { error: "Invalid admission data" });
      }
      if (e instanceof Error && (e.message.startsWith("Invalid") ||
                                 e.message.startsWith("Missing"))) {
        return respond(400, { error: "Invalid or missing fields" });
      }
      return respond(500, { error: "Admission operation failed" });
    } finally {
      conn?.release();
    }
  },
};
