package aggregator

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestParseRetryAfterSeconds(t *testing.T) {
	d := parseRetryAfter("7")
	if d != 7*time.Second {
		t.Fatalf("expected 7s, got %s", d)
	}
}

func TestParseRetryAfterHTTPDate(t *testing.T) {
	target := time.Now().Add(10 * time.Second).UTC()
	h := strings.Replace(target.Format(time.RFC1123), "UTC", "GMT", 1)
	d := parseRetryAfter(h)
	if d <= 0 {
		t.Fatalf("expected positive duration, got %s", d)
	}
}

func TestErrRateLimitedErrorIncludesRetry(t *testing.T) {
	err := (&ErrRateLimited{RetryAfter: 3 * time.Second}).Error()
	expected := "rate limited (retry after 3s)"
	if err != expected {
		t.Fatalf("expected %q, got %q", expected, err)
	}
}

func TestErrRateLimitedErrorWithoutRetry(t *testing.T) {
	err := (&ErrRateLimited{}).Error()
	if err != "rate limited" {
		t.Fatalf("unexpected message: %s", err)
	}
}

func TestIsBatchUnavailablePayload(t *testing.T) {
	body := `{"success":false,"data":{"success":false,"data":{"message":"Requested batch 17 is not available"}}}`
	if !isBatchUnavailablePayload(http.StatusNotFound, body) {
		t.Fatalf("expected payload to be treated as terminal batch-not-available")
	}
}

func TestIsBatchUnavailablePayloadWrongStatus(t *testing.T) {
	body := `{"message":"Requested batch 17 is not available"}`
	if isBatchUnavailablePayload(http.StatusBadRequest, body) {
		t.Fatalf("did not expect non-404 status to be terminal batch-not-available")
	}
}
