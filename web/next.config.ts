import type { NextConfig } from "next";

// The dashboard is a client-side app talking to the StaffMint API, so we keep the
// config minimal. `standalone` output is used by the Dockerfile.
const nextConfig: NextConfig = {
  output: "standalone",
  poweredByHeader: false,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
