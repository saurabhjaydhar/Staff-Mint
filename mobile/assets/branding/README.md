# StaffMint app icon

An attendance register with a tick and a gold ₹ coin: the app's two jobs, attendance and salary,
on the brand mint gradient (`#2FC07C` → `#11683F`; tick `#1A9A60`; coin `#FFD25E` → `#E39A0B`).
The ₹ is drawn as strokes, so no font is needed to render it.
Preview: `docs/design/app-icon-preview.png`; the other ideas considered: `docs/design/app-icon-concepts.png`.

| File | Used for |
|---|---|
| `icon_square.svg` | iOS app icon (full square; iOS rounds it) and the Play Store icon |
| `icon_legacy.svg` | Android launchers before 8.0 (rounded square, transparent corners) |
| `icon_adaptive_background.svg` / `icon_adaptive_foreground.svg` | Android 8+ adaptive icon (108dp canvas, art inside the 66dp safe circle) |
| `icon_monochrome.svg` | Android 13+ themed icons (one colour; tick and ₹ cut out) |
| `play_store_icon_512.png` | Upload to Play Console → Store listing → App icon |

To change the icon, edit the SVGs, render each at 1024×1024 (any SVG renderer, e.g. a browser),
then resize to the existing files:
- `android/app/src/main/res/mipmap-*/ic_launcher.png` (48dp: 48/72/96/144/192 px) from `icon_legacy`
- `mipmap-*/ic_launcher_{background,foreground,monochrome}.png` (108dp: 108/162/216/324/432 px)
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/*` (sizes in its `Contents.json`) from `icon_square`
