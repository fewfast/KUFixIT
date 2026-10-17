import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export const profileAvatarMaxFileSize = 2 * 1024 * 1024;
export const profileAvatarMimeTypes = [
  "image/gif",
  "image/jpeg",
  "image/png",
  "image/webp",
] as const;

const profileAvatarUidPattern = /^u_[0-9]{10}$/;

export async function ensureProfileAvatarBucket(
  supabase: SupabaseClient,
  uid: string,
): Promise<void> {
  if (!profileAvatarUidPattern.test(uid)) {
    throw new Error("Cannot create a profile image bucket for an invalid UID.");
  }

  const bucketOptions = {
    public: false,
    fileSizeLimit: profileAvatarMaxFileSize,
    allowedMimeTypes: [...profileAvatarMimeTypes],
  };
  const { data: buckets, error: listError } = await supabase.storage.listBuckets();
  if (listError) throw listError;

  if (buckets.some((bucket) => bucket.id === uid)) {
    const { error } = await supabase.storage.updateBucket(uid, bucketOptions);
    if (error) throw error;
    return;
  }

  const { error: createError } = await supabase.storage.createBucket(
    uid,
    bucketOptions,
  );
  if (!createError) return;

  const { data: latestBuckets, error: verifyError } = await supabase.storage
    .listBuckets();
  if (verifyError) throw verifyError;
  if (!latestBuckets.some((bucket) => bucket.id === uid)) throw createError;

  const { error: updateError } = await supabase.storage.updateBucket(
    uid,
    bucketOptions,
  );
  if (updateError) throw updateError;
}
