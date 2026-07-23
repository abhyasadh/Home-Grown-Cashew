# Stage 1: Build the Flutter web app
FROM ghcr.io/cirruslabs/flutter:stable AS web-builder

WORKDIR /app
COPY budget/pubspec.yaml budget/pubspec.lock ./
RUN flutter pub get
COPY budget/ ./
RUN flutter build web --release

# Stage 2: Build the Go server
FROM golang:1.22-alpine AS go-builder

RUN apk add --no-cache gcc musl-dev

WORKDIR /app
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=1 go build -o /server ./cmd/server/main.go

# Stage 3: Runtime image
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app
COPY --from=go-builder /server /app/server
COPY --from=web-builder /app/build/web /app/web/build

RUN mkdir -p /app/data

EXPOSE 2580

ENV DATA_DIR=/app/data
ENV WEB_DIR=/app/web/build
ENV PORT=2580

ENTRYPOINT ["/app/server"]
