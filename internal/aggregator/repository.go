package aggregator

import (
	"context"
	"errors"
	"fmt"
	"time"

	"fuelify/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	cursorInformation = "pfs_information"
	cursorFuelPrices  = "pfs_fuel_prices"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) SyncCursor(ctx context.Context, key string) (time.Time, error) {
	q := db.New(r.pool)
	cursor, err := q.GetSyncCursor(ctx, key)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return time.Now().UTC().Add(-5 * time.Minute), nil
		}
		return time.Time{}, err
	}

	if !cursor.LastEffectiveTs.Valid {
		return time.Now().UTC().Add(-5 * time.Minute), nil
	}

	return cursor.LastEffectiveTs.Time.UTC(), nil
}

func (r *Repository) SetSyncCursor(ctx context.Context, key string, ts time.Time) error {
	q := db.New(r.pool)
	return q.UpsertSyncCursor(ctx, db.UpsertSyncCursorParams{
		CursorKey: key,
		LastEffectiveTs: pgtype.Timestamptz{
			Time:  ts.UTC(),
			Valid: true,
		},
	})
}

func (r *Repository) SaveInformation(ctx context.Context, item PFSInformation) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	q := db.New(tx)
	if err := q.UpsertPFS(ctx, db.UpsertPFSParams{
		ID:               item.NodeID,
		PhoneNumber:      item.PublicPhoneNumber,
		TradingName:      item.TradingName,
		BrandName:        item.BrandName,
		TradingAsBrand:   item.IsSameTradingAndBrandName,
		TemporaryClosure: item.TemporaryClosure,
		PermanentClosure: item.PermanentClosure,
		Motorway:         item.IsMotorwayServiceStation,
		Supermarket:      item.IsSupermarketServiceStation,
	}); err != nil {
		return err
	}

	if err := q.UpsertLocation(ctx, db.UpsertLocationParams{
		StationID:    item.NodeID,
		AddressLine1: item.Location.AddressLine1,
		AddressLine2: item.Location.AddressLine2,
		City:         item.Location.City,
		Country:      item.Location.Country,
		County:       item.Location.County,
		Postcode:     item.Location.Postcode,
		Latitude:     item.Location.Latitude,
		Longitude:    item.Location.Longitude,
	}); err != nil {
		return err
	}

	if err := q.DeleteAmenitiesForStation(ctx, item.NodeID); err != nil {
		return err
	}
	for _, amenity := range item.Amenities {
		if err := q.InsertAmenity(ctx, db.InsertAmenityParams{StationID: item.NodeID, Type: string(amenity)}); err != nil {
			return err
		}
	}

	if err := q.DeleteOpeningHoursForStation(ctx, item.NodeID); err != nil {
		return err
	}
	for _, h := range openingHoursRows(item) {
		if err := q.InsertOpeningHour(ctx, db.InsertOpeningHourParams{
			StationID: item.NodeID,
			Day:       h.day,
			OpenTime:  h.open,
			CloseTime: h.close,
			Is24Hours: h.is24,
		}); err != nil {
			return err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return err
	}
	return nil
}

func (r *Repository) SaveFuelPrices(ctx context.Context, item PFSFuelPrices) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	q := db.New(tx)
	if err := ensureStationExists(ctx, q, item); err != nil {
		return err
	}

	if err := q.DeleteFuelPricesForStation(ctx, item.NodeID); err != nil {
		return err
	}
	for _, p := range item.FuelPrices {
		if err := q.InsertFuelPrice(ctx, db.InsertFuelPriceParams{
			StationID: item.NodeID,
			FuelType:  string(p.FuelType),
			Price:     p.Price,
		}); err != nil {
			return err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return err
	}
	return nil
}

func ensureStationExists(ctx context.Context, q *db.Queries, item PFSFuelPrices) error {
	_, err := q.GetPFS(ctx, item.NodeID)
	if err == nil {
		return nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	if item.TradingName == "" {
		return fmt.Errorf("cannot create station %s from fuel payload without trading_name", item.NodeID)
	}

	return q.UpsertPFS(ctx, db.UpsertPFSParams{
		ID:               item.NodeID,
		PhoneNumber:      item.PublicPhoneNumber,
		TradingName:      item.TradingName,
		BrandName:        item.TradingName,
		TradingAsBrand:   true,
		TemporaryClosure: false,
		PermanentClosure: false,
		Motorway:         false,
		Supermarket:      false,
	})
}

type openingHoursRow struct {
	day   string
	open  string
	close string
	is24  bool
}

func openingHoursRows(item PFSInformation) []openingHoursRow {
	rows := []openingHoursRow{
		{day: "monday", open: item.OpeningTimes.UsualDays.Monday.Open, close: item.OpeningTimes.UsualDays.Monday.Close, is24: item.OpeningTimes.UsualDays.Monday.Is24Hours},
		{day: "tuesday", open: item.OpeningTimes.UsualDays.Tuesday.Open, close: item.OpeningTimes.UsualDays.Tuesday.Close, is24: item.OpeningTimes.UsualDays.Tuesday.Is24Hours},
		{day: "wednesday", open: item.OpeningTimes.UsualDays.Wednesday.Open, close: item.OpeningTimes.UsualDays.Wednesday.Close, is24: item.OpeningTimes.UsualDays.Wednesday.Is24Hours},
		{day: "thursday", open: item.OpeningTimes.UsualDays.Thursday.Open, close: item.OpeningTimes.UsualDays.Thursday.Close, is24: item.OpeningTimes.UsualDays.Thursday.Is24Hours},
		{day: "friday", open: item.OpeningTimes.UsualDays.Friday.Open, close: item.OpeningTimes.UsualDays.Friday.Close, is24: item.OpeningTimes.UsualDays.Friday.Is24Hours},
		{day: "saturday", open: item.OpeningTimes.UsualDays.Saturday.Open, close: item.OpeningTimes.UsualDays.Saturday.Close, is24: item.OpeningTimes.UsualDays.Saturday.Is24Hours},
		{day: "sunday", open: item.OpeningTimes.UsualDays.Sunday.Open, close: item.OpeningTimes.UsualDays.Sunday.Close, is24: item.OpeningTimes.UsualDays.Sunday.Is24Hours},
		{day: "bank_holiday", open: item.OpeningTimes.BankHoliday.OpenTime, close: item.OpeningTimes.BankHoliday.CloseTime, is24: item.OpeningTimes.BankHoliday.Is24Hours},
	}
	return rows
}
