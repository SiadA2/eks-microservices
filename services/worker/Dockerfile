#Builder
FROM golang:alpine@sha256:8e52afc2f64fd75eebd4f74e198a46f1786c8648a5bf92527f5fee64771b696f AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o worker .

# Runtime
FROM scratch

WORKDIR /app
COPY --from=builder /app/worker ./

EXPOSE 8080
CMD ["./worker"]