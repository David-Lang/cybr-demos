package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/spiffe/go-spiffe/v2/svid/jwtsvid"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

type cspTestResult struct {
	Cloud    string `json:"cloud"`
	SpiffeID string `json:"spiffeId"`
	Audience string `json:"audience"`
	Source   string `json:"source"`
	Content  string `json:"content,omitempty"`
	Error    string `json:"error,omitempty"`
}

func newCSPTestHandler(mode, socket string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if mode != "swa" {
			http.Error(w, "csp-test only available in swa mode", http.StatusBadRequest)
			return
		}
		cloud := r.URL.Query().Get("cloud")
		if cloud == "" {
			http.Error(w, "cloud query param required: aws, azure, or gcp", http.StatusBadRequest)
			return
		}
		result, err := cspTest(r.Context(), cloud, socket)
		if err != nil {
			result.Error = err.Error()
		}
		writeJSON(w, result)
	}
}

func cspTest(ctx context.Context, cloud, socket string) (cspTestResult, error) {
	switch cloud {
	case "aws":
		return awsS3Test(ctx, socket)
	case "azure":
		return azureBlobTest(ctx, socket)
	case "gcp":
		return gcpStorageTest(ctx, socket)
	default:
		return cspTestResult{Cloud: cloud},
			fmt.Errorf("unknown cloud %q — valid values: aws, azure, gcp", cloud)
	}
}

// ── SVID fetch ────────────────────────────────────────────────────────────────

func fetchSVID(ctx context.Context, socket, audience string) (token, spiffeID string, err error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	source, err := workloadapi.NewJWTSource(ctx,
		workloadapi.WithClientOptions(workloadapi.WithAddr(socket)))
	if err != nil {
		return "", "", err
	}
	defer source.Close()

	svid, err := source.FetchJWTSVID(ctx, jwtsvid.Params{Audience: audience})
	if err != nil {
		return "", "", err
	}
	return svid.Marshal(), svid.ID.String(), nil
}

// ── AWS ───────────────────────────────────────────────────────────────────────

type awsCreds struct {
	AccessKeyId     string
	SecretAccessKey string
	SessionToken    string
}

func awsS3Test(ctx context.Context, socket string) (cspTestResult, error) {
	roleARN := os.Getenv("AWS_SPIFFE_ROLE_ARN")
	bucket := os.Getenv("AWS_SPIFFE_BUCKET")
	region := os.Getenv("AWS_SPIFFE_REGION")
	if roleARN == "" || bucket == "" || region == "" {
		return cspTestResult{Cloud: "aws"},
			fmt.Errorf("AWS_SPIFFE_ROLE_ARN, AWS_SPIFFE_BUCKET, and AWS_SPIFFE_REGION must be set")
	}

	jwt, spiffeID, err := fetchSVID(ctx, socket, "sts.amazonaws.com")
	if err != nil {
		return cspTestResult{Cloud: "aws", Audience: "sts.amazonaws.com"},
			fmt.Errorf("fetch svid: %w", err)
	}

	creds, err := stsAssumeRole(ctx, roleARN, jwt)
	if err != nil {
		return cspTestResult{Cloud: "aws", SpiffeID: spiffeID, Audience: "sts.amazonaws.com"},
			fmt.Errorf("sts assume role: %w", err)
	}

	content, err := s3GetObject(ctx, bucket, "test.txt", region, creds)
	if err != nil {
		return cspTestResult{Cloud: "aws", SpiffeID: spiffeID, Audience: "sts.amazonaws.com"},
			fmt.Errorf("s3 get object: %w", err)
	}

	return cspTestResult{
		Cloud:    "aws",
		SpiffeID: spiffeID,
		Audience: "sts.amazonaws.com",
		Source:   fmt.Sprintf("s3://%s/test.txt", bucket),
		Content:  strings.TrimSpace(content),
	}, nil
}

