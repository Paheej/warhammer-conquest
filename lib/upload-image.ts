// Browser-side image upload to Cloudinary using an unsigned upload preset.
// Returns the public HTTPS URL (e.g. https://res.cloudinary.com/.../image.jpg).

export async function uploadImage(file: File): Promise<string> {
  const cloudName = process.env.NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME;
  const preset = process.env.NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET;
  if (!cloudName || !preset) {
    throw new Error(
      "Image upload is not configured. Set NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME and NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET.",
    );
  }

  const fd = new FormData();
  fd.append("file", file);
  fd.append("upload_preset", preset);

  const res = await fetch(
    `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`,
    { method: "POST", body: fd },
  );

  const json = (await res.json().catch(() => null)) as
    | { secure_url?: string; url?: string; error?: { message?: string } }
    | null;

  if (!res.ok || !json?.secure_url) {
    const msg = json?.error?.message ?? `Image upload failed (${res.status}).`;
    throw new Error(msg);
  }

  return json.secure_url;
}
