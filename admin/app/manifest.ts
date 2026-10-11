import type { MetadataRoute } from "next";

/** Add to home screen on a phone: opens like an app. */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "StaffMint Admin",
    short_name: "SM Admin",
    start_url: "/",
    display: "standalone",
    background_color: "#f8fafc",
    theme_color: "#2BB673",
    icons: [{ src: "/icon.svg", sizes: "any", type: "image/svg+xml" }],
  };
}
