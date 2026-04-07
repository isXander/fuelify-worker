use std::collections::HashMap;

// --- Nearby stations ---

#[derive(serde::Deserialize)]
pub struct NearbyStationsRequest {
    pub fuel_type: FuelType,
    pub origin: String,
    pub k_rings: u32,
}

#[derive(serde::Serialize)]
pub struct NearbyStationsResponse {
    pub results: Vec<Station>,
}

#[derive(serde::Deserialize)]
pub struct PriceHistoryRequest {
    pub station_id: String,
    pub interval: HistoryInterval,
    pub fuel_type: FuelType,
}

#[derive(serde::Serialize)]
pub struct PriceHistoryResponse {
    pub samples: Vec<FuelPriceSample>,
}

#[derive(serde::Serialize)]
pub struct Station {
    pub info: StationInfo,
    /// All fuel types available at the station, along with their latest price sample.
    pub latest_fuel_prices: HashMap<FuelType, FuelPriceSample>,
}

#[derive(serde::Serialize)]
pub struct StationInfo {
    pub station_id: String,
    pub phone_number: String,
    pub trading_name: String,
    pub brand_name: String,
    pub trading_as_brand: bool,
    pub temporary_closure: bool,
    pub permanent_closure: bool,
    pub motorway: bool,
    pub supermarket: bool,
    pub address_line_1: String,
    pub address_line_2: String,
    pub city: String,
    pub county: String,
    pub country: String,
    pub postcode: String,
    pub latitude: f64,
    pub longitude: f64,
    pub h3_index_r6: String,
    pub h3_index_r3: String,
    pub amenities: Vec<Amenity>,
    pub opening_hours: OpeningHours,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, Default)]
pub struct DaySchedule {
    pub open: String,
    pub close: String,
    pub is_24_hours: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, Default)]
pub struct OpeningHours {
    pub monday: DaySchedule,
    pub tuesday: DaySchedule,
    pub wednesday: DaySchedule,
    pub thursday: DaySchedule,
    pub friday: DaySchedule,
    pub saturday: DaySchedule,
    pub sunday: DaySchedule,
    pub bank_holiday: DaySchedule,
}

#[derive(serde::Serialize)]
pub struct FuelPriceSample {
    /// Price in pence per litre.
    pub price: f64,
    /// ISO 8601 UTC timestamp, e.g. "2026-04-07T13:45:00Z".
    pub effective_date: String,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoryInterval {
    /// Returns all available price samples in the last 7 days.
    Last7Days,
    /// Returns all available price samples in the last 30 days.
    Last30Days,
    /// Returns all available price samples in the last 90 days.
    Last90Days,
    /// Returns all available price samples in the last 180 days.
    Last180Days,
    /// Returns all available price samples in the last 365 days.
    Last365Days,
}

impl HistoryInterval {
    pub fn days(&self) -> u32 {
        match self {
            HistoryInterval::Last7Days => 7,
            HistoryInterval::Last30Days => 30,
            HistoryInterval::Last90Days => 90,
            HistoryInterval::Last180Days => 180,
            HistoryInterval::Last365Days => 365,
        }
    }
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[serde(rename_all = "UPPERCASE")]
pub enum FuelType {
    E10,
    E5,
    B7Standard,
    B7Premium,
    B10,
    HVO,
}

impl FuelType {
    pub fn as_db_str(&self) -> &'static str {
        match self {
            FuelType::E10 => "E10",
            FuelType::E5 => "E5",
            FuelType::B7Standard => "B7Standard",
            FuelType::B7Premium => "B7Premium",
            FuelType::B10 => "B10",
            FuelType::HVO => "HVO",
        }
    }

    pub fn from_db_str(s: &str) -> Option<Self> {
        match s {
            "E10" => Some(FuelType::E10),
            "E5" => Some(FuelType::E5),
            "B7Standard" => Some(FuelType::B7Standard),
            "B7Premium" => Some(FuelType::B7Premium),
            "B10" => Some(FuelType::B10),
            "HVO" => Some(FuelType::HVO),
            _ => None,
        }
    }
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Amenity {
    AdbluePackaged,
    AdbluePumps,
    CarWash,
    CustomerToilets,
    WaterFilling,
    LpgPumps,
}

