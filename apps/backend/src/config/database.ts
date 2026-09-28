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
 * Never sign an end user in through the shared service-role client above.
 * Supabase Auth attaches the returned user session to that client in memory,
 * which would make later database queries run under the user's RLS context.
 * A disposable client keeps the administrative database client immutable.
 */
export function createSupabaseAuthClient(): SupabaseClient {
  return createClient(
    env.SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    }
  );
}
