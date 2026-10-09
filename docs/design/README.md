# StaffMint mobile redesign: research and references

Status: **options for review. No code has changed yet.**

| Board | What it shows |
|---|---|
| [01 · Niche analysis](01-niche-analysis.jpg) | Who uses StaffMint, their real context, competitor gap, patterns they already trust, design principles |
| [02 · Flow improvements](02-flow-improvements.jpg) | Shorter journeys for the most frequent tasks (apply with any style) |
| [03 · E · Bahi-Khata Modern](03-direction-E-bahi-khata-modern.jpg) | **Recommended.** The direction derived from the niche analysis |
| [04 · A · Soft Minimal](04-direction-A-soft-minimal.jpg) | Calm, white space, one hero card |
| [05 · B · Vibrant Bento](05-direction-B-vibrant-bento.jpg) | Colourful tiles, emoji, festive palette |
| [06 · C · Neo-Brutalism](06-direction-C-neo-brutalism.jpg) | Thick outlines, hard shadows, maximum contrast |
| [07 · D · Dark Glass](07-direction-D-dark-glass.jpg) | Dark premium fintech look |

## Niche summary
- **Users:** owners of Indian shops, clinics, salons and restaurants with 8–50 staff (Hindi/Hinglish, phone-only, 20-second sessions between customers), plus their staff, who include low-literacy daily-wage workers.
- **Context:** bright shop light, one hand busy, noisy counter, budget Android phones (the largest band is $100–200, about ₹9k–18k), patchy 4G.
- **Language:** 57% of Indian internet users prefer Indian languages, Hindi first, with voice search a key driver (IAMAI-Kantar 2024).
- **Trust anchors they already use daily:** the paper bahi-khata ledger, WhatsApp, and UPI apps (PhonePe/GPay).
- **Lesson from Khatabook:** keep the familiar ledger mental model, and change the UI step by step. A big one-shot redesign made users feel "it's not the same app" and they dropped off.
- **Competitors** (SalaryBox, PagarBook, registers) all look like generic blue/white SaaS. A warm, ledger-familiar, Hindi-first, voice-first look would stand out.

## Design principles
1. **Answer first.** The first screen says who came and who is owed what, without a tap.
2. **Familiar, then better.** Use ledger, chat and UPI patterns; never break the mental model.
3. **Hindi-first, icon-led.** Hindi label + English hint; colour + icon + number carry the meaning.
4. **Thumb & voice.** Actions sit in the bottom third, the mic is on every screen, targets are ≥ 48 dp.
5. **Money feels official.** Receipts, stamps, slide-to-confirm, success screens, undo.
6. **Sunlight-proof.** Warm light background, ink text, colour never the only signal.
7. **Fast on bad networks.** Offline-first, skeleton loaders, no heavy blur or animation.
8. **Calm, not childish.** Warm, but money screens stay precise.

## Sources
- [IAMAI-Kantar: 57% of internet users prefer Indic languages (storyboard18)](https://www.storyboard18.com/how-it-works/57-percent-internet-users-prefer-internet-content-in-indic-languages-in-urban-india-report-24598.htm)
- [Think with Google: App and website localization for Indian users](https://thinkwithgoogle.com/_qs/documents/13326/App_and_website_localization_for_Indian_users.pdf)
- [IDC: Indian smartphone market 2025 (GSMArena)](https://m.gsmarena.com/indian_smartphone_market_remains_flat_in_2025_signals_structural_changes-news-71575.php) · [91mobiles](https://www.91mobiles.com/updates/india-smartphone-growth-flat-q4-2025-idc/amp/)
- [Khatabook product roadmap (YourStory)](https://yourstory.com/2021/08/product-roadmap-fintech-startup-khatabook-10-million-msme-users/amp) · [How Khatabook became the premier fintech app for Bharat (Substack)](https://ameya.substack.com/p/how-khatabook-became-the-premier)
- [PagarBook reviews (Capterra)](https://www.capterra.com/p/228217/PagarBook/reviews/) · [SalaryBox (Capterra India)](https://www.capterra.in/software/1031162/salarybox) · [PagarBook (Techjockey)](https://techjockey.com/reviews/pagarbook)
