const sessionLifetimeSeconds = 8 * 60 * 60;

const encoder = new TextEncoder();

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromBase64Url(value: string): Uint8Array {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

export type TemporaryUser = {
  id: string;
  username: string;
  firstname: string;
  lastname: string;
  role: string;
}

export async function createTemporarySession(
  user: TemporaryUser,
  signingSecret: string,
  requestedExpiresAt?: number,
): Promise<{ accessToken: string; expiresAt: number }> {
  const issuedAt = Math.floor(Date.now() / 1000);
  const expiresAt = Math.min(
    issuedAt + sessionLifetimeSeconds,
    requestedExpiresAt ?? Number.POSITIVE_INFINITY,
  );
  if (!Number.isFinite(expiresAt) || expiresAt <= issuedAt) {
    throw new Error("Temporary session expiration must be in the future.");
  }
  const header = toBase64Url(
    encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })),
  );
  const payload = toBase64Url(
    encoder.encode(
      JSON.stringify({
        sub: user.id,
        username: user.username,
        role: user.role,
        iat: issuedAt,
        exp: expiresAt,
        iss: "kufixit-temporary-auth",
      }),
    ),
  );
  const unsignedToken = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(signingSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(unsignedToken),
  );
  return { accessToken: `${unsignedToken}.${toBase64Url(new Uint8Array(signature))}`, expiresAt };
}

export async function verifyTemporarySession(
  token: string,
  signingSecret: string,
): Promise<Record<string, unknown> | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [header, payload, signature] = parts;

  try {
    const parsedHeader: unknown = JSON.parse(
      new TextDecoder().decode(fromBase64Url(header)),
    );
    if (
      typeof parsedHeader !== "object" ||
      parsedHeader === null ||
      (parsedHeader as Record<string, unknown>).alg !== "HS256"
    ) {
      return null;
    }
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(signingSecret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const isValid = await crypto.subtle.verify(
      "HMAC",
      key,
      fromBase64Url(signature),
      encoder.encode(`${header}.${payload}`),
    );
    if (!isValid) return null;

    const claims: unknown = JSON.parse(
      new TextDecoder().decode(fromBase64Url(payload)),
    );
    if (
      typeof claims !== "object" ||
      claims === null ||
      (claims as Record<string, unknown>).iss !== "kufixit-temporary-auth" ||
      typeof (claims as Record<string, unknown>).exp !== "number" ||
      (claims as Record<string, number>).exp <= Math.floor(Date.now() / 1000)
    ) {
      return null;
    }
    return claims as Record<string, unknown>;
  } catch {
    return null;
  }
}
