mod apitypes;
mod fetch;

use serde::{Deserialize, Serialize};
use worker::*;
use fetch::*;
use wasm_bindgen::JsValue;
use crate::models::StationBrand;

pub async fn scheduled(_event: &ScheduledEvent, env: &Env, _ctx: &ScheduleContext) -> worker::Result<()> {
    let sync_queue = env.queue("sync-queue")?;

    let kv = env.kv("fuelify_ingest")?;
    let last_date = match kv.get("last_sync_date").text().await? {
        Some(date_str) => {
            console_log!("Found last sync date in KV: {}", date_str);
            chrono::NaiveDateTime::parse_from_str(&date_str, "%Y-%m-%dT%H:%M:%SZ").ok()
        },
        None => {
            console_log!("No last sync date found in KV, starting full sync");
            None
        }
    };

    let first_task = SyncTask {
        phase: SyncPhase::Information,
        batch_number: 1,
        incremental_from: last_date,
    };

    sync_queue.send(&first_task).await?;

    Ok(())
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SyncTask {
    phase: SyncPhase,
    batch_number: u32,
    incremental_from: Option<chrono::NaiveDateTime>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
enum SyncPhase {
    /// Fetch station information batches first so all stations exist in DB.
    Information,
    /// Then fetch fuel price batches — stations are guaranteed to exist.
    FuelPrices,
}

#[event(queue)]
pub async fn queue(message_batch: MessageBatch<SyncTask>, env: Env, _ctx: Context) -> worker::Result<()> {
    let sync_queue = env.queue("sync-queue")?;

    for message in message_batch.messages()? {
        let task = message.body();
        console_log!("Processing task: {:?}", task);

        match do_task(&task, &env).await {
            Ok(TaskOutcome::Continue) => {
                console_log!("Batch completed, queuing next: {:?}", task);
                message.ack();

                let next_task = SyncTask {
                    phase: task.phase.clone(),
                    batch_number: task.batch_number + 1,
                    incremental_from: task.incremental_from,
                };
                sync_queue.send(&next_task).await?;
            }
            Ok(TaskOutcome::PhaseComplete) => {
                message.ack();

                match task.phase {
                    SyncPhase::Information => {
                        console_log!("Information phase complete, starting FuelPrices phase");
                        let next_task = SyncTask {
                            phase: SyncPhase::FuelPrices,
                            batch_number: 1,
                            incremental_from: task.incremental_from,
                        };
                        sync_queue.send(&next_task).await?;
                    }
                    SyncPhase::FuelPrices => {
                        console_log!("FuelPrices phase complete, sync done");
                        conclude_sync(&env, chrono::Utc::now().naive_utc()).await?;
                    }
                }
            }
            Err(e) => {
                console_error!("Error processing task {:?}: {:?}", task, e);
                message.retry();
            }
        }
    }

    Ok(())
}

async fn do_task(task: &SyncTask, env: &Env) -> Result<TaskOutcome> {
    let kv = env.kv("fuelify_ingest")?;

    let token = match kv.get("access_token").text().await? {
        Some(v) => v,
        None => {
            console_log!("No token found in KV, fetching new token");
            let token = fetch_bearer_token(env).await?;
            kv.put("access_token", &token.access_token)?
                .expiration_ttl(token.expires_in - 100)
                .execute()
                .await?;
            token.access_token
        }
    };

    match task.phase {
        SyncPhase::Information => do_information_batch(env, &token, task).await,
        SyncPhase::FuelPrices => do_fuel_prices_batch(env, &token, task).await,
    }
}

async fn do_information_batch(env: &Env, token: &str, task: &SyncTask) -> Result<TaskOutcome> {
    let info_batch = match fetch_pfs_information(env, token, task.batch_number, task.incremental_from).await {
        Ok(batch) => batch,
        Err(FetchError::NotFound) => {
            console_log!("Info batch {} returned 404, information phase complete", task.batch_number);
            return Ok(TaskOutcome::PhaseComplete);
        }
        Err(FetchError::RequestError(e)) => return Err(e),
    };

    let db = env.d1("DB")?;
    let mut statements = Vec::new();

    for station_info in info_batch {
        let Ok(coord) = h3o::LatLng::new(
            station_info.location.latitude,
            station_info.location.longitude
        ) else {
            return Err(Error::RustError(format!(
                "Invalid coordinates for station {}: lat {}, lng {}",
                station_info.node_id, station_info.location.latitude, station_info.location.longitude
            )));
        };
        let cell_r6 = coord.to_cell(h3o::Resolution::Six);
        let cell_r3 = coord.to_cell(h3o::Resolution::Three);

        let amenities_json = serde_json::to_string(
            &station_info.amenities.iter().map(|a| a.to_string()).collect::<Vec<_>>()
        ).unwrap_or_else(|_| "[]".to_string());

        let opening_hours_json = serialize_opening_hours(&station_info.opening_times);

        let stmt = db.prepare(
            "INSERT INTO stations (
                id, phone_number, trading_name, brand_name, trading_as_brand,
                temporary_closure, permanent_closure, motorway, supermarket,
                address_line_1, address_line_2, city, country, county, postcode,
                latitude, longitude, amenities, opening_hours, h3_index_r6, h3_index_r3
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9,
                ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21
            )
            ON CONFLICT (id) DO UPDATE SET
                phone_number = EXCLUDED.phone_number,
                trading_name = EXCLUDED.trading_name,
                brand_name = EXCLUDED.brand_name,
                trading_as_brand = EXCLUDED.trading_as_brand,
                temporary_closure = EXCLUDED.temporary_closure,
                permanent_closure = EXCLUDED.permanent_closure,
                motorway = EXCLUDED.motorway,
                supermarket = EXCLUDED.supermarket,
                address_line_1 = EXCLUDED.address_line_1,
                address_line_2 = EXCLUDED.address_line_2,
                city = EXCLUDED.city,
                country = EXCLUDED.country,
                county = EXCLUDED.county,
                postcode = EXCLUDED.postcode,
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude,
                amenities = EXCLUDED.amenities,
                opening_hours = EXCLUDED.opening_hours,
                h3_index_r6 = EXCLUDED.h3_index_r6,
                h3_index_r3 = EXCLUDED.h3_index_r3
                "
        ).bind(&[
            station_info.node_id.into(),
            nullable_text(station_info.public_phone_number),
            station_info.trading_name.trim().to_uppercase().into(),
            station_info.brand_name.trim().to_uppercase().into(),
            station_info.is_same_trading_and_brand_name.into(),
            station_info.temporary_closure.into(),
            station_info.permanent_closure.into(),
            station_info.is_motorway_service_station.into(),
            station_info.is_supermarket_service_station.into(),
            station_info.location.address_line_1.trim().to_uppercase().into(),
            station_info.location.address_line_2.trim().to_uppercase().into(),
            station_info.location.city.trim().to_uppercase().into(),
            station_info.location.country.trim().to_uppercase().into(),
            station_info.location.county.trim().to_uppercase().into(),
            station_info.location.postcode.trim().to_uppercase().into(),
            station_info.location.latitude.into(),
            station_info.location.longitude.into(),
            amenities_json.into(),
            opening_hours_json.into(),
            cell_r6.to_string().into(),
            cell_r3.to_string().into(),
        ])?;
        statements.push(stmt);
    }

    if !statements.is_empty() {
        db.batch(statements).await?;
    }

    Ok(TaskOutcome::Continue)
}

async fn do_fuel_prices_batch(env: &Env, token: &str, task: &SyncTask) -> Result<TaskOutcome> {
    let prices_batch = match fetch_pfs_fuel_prices(env, token, task.batch_number, task.incremental_from).await {
        Ok(batch) => batch,
        Err(FetchError::NotFound) => {
            console_log!("Prices batch {} returned 404, fuel prices phase complete", task.batch_number);
            return Ok(TaskOutcome::PhaseComplete);
        }
        Err(FetchError::RequestError(e)) => return Err(e),
    };

    let db = env.d1("DB")?;
    let mut statements = Vec::new();

    for station_prices in prices_batch {
        for fuel_price in station_prices.fuel_prices {
            let price_tenths = normalize_price(fuel_price.price);
            let stmt = db.prepare(
                "INSERT INTO fuel_prices (station_id, fuel_type, price, effective_date)
                VALUES (?1, ?2, ?3, ?4)
                ON CONFLICT (station_id, fuel_type, effective_date) DO UPDATE SET
                    price = EXCLUDED.price
                WHERE fuel_prices.price != EXCLUDED.price"
            ).bind(&[
                station_prices.node_id.clone().into(),
                fuel_price.fuel_type.to_string().into(),
                wasm_bindgen::JsValue::from_f64(price_tenths as f64),
                fuel_price.price_change_effective_timestamp.format("%Y-%m-%dT%H:%M:%SZ").to_string().into(),
            ])?;
            statements.push(stmt);
        }
    }

    if !statements.is_empty() {
        db.batch(statements).await?;
    }

    Ok(TaskOutcome::Continue)
}

enum TaskOutcome {
    /// Batch processed, continue with next batch in the same phase.
    Continue,
    /// This phase has no more data (got 404). Transition to next phase or finish.
    PhaseComplete,
}

fn serialize_opening_hours(times: &apitypes::OpeningTimes) -> String {
    let mut map = serde_json::Map::new();
    for (day, hours) in [
        ("monday", &times.usual_days.monday),
        ("tuesday", &times.usual_days.tuesday),
        ("wednesday", &times.usual_days.wednesday),
        ("thursday", &times.usual_days.thursday),
        ("friday", &times.usual_days.friday),
        ("saturday", &times.usual_days.saturday),
        ("sunday", &times.usual_days.sunday),
    ] {
        map.insert(day.to_string(), serde_json::json!({
            "open": hours.open.to_string(),
            "close": hours.close.to_string(),
            "is_24_hours": hours.is_24_hours,
        }));
    }
    map.insert("bank_holiday".to_string(), serde_json::json!({
        "open": times.bank_holiday.open_time.to_string(),
        "close": times.bank_holiday.close_time.to_string(),
        "is_24_hours": times.bank_holiday.is_24_hours,
    }));
    serde_json::Value::Object(map).to_string()
}

async fn conclude_sync(env: &Env, last_effective_date: chrono::NaiveDateTime) -> Result<()> {
    let kv = env.kv("fuelify_ingest")?;
    kv.put("last_sync_date", last_effective_date.format("%Y-%m-%dT%H:%M:%SZ").to_string())?
        .execute()
        .await?;

    console_log!("Sync completed, updated last sync date in KV to {}", last_effective_date);

    Ok(())
}

/// Convert an upstream price (float pence-per-litre) to tenths of a penny.
///
/// Handles two issues:
/// 1. Floating-point imprecision: 189.89999… → round(× 10) → 1899
/// 2. Misentry detection: some stations enter the price in tenths of pence
///    instead of pence (e.g. 1549 instead of 154.9). Some in £.
///    Anything above 500p (£5/litre) is assumed to already be in tenths and is kept as-is.
fn normalize_price(pence: f32) -> i64 {
    let pence = pence as f64;

    if pence < 5.0 {
        // In £, not pence
        (pence * 100.0 * 10.0).round() as i64
    } else if pence > 500.0 {
        // Already in tenths of pence — just round off any fractional noise
        pence.round() as i64
    } else {
        (pence * 10.0).round() as i64
    }
}

#[inline]
fn nullable_text(value: Option<String>) -> JsValue {
    match value {
        Some(v) => v.into(),
        None => JsValue::NULL,
    }
}

pub fn parse_station_brand(input: &str) -> StationBrand {
    let brand = input.trim().to_uppercase();

    if brand == "" {
        return StationBrand::Unbranded
    }

    const MATCHES: &[(&str, fn() -> StationBrand)] = &[
        ("HARVEST ENERGY", || StationBrand::HarvestEnergy),
        ("WELCOME BREAK", || StationBrand::WelcomeBreak),
        ("EG ON THE MOVE", || StationBrand::EGOnTheMove),
        ("ASDA EXPRESS", || StationBrand::ASDAExpress),
        ("COSTCO", || StationBrand::CostcoWholesale),
        ("TESCO", || StationBrand::Tesco),
        ("MORRISONS", || StationBrand::Morrisons),
        ("SAINSBURY", || StationBrand::SAINSBURYS),
        ("ASDA", || StationBrand::ASDA),
        ("ESSO", || StationBrand::Esso),
        ("SHELL", || StationBrand::Shell),
        ("BP", || StationBrand::BP),
        ("TEXACO", || StationBrand::Texaco),
        ("JET", || StationBrand::JET),
        ("GULF", || StationBrand::Gulf),
        ("MURCO", || StationBrand::Murco),
        ("VALERO", || StationBrand::Valero),
        ("MAXOL", || StationBrand::Maxol),
        ("ESSAR", || StationBrand::Essar),
        ("NONE", || StationBrand::Unbranded),
    ];

    for (needle, constructor) in MATCHES {
        if brand.contains(needle) {
            return constructor();
        }
    }

    StationBrand::Other(brand)
}
