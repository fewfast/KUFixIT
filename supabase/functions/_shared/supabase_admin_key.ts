export function getSupabaseAdminKey(): string | undefined {
  const secretKeysJson = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (secretKeysJson) {
    const secretKeys: unknown = JSON.parse(secretKeysJson);
    if (
      typeof secretKeys !== "object" ||
      secretKeys === null ||
      Array.isArray(secretKeys)
    ) {
      throw new Error("SUPABASE_SECRET_KEYS must be a JSON object.");
    }

    const defaultKey = (secretKeys as Record<string, unknown>).default;
    if (typeof defaultKey === "string" && defaultKey.length > 0) {
      return defaultKey;
    }
  }

  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || undefined;
}