func stsAssumeRole(ctx context.Context, roleARN, jwt string) (awsCreds, error) {
	form := url.Values{}
	form.Set("Action", "AssumeRoleWithWebIdentity")
	form.Set("Version", "2011-06-15")
	form.Set("RoleArn", roleARN)
	form.Set("RoleSessionName", "spiffe-session")
	form.Set("WebIdentityToken", jwt)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://sts.amazonaws.com/", strings.NewReader(form.Encode()))
	if err != nil {
		return awsCreds{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	body, err := do(req)
	if err != nil {
		return awsCreds{}, err
	}

	// Strip the default namespace so Go's xml decoder can match by local name.
	body = strings.ReplaceAll(body,
		` xmlns="https://sts.amazonaws.com/doc/2011-06-15/"`, "")

	var resp struct {
		Result struct {
			Credentials struct {
				AccessKeyId     string `xml:"AccessKeyId"`
				SecretAccessKey string `xml:"SecretAccessKey"`
				SessionToken    string `xml:"SessionToken"`
			} `xml:"Credentials"`
		} `xml:"AssumeRoleWithWebIdentityResult"`
	}
	if err := xml.Unmarshal([]byte(body), &resp); err != nil {
		return awsCreds{}, fmt.Errorf("parse sts response: %w", err)
	}
	return awsCreds{
		AccessKeyId:     resp.Result.Credentials.AccessKeyId,
		SecretAccessKey: resp.Result.Credentials.SecretAccessKey,
		SessionToken:    resp.Result.Credentials.SessionToken,
	}, nil
}

func s3GetObject(ctx context.Context, bucket, key, region string, creds awsCreds) (string, error) {
	host := fmt.Sprintf("%s.s3.%s.amazonaws.com", bucket, region)
	now := time.Now().UTC()
	dateTime := now.Format("20060102T150405Z")
	date := now.Format("20060102")

	payloadHash := awsSHA256Hex("")

	type hdr struct{ name, val string }
	headers := []hdr{
		{"host", host},
		{"x-amz-content-sha256", payloadHash},
		{"x-amz-date", dateTime},
	}
	if creds.SessionToken != "" {
		headers = append(headers, hdr{"x-amz-security-token", creds.SessionToken})
	}
	sort.Slice(headers, func(i, j int) bool { return headers[i].name < headers[j].name })

	var canonHeaders strings.Builder
	signedNames := make([]string, len(headers))
	for i, h := range headers {
		canonHeaders.WriteString(h.name + ":" + h.val + "\n")
		signedNames[i] = h.name
	}
	signedHeadersStr := strings.Join(signedNames, ";")

	canonReq := strings.Join([]string{
		"GET", "/" + key, "",
		canonHeaders.String(),
		signedHeadersStr,
		payloadHash,
	}, "\n")

	credScope := strings.Join([]string{date, region, "s3", "aws4_request"}, "/")
	strToSign := strings.Join([]string{
		"AWS4-HMAC-SHA256", dateTime, credScope, awsSHA256Hex(canonReq),
	}, "\n")

	sigKey := awsSigningKey(creds.SecretAccessKey, date, region, "s3")
	sig := hex.EncodeToString(awsHMACSHA256(sigKey, strToSign))
	authHeader := fmt.Sprintf(
		"AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
		creds.AccessKeyId, credScope, signedHeadersStr, sig,
	)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		fmt.Sprintf("https://%s/%s", host, key), nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("x-amz-date", dateTime)
	req.Header.Set("x-amz-content-sha256", payloadHash)
	req.Header.Set("Authorization", authHeader)
	if creds.SessionToken != "" {
		req.Header.Set("x-amz-security-token", creds.SessionToken)
	}
	return do(req)
}

func awsHMACSHA256(key []byte, data string) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(data))
	return mac.Sum(nil)
}

func awsSHA256Hex(data string) string {
	sum := sha256.Sum256([]byte(data))
	return hex.EncodeToString(sum[:])
}

func awsSigningKey(secret, date, region, service string) []byte {
	kDate := awsHMACSHA256([]byte("AWS4"+secret), date)
	kRegion := awsHMACSHA256(kDate, region)
	kService := awsHMACSHA256(kRegion, service)
	return awsHMACSHA256(kService, "aws4_request")
}

// ── Azure ─────────────────────────────────────────────────────────────────────

func azureBlobTest(ctx context.Context, socket string) (cspTestResult, error) {
	clientID := os.Getenv("AZURE_SPIFFE_CLIENT_ID")
	tenantID := os.Getenv("AZURE_SPIFFE_TENANT_ID")
	storageAcct := os.Getenv("AZURE_SPIFFE_STORAGE_ACCOUNT")
	container := os.Getenv("AZURE_SPIFFE_CONTAINER")
	if clientID == "" || tenantID == "" || storageAcct == "" || container == "" {
		return cspTestResult{Cloud: "azure"},
			fmt.Errorf("AZURE_SPIFFE_CLIENT_ID, AZURE_SPIFFE_TENANT_ID, AZURE_SPIFFE_STORAGE_ACCOUNT, and AZURE_SPIFFE_CONTAINER must be set")
	}

	audience := "api://AzureADTokenExchange"
	jwt, spiffeID, err := fetchSVID(ctx, socket, audience)
	if err != nil {
		return cspTestResult{Cloud: "azure", Audience: audience},
			fmt.Errorf("fetch svid: %w", err)
	}

	entraToken, err := entraTokenExchange(ctx, tenantID, clientID, jwt,
		"https://storage.azure.com/.default")
	if err != nil {
		return cspTestResult{Cloud: "azure", SpiffeID: spiffeID, Audience: audience},
			fmt.Errorf("entra token exchange: %w", err)
	}

	blobURL := fmt.Sprintf("https://%s.blob.core.windows.net/%s/test.txt",
		storageAcct, container)
	content, err := bearerGet(ctx, blobURL, entraToken,
		map[string]string{"x-ms-version": "2020-04-08"})
	if err != nil {
		return cspTestResult{Cloud: "azure", SpiffeID: spiffeID, Audience: audience},
			fmt.Errorf("blob get: %w", err)
	}

	return cspTestResult{
		Cloud:    "azure",
		SpiffeID: spiffeID,
		Audience: audience,
		Source:   blobURL,
		Content:  strings.TrimSpace(content),
	}, nil
}

