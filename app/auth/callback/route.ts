import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type");
  const cookieStore = await cookies();
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  let authError: string | null = null;
  if (supabaseUrl && supabaseKey && (code || (tokenHash && type === "invite"))) {
    const supabase = createServerClient(supabaseUrl, supabaseKey, {
      cookies: {
        getAll() { return cookieStore.getAll(); },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
        },
      },
    });

    if (code) {
      const { error } = await supabase.auth.exchangeCodeForSession(code);
      if (error) authError = error.message;
    } else if (tokenHash && type === "invite") {
      // App-generated invite URLs verify the token hash server-side, so the new
      // session is persisted into the SSR cookies before redirecting to the app.
      const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: "invite" });
      if (error) authError = error.message;
    }
  }

  const destination = authError
    ? new URL("/?invite_error=invalid_or_expired", url.origin)
    : new URL("/", url.origin);
  return NextResponse.redirect(destination);
}
