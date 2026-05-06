package main

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spiffe/go-spiffe/v2/svid/jwtsvid"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

type appState struct {
	Mode        string            `json:"mode"`
	DB          map[string]string `json:"db"`
	Secrets     map[string]string `json:"secrets"`
	SWAReady    bool              `json:"swaReady"`
	LastRefresh string            `json:"lastRefresh,omitempty"`
	LastError   string            `json:"lastError,omitempty"`
}

func main() {
	log.SetFlags(log.LstdFlags | log.LUTC | log.Lmicroseconds)

	mode := getenv("GIFTAPP_MODE", "hardcoded")
	state := &appState{
		Mode:    mode,
		DB:      map[string]string{},
		Secrets: map[string]string{},
	}

	switch mode {
	case "hardcoded":
		loadHardcoded(state)
	case "swa":
		loadWithSWA(context.Background(), state)
	default:
		log.Fatalf("unsupported GIFTAPP_MODE %q", mode)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, state)
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if state.LastError != "" {
			w.WriteHeader(http.StatusServiceUnavailable)
		}
		writeJSON(w, state)
	})

	certPath := getenv("SSL_CERT_PATH", "/certs/giftapp.pem")
	keyPath := getenv("SSL_KEY_PATH", "/certs/giftapp.key")
	server := &http.Server{
		Addr:              ":8443",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		TLSConfig:         &tls.Config{MinVersion: tls.VersionTLS12},
	}

	log.Printf("giftapp listening on https://0.0.0.0:8443 mode=%s", mode)
	log.Fatal(server.ListenAndServeTLS(certPath, keyPath))
}

func loadHardcoded(state *appState) {
	state.DB["user"] = secretFile("DB_USER")
	state.DB["host"] = secretFile("DB_HOST")
	state.DB["port"] = secretFile("DB_PORT")
	state.DB["name"] = secretFile("DB_NAME")
	state.Secrets["dbPassword"] = presence(secretFile("DB_PASS"))
	state.Secrets["giftappApiKey"] = presence(secretFile("GIFTAPP_API_KEY"))
	state.LastRefresh = time.Now().UTC().Format(time.RFC3339)
	log.Printf("loaded hardcoded Kubernetes Secret mounts")
}

func loadWithSWA(ctx context.Context, state *appState) {
	state.DB["user"] = secretFile("DB_USER")
	state.DB["host"] = secretFile("DB_HOST")
	state.DB["port"] = secretFile("DB_PORT")
	state.DB["name"] = secretFile("DB_NAME")

	token, err := fetchJWTSVID(ctx, getenv("SPIFFE_ENDPOINT_SOCKET", "unix:///tmp/swa-agent/public/api.sock"))
	if err != nil {
		state.LastError = fmt.Sprintf("fetch jwt-svid: %v", err)
		log.Print(state.LastError)
		return
	}
	logJWTClaims(token)

	conjurToken, err := authenticateConjur(ctx, token)
	if err != nil {
		state.LastError = fmt.Sprintf("authenticate conjur: %v", err)
		log.Print(state.LastError)
		return
	}

	dbPass, err := fetchConjurSecret(ctx, conjurToken, os.Getenv("DB_PASS_SECRET_ID"))
	if err != nil {
		state.LastError = fmt.Sprintf("fetch db password: %v", err)
		log.Print(state.LastError)
		return
	}
	apiKey, err := fetchConjurSecret(ctx, conjurToken, os.Getenv("GIFTAPP_API_KEY_SECRET_ID"))
	if err != nil {
		state.LastError = fmt.Sprintf("fetch api key: %v", err)
		log.Print(state.LastError)
		return
	}

	state.SWAReady = true
	state.Secrets["dbPassword"] = presence(dbPass)
	state.Secrets["giftappApiKey"] = presence(apiKey)
	state.LastRefresh = time.Now().UTC().Format(time.RFC3339)
	log.Printf("loaded secrets through SWA JWT-SVID and Conjur")
}

func fetchJWTSVID(ctx context.Context, socket string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	source, err := workloadapi.NewJWTSource(ctx, workloadapi.WithClientOptions(workloadapi.WithAddr(socket)))
	if err != nil {
		return "", err
	}
	defer source.Close()

	svid, err := source.FetchJWTSVID(ctx, jwtsvid.Params{Audience: "conjur"})
	if err != nil {
		return "", err
	}
	return svid.Marshal(), nil
}

func logJWTClaims(token string) {
	parts := strings.Split(token, ".")
	if len(parts) < 2 {
		return
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return
	}
	var claims struct {
		Iss string `json:"iss"`
		Sub string `json:"sub"`
		Aud any    `json:"aud"`
	}
	if err := json.Unmarshal(payload, &claims); err != nil {
		return
	}
	log.Printf("jwt-svid claims iss=%q sub=%q aud=%v", claims.Iss, claims.Sub, claims.Aud)
}

func authenticateConjur(ctx context.Context, jwt string) (string, error) {
	base := requiredEnv("CONJUR_APPLIANCE_URL")
	authenticator := requiredEnv("CONJUR_AUTHENTICATOR_ID")
	account := requiredEnv("CONJUR_ACCOUNT")
	endpoint := fmt.Sprintf("%s/%s/%s/authenticate", strings.TrimRight(base, "/"), authenticator, account)

	form := url.Values{}
	form.Set("jwt", jwt)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept-Encoding", "base64")

	body, err := do(req)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(body), nil
}

func fetchConjurSecret(ctx context.Context, token, id string) (string, error) {
	if id == "" {
		return "", errors.New("secret id is empty")
	}
	base := requiredEnv("CONJUR_APPLIANCE_URL")
	account := requiredEnv("CONJUR_ACCOUNT")
	endpoint := fmt.Sprintf("%s/secrets/%s/variable/%s", strings.TrimRight(base, "/"), account, url.PathEscape(id))

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", fmt.Sprintf(`Token token="%s"`, token))

	return do(req)
}

func do(req *http.Request) (string, error) {
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, readErr := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return "", fmt.Errorf("%s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	if readErr != nil {
		return "", readErr
	}
	return string(body), nil
}

func secretFile(name string) string {
	value, err := os.ReadFile(filepath.Join("/etc/secrets", name))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(value))
}

func presence(value string) string {
	if value == "" {
		return "missing"
	}
	return "present"
}

func getenv(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func requiredEnv(name string) string {
	value := os.Getenv(name)
	if value == "" {
		log.Fatalf("%s is required", name)
	}
	return value
}

func writeJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("write response: %v", err)
	}
}
