package aggregator

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const apiBaseURL = "https://www.fuel-finder.service.gov.uk/api/v1"

func route(path string) string {
	return apiBaseURL + path
}

type HTTPService struct {
	client *http.Client
}

func NewHTTPService(client *http.Client) *HTTPService {
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	return &HTTPService{client: client}
}

type OAuthCredentials struct {
	ClientID     string `json:"client_id"`
	ClientSecret string `json:"client_secret"`
}

type tokenResponse struct {
	Success bool `json:"success"`
	Data    *struct {
		AccessToken  string `json:"access_token"`
		TokenType    string `json:"token_type"`
		ExpiresIn    int    `json:"expires_in"`
		RefreshToken string `json:"refresh_token"`
	} `json:"data"`
	Message string `json:"message"`
}

type ErrRateLimited struct {
	RetryAfter time.Duration
}

func (e *ErrRateLimited) Error() string {
	if e.RetryAfter > 0 {
		return fmt.Sprintf("rate limited (retry after %s)", e.RetryAfter)
	}
	return "rate limited"
}

type ErrHTTPStatus struct {
	StatusCode int
}

func (e *ErrHTTPStatus) Error() string {
	return fmt.Sprintf("unexpected status code: %d", e.StatusCode)
}

type ErrBatchUnavailable struct {
	Message string
}

func (e *ErrBatchUnavailable) Error() string {
	if e.Message != "" {
		return e.Message
	}
	return "requested batch is not available"
}

func parseRetryAfter(v string) time.Duration {
	if v == "" {
		return 0
	}

	if seconds, err := strconv.Atoi(strings.TrimSpace(v)); err == nil {
		if seconds < 0 {
			return 0
		}
		return time.Duration(seconds) * time.Second
	}

	if t, err := http.ParseTime(v); err == nil {
		d := time.Until(t)
		if d < 0 {
			return 0
		}
		return d
	}

	return 0
}

func (s *HTTPService) GetToken(ctx context.Context, credentials OAuthCredentials) (string, error) {
	form := url.Values{}
	form.Set("grant_type", "client_credentials")
	form.Set("client_id", credentials.ClientID)
	form.Set("client_secret", credentials.ClientSecret)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, route("/oauth/generate_access_token"), strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusTooManyRequests {
		return "", &ErrRateLimited{RetryAfter: parseRetryAfter(resp.Header.Get("Retry-After"))}
	}
	if resp.StatusCode != http.StatusOK {
		return "", &ErrHTTPStatus{StatusCode: resp.StatusCode}
	}

	var tokenResp tokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
		return "", fmt.Errorf("failed to decode token response: %w", err)
	}
	if !tokenResp.Success || tokenResp.Data == nil {
		return "", fmt.Errorf("token request failed: %s", tokenResp.Message)
	}

	return tokenResp.Data.AccessToken, nil
}

func isBatchUnavailablePayload(statusCode int, body string) bool {
	if statusCode != http.StatusNotFound {
		return false
	}
	lower := strings.ToLower(body)
	return strings.Contains(lower, "requested batch") && strings.Contains(lower, "not available")
}

func (s *HTTPService) doGET(ctx context.Context, token string, endpoint string, query url.Values, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, route(endpoint), nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}
	req.URL.RawQuery = query.Encode()
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusTooManyRequests {
		return &ErrRateLimited{RetryAfter: parseRetryAfter(resp.Header.Get("Retry-After"))}
	}
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 8*1024))
		message := strings.TrimSpace(string(body))
		if isBatchUnavailablePayload(resp.StatusCode, message) {
			return &ErrBatchUnavailable{Message: message}
		}
		return &ErrHTTPStatus{StatusCode: resp.StatusCode}
	}

	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("failed to decode response: %w", err)
	}
	return nil
}

func (s *HTTPService) GetAllPFSFuelPrices(ctx context.Context, token string, batchNumber int) ([]PFSFuelPrices, error) {
	q := url.Values{}
	q.Add("batch_number", fmt.Sprintf("%d", batchNumber))

	var fuelPrices []PFSFuelPrices
	if err := s.doGET(ctx, token, "/pfs/fuel-prices", q, &fuelPrices); err != nil {
		return nil, err
	}
	return fuelPrices, nil
}

func (s *HTTPService) GetIncrementalPFSFuelPrices(ctx context.Context, token string, effectiveStartTimestamp time.Time, batchNumber int) ([]PFSFuelPrices, error) {
	q := url.Values{}
	q.Add("batch_number", fmt.Sprintf("%d", batchNumber))
	q.Add("effective-start-timestamp", effectiveStartTimestamp.UTC().Format(time.RFC3339))

	var fuelPrices []PFSFuelPrices
	if err := s.doGET(ctx, token, "/pfs/fuel-prices", q, &fuelPrices); err != nil {
		return nil, err
	}
	return fuelPrices, nil
}

func (s *HTTPService) GetAllPFSInformation(ctx context.Context, token string, batchNumber int) ([]PFSInformation, error) {
	q := url.Values{}
	q.Add("batch_number", fmt.Sprintf("%d", batchNumber))

	var information []PFSInformation
	if err := s.doGET(ctx, token, "/pfs", q, &information); err != nil {
		return nil, err
	}
	return information, nil
}

func (s *HTTPService) GetIncrementalPFSInformation(ctx context.Context, token string, effectiveStartTimestamp time.Time, batchNumber int) ([]PFSInformation, error) {
	q := url.Values{}
	q.Add("batch_number", fmt.Sprintf("%d", batchNumber))
	q.Add("effective-start-timestamp", effectiveStartTimestamp.UTC().Format(time.RFC3339))

	var information []PFSInformation
	if err := s.doGET(ctx, token, "/pfs", q, &information); err != nil {
		return nil, err
	}
	return information, nil
}
