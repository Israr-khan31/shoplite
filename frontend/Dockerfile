# Stage 1: Build React application
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Serve using Nginx
FROM nginx:1.31-alpine-slim
# hadolint ignore=DL3017
RUN apk upgrade --no-cache zlib
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 CMD wget -q -O /dev/null --header "Host: ${SERVER_NAME}" http://127.0.0.1/ || exit 1
CMD ["nginx", "-g", "daemon off;"]
