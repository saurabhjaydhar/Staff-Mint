import type { Metadata, Viewport } from "next";
import { Providers } from "@/components/providers";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "StaffMint Admin", template: "%s · StaffMint Admin" },
  description: "Run StaffMint: businesses, plans, trials, settings and support.",
  robots: { index: false, follow: false },
  appleWebApp: { capable: true, title: "SM Admin", statusBarStyle: "default" },
};

export const viewport: Viewport = {
  themeColor: "#2BB673",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full">
      <body className="min-h-full">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
