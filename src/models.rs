use serde::{Deserialize, Deserializer, Serialize};

pub type TenthsOfPence = i64;

// SQLite stores booleans as 0/1 integers. D1's wasm binding deserialises them
// as numbers, so we need a helper to convert them when reading from the DB.
fn int_as_bool<'de, D: Deserializer<'de>>(d: D) -> Result<bool, D::Error> {
    Ok(i64::deserialize(d)? != 0)
}

/// Corresponds to the `stations` table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Station {
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
    pub address_line_1: String,
    pub address_line_2: String,
    pub city: String,
    pub country: String,
    pub county: String,
    pub postcode: String,
    pub latitude: f64,
    pub longitude: f64,
    /// JSON array of amenity strings, e.g. `["car_wash","customer_toilets"]`
    pub amenities: String,
    /// JSON object of opening hours, e.g. `{"monday":{"open":"06:00","close":"22:00","is_24_hours":false},...}`
    pub opening_hours: String,
}

/// Corresponds to the `fuel_prices` table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FuelPrice {
    pub station_id: String,
    pub fuel_type: String,
    /// Price in tenths of a penny per litre (e.g. 146.9p = 1469).
    pub price: TenthsOfPence,
    pub effective_date: String,
}

#[derive(Debug, Clone)]
pub enum StationBrand {
    Esso,
    BP,
    Shell,
    Tesco,
    Texaco,
    Morrisons,
    ASDA,
    SAINSBURYS,
    JET,
    Gulf,
    EGOnTheMove,
    Murco,
    ASDAExpress,
    Valero,
    Unbranded,
    Maxol,
    WelcomeBreak,
    HarvestEnergy,
    Essar,
    CostcoWholesale,
    Other(String),
}
