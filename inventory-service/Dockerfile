# Stage 1: Build the Go application
FROM golang:1.26-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o inventory-service .

# Stage 2: Run the compiled application
FROM alpine:3.22
WORKDIR /app
# hadolint ignore=DL3017,DL3018
RUN apk add --no-cache ca-certificates && apk upgrade --no-cache zlib && adduser -D -u 10001 app
COPY --from=build /app/inventory-service .
USER app
EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1:8081/health || exit 1
CMD ["./inventory-service"]
