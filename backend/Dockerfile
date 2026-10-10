# StaffMint API + worker image
FROM node:22-bookworm-slim AS build
WORKDIR /app
ENV PUPPETEER_SKIP_DOWNLOAD=1
COPY package*.json ./
RUN npm ci
COPY tsconfig*.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-bookworm-slim
# Chromium for PDF rendering; Noto fonts for Hindi (Devanagari) payslips.
RUN apt-get update && apt-get install -y --no-install-recommends chromium fonts-noto-core fonts-noto-ui-core ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production PUPPETEER_SKIP_DOWNLOAD=1 CHROME_EXECUTABLE_PATH=/usr/bin/chromium PDF_PROVIDER=puppeteer \
  LOCAL_STORAGE_DIR=/data/storage
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
# Owned by `node` so a volume mounted here is writable by the non-root user.
RUN mkdir -p /data/storage && chown node:node /data/storage
USER node
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD node -e "fetch('http://localhost:4000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/server.js"]
