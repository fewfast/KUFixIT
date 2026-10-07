import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyTemporarySession } from "../_shared/credentials.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version, x-avatar-action",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const maxFileSize = 5 * 1024 * 1024;
const allowedImageTypes = new Set([
  "image/gif",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

type ProfileIdentity = { id: string; role: string };

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isImageContent(type: string, bytes: Uint8Array): boolean {
  if (type === "image/png") {
    return bytes.length >= 8 &&
      bytes[0] === 0x89 &&
      bytes[1] === 0x50 &&
      bytes[2] === 0x4e &&
      bytes[3] === 0x47 &&
      bytes[4] === 0x0d &&
      bytes[5] === 0x0a &&
      bytes[6] === 0x1a &&
      bytes[7] === 0x0a;
  }
  if (type === "image/jpeg") {
    return bytes.length >= 3 &&
      bytes[0] === 0xff &&
      bytes[1] === 0xd8 &&
      bytes[2] === 0xff;
  }
  if (type === "image/gif") {
    const signature = new TextDecoder().decode(bytes.subarray(0, 6));
    return signature === "GIF87a" || signature === "GIF89a";
  }
  if (type === "image/webp") {
    return bytes.length >= 12 &&
      new TextDecoder().decode(bytes.subarray(0, 4)) === "RIFF" &&
      new TextDecoder().decode(bytes.subarray(8, 12)) === "WEBP";
  }
  return false;
}

async function getProfileIdentity(
  token: string,
  serviceClient: SupabaseClient,
  signingSecret: string,
): Promise<ProfileIdentity | null> {
  const claims = await verifyTemporarySession(token, signingSecret);
  if (
    claims &&
    typeof claims.sub === "string" &&
    /^\d{1,19}$/.test(claims.sub) &&
    (claims.role === "User" || claims.role === "Admin")
  ) {
    return { id: claims.sub, role: claims.role };
  }

  const { data, error } = await serviceClient.auth.getUser(token);
  if (error || !data.user) return null;
  const role = data.user.app_metadata.role;
  if (role != null && role !== "User" && role !== "Admin") return null;
  return { id: data.user.id, role: role ?? "User" };
}

async function ensureUserBucket(
  serviceClient: SupabaseClient,
  userId: string,
): Promise<boolean> {
  const { data: buckets, error: listError } = await serviceClient.storage
    .listBuckets();
  if (listError) throw listError;
  if (buckets.some((bucket) => bucket.id === userId)) return false;

  const { error: createError } = await serviceClient.storage.createBucket(
    userId,
    {
      public: false,
      fileSizeLimit: maxFileSize,
      allowedMimeTypes: [...allowedImageTypes],
    },
  );
  if (!createError) return true;

  const { data: latestBuckets, error: verifyError } = await serviceClient.storage
    .listBuckets();
  if (verifyError) throw verifyError;
  if (latestBuckets.some((bucket) => bucket.id === userId)) return false;
  throw createError;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Supabase server configuration is missing.");
    return jsonResponse(500, { error: "Profile image service is not configured." });
  }

  const token = request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)
    ?.[1];
  if (!token) {
    return jsonResponse(401, { error: "Please sign in again to manage your profile image." });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const identity = await getProfileIdentity(token, serviceClient, serviceRoleKey);
  if (!identity) {
    return jsonResponse(401, { error: "Please sign in again to manage your profile image." });
  }

  const action = request.headers.get("x-avatar-action");
  if (action === "get") {
    const { data: buckets, error: listError } = await serviceClient.storage
      .listBuckets();
    if (listError) {
      console.error("Failed to list profile image buckets.", listError);
      return jsonResponse(500, { error: "Profile image could not be loaded." });
    }
    if (!buckets.some((bucket) => bucket.id === identity.id)) {
      return jsonResponse(200, { url: null });
    }

    const { data: files, error: filesError } = await serviceClient.storage
      .from(identity.id)
      .list("", { limit: 100, search: "avatar" });
    if (filesError) {
      console.error("Failed to find profile image.", filesError);
      return jsonResponse(500, { error: "Profile image could not be loaded." });
    }
    if (!files.some((file) => file.name === "avatar")) {
      return jsonResponse(200, { url: null });
    }

    const { data, error: signedUrlError } = await serviceClient.storage
      .from(identity.id)
      .createSignedUrl("avatar", 3600);
    if (signedUrlError) {
      console.error("Failed to sign profile image URL.", signedUrlError);
      return jsonResponse(500, { error: "Profile image could not be loaded." });
    }
    return jsonResponse(200, { url: data.signedUrl });
  }

  if (action !== "upload") {
    return jsonResponse(400, { error: "Invalid profile image action." });
  }

  const contentType = request.headers.get("content-type")?.split(";")[0]
    .trim().toLowerCase() ?? "";
  if (!allowedImageTypes.has(contentType)) {
    return jsonResponse(400, { error: "Choose a PNG, JPG, WEBP, or GIF image." });
  }
  const contentLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > maxFileSize) {
    return jsonResponse(413, { error: "Profile images must be 5 MB or smaller." });
  }

  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length === 0 || bytes.length > maxFileSize) {
    return jsonResponse(413, { error: "Profile images must be 5 MB or smaller." });
  }
  if (!isImageContent(contentType, bytes)) {
    return jsonResponse(400, { error: "The selected file is not a valid image." });
  }

  try {
    await ensureUserBucket(serviceClient, identity.id);
  } catch (error) {
    console.error("Failed to create profile image bucket.", error);
    return jsonResponse(500, { error: "Profile image storage could not be prepared." });
  }

  const bucket = serviceClient.storage.from(identity.id);
  const { error: removeError } = await bucket.remove(["avatar"]);
  if (removeError) {
    console.error("Failed to remove previous profile image.", removeError);
    return jsonResponse(500, { error: "Previous profile image could not be replaced." });
  }
  const { error: uploadError } = await bucket.upload("avatar", bytes, {
    contentType,
    upsert: true,
  });
  if (uploadError) {
    console.error("Failed to upload profile image.", uploadError);
    return jsonResponse(500, { error: "Profile image could not be uploaded." });
  }
  const { data, error: signedUrlError } = await bucket.createSignedUrl(
    "avatar",
    3600,
  );
  if (signedUrlError) {
    console.error("Failed to sign uploaded profile image URL.", signedUrlError);
    return jsonResponse(500, { error: "Profile image was uploaded but could not be displayed." });
  }
  return jsonResponse(200, { url: data.signedUrl });
});
