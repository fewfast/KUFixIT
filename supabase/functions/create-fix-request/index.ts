import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyTemporarySession } from "../_shared/credentials.ts";
import { getSupabaseAdminKey } from "../_shared/supabase_admin_key.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const bytesPerDevice = 2 * 1024 * 1024;
const allowedImageTypes = new Set([
  "image/gif",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

type RepairDevice = {
  device: string;
  description: string | null;
  floor: string | null;
  room: string | null;
  photo: { contentType: string; bytes: Uint8Array } | null;
};

type DeviceParseResult =
  | { devices: RepairDevice[]; error: null }
  | { devices: null; error: string };

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function detectImageContentType(bytes: Uint8Array): string | null {
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) {
    return "image/png";
  }
  if (
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) {
    return "image/jpeg";
  }
  if (bytes.length >= 6) {
    const gifSignature = new TextDecoder().decode(bytes.subarray(0, 6));
    if (gifSignature === "GIF87a" || gifSignature === "GIF89a") {
      return "image/gif";
    }
  }
  if (
    bytes.length >= 12 &&
    new TextDecoder().decode(bytes.subarray(0, 4)) === "RIFF" &&
    new TextDecoder().decode(bytes.subarray(8, 12)) === "WEBP"
  ) {
    return "image/webp";
  }
  return null;
}

function optionalText(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") throw new Error("Invalid optional text field.");
  return value.trim() || null;
}

function parseDevices(value: unknown): DeviceParseResult {
  if (!Array.isArray(value) || value.length === 0) {
    return { devices: null, error: "At least one equipment item is required." };
  }
  const devices: RepairDevice[] = [];
  let totalPhotoBytes = 0;

  for (const rawDevice of value) {
    if (!isRecord(rawDevice) || typeof rawDevice.device !== "string") {
      return { devices: null, error: "Each equipment item needs a name." };
    }
    const device = rawDevice.device.trim();
    if (!device) {
      return { devices: null, error: "Each equipment item needs a name." };
    }
    if (
      (rawDevice.floor != null &&
        (typeof rawDevice.floor !== "string" ||
          !/^\d+$/.test(rawDevice.floor))) ||
      (rawDevice.room != null &&
        (typeof rawDevice.room !== "string" ||
          !/^\d+$/.test(rawDevice.room)))
    ) {
      return { devices: null, error: "Floor and room must contain digits only." };
    }

    const photoData = rawDevice.photo;
    let photo: RepairDevice["photo"] = null;
    if (photoData == null) {
      return { devices: null, error: "Each equipment item must include a photo." };
    }
    if (
      !isRecord(photoData) ||
      typeof photoData.contentType !== "string" ||
      typeof photoData.base64 !== "string"
    ) {
      return {
        devices: null,
        error: "Photo must be a JPG, PNG, GIF, or WEBP image.",
      };
    }
    let bytes: Uint8Array;
    try {
      bytes = Uint8Array.from(atob(photoData.base64), (c) => c.charCodeAt(0));
    } catch {
      return { devices: null, error: "The photo's base64 data is invalid." };
    }
    const detectedContentType = detectImageContentType(bytes);
    if (!detectedContentType || !allowedImageTypes.has(detectedContentType)) {
      return {
        devices: null,
        error: "The photo data is not a valid JPG, PNG, GIF, or WEBP image.",
      };
    }
    if (bytes.length > bytesPerDevice) {
      return { devices: null, error: "Each photo must be 2 MB or smaller." };
    }
    totalPhotoBytes += bytes.length;

    try {
      devices.push({
        device,
        description: optionalText(rawDevice.description),
        floor: optionalText(rawDevice.floor),
        room: optionalText(rawDevice.room),
        photo: { contentType: detectedContentType, bytes },
      });
    } catch {
      return { devices: null, error: "Equipment details are invalid." };
    }
  }

  if (totalPhotoBytes > bytesPerDevice * devices.length) {
    return { devices: null, error: "The total photo size is too large." };
  }
  return { devices, error: null };
}

async function hasValidIdentity(
  token: string,
  serviceClient: SupabaseClient,
  signingSecret: string,
): Promise<boolean> {
  const claims = await verifyTemporarySession(token, signingSecret);
  if (
    claims &&
    typeof claims.sub === "string" &&
    (/^\d{1,19}$/.test(claims.sub) ||
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        .test(claims.sub)) &&
    ["User", "Admin", "SuperAdmin", "Technician"].includes(String(claims.role))
  ) {
    return true;
  }

  const { data, error } = await serviceClient.auth.getUser(token);
  if (error || !data.user) return false;
  const role = data.user.app_metadata.role;
  return role == null ||
    ["User", "Admin", "SuperAdmin", "Technician"].includes(String(role));
}

async function getRequesterUid(
  token: string,
  serviceClient: SupabaseClient,
  signingSecret: string,
): Promise<string | null> {
  const claims = await verifyTemporarySession(token, signingSecret);
  let subject: string;
  if (claims && typeof claims.sub === "string") {
    subject = claims.sub;
  } else {
    const { data, error } = await serviceClient.auth.getUser(token);
    if (error || !data.user) return null;
    subject = data.user.id;
  }

  if (/^\d{10}$/.test(subject)) return subject;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(subject)
  ) {
    return null;
  }

  const { data, error } = await serviceClient
    .from("Users")
    .select("uid")
    .eq("google_auth_user_id", subject)
    .maybeSingle();
  if (error) throw error;
  const uid = data?.uid;
  if (typeof uid === "number" && Number.isSafeInteger(uid)) {
    const uidText = String(uid);
    return /^\d{10}$/.test(uidText) ? uidText : null;
  }
  return typeof uid === "string" && /^\d{10}$/.test(uid) ? uid : null;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = getSupabaseAdminKey();
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Supabase server configuration is missing.");
    return jsonResponse(500, { error: "Repair request service is not configured." });
  }

  const token = request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)
    ?.[1];
  if (!token) {
    return jsonResponse(401, { error: "Please sign in before submitting a repair request." });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  if (!await hasValidIdentity(token, serviceClient, serviceRoleKey)) {
    return jsonResponse(401, { error: "Please sign in before submitting a repair request." });
  }
  let requester: string | null;
  try {
    requester = await getRequesterUid(token, serviceClient, serviceRoleKey);
  } catch (error) {
    console.error("Failed to resolve repair requester's UID.", error);
    return jsonResponse(500, { error: "The requester UID could not be verified." });
  }
  if (!requester) {
    return jsonResponse(400, {
      error: "A registered account with a 10-digit UID is required to submit a repair request.",
    });
  }

  let payload: Record<string, unknown>;
  try {
    const value: unknown = await request.json();
    if (!isRecord(value)) return jsonResponse(400, { error: "Invalid request body." });
    payload = value;
  } catch {
    return jsonResponse(400, { error: "Invalid JSON request body." });
  }

  const building = payload.building;
  const area = payload.area;
  const longitude = payload.longtitude;
  const latitude = payload.latitude;
  if (
    typeof building !== "string" ||
    (building !== "other" && !/^\d{1,2}$/.test(building))
  ) {
    return jsonResponse(400, { error: "Select a valid building." });
  }
  if (
    building === "other"
      ? typeof area !== "string" || area.trim().length === 0
      : area != null
  ) {
    return jsonResponse(400, { error: "Enter a valid location." });
  }
  if (
    typeof longitude !== "number" ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180 ||
    typeof latitude !== "number" ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90
  ) {
    return jsonResponse(400, { error: "Select a valid location on the map." });
  }
  const parsedDevices = parseDevices(payload.devices);
  if (!parsedDevices.devices) {
    return jsonResponse(400, { error: parsedDevices.error });
  }
  const devices = parsedDevices.devices;

  const { data: ticketId, error: createError } = await serviceClient.rpc(
    "create_fix_request",
    {
      p_requester: requester,
      p_building: building,
      p_area: building === "other" ? (area as string).trim() : null,
      p_longtitude: longitude,
      p_latitude: latitude,
      p_devices: devices.map(({ device, description, floor, room }) => ({
        device,
        description,
        floor,
        room,
      })),
    },
  );
  if (createError || typeof ticketId !== "string") {
    console.error("Failed to create repair request records.", createError);
    return jsonResponse(500, { error: "Repair request could not be saved. Please try again." });
  }

  const bucketName = ticketId;
  const photoNames = devices.map((_, index) => String(index + 1));
  let bucketCreated = false;
  let storageStep = "prepare photo bucket";
  try {
    const { data: buckets, error: listError } = await serviceClient.storage
      .listBuckets();
    if (listError) throw listError;
    if (buckets.some((bucket) => bucket.id === bucketName)) {
      throw new Error("A storage bucket already exists for the generated ticket.");
    }

    const { error: bucketError } = await serviceClient.storage.createBucket(
      bucketName,
      {
        public: false,
        fileSizeLimit: bytesPerDevice * devices.length,
        allowedMimeTypes: [...allowedImageTypes],
      },
    );
    if (bucketError) throw bucketError;
    bucketCreated = true;

    for (let index = 0; index < devices.length; index++) {
      const photo = devices[index].photo;
      if (!photo) continue;
      storageStep = `upload photo ${photoNames[index]}`;
      const { error: uploadError } = await serviceClient.storage
        .from(bucketName)
        .upload(photoNames[index], photo.bytes, {
          contentType: photo.contentType,
          upsert: false,
        });
      if (uploadError) throw uploadError;
      console.info("Uploaded repair request photo.", {
        ticketId,
        objectName: photoNames[index],
        contentType: photo.contentType,
        bytes: photo.bytes.length,
      });
    }

    storageStep = "verify uploaded photos";
    const { data: uploadedFiles, error: verifyError } = await serviceClient
      .storage
      .from(bucketName)
      .list("", { limit: photoNames.length });
    if (verifyError) throw verifyError;
    const uploadedNames = new Set(uploadedFiles.map((file) => file.name));
    const missingPhotos = photoNames.filter((name) => !uploadedNames.has(name));
    if (missingPhotos.length > 0) {
      throw new Error(`Photos missing from bucket: ${missingPhotos.join(", ")}`);
    }
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    console.error("Failed to save repair request photo.", {
      ticketId,
      step: storageStep,
      error: detail,
    });
    if (bucketCreated) {
      const { error: removeFilesError } = await serviceClient.storage
        .from(bucketName)
        .remove(photoNames);
      if (removeFilesError) {
        console.error("Failed to remove incomplete repair request photos.", removeFilesError);
      }
      const { error: deleteBucketError } = await serviceClient.storage
        .deleteBucket(bucketName);
      if (deleteBucketError) {
        console.error("Failed to remove incomplete repair request storage.", deleteBucketError);
      }
    }
    const { error: cleanupError } = await serviceClient.rpc(
      "discard_fix_request",
      { p_ticket_id: ticketId },
    );
    if (cleanupError) {
      console.error("Failed to remove incomplete repair request records.", cleanupError);
    }
    return jsonResponse(500, {
      error: `Could not ${storageStep}: ${detail}`,
    });
  }

  return jsonResponse(200, {
    TicketId: ticketId,
    PhotoCount: photoNames.length,
    PhotoNames: photoNames,
  });
});
