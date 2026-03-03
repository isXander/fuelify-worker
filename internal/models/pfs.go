package models

type PFS struct {
	ID               string
	PhoneNumber      string
	TradingName      string
	BrandName        string
	TradingAsBrand   bool
	TemporaryClosure bool
	PermanentClosure bool
	Motorway         bool
	Supermarket      bool
}

type Location struct {
	StationID    string
	AddressLine1 string
	AddressLine2 string
	City         string
	Country      string
	County       string
	Postcode     string
	Latitude     float32
	Longitude    float32
}

type FuelPrice struct {
	FuelType string
	// pence per litre
	Price float32
	// reference to the pfs this price is for
	StationID string
}

type Amenity struct {
	StationID string
	Type      string
	// PRIMARY KEY (station_id, type)
}

type OpeningHours struct {
	StationID string
	Day       string // e.g. "monday" or "bank_holiday"
	OpenTime  string // e.g. "08:00"
	CloseTime string // e.g. "18:00"
	Is24Hours bool
	// PRIMARY KEY (station_id, day)
}
