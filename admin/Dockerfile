# syntax=docker/dockerfile:1
# StaffMint admin app — multi-stage build using Next.js `output: "standalone"`.
#
#   docker build -t staffmint-admin --build-arg NEXT_PUBLIC_API_BASE_URL=https://api.example.com/api/v1 .
#   docker run -p 3200:3200 staffmint-admin
#
# NEXT_PUBLIC_* values are inlined into the browser bundle at BUILD time, so pass the API URL as a build arg.
# Add the admin app's URL to the API's CORS_ORIGINS.

FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ARG NEXT_PUBLIC_API_BASE_URL=http://localhost:4000/api/v1
ENV NEXT_PUBLIC_API_BASE_URL=${NEXT_PUBLIC_API_BASE_URL} \
    NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3200 \
    HOSTNAME=0.0.0.0
RUN addgroup -S -g 1001 nodejs && adduser -S -u 1001 -G nodejs nextjs
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3200
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD wget -qO- http://127.0.0.1:3200/login >/dev/null || exit 1
CMD ["node", "server.js"]
