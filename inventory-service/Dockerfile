# Stage 1: Build the Go application
FROM golang:1.26-alpine AS build

WORKDIR /app

# Copy dependency files
COPY go.mod go.sum ./

# Download Go dependencies
RUN go mod download

# Copy application source code
COPY . .

# Compile the application
RUN CGO_ENABLED=0 GOOS=linux go build -o inventory-service .

# Stage 2: Run the compiled application
FROM alpine:3.22

WORKDIR /app

# Install certificates
RUN apk add --no-cache ca-certificates

# Copy compiled binary from build stage
COPY --from=build /app/inventory-service .

# Application port
EXPOSE 8081

# Start the application
CMD ["./inventory-service"]
