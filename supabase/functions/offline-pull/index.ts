// D04-T04 — campus-scoped, cursor-paginated admission change pull.
// REVIEW-ONLY: depends on undeployed DB04_CHANGE_FEED.sql / D04-T03.
// Never deploy with verify_jwt disabled. No browser CORS, no financial data.
import { createClient } from "jsr:@supabase/supabase-js@2.119.0";
import { Pool } from "jsr:@db/postgres@0.19.5";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const publicKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
  Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const databaseUrl = Deno.env.get("SUPABASE_DB_URL") ?? "";
if (!url || !publicKey || !databaseUrl) {
  throw new Error("Missing private offline pull server configuration");
}

const authClient = createClient(url, publicKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
});
const pool = new Pool(databaseUrl, 1, true);
type JsonObject = Record<string, unknown>;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const cursorPattern = /^(?:0|[1-9][0-9]{0,18})$/;
const maxInt64 = 9223372036854775807n;

function uuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new Error("Invalid " + field);
  }
  return value.toLowerCase();
}
function decimalCursor(value: unknown): string {
  // Sending bigint cursors as JSON numbers is not safe in JavaScript.
  if (typeof value !== "string" || !cursorPattern.test(value) ||
      BigInt(value) > maxInt64) {
    throw new Error("Invalid after_cursor");
  }
  return value;
}
function jsonObject(value: unknown): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid JSON object");
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
    if (!/^Bearer [^\s]+$/.test(auth) || auth.length > 9000 ||
        auth.includes("sb_publishable_") || auth.includes("sb_secret_")) {
      return respond(401, { error: "Valid user session required" });
    }
    const proof = request.headers.get("X-Offline-Device-Proof") ?? "";
    if (!/^[0-9a-f]{64}$/i.test(proof)) {
      return respond(403, { error: "Device credential required" });
    }
    // An already-issued JWT may be stale. Ask Auth for the CURRENT user.
    const { data, error } = await authClient.auth.getUser(auth.slice(7));
    if (error || !data.user?.id) {
      return respond(401, { error: "Invalid or expired user session" });
    }
    const actor = data.user.id; // Never accept an actor_id from the request.

    let input: JsonObject;
    try {
      const raw = await request.text();
      if (raw.length > 4096) return respond(413, { error: "Request too large" });
      input = jsonObject(JSON.parse(raw));
      const allowed = new Set([
        "action", "school_id", "campus_id", "device_id",
        "after_cursor", "page_size",
      ]);
      if (Object.keys(input).some((k) => !allowed.has(k)) ||
          input.action !== "pull_admission_changes") {
        throw new Error("Invalid action or fields");
      }
    } catch {
      return respond(400, { error: "Invalid change feed request" });
    }

    let conn;
    try {
      const school = uuid(input.school_id, "school_id");
      const campus = uuid(input.campus_id, "campus_id");
      const device = uuid(input.device_id, "device_id");
      const after = decimalCursor(input.after_cursor);
      const pageSize = input.page_size ?? 100;
      if (typeof pageSize !== "number" ||
          !Number.isSafeInteger(pageSize) ||
          pageSize < 1 || pageSize > 100) {
        throw new Error("Invalid page_size");
      }

      // SQL does all AUTHORIZATION and CAMPUS FILTERING server-side,
      // with the same registered-device proof as offline-ingest.
      conn = await pool.connect();
      const result = await conn.queryObject<{ result: JsonObject }>(
        "select app_private.offline_pull_admission_changes(" +
          "$1::uuid,$2::uuid,$3::uuid,$4::uuid," +
          "$5::text,$6::bigint,$7::integer) as result",
        [actor, school, campus, device, proof, after, pageSize],
      );
      if (!result.rows[0]?.result) {
        return respond(500, { error: "Change feed unavailable" });
      }
      return respond(200, { data: result.rows[0].result });
    } catch (e) {
      // Never include child name, guardian, raw payload or device proof in errors.
      const code = e && typeof e === "object" && "code" in e
        ? String(e.code) : "";
      if (code === "42501") {
        return respond(403, { error: "Not authorized for campus feed" });
      }
      if (["22023", "22P02", "22003"].includes(code)) {
        return respond(422, { error: "Invalid cursor or change feed request" });
      }
      if (e instanceof Error && e.message.startsWith("Invalid")) {
        return respond(400, { error: "Invalid change feed request" });
      }
      return respond(500, { error: "Change feed failed" });
    } finally {
      conn?.release();
    }
  },
};
