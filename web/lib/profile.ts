// Pure helpers for the profile page (kept out of the component for tests).

export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** 10-digit Indian mobile from free input ("+91 98765 43210" → "9876543210"), or null. */
export function indianMobile(raw: string): string | null {
  let d = raw.replace(/\D/g, "");
  if (d.length === 12 && d.startsWith("91")) d = d.slice(2);
  if (d.length === 11 && d.startsWith("0")) d = d.slice(1);
  return /^[6-9]\d{9}$/.test(d) ? d : null;
}

/** "+919876543210" → "+91 98765 43210". */
export function displayPhone(e164: string): string {
  const m = /^\+91(\d{5})(\d{5})$/.exec(e164);
  return m ? `+91 ${m[1]} ${m[2]}` : e164;
}

/** First user-visible character (so Hindi "रा" stays whole). */
function firstGrapheme(word: string): string {
  if (typeof Intl !== "undefined" && "Segmenter" in Intl) {
    const it = new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(word)[Symbol.iterator]().next();
    if (!it.done) return it.value.segment;
  }
  return Array.from(word)[0] ?? "";
}

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return "?";
  const last = parts.length > 1 ? firstGrapheme(parts[parts.length - 1]) : "";
  return (firstGrapheme(parts[0]) + last).toUpperCase();
}

/** Resize an image file to a ≤ max px JPEG and return base64 (no data: prefix). Browser only. */
export async function fileToJpegBase64(file: File, max = 600, quality = 0.85): Promise<string> {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = () => reject(new Error("Could not read that image"));
      i.src = url;
    });
    const scale = Math.min(1, max / Math.max(img.width, img.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(img.width * scale);
    canvas.height = Math.round(img.height * scale);
    canvas.getContext("2d")!.drawImage(img, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL("image/jpeg", quality).split(",")[1] ?? "";
  } finally {
    URL.revokeObjectURL(url);
  }
}
