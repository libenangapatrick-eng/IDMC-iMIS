import { createClient, SupabaseClient } from "@supabase/supabase-js";
import { env } from "./env.js";

let supabase: SupabaseClient | null = null;

if (env.SUPABASE_URL && env.SUPABASE_SERVICE_ROLE_KEY) {
  supabase = createClient(
    env.SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
}

export function getSupabase(): SupabaseClient {
  if (!supabase) {
    throw new Error(
      "Supabase is not configured. Add SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to .env"
    );
  }

  return supabase;
}

/*
 * Password sign-in must never run on the shared service-role client. A login
 * creates a user session, which could otherwise replace the credentials used
 * by later privileged database queries. Create a short-lived public client for
 * every login request and keep the admin client session-free.
 */
export function createLoginClient(): SupabaseClient {
  return createClient(
    env.SUPABASE_URL,
    env.SUPABASE_PUBLISHABLE_KEY,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    }
  );
}

