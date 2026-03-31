#Builder
FROM golang:alpine@sha256:683792682c6aa8b6d43eb69ba09aa3bb64bf0e8ddcdbf4bc6ec3260bd312cb93 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./
COPY static/ ./static/
RUN CGO_ENABLED=0 GOOS=linux go build -o dashboard-api .

# Runtime
FROM scratch

WORKDIR /app
COPY --from=builder /app/dashboard-api ./

EXPOSE 8080
CMD ["./dashboard-api"]