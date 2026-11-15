// D04-T03 — offline admission draft ingest (REVIEW DRAFT, NOT DEPLOYED).
// Uses the trusted SQL function defined in DB04_OFFLINE_INGEST.sql.
// The client never supplies the actor identity: Supabase Auth verifies JWT.
// Only a registered campus desktop with a valid protected 32-byte credential
// may submit operations, and SQL checks CURRENT actor/campus permissions.
// No browser CORS or insecure JWT bypass is included.
import { createClient } from "jsr:@supabase/supabase-js@2.119.0";
import { Pool } from "jsr:@db/postgres@0.19.5";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const publicKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
  Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const databaseUrl = Deno.env.get("SUPABASE_DB_URL") ?? "";
if (!url || !publicKey || !databaseUrl) {
  throw new Error("Missing private offline ingest server configuration");
}
const authClient = createClient(url, publicKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});
const pool = new Pool(databaseUrl, 1, true);
type JsonObject = Record<string, unknown>;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const v4Pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function uuid(value: unknown, field: string, v4 = false): string {
  if (typeof value !== "string" || !(v4 ? v4Pattern : uuidPattern).test(value)) {
    throw new Error("Invalid " + field);
  }
  return value.toLowerCase();
}
function revision(value: unknown, optional = false): number | null {
  if (optional && (value === undefined || value === null)) return null;
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) {
    throw new Error("Invalid revision");
  }
  return value;
}
function jsonObject(value: unknown): JsonObject {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid payload");
  }
  return value as JsonObject;
}
function respond(status: number, body: JsonObject): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export default {
  fetch: async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return respond(405, { error: "POST required" });
    }
    const auth = request.headers.get("Authorization") ?? "";
    // A publishable/secret API key is NOT a signed-in user's access token.
    if (!/^Bearer [^\s]+$/.test(auth) || auth.length > 9000 ||
        auth.includes("sb_publishable_") || auth.includes("sb_secret_")) {
      return respond(401, { error: "Valid user session required" });
    }
    const proof = request.headers.get("X-Offline-Device-Proof") ?? "";
    if (!/^[0-9a-f]{64}$/i.test(proof)) {
      return respond(403, { error: "Device credential required" });
    }
    const { data, error } = await authClient.auth.getUser(auth.slice(7));
    if (error || !data.user?.id) {
      return respond(401, { error: "Invalid or expired user session" });
    }
    const actor = data.user.id; // NEVER accept actor from request JSON.

    let input: JsonObject;
    try {
      const raw = await request.text();
      if (raw.length > 12500) {
        return respond(413, { error: "Operation too large" });
      }
      input = jsonObject(JSON.parse(raw));
      if (input.action !== "ingest_offline_draft") {
        throw new Error("Invalid action");
      }
      if (input.expected_cloud_revision !== null &&
          input.expected_cloud_revision !== undefined) {
        // V1 supports only draft chains initially created on this device.
        throw new Error("Existing-cloud draft edits unsupported");
      }
    } catch {
      return respond(400, { error: "Invalid offline operation envelope" });
    }

    let conn;
    try {
      const operation = uuid(input.operation_id, "operation_id", true);
      const localId = uuid(input.local_application_id, "local_application_id", true);
      const school = uuid(input.school_id, "school_id");
      const campus = uuid(input.campus_id, "campus_id");
      const device = uuid(input.device_id, "device_id");
      const rev = revision(input.local_revision);
      const payload = jsonObject(input.payload);
      // The SQL function performs the AUTHORITATIVE scope, exact-envelope,
      // device proof and operation-replay checks. All values are parameterized.
      conn = await pool.connect();
      const result = await conn.queryObject<{ result: JsonObject }>(
        "select app_private.offline_ingest_admission_draft(" +
          "$1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text," +
          "$6::uuid,$7::uuid,$8::bigint,$9::bigint,$10::jsonb) as result",
        [
          actor, school, campus, device, proof, operation, localId,
          rev, null, JSON.stringify(payload),
        ],
      );
      if (!result.rows[0]?.result) {
        return respond(500, { error: "No operation receipt returned" });
      }
      return respond(200, { data: result.rows[0].result });
    } catch (e) {
      // Never disclose child name, device proof, DB credentials or query text.
      const code = e && typeof e === "object" && "code" in e
        ? String(e.code) : "";
      if (code === "42501") {
        return respond(403, { error: "Actor or device not authorized" });
      }
      if (code === "40001" || code === "23505") {
        return respond(409, { error: "Offline operation conflict or duplicate" });
      }
      if (["22023", "22P02", "22007", "23503", "23514"].includes(code)) {
        return respond(422, { error: "Invalid offline operation" });
      }
      if (e instanceof Error && e.message.startsWith("Invalid")) {
        return respond(400, { error: "Invalid offline operation" });
      }
      return respond(500, { error: "Offline ingest failed" });
    } finally {
      conn?.release();
    }
  },
};
