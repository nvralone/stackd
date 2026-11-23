// Sign in with username + password. Runs on Supabase (server side) so the email that belongs to a
// username never reaches anyone's device. Returns a normal Supabase session on success.
// Deploy with "Verify JWT" OFF (people call it before they are signed in).
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// New-style API keys are provided as JSON maps; fall back to the legacy single keys.
function key(jsonVar: string, legacyVar: string): string {
  const raw = Deno.env.get(jsonVar);
  if (raw) {
    try {
      const v = JSON.parse(raw);
      const first = typeof v === "string" ? v : (v.default ?? Object.values(v)[0]);
      if (typeof first === "string" && first) return first;
    } catch { /* not JSON */ }
  }
  return Deno.env.get(legacyVar) ?? "";
}

const WRONG = "Wrong username or password.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let body: { username?: unknown; password?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: WRONG }, 400);
  }
  const username = String(body.username ?? "").trim().toLowerCase();
  const password = typeof body.password === "string" ? body.password : "";
  if (!/^[a-z0-9_.]{3,20}$/.test(username) || password.length < 6) return json({ error: WRONG }, 400);

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, key("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: profile } = await admin.from("profiles").select("user_id").eq("username", username).maybeSingle();
  if (!profile) return json({ error: WRONG }, 400);
  const { data: u, error: ue } = await admin.auth.admin.getUserById(profile.user_id);
  if (ue || !u?.user?.email) return json({ error: WRONG }, 400);

  const pub = createClient(url, key("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await pub.auth.signInWithPassword({ email: u.user.email, password });
  if (error || !data.session) return json({ error: WRONG }, 400);
  return json({ refresh_token: data.session.refresh_token });
});
