import type { Metadata, Viewport } from "next";
import { Providers } from "@/components/providers";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "StaffMint", template: "%s · StaffMint" },
  description: "StaffMint web dashboard — staff attendance & salary for small businesses.",
};

export const viewport: Viewport = {
  themeColor: "#2BB673",
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
