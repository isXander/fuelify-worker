package aggregator

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"time"
)

const (
	requestsPerMinute = 30
	requestInterval   = time.Minute / requestsPerMinute
)

type ServiceConfig struct {
	ClientID        string
	ClientSecret    string
	InfoSyncPeriod  time.Duration
	FullSyncOnStart bool
}

type Service struct {
	http   *HTTPService
	repo   *Repository
	cfg    ServiceConfig
	logger *log.Logger
}

func NewService(httpSvc *HTTPService, repo *Repository, cfg ServiceConfig, logger *log.Logger) *Service {
	if cfg.InfoSyncPeriod <= 0 {
		cfg.InfoSyncPeriod = 15 * time.Minute
	}
	if logger == nil {
		logger = log.Default()
	}

	return &Service{
		http:   httpSvc,
		repo:   repo,
		cfg:    cfg,
		logger: logger,
	}
}

func (s *Service) Run(ctx context.Context) error {
	token, err := s.refreshToken(ctx)
	if err != nil {
		return fmt.Errorf("get token: %w", err)
	}

	fuelCursor, err := s.repo.SyncCursor(ctx, cursorFuelPrices)
	if err != nil {
		return fmt.Errorf("load fuel cursor: %w", err)
	}
	informationCursor, err := s.repo.SyncCursor(ctx, cursorInformation)
	if err != nil {
		return fmt.Errorf("load information cursor: %w", err)
	}

	if s.cfg.FullSyncOnStart {
		s.logger.Println("running full bootstrap sync")
		if err := s.syncAllInformation(ctx, token); err != nil {
			s.logger.Printf("full information sync failed: %v", err)
		}
		if err := s.syncAllFuelPrices(ctx, token); err != nil {
			s.logger.Printf("full fuel price sync failed: %v", err)
		}
	}

	ticker := time.NewTicker(requestInterval)
	defer ticker.Stop()

	nextInfoSync := time.Now().UTC()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			now := time.Now().UTC()
			if now.After(nextInfoSync) {
				if err := s.syncIncrementalInformation(ctx, token, informationCursor); err != nil {
					if isUnauthorized(err) {
						if refreshedToken, refreshErr := s.refreshToken(ctx); refreshErr == nil {
							token = refreshedToken
							continue
						}
					}
					s.logger.Printf("incremental information sync failed: %v", err)
				} else {
					informationCursor = now
					if err := s.repo.SetSyncCursor(ctx, cursorInformation, informationCursor); err != nil {
						s.logger.Printf("persist information cursor failed: %v", err)
					}
					nextInfoSync = now.Add(s.cfg.InfoSyncPeriod)
				}
				continue
			}

			if err := s.syncIncrementalFuelPrices(ctx, token, fuelCursor); err != nil {
				if isUnauthorized(err) {
					if refreshedToken, refreshErr := s.refreshToken(ctx); refreshErr == nil {
						token = refreshedToken
						continue
					}
				}
				s.logger.Printf("incremental fuel sync failed: %v", err)
				continue
			}
			fuelCursor = now
			if err := s.repo.SetSyncCursor(ctx, cursorFuelPrices, fuelCursor); err != nil {
				s.logger.Printf("persist fuel cursor failed: %v", err)
			}
		}
	}
}

func (s *Service) refreshToken(ctx context.Context) (string, error) {
	token, err := withRateLimitRetry(ctx, s.logger, func(runCtx context.Context) (string, error) {
		return s.http.GetToken(runCtx, OAuthCredentials{
			ClientID:     s.cfg.ClientID,
			ClientSecret: s.cfg.ClientSecret,
		})
	})
	if err != nil {
		return "", err
	}
	s.logger.Println("access token refreshed")
	return token, nil
}

func (s *Service) syncAllInformation(ctx context.Context, token string) error {
	for batch := 1; ; batch++ {
		rows, err := withRateLimitRetry(ctx, s.logger, func(runCtx context.Context) ([]PFSInformation, error) {
			return s.http.GetAllPFSInformation(runCtx, token, batch)
		})
		if isBatchUnavailable(err) {
			return nil
		}
		if err != nil {
			return err
		}
		for _, row := range rows {
			if err := s.repo.SaveInformation(ctx, row); err != nil {
				return err
			}
		}
	}
}

func (s *Service) syncAllFuelPrices(ctx context.Context, token string) error {
	for batch := 1; ; batch++ {
		rows, err := withRateLimitRetry(ctx, s.logger, func(runCtx context.Context) ([]PFSFuelPrices, error) {
			return s.http.GetAllPFSFuelPrices(runCtx, token, batch)
		})
		if isBatchUnavailable(err) {
			return nil
		}
		if err != nil {
			return err
		}
		for _, row := range rows {
			if err := s.repo.SaveFuelPrices(ctx, row); err != nil {
				return err
			}
		}
	}
}

func (s *Service) syncIncrementalInformation(ctx context.Context, token string, since time.Time) error {
	for batch := 1; ; batch++ {
		rows, err := withRateLimitRetry(ctx, s.logger, func(runCtx context.Context) ([]PFSInformation, error) {
			return s.http.GetIncrementalPFSInformation(runCtx, token, since.UTC(), batch)
		})
		if isBatchUnavailable(err) {
			return nil
		}
		if err != nil {
			return err
		}
		for _, row := range rows {
			if err := s.repo.SaveInformation(ctx, row); err != nil {
				return err
			}
		}
	}
}

func (s *Service) syncIncrementalFuelPrices(ctx context.Context, token string, since time.Time) error {
	for batch := 1; ; batch++ {
		rows, err := withRateLimitRetry(ctx, s.logger, func(runCtx context.Context) ([]PFSFuelPrices, error) {
			return s.http.GetIncrementalPFSFuelPrices(runCtx, token, since.UTC(), batch)
		})
		if isBatchUnavailable(err) {
			return nil
		}
		if err != nil {
			return err
		}
		for _, row := range rows {
			if err := s.repo.SaveFuelPrices(ctx, row); err != nil {
				return err
			}
		}
	}
}

func isBatchUnavailable(err error) bool {
	var batchErr *ErrBatchUnavailable
	return errors.As(err, &batchErr)
}

func withRateLimitRetry[T any](ctx context.Context, logger *log.Logger, fn func(context.Context) (T, error)) (T, error) {
	var zero T
	for {
		out, err := fn(ctx)
		if err == nil {
			return out, nil
		}

		var rateErr *ErrRateLimited
		if !errors.As(err, &rateErr) {
			return zero, err
		}

		wait := rateErr.RetryAfter
		if wait <= 0 {
			wait = 5 * time.Second
		}

		logger.Printf("429 received, throttling for %s", wait)

		timer := time.NewTimer(wait)
		select {
		case <-ctx.Done():
			timer.Stop()
			return zero, ctx.Err()
		case <-timer.C:
		}
	}
}

func isUnauthorized(err error) bool {
	var statusErr *ErrHTTPStatus
	if !errors.As(err, &statusErr) {
		return false
	}
	return statusErr.StatusCode == http.StatusUnauthorized
}
