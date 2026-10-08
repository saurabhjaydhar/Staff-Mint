/** Trigger a browser download for a Blob. */
export function saveBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function saveText(text: string, filename: string, type = "text/csv;charset=utf-8") {
  // BOM so Excel opens UTF-8 (Hindi names) correctly.
  saveBlob(new Blob(["﻿", text], { type }), filename);
}
