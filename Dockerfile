# syntax=docker/dockerfile:1.6

# Build stage
FROM golang:1.23-alpine AS builder

# Build arguments for cross-compilation
ARG TARGETOS=linux
ARG TARGETARCH

WORKDIR /build

# Copy go module files
COPY go.mod ./

# Copy source code
COPY main.go ./

# Build the binary for the target architecture
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -a -installsuffix cgo -o webhook .

# Runtime stage
FROM alpine:latest

# Create non-root user
RUN adduser -u 1001 -D -H -G root appuser && \
    mkdir -p /tls && chown -R appuser:root /tls

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/webhook /app/webhook

USER 1001
EXPOSE 8443

CMD ["/app/webhook"]


