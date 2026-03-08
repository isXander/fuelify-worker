#![allow(dead_code)]

use serde::{Deserializer, Deserialize};

pub type PFSInformationResponse = Vec<PFSInformation>;
pub type PFSFuelPricesResponse = Vec<PFSFuelPrices>;
#[derive(serde::Deserialize)]
pub struct PFSTokenResponse {
    pub success: bool,
    pub data: PFSToken,
    pub message: Option<String>,
}

#[derive(serde::Serialize)]
pub struct PFSFetchRequestQueryParams {
    #[serde(rename = "batch-number")]
    pub batch_number: u32,
    #[serde(rename = "effective-start-timestamp", skip_serializing_if = "Option::is_none")]
    pub incremental_from: Option<chrono::NaiveDate>,
}

#[derive(serde::Deserialize)]
pub struct PFSInformation {
    pub node_id: String,
    pub public_phone_number: Option<String>,
    pub trading_name: String,
    pub is_same_trading_and_brand_name: bool,
    pub brand_name: String,
    pub temporary_closure: bool,
    #[serde(deserialize_with = "null_to_false")]
    pub permanent_closure: bool,
    pub permanent_closure_date: Option<String>,
    pub is_motorway_service_station: bool,
    pub is_supermarket_service_station: bool,
    pub location: Location,
    pub amenities: Vec<Amenity>,
    pub opening_times: OpeningTimes,
    pub fuel_types: Vec<FuelType>,
}

#[derive(serde::Deserialize)]
pub struct Location {
    #[serde(deserialize_with = "null_to_empty_string")]
    pub address_line_1: String,
    #[serde(deserialize_with = "null_to_empty_string")]
    pub address_line_2: String,
    #[serde(deserialize_with = "null_to_empty_string")]
    pub city: String,
    #[serde(deserialize_with = "null_to_empty_string")]
    pub country: String,
    #[serde(deserialize_with = "null_to_empty_string")]
    pub county: String,
    #[serde(deserialize_with = "null_to_empty_string")]
    pub postcode: String,
    pub latitude: f32,
    pub longitude: f32,
}

// TODO: investigate if there are more amenities
#[derive(serde::Deserialize, strum_macros::Display)]
#[serde(rename_all = "snake_case")]
#[strum(serialize_all = "snake_case")]
pub enum Amenity {
    AdbluePackaged,
    AdbluePumps,
    CarWash,
    CustomerToilets,
    WaterFilling,
    LpgPumps,
}

#[derive(serde::Deserialize)]
pub struct OpeningTimes {
    pub usual_days: UsualDays,
    pub bank_holiday: BankHoliday,
}

#[derive(serde::Deserialize)]
pub struct UsualDays {
    pub monday: DayHours,
    pub tuesday: DayHours,
    pub wednesday: DayHours,
    pub thursday: DayHours,
    pub friday: DayHours,
    pub saturday: DayHours,
    pub sunday: DayHours,
}

#[derive(serde::Deserialize)]
pub struct DayHours {
    pub open: chrono::NaiveTime,
    pub close: chrono::NaiveTime,
    pub is_24_hours: bool,
}

#[derive(serde::Deserialize)]
pub struct BankHoliday {
    #[serde(rename = "type")]
    pub kind: BankHolidayType,
    pub open_time: chrono::NaiveTime,
    pub close_time: chrono::NaiveTime,
    pub is_24_hours: bool,
}

impl Into<DayHours> for BankHoliday {
    fn into(self) -> DayHours {
        DayHours {
            open: self.open_time,
            close: self.close_time,
            is_24_hours: self.is_24_hours,
        }
    }
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BankHolidayType {
    Standard,
    #[serde(rename = "bank holiday")]
    BankHoliday,
}

// TODO: investigate if there are more fuel types
#[derive(serde::Deserialize, strum_macros::EnumString, strum_macros::Display)]
pub enum FuelType {
    E5,
    E10,
    HVO,
    B10,
    #[serde(rename = "B7_STANDARD")]
    B7Standard,
    #[serde(rename = "B7_PREMIUM")]
    B7Premium,
}


#[derive(serde::Deserialize)]
pub struct PFSFuelPrices {
    pub node_id: String,
    pub public_phone_number: Option<String>,
    pub trading_name: String,
    pub fuel_prices: Vec<FuelPrice>,
}

#[derive(serde::Deserialize)]
pub struct FuelPrice {
    pub fuel_type: FuelType,
    /// Price in pence per litre
    pub price: f32,
    /// ISO 8601 format, e.g. "2024-06-01T12:00:00Z"
    pub price_last_updated: chrono::DateTime<chrono::Utc>,
    /// ISO 8601 format, e.g. "2024-06-01T12:00:00Z"
    pub price_change_effective_timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct PFSToken {
    pub access_token: String,
    pub token_type: String,
    pub expires_in: u64,
    pub refresh_token: String,
}

fn null_to_false<'de, D>(deserialiser: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    // Try to deserialise as an Option<bool>
    let opt = Option::<bool>::deserialize(deserialiser)?;
    // If it's None (null), return false. Otherwise, return the boolean value.
    Ok(opt.unwrap_or(false))
}

fn null_to_empty_string<'de, D>(deserialiser: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    // Try to deserialise as an Option<String>
    let opt = Option::<String>::deserialize(deserialiser)?;
    // If it's None (null), return an empty string. Otherwise, return the string value.
    Ok(opt.unwrap_or("".to_owned()))
}