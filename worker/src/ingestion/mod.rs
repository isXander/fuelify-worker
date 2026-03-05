mod apitypes;
mod fetch;

use serde::{Deserialize, Serialize};
use sqlx_d1::sqlx_core::executor::Executor;
use worker::*;
use fetch::*;
use crate::db::new_d1_connection;
use wasm_bindgen::JsValue;

#[event(scheduled)]
pub async fn scheduled(_event: ScheduledEvent, env: Env, _ctx: ScheduleContext) -> worker::Result<()> {
    let sync_queue = env.queue("sync-queue")?;

    let kv = env.kv("fuelify_ingest")?;
    let last_date = match kv.get("last_sync_date").text().await? {
        Some(date_str) => {
            console_log!("Found last sync date in KV: {}", date_str);
            chrono::NaiveDate::parse_from_str(&date_str, "%Y-%m-%d").ok()
        },
        None => {
            console_log!("No last sync date found in KV, starting with None");
            None
        }
    };

    let first_task = SyncTask {
        batch_number: 1,
        incremental_from: last_date,
    };

    sync_queue.send(&first_task).await?;

    Ok(())
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SyncTask {
    batch_number: u32,
    incremental_from: Option<chrono::NaiveDate>,
}

#[event(queue)]
pub async fn queue(message_batch: MessageBatch<SyncTask>, env: Env, ctx: Context) -> worker::Result<()> {
    let sync_queue = env.queue("sync-queue")?;

    for message in message_batch.messages()? {
        let task = message.body();
        console_log!("Processing task: {:?}", task);

        match do_task(&task, &env).await {
            Ok(TaskOutcome::Success) => {
                console_log!("Task completed successfully: {:?}", task);
                message.ack();

                let next_task = SyncTask {
                    batch_number: task.batch_number + 1,
                    incremental_from: task.incremental_from,
                };
                sync_queue.send(&next_task).await?;
            }
            Ok(TaskOutcome::NoMoreData) => {
                console_log!("No more data to fetch for task {:?}, not queuing next batch", task);
                message.ack();

                conclude_sync(&env, chrono::Utc::now().date_naive()).await?;
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

    let pfs_information_batch = match fetch_pfs_information(&token, task.batch_number, task.incremental_from).await {
        Ok(batch) => {
            console_log!("Fetched PFS information for batch {}: {} records", task.batch_number, batch.len());
            batch
        },
        Err(FetchError::NotFound) => {
            console_log!("Received 404 for PFS information batch {}, assuming no more data to fetch", task.batch_number);
            return Ok(TaskOutcome::NoMoreData);
        },
        Err(FetchError::RequestError(e)) => {
            console_error!("Error fetching PFS information for batch {}: {:?}", task.batch_number, e);
            return Err(worker::Error::RustError(format!("Error fetching PFS information: {:?}", e)));
        }
    };
    let pfs_fuel_prices_batch = match fetch_pfs_fuel_prices(&token, task.batch_number, task.incremental_from).await {
        Ok(batch) => {
            console_log!("Fetched PFS fuel prices for batch {}: {} records", task.batch_number, batch.len());
            batch
        },
        Err(FetchError::NotFound) => {
            console_log!("Received 404 for PFS fuel prices batch {}, assuming no more data to fetch", task.batch_number);
            return Ok(TaskOutcome::NoMoreData);
        },
        Err(e) => {
            console_error!("Error fetching PFS fuel prices for batch {}: {:?}", task.batch_number, e);
            return Err(worker::Error::RustError(format!("Error fetching PFS fuel prices: {:?}", e)));
        }
    };

    let db = env.d1("DB")?;

    let mut statements = Vec::new();

    for pfs_info in pfs_information_batch {
        let pfs_stmt = db.prepare(
            "
            INSERT INTO pfs (
                id,
                phone_number,
                trading_name,
                brand_name,
                trading_as_brand,
                temporary_closure,
                permanent_closure,
                motorway,
                supermarket
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT (id) DO UPDATE SET
                phone_number = EXCLUDED.phone_number,
                trading_name = EXCLUDED.trading_name,
                brand_name = EXCLUDED.brand_name,
                trading_as_brand = EXCLUDED.trading_as_brand,
                temporary_closure = EXCLUDED.temporary_closure,
                permanent_closure = EXCLUDED.permanent_closure,
                motorway = EXCLUDED.motorway,
                supermarket = EXCLUDED.supermarket;
            "
            )
            .bind(&[
                pfs_info.node_id.clone().into(), nullable_text(pfs_info.public_phone_number), pfs_info.trading_name.into(),
                pfs_info.brand_name.into(), pfs_info.is_same_trading_and_brand_name.into(),
                pfs_info.temporary_closure.into(), pfs_info.permanent_closure.into(),
                pfs_info.is_motorway_service_station.into(), pfs_info.is_supermarket_service_station.into(),
            ])?;
        statements.push(pfs_stmt);

        let pfs_location_stmt = db.prepare(
            "
            INSERT INTO pfs_locations (
                station_id,
                address_line_1,
                address_line_2,
                city,
                country,
                county,
                postcode,
                latitude,
                longitude
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT (station_id) DO UPDATE SET
                address_line_1 = EXCLUDED.address_line_1,
                address_line_2 = EXCLUDED.address_line_2,
                city = EXCLUDED.city,
                country = EXCLUDED.country,
                county = EXCLUDED.county,
                postcode = EXCLUDED.postcode,
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude;
            "
            )
            .bind(&[
                pfs_info.node_id.clone().into(), pfs_info.location.address_line_1.into(), pfs_info.location.address_line_2.into(),
                pfs_info.location.city.into(), pfs_info.location.country.into(), pfs_info.location.county.into(),
                pfs_info.location.postcode.into(), pfs_info.location.latitude.into(), pfs_info.location.longitude.into()
            ])?;
        statements.push(pfs_location_stmt);

        for amenity in pfs_info.amenities {
            let pfs_amenity_stmt = db.prepare(
                "
                INSERT INTO pfs_amenities (
                    station_id,
                    type
                ) VALUES (
                    ?, ?
                )
                ON CONFLICT (station_id, type) DO NOTHING
                "
                )
                .bind(&[pfs_info.node_id.clone().into(), amenity.to_string().into()])?;
            statements.push(pfs_amenity_stmt);
        }

        for (day, hours) in [
            ("monday", &pfs_info.opening_times.usual_days.monday),
            ("tuesday", &pfs_info.opening_times.usual_days.tuesday),
            ("wednesday", &pfs_info.opening_times.usual_days.wednesday),
            ("thursday", &pfs_info.opening_times.usual_days.thursday),
            ("friday", &pfs_info.opening_times.usual_days.friday),
            ("saturday", &pfs_info.opening_times.usual_days.saturday),
            ("sunday", &pfs_info.opening_times.usual_days.sunday),
            ("bank_holiday", &pfs_info.opening_times.bank_holiday.into()),
        ] {
            let pfs_opening_hours_stmt = db.prepare(
                "
                INSERT INTO pfs_opening_hours (
                    station_id,
                    day,
                    open_time,
                    close_time,
                    is_24_hours
                ) VALUES (
                    ?, ?, ?, ?, ?
                )
                ON CONFLICT (station_id, day) DO UPDATE SET
                    open_time = EXCLUDED.open_time,
                    close_time = EXCLUDED.close_time,
                    is_24_hours = EXCLUDED.is_24_hours
                "
                )
                .bind(&[
                    pfs_info.node_id.clone().into(), day.into(), hours.open.to_string().into(), hours.close.to_string().into(), hours.is_24_hours.into()
                ])?;
            statements.push(pfs_opening_hours_stmt);
        }
    }
    for pfs_fuel_prices in pfs_fuel_prices_batch {
        for fuel_price in pfs_fuel_prices.fuel_prices {
            let pfs_fuel_price_stmt = db.prepare(
                "
                INSERT INTO pfs_fuel_prices (
                    station_id,
                    fuel_type,
                    price,
                    effective_date
                ) VALUES (
                    ?, ?, ?, ?
                )
                ON CONFLICT (station_id, fuel_type, effective_date) DO UPDATE SET
                    price = EXCLUDED.price
                "
                )
                .bind(&[
                    pfs_fuel_prices.node_id.clone().into(), fuel_price.fuel_type.to_string().into(),
                    fuel_price.price.into(), fuel_price.price_change_effective_timestamp.format("%Y-%m-%d").to_string().into()
                ])?;
            statements.push(pfs_fuel_price_stmt);
        }
    }

    db.batch(statements).await?;

    Ok(TaskOutcome::Success)
}

enum TaskOutcome {
    Success,
    NoMoreData,
}

async fn conclude_sync(env: &Env, last_effective_date: chrono::NaiveDate) -> Result<()> {
    let kv = env.kv("fuelify_ingest")?;
    kv.put("last_sync_date", last_effective_date.format("%Y-%m-%d").to_string())?
        .execute()
        .await?;
    console_log!("Sync completed, updated last sync date in KV to {}", last_effective_date);
    Ok(())
}

#[inline]
fn nullable_text(value: Option<String>) -> JsValue {
    match value {
        Some(v) => v.into(),
        None => JsValue::NULL,
    }
}
