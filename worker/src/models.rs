use serde::{Deserialize, Deserializer, Serialize};

// SQLite stores booleans as 0/1 integers. D1's wasm binding deserialises them
// as numbers, so we need a helper to convert them when reading from the DB.
fn int_as_bool<'de, D: Deserializer<'de>>(d: D) -> Result<bool, D::Error> {
    Ok(i64::deserialize(d)? != 0)
}

/// Corresponds to the `pfs` table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pfs {
    pub id: String,
    pub phone_number: Option<String>,
    pub trading_name: String,
    pub brand_name: String,
    #[serde(deserialize_with = "int_as_bool")]
    pub trading_as_brand: bool,
    #[serde(deserialize_with = "int_as_bool")]
    pub temporary_closure: bool,
    #[serde(deserialize_with = "int_as_bool")]
    pub permanent_closure: bool,
    #[serde(deserialize_with = "int_as_bool")]
    pub motorway: bool,
    #[serde(deserialize_with = "int_as_bool")]
    pub supermarket: bool,
}

/// Corresponds to the `pfs_locations` table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PfsLocation {
    pub station_id: String,
    pub address_line_1: String,
    pub address_line_2: String,
    pub city: String,
    pub country: String,
    pub county: String,
    pub postcode: String,
    pub latitude: f64,
    pub longitude: f64,
}

/// Corresponds to the `pfs_fuel_prices` table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PfsFuelPrice {
    pub station_id: String,
    pub fuel_type: String,
    /// Price in pence per litre.
    pub price: f64,
    pub effective_date: String,
}

/// Corresponds to the `pfs_amenities` table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PfsAmenity {
    pub station_id: String,
    #[serde(rename = "type")]
    pub amenity_type: String,
}

/// Corresponds to the `pfs_opening_hours` table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PfsOpeningHours {
    pub station_id: String,
    pub day: String,
    pub open_time: String,
    pub close_time: String,
    #[serde(deserialize_with = "int_as_bool")]
    pub is_24_hours: bool,
}


