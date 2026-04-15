package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/golang-jwt/jwt/v5"
)

var (
	redisClient *redis.Client
	ctx         = context.Background()
	jwtSecret   []byte
	routes      []route
)

type route struct {
	prefix      string
	targetURL   string
	stripPrefix bool
}

func main() {
	jwtSecret = []byte(getEnv("JWT_SECRET", "change-me-in-production"))

	// Service routes - internal service URLs
	dashboardURL := getEnv("DASHBOARD_SERVICE_URL", "http://dashboard-api:8086")
	routes = []route{
		{prefix: "/api/orders", targetURL: getEnv("ORDER_SERVICE_URL", "http://order-service:8081"), stripPrefix: true},
		{prefix: "/api/inventory", targetURL: getEnv("INVENTORY_SERVICE_URL", "http://inventory-service:8082"), stripPrefix: true},
		{prefix: "/api/payments", targetURL: getEnv("PAYMENT_SERVICE_URL", "http://payment-service:8083"), stripPrefix: true},
		{prefix: "/api/notifications", targetURL: getEnv("NOTIFICATION_SERVICE_URL", "http://notification-service:8084"), stripPrefix: true},
		{prefix: "/api/shipping", targetURL: getEnv("SHIPPING_SERVICE_URL", "http://shipping-service:8085"), stripPrefix: true},
		{prefix: "/api/dashboard", targetURL: dashboardURL, stripPrefix: true},
		{prefix: "/dashboard", targetURL: dashboardURL, stripPrefix: false},
	}

	// Redis for rate limiting
	redisURL := os.Getenv("REDIS_URL")
	if redisURL != "" {
		opt, err := redis.ParseURL(redisURL)
		if err == nil {
			redisClient = redis.NewClient(opt)
			if _, err := redisClient.Ping(ctx).Result(); err != nil {
				log.Printf("WARNING: Redis not reachable, rate limiting disabled: %v", err)
				redisClient = nil
			} else {
				log.Println("Redis connected for rate limiting")
			}
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", handleHealth)
	mux.HandleFunc("/auth/login", handleLogin)
	mux.HandleFunc("/auth/register", handleRegister)
	mux.HandleFunc("/", handleProxy)

	port := getEnv("PORT", "8080")
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go gracefulShutdown(server)

	log.Printf("API Gateway listening on :%s", port)
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy", "service": "api-gateway"})
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpError(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpError(w, "invalid request body", http.StatusBadRequest)
		return
	}

	// In production this would validate against a user database
	// For this project, accept any email/password and return a JWT
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":   req.Email,
		"role":  "customer",
		"exp":   time.Now().Add(24 * time.Hour).Unix(),
		"iat":   time.Now().Unix(),
	})

	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		httpError(w, "failed to generate token", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"token": tokenString})
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpError(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
		Name     string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpError(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if req.Email == "" || req.Password == "" {
		httpError(w, "email and password required", http.StatusBadRequest)
		return
	}

	// Return a JWT for the new user
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  req.Email,
		"name": req.Name,
		"role": "customer",
		"exp":  time.Now().Add(24 * time.Hour).Unix(),
		"iat":  time.Now().Unix(),
	})

	tokenString, _ := token.SignedString(jwtSecret)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message": "registered",
		"email":   req.Email,
		"token":   tokenString,
	})
}

func handleProxy(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/" {
		serveProxy(w, r, getEnv("DASHBOARD_SERVICE_URL", "http://dashboard-api:8086"), "/", false)
		return
	}

	// Rate limiting
	if redisClient != nil {
		ip := r.RemoteAddr
		key := fmt.Sprintf("rate:%s", ip)
		count, _ := redisClient.Incr(ctx, key).Result()
		if count == 1 {
			redisClient.Expire(ctx, key, time.Minute)
		}
		limit := 100 // requests per minute
		if count > int64(limit) {
			httpError(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
	}

	// Auth check (skip for public endpoints)
	if !isPublicPath(r.URL.Path) {
		claims, err := validateToken(r)
		if err != nil {
			httpError(w, "unauthorized: "+err.Error(), http.StatusUnauthorized)
			return
		}
		// Forward user info to downstream services
		r.Header.Set("X-User-Email", claims["sub"].(string))
		if role, ok := claims["role"].(string); ok {
			r.Header.Set("X-User-Role", role)
		}
	}

	// Find matching route
	for _, route := range routes {
		if strings.HasPrefix(r.URL.Path, route.prefix) {
			path := r.URL.Path
			if route.stripPrefix {
				path = strings.TrimPrefix(path, route.prefix)
				if path == "" {
					path = "/"
				}
			}

			serveProxy(w, r, route.targetURL, path, true)
			return
		}
	}

	httpError(w, "not found", http.StatusNotFound)
}

func isPublicPath(path string) bool {
	public := []string{"/", "/healthz", "/auth/", "/dashboard", "/api/shipping/webhook"}
	for _, p := range public {
		if strings.HasSuffix(p, "/") {
			if strings.HasPrefix(path, p) {
				return true
			}
			continue
		}
		if path == p || strings.HasPrefix(path, p+"/") {
			return true
		}
	}
	// Allow health checks through to downstream services
	if strings.HasSuffix(path, "/healthz") {
		return true
	}
	return false
}

func serveProxy(w http.ResponseWriter, r *http.Request, targetURL, upstreamPath string, setProxyHeaders bool) {
	target, err := url.Parse(targetURL)
	if err != nil {
		httpError(w, "bad upstream config", http.StatusInternalServerError)
		return
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("Proxy error: %v", err)
		httpError(w, "service unavailable", http.StatusBadGateway)
	}

	req := r.Clone(r.Context())
	req.URL.Path = upstreamPath
	req.URL.RawPath = upstreamPath
	if setProxyHeaders {
		req.Header.Set("X-Forwarded-For", r.RemoteAddr)
		req.Header.Set("X-Request-ID", fmt.Sprintf("%d", time.Now().UnixNano()))
	}

	proxy.ServeHTTP(w, req)
}

func validateToken(r *http.Request) (jwt.MapClaims, error) {
	auth := r.Header.Get("Authorization")
	if auth == "" {
		return nil, fmt.Errorf("missing Authorization header")
	}

	parts := strings.SplitN(auth, " ", 2)
	if len(parts) != 2 || parts[0] != "Bearer" {
		return nil, fmt.Errorf("invalid Authorization format")
	}

	token, err := jwt.Parse(parts[1], func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return jwtSecret, nil
	})
	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
		return claims, nil
	}
	return nil, fmt.Errorf("invalid token")
}

func httpError(w http.ResponseWriter, msg string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

var shutdownOnce sync.Once

func gracefulShutdown(server *http.Server) {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan
	shutdownOnce.Do(func() {
		log.Println("Shutting down...")
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		server.Shutdown(ctx)
	})
}
