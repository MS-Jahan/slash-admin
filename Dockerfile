# syntax=docker/dockerfile:1

# ---------- Build stage ----------
FROM node:22-alpine AS build
WORKDIR /app

# Pin pnpm to the major version used by the lockfile
RUN npm install -g pnpm@9.15.9

# Install dependencies first so Docker can cache this layer.
# --ignore-scripts skips the "preinstall: lefthook install" git-hook script,
# which is useless (and may fail) inside a container without a .git folder.
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --ignore-scripts

COPY . .

# Vite env vars are baked in at BUILD time, so they must be build args.
# In Coolify, set them as env vars and tick "Available at Buildtime".
ARG VITE_APP_DEFAULT_ROUTE=/workbench
ARG VITE_APP_PUBLIC_PATH=/
ARG VITE_APP_API_BASE_URL=/api
ARG VITE_APP_ROUTER_MODE=frontend
ENV VITE_APP_DEFAULT_ROUTE=$VITE_APP_DEFAULT_ROUTE \
    VITE_APP_PUBLIC_PATH=$VITE_APP_PUBLIC_PATH \
    VITE_APP_API_BASE_URL=$VITE_APP_API_BASE_URL \
    VITE_APP_ROUTER_MODE=$VITE_APP_ROUTER_MODE

# The type-check + bundle can be memory hungry; raise the Node heap limit
ENV NODE_OPTIONS=--max-old-space-size=3072

# vite.config.ts tries to open a browser (bundle visualizer) on production builds.
# Disable it, since there is no browser inside the container.
RUN sed -i 's/open: true,/open: false,/g' vite.config.ts \
    && pnpm build

# ---------- Runtime stage ----------
FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null 2>&1 || exit 1
