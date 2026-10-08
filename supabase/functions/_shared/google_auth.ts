import {
  type SupabaseClient,
  type User,
} from "https://esm.sh/@supabase/supabase-js@2";

export function bearerToken(request: Request): string | null {
  return request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1] ??
    null;
}

export async function verifyGoogleUser(
  client: SupabaseClient,
  token: string,
): Promise<User | null> {
  const { data, error } = await client.auth.getUser(token);
  if (error) {
    console.error("Failed to verify the Supabase Auth session.", error);
    return null;
  }
  if (!data.user) return null;

  const hasGoogleIdentity = data.user.app_metadata.provider === "google" ||
    data.user.identities?.some((identity) => identity.provider === "google");
  return hasGoogleIdentity ? data.user : null;
}
