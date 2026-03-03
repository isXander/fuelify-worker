package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"fuelify/internal/aggregator"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL is required")
	}

	clientID := os.Getenv("AGGREGATOR_CLIENT_ID")
	clientSecret := os.Getenv("AGGREGATOR_CLIENT_SECRET")
	if clientID == "" || clientSecret == "" {
		log.Fatal("AGGREGATOR_CLIENT_ID and AGGREGATOR_CLIENT_SECRET are required")
	}

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer pool.Close()

	httpSvc := aggregator.NewHTTPService(&http.Client{Timeout: 30 * time.Second})
	repo := aggregator.NewRepository(pool)

	service := aggregator.NewService(httpSvc, repo, aggregator.ServiceConfig{
		ClientID:        clientID,
		ClientSecret:    clientSecret,
		InfoSyncPeriod:  envDuration("AGGREGATOR_INFO_SYNC_PERIOD", 15*time.Minute),
		FullSyncOnStart: envBool("AGGREGATOR_FULL_SYNC_ON_START", false),
	}, log.Default())

	if err := service.Run(ctx); err != nil && err != context.Canceled {
		log.Fatalf("aggregator stopped: %v", err)
	}
}

func envDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}

func envBool(key string, fallback bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return fallback
	}
	return b
}
