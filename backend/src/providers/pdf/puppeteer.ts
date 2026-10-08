import puppeteer, { type Browser } from 'puppeteer-core';
import type { PdfRenderer } from '../types.js';

/** HTML → PDF via headless Chromium. HTML templates embed Noto Sans Devanagari for Hindi. */
export class PuppeteerPdfRenderer implements PdfRenderer {
  readonly name = 'puppeteer';
  private browser: Promise<Browser> | null = null;
  constructor(private cfg: { executablePath: string }) {}
  private getBrowser() {
    this.browser ??= puppeteer.launch({ executablePath: this.cfg.executablePath, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage', '--font-render-hinting=none'] });
    return this.browser;
  }
  async render(html: string, opts?: { landscape?: boolean }) {
    const browser = await this.getBrowser();
    const page = await browser.newPage();
    try {
      await page.setContent(html, { waitUntil: 'load', timeout: 20000 });
      const pdf = await page.pdf({ format: 'A4', landscape: opts?.landscape ?? false, printBackground: true, margin: { top: '12mm', bottom: '12mm', left: '10mm', right: '10mm' } });
      return Buffer.from(pdf);
    } finally {
      await page.close();
    }
  }
  async close() {
    if (this.browser) await (await this.browser).close();
    this.browser = null;
  }
}
