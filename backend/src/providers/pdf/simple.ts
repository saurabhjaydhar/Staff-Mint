import type { PdfRenderer } from '../types.js';

/**
 * Dependency-free fallback PDF renderer for dev/tests: converts HTML to plain text
 * lines in Helvetica. Non-Latin glyphs (Devanagari) are not supported here — use
 * PDF_PROVIDER=puppeteer in production for proper Hindi rendering.
 */
export class SimplePdfRenderer implements PdfRenderer {
  readonly name = 'simple';
  async render(html: string, opts?: { landscape?: boolean }): Promise<Buffer> {
    const text = html
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<(br|\/p|\/tr|\/h\d|\/div|\/li)>/gi, '\n')
      .replace(/<\/t[dh]>/gi, '   ')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/₹/g, 'Rs.')
      .replace(/[^\x20-\x7E\n]/g, '')
      .split('\n')
      .map((l) => l.replace(/\s+/g, ' ').trim())
      .filter((l, i, a) => l || (i > 0 && a[i - 1]));
    return buildPdf(text, opts?.landscape ?? false);
  }
}

function esc(s: string) {
  return s.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
}

export function buildPdf(lines: string[], landscape = false): Buffer {
  const [w, h] = landscape ? [842, 595] : [595, 842];
  const perPage = Math.floor((h - 80) / 14);
  const pages: string[][] = [];
  for (let i = 0; i < Math.max(lines.length, 1); i += perPage) pages.push(lines.slice(i, i + perPage));
  const objects: string[] = [];
  const pageIds: number[] = [];
  // 1: catalog, 2: pages, 3: font
  objects[1] = '';
  objects[2] = '';
  objects[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
  let next = 4;
  for (const pl of pages) {
    const content = ['BT', '/F1 10 Tf', `40 ${h - 50} Td`, '14 TL', ...pl.map((l) => `(${esc(l.slice(0, 120))}) '`), 'ET'].join('\n');
    const contentId = next++;
    const pageId = next++;
    objects[contentId] = `<< /Length ${Buffer.byteLength(content)} >>\nstream\n${content}\nendstream`;
    objects[pageId] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${w} ${h}] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentId} 0 R >>`;
    pageIds.push(pageId);
  }
  objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objects[2] = `<< /Type /Pages /Kids [${pageIds.map((id) => `${id} 0 R`).join(' ')}] /Count ${pageIds.length} >>`;
  let out = '%PDF-1.4\n';
  const offsets: number[] = [];
  for (let i = 1; i < objects.length; i++) {
    offsets[i] = Buffer.byteLength(out);
    out += `${i} 0 obj\n${objects[i]}\nendobj\n`;
  }
  const xref = Buffer.byteLength(out);
  out += `xref\n0 ${objects.length}\n0000000000 65535 f \n`;
  for (let i = 1; i < objects.length; i++) out += `${String(offsets[i]).padStart(10, '0')} 00000 n \n`;
  out += `trailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, 'latin1');
}
