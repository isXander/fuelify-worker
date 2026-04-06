use std::collections::HashMap;

// --- User & device registration ---

#[derive(serde::Serialize)]
pub struct RegisterUserResponse {
    pub user_id: String,
}

#[derive(serde::Deserialize)]
pub struct RegisterDeviceRequest {
    pub user_id: String,
    pub device_token: String,
}

// --- Station watches ---

#[derive(serde::Deserialize)]
pub struct WatchStationRequest {
    pub user_id: String,
    pub station_id: String,
    pub fuel_type: FuelType,
}

#[derive(serde::Serialize)]
pub struct ListWatchesResponse {
    pub stations: Vec<WatchedStation>,
}

#[derive(serde::Serialize)]
pub struct WatchedStation {
    pub station_id: String,
    pub trading_name: String,
    pub brand_name: String,
    pub fuel_type: FuelType,
}

// --- Nearby stations ---

#[derive(serde::Deserialize)]
pub struct NearbyStationsRequest {
    pub fuel_type: FuelType,
    pub origin_lat: f64,
    pub origin_lon: f64,
    pub span_lat: f64,
    pub span_lon: f64,
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
    pub location: StationLocation,
    pub amenities: Vec<Amenity>,
    /// All fuel types available at the station, along with their latest price sample.
    pub latest_fuel_prices: HashMap<FuelType, FuelPriceSample>,
}

#[derive(serde::Serialize)]
pub struct StationInfo {
    pub station_id: String,
    pub trading_name: String,
    pub brand_name: String,
    pub motorway: bool,
    pub supermarket: bool,
}

#[derive(serde::Serialize)]
pub struct StationLocation {
    pub latitude: f64,
    pub longitude: f64,
    pub address_line_1: String,
    pub address_line_2: String,
    pub city: String,
    pub county: String,
    pub postcode: String,
}

#[derive(serde::Serialize)]
pub struct FuelPriceSample {
    /// Price in pence per litre.
    pub price: f64,
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