func entraTokenExchange(ctx context.Context, tenantID, clientID, jwt, scope string) (string, error) {
	form := url.Values{}
	form.Set("grant_type", "client_credentials")
	form.Set("client_id", clientID)
	form.Set("client_assertion_type",
		"urn:ietf:params:oauth:client-assertion-type:jwt-bearer")
	form.Set("client_assertion", jwt)
	form.Set("scope", scope)

	endpoint := fmt.Sprintf(
		"https://login.microsoftonline.com/%s/oauth2/v2.0/token", tenantID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint,
		strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	body, err := do(req)
	if err != nil {
		return "", err
	}

	var resp struct {
		AccessToken string `json:"access_token"`
		Error       string `json:"error"`
		Description string `json:"error_description"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return "", fmt.Errorf("parse entra response: %w", err)
	}
	if resp.Error != "" {
		return "", fmt.Errorf("%s: %s", resp.Error, resp.Description)
	}
	return resp.AccessToken, nil
}

// ── GCP ───────────────────────────────────────────────────────────────────────

func gcpStorageTest(ctx context.Context, socket string) (cspTestResult, error) {
	poolAudience := os.Getenv("GCP_SPIFFE_POOL_AUDIENCE")
	saEmail := os.Getenv("GCP_SPIFFE_SA_EMAIL")
	bucket := os.Getenv("GCP_SPIFFE_BUCKET")
	if poolAudience == "" || saEmail == "" || bucket == "" {
		return cspTestResult{Cloud: "gcp"},
			fmt.Errorf("GCP_SPIFFE_POOL_AUDIENCE, GCP_SPIFFE_SA_EMAIL, and GCP_SPIFFE_BUCKET must be set")
	}

	jwt, spiffeID, err := fetchSVID(ctx, socket, poolAudience)
	if err != nil {
		return cspTestResult{Cloud: "gcp", Audience: poolAudience},
			fmt.Errorf("fetch svid: %w", err)
	}

	stsToken, err := gcpSTSExchange(ctx, poolAudience, jwt)
	if err != nil {
		return cspTestResult{Cloud: "gcp", SpiffeID: spiffeID, Audience: poolAudience},
			fmt.Errorf("gcp sts exchange: %w", err)
	}

	accessToken, err := gcpImpersonateSA(ctx, saEmail, stsToken)
	if err != nil {
		return cspTestResult{Cloud: "gcp", SpiffeID: spiffeID, Audience: poolAudience},
			fmt.Errorf("gcp impersonate sa: %w", err)
	}

	gcsURL := fmt.Sprintf(
		"https://storage.googleapis.com/storage/v1/b/%s/o/test.txt?alt=media", bucket)
	content, err := bearerGet(ctx, gcsURL, accessToken, nil)
	if err != nil {
		return cspTestResult{Cloud: "gcp", SpiffeID: spiffeID, Audience: poolAudience},
			fmt.Errorf("gcs get: %w", err)
	}

	return cspTestResult{
		Cloud:    "gcp",
		SpiffeID: spiffeID,
		Audience: poolAudience,
		Source:   fmt.Sprintf("gs://%s/test.txt", bucket),
		Content:  strings.TrimSpace(content),
	}, nil
}

func gcpSTSExchange(ctx context.Context, poolAudience, jwt string) (string, error) {
	payload, err := json.Marshal(map[string]string{
		"audience":           poolAudience,
		"grantType":          "urn:ietf:params:oauth:grant-type:token-exchange",
		"requestedTokenType": "urn:ietf:params:oauth:token-type:access_token",
		"scope":              "https://www.googleapis.com/auth/cloud-platform",
		"subjectTokenType":   "urn:ietf:params:oauth:token-type:jwt",
		"subjectToken":       jwt,
	})
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://sts.googleapis.com/v1/token", strings.NewReader(string(payload)))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	body, err := do(req)
	if err != nil {
		return "", err
	}

	var resp struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return "", fmt.Errorf("parse gcp sts response: %w", err)
	}
	return resp.AccessToken, nil
}

func gcpImpersonateSA(ctx context.Context, saEmail, stsToken string) (string, error) {
	payload, err := json.Marshal(map[string]interface{}{
		"scope": []string{"https://www.googleapis.com/auth/cloud-platform"},
	})
	if err != nil {
		return "", err
	}

	endpoint := fmt.Sprintf(
		"https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/%s:generateAccessToken",
		saEmail)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint,
		strings.NewReader(string(payload)))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+stsToken)

	body, err := do(req)
	if err != nil {
		return "", err
	}

	var resp struct {
		AccessToken string `json:"accessToken"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return "", fmt.Errorf("parse gcp iam response: %w", err)
	}
	return resp.AccessToken, nil
}

// ── Shared ────────────────────────────────────────────────────────────────────

func bearerGet(ctx context.Context, rawURL, token string, extraHeaders map[string]string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	for k, v := range extraHeaders {
		req.Header.Set(k, v)
	}
	return do(req)
}
