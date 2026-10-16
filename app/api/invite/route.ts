import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return NextResponse.json({ error: "Server environment variables are missing. Set the Supabase URL, anon key and service-role key in your hosting settings." }, { status: 500 });
  }

  const cookieStore = await cookies();
  const sessionClient = createServerClient(supabaseUrl, anonKey, {
    cookies: {
      getAll() { return cookieStore.getAll(); },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
      },
    },
  });
  const { data: { user }, error: userError } = await sessionClient.auth.getUser();
  if (userError || !user) return NextResponse.json({ error: "Sign in is required." }, { status: 401 });

  const admin = createClient(supabaseUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: currentMember, error: memberError } = await admin.from("app_members").select("role").eq("user_id", user.id).maybeSingle();
  if (memberError || currentMember?.role !== "admin") return NextResponse.json({ error: "Only an admin can invite teammates." }, { status: 403 });

  let body: { email?: string; role?: string };
  try { body = await request.json(); } catch { return NextResponse.json({ error: "Invalid request body." }, { status: 400 }); }
  const email = String(body.email || "").trim().toLowerCase();
  const role = body.role === "editor" ? "editor" : "viewer";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });

  const origin = new URL(request.url).origin;
  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo: `${origin}/auth/callback` });
  if (inviteError) return NextResponse.json({ error: inviteError.message }, { status: 400 });
  if (!invited.user) return NextResponse.json({ error: "Supabase did not return the invited user." }, { status: 500 });

  const { error: roleError } = await admin.from("app_members").upsert({
    user_id: invited.user.id,
    email,
    role,
    invited_by: user.id,
  }, { onConflict: "user_id" });
  if (roleError) return NextResponse.json({ error: `Invite sent, but role setup failed: ${roleError.message}` }, { status: 500 });

  return NextResponse.json({ ok: true, email, role, message: `Invitation sent to ${email}.` });
}
