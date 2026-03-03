package aggregator

import (
	"time"
)

type PFSInformation struct {
	NodeID                      string       `json:"node_id"`
	PublicPhoneNumber           string       `json:"public_phone_number"`
	TradingName                 string       `json:"trading_name"`
	IsSameTradingAndBrandName   bool         `json:"is_same_trading_and_brand_name"`
	BrandName                   string       `json:"brand_name"`
	TemporaryClosure            bool         `json:"temporary_closure"`
	PermanentClosure            bool         `json:"permanent_closure"`
	PermanentClosureDate        *string      `json:"permanent_closure_date"`
	IsMotorwayServiceStation    bool         `json:"is_motorway_service_station"`
	IsSupermarketServiceStation bool         `json:"is_supermarket_service_station"`
	Location                    Location     `json:"location"`
	Amenities                   []Amenity    `json:"amenities"`
	OpeningTimes                OpeningTimes `json:"opening_times"`
	FuelTypes                   []FuelType   `json:"fuel_types"`
}

type Location struct {
	AddressLine1 string  `json:"address_line_1"`
	AddressLine2 string  `json:"address_line_2"`
	City         string  `json:"city"`
	Country      string  `json:"country"`
	County       string  `json:"county"`
	Postcode     string  `json:"postcode"`
	Latitude     float32 `json:"latitude"`
	Longitude    float32 `json:"longitude"`
}

type Amenity string

const (
	AmenityAdBluePackaged  Amenity = "adblue_packaged"
	AmenityAdBluePumps     Amenity = "adblue_pumps"
	AmenityCarWash         Amenity = "car_wash"
	AmenityCustomerToilets Amenity = "customer_toilets"
	AmenityWaterFilling    Amenity = "water_filling"
	// TODO: investigate if there are more amenities
)

type OpeningTimes struct {
	UsualDays   UsualDays   `json:"usual_days"`
	BankHoliday BankHoliday `json:"bank_holiday"`
}

type UsualDays struct {
	Monday    DayHours `json:"monday"`
	Tuesday   DayHours `json:"tuesday"`
	Wednesday DayHours `json:"wednesday"`
	Thursday  DayHours `json:"thursday"`
	Friday    DayHours `json:"friday"`
	Saturday  DayHours `json:"saturday"`
	Sunday    DayHours `json:"sunday"`
}

type DayHours struct {
	Open      string `json:"open"`
	Close     string `json:"close"`
	Is24Hours bool   `json:"is_24_hours"`
}

type BankHoliday struct {
	Type      BankHolidayType `json:"type"`
	OpenTime  string          `json:"open_time"`
	CloseTime string          `json:"close_time"`
	Is24Hours bool            `json:"is_24_hours"`
}

type BankHolidayType string

const (
	BankHolidayTypeStandard    BankHolidayType = "standard"
	BankHolidayTypeBankHoliday BankHolidayType = "bank holiday"
)

type FuelType string

const (
	FuelTypeE5         FuelType = "E5"
	FuelType10         FuelType = "E10"
	FuelTypeHVO        FuelType = "HVO"
	FuelTypeB10        FuelType = "B10"
	FuelTypeB7Standard FuelType = "B7_STANDARD"
	FuelTypeB7Premium  FuelType = "B7_PREMIUM"
	// TODO: investigate if there are more fuel types
)

type PFSFuelPrices struct {
	NodeID            string      `json:"node_id"`
	PublicPhoneNumber string      `json:"public_phone_number"`
	TradingName       string      `json:"trading_name"`
	FuelPrices        []FuelPrice `json:"fuel_prices"`
}

type FuelPrice struct {
	FuelType FuelType `json:"fuel_type"`
	// Price in pence per litre
	Price float32 `json:"price"`
	// ISO 8601 format, e.g. "2024-06-01T12:00:00Z"
	PriceLastUpdated time.Time `json:"price_last_updated"`
	// ISO 8601 format, e.g. "2024-06-01T12:00:00Z"
	PriceChangeEffectiveTimestamp time.Time `json:"price_change_effective_timestamp"`
}
