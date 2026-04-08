pub mod apitypes;
mod proxy;

use crate::api::proxy::on_fuel_finder_proxy;
use apitypes::*;
use serde::de::{Deserializer, Visitor};
use serde::Deserialize;
use std::str::FromStr;
use worker::*;

const MAX_SEARCH_RADIUS: u32 = 10;

#[event(fetch)]
async fn fetch(
    req: Request,
    env: Env,
    _ctx: Context,
) -> Result<Response> {
    let app = Router::new()
        .post_async("/nearby", get_stations)
        .post_async("/stations", get_stations_by_ids)
        .post_async("/price_history", get_price_history)
        .on_async("/fuel-finder-proxy/*path", on_fuel_finder_proxy);

    app.run(req, env).await
}

async fn get_stations(
    mut req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let db = ctx.d1("DB")?;

    let body = match req.json::<NearbyStationsRequest>().await {
        Ok(b) => b,
        Err(_) => {
            return Response::builder()
                .with_status(400)
                .from_json(&ErrorResponse::new("Invalid request body"));
        }
    };

    let fuel_type_str = body.fuel_type.as_db_str();

    // parse the origin
    let origin_cell = match h3o::CellIndex::from_str(body.origin.as_str()) {
        Ok(c) if c.resolution() != h3o::Resolution::Six => {
            return Response::builder()
                .with_status(400)
                .from_json(&ErrorResponse::new("h3_index_r6 must be a valid H3 index at resolution 6"));
        }
        Err(e) => {
            return Response::builder()
                .with_status(400)
                .from_json(&ErrorResponse::new(format!("Invalid h3_index_r6: {e}")));
        }
        Ok(c) => c,
    };

    let k_rings = body.k_rings;

    if k_rings > MAX_SEARCH_RADIUS {
        return Response::builder()
            .with_status(400)
            .from_json(&ErrorResponse::new(format!("k_rings must be <= {MAX_SEARCH_RADIUS}")));
    }

    let search_cells = origin_cell.grid_disk::<Vec<_>>(k_rings);
    let search_cells_json = serde_json::to_string(
        &search_cells.iter().map(|c| c.to_string()).collect::<Vec<_>>()
    ).unwrap_or_default();

    let sql = "
        WITH requested_latest AS (
            SELECT
                fp.station_id,
                MAX(fp.effective_date) AS requested_effective_date
            FROM fuel_prices fp
            WHERE fp.fuel_type = ?
            GROUP BY fp.station_id
        ),
        selected_stations AS (
            SELECT
                s.id AS station_id,
                s.phone_number,
                s.trading_name,
                s.brand_name,
                s.trading_as_brand,
                s.temporary_closure,
                s.permanent_closure,
                s.motorway,
                s.supermarket,
                s.address_line_1,
                s.address_line_2,
                s.city,
                s.county,
                s.country,
                s.postcode,
                s.latitude,
                s.longitude,
                s.h3_index_r6,
                s.h3_index_r3,
                s.amenities,
                s.opening_hours,
                rl.requested_effective_date
            FROM stations s
            INNER JOIN requested_latest rl ON rl.station_id = s.id
            WHERE s.h3_index_r6 IN (SELECT value FROM json_each(?))
              AND s.temporary_closure = FALSE
              AND s.permanent_closure = FALSE
            ORDER BY rl.requested_effective_date DESC, s.trading_name ASC
            LIMIT 200
        )
        SELECT
            ss.station_id,
            ss.phone_number,
            ss.trading_name,
            ss.brand_name,
            ss.trading_as_brand,
            ss.temporary_closure,
            ss.permanent_closure,
            ss.motorway,
            ss.supermarket,
            ss.address_line_1,
            ss.address_line_2,
            ss.city,
            ss.county,
            ss.country,
            ss.postcode,
            ss.latitude,
            ss.longitude,
            ss.h3_index_r6,
            ss.h3_index_r3,
            ss.amenities,
            ss.opening_hours,
            fp.fuel_type,
            fp.price,
            fp.effective_date
        FROM selected_stations ss
        INNER JOIN fuel_prices fp ON fp.station_id = ss.station_id
        WHERE fp.effective_date = (
            SELECT MAX(fp2.effective_date)
            FROM fuel_prices fp2
            WHERE fp2.station_id = fp.station_id
              AND fp2.fuel_type = fp.fuel_type
        )
        ORDER BY ss.requested_effective_date DESC, ss.trading_name ASC, fp.fuel_type ASC
    ";

    let bind_params: Vec<wasm_bindgen::JsValue> = vec![
        fuel_type_str.into(),
        search_cells_json.into(),
    ];

    let rows = db.prepare(sql).bind(&bind_params)?.all().await?;

    #[derive(Deserialize)]
    #[serde(rename_all = "snake_case")]
    struct ResultRow {
        station_id: String,
        phone_number: Option<String>,
        trading_name: String,
        brand_name: String,
        trading_as_brand: i64,
        temporary_closure: i64,
        permanent_closure: i64,
        motorway: i64,
        supermarket: i64,
        address_line_1: String,
        address_line_2: String,
        city: String,
        county: String,
        country: String,
        postcode: String,
        latitude: f64,
        longitude: f64,
        h3_index_r6: String,
        h3_index_r3: String,
        amenities: String,
        opening_hours: String,
        fuel_type: String,
        price: i64,
        effective_date: String,
    }

    let result_rows = rows.results::<ResultRow>()?;

    let mut stations: Vec<Station> = Vec::new();
    let mut station_indices: std::collections::HashMap<String, usize> = std::collections::HashMap::new();

    for row in result_rows {
        if let Some(&index) = station_indices.get(&row.station_id) {
            if let Some(fuel_type) = FuelType::from_db_str(&row.fuel_type) {
                stations[index].latest_fuel_prices.insert(
                    fuel_type,
                    FuelPriceSample {
                        price: row.price as f64 / 10.0,
                        effective_date: row.effective_date,
                    },
                );
            }
            continue;
        }

        let amenities: Vec<Amenity> = serde_json::from_str(&row.amenities).unwrap_or_default();
        let opening_hours: OpeningHours = serde_json::from_str(&row.opening_hours).unwrap_or_default();

        let mut latest_fuel_prices = std::collections::HashMap::new();
        if let Some(fuel_type) = FuelType::from_db_str(&row.fuel_type) {
            latest_fuel_prices.insert(
                fuel_type,
                FuelPriceSample {
                    price: row.price as f64 / 10.0,
                    effective_date: row.effective_date,
                },
            );
        }

        let station_id = row.station_id.clone();

        stations.push(Station {
            info: StationInfo {
                station_id: row.station_id,
                phone_number: row.phone_number.unwrap_or_default(),
                trading_name: row.trading_name,
                brand_name: row.brand_name,
                trading_as_brand: row.trading_as_brand != 0,
                temporary_closure: row.temporary_closure != 0,
                permanent_closure: row.permanent_closure != 0,
                motorway: row.motorway != 0,
                supermarket: row.supermarket != 0,
                address_line_1: row.address_line_1,
                address_line_2: row.address_line_2,
                city: row.city,
                county: row.county,
                country: row.country,
                postcode: row.postcode,
                latitude: row.latitude,
                longitude: row.longitude,
                h3_index_r6: row.h3_index_r6,
                h3_index_r3: row.h3_index_r3,
                amenities,
                opening_hours,
            },
            latest_fuel_prices,
        });

        station_indices.insert(station_id, stations.len() - 1);
    }

    Response::from_json(&StationsListResponse { results: stations })
}

async fn get_stations_by_ids(
    mut req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let db = ctx.d1("DB")?;

    let body = match req.json::<GetStationsRequest>().await {
        Ok(b) => b,
        Err(_) => {
            return Response::builder()
                .with_status(400)
                .from_json(&ErrorResponse::new("Invalid request body"));
        }
    };

    let ids_json = serde_json::to_string(&body.station_ids).unwrap_or_default();

    let sql = "
        SELECT
            s.id AS station_id,
            s.phone_number,
            s.trading_name,
            s.brand_name,
            s.trading_as_brand,
            s.temporary_closure,
            s.permanent_closure,
            s.motorway,
            s.supermarket,
            s.address_line_1,
            s.address_line_2,
            s.city,
            s.county,
            s.country,
            s.postcode,
            s.latitude,
            s.longitude,
            s.h3_index_r6,
            s.h3_index_r3,
            s.amenities,
            s.opening_hours,
            fp.fuel_type,
            fp.price,
            fp.effective_date
        FROM stations s
        INNER JOIN fuel_prices fp ON fp.station_id = s.id
        WHERE s.id IN (SELECT value FROM json_each(?))
          AND fp.effective_date = (
              SELECT MAX(fp2.effective_date)
              FROM fuel_prices fp2
              WHERE fp2.station_id = fp.station_id
                AND fp2.fuel_type = fp.fuel_type
          )
        ORDER BY s.trading_name ASC, fp.fuel_type ASC
    ";

    let bind_params: Vec<wasm_bindgen::JsValue> = vec![ids_json.into()];

    let rows = db.prepare(sql).bind(&bind_params)?.all().await?;

    #[derive(Deserialize)]
    #[serde(rename_all = "snake_case")]
    struct ResultRow {
        station_id: String,
        phone_number: Option<String>,
        trading_name: String,
        brand_name: String,
        trading_as_brand: i64,
        temporary_closure: i64,
        permanent_closure: i64,
        motorway: i64,
        supermarket: i64,
        address_line_1: String,
        address_line_2: String,
        city: String,
        county: String,
        country: String,
        postcode: String,
        latitude: f64,
        longitude: f64,
        h3_index_r6: String,
        h3_index_r3: String,
        amenities: String,
        opening_hours: String,
        fuel_type: String,
        price: i64,
        effective_date: String,
    }

    let result_rows = rows.results::<ResultRow>()?;

    let mut stations: Vec<Station> = Vec::new();
    let mut station_indices: std::collections::HashMap<String, usize> = std::collections::HashMap::new();

    for row in result_rows {
        if let Some(&index) = station_indices.get(&row.station_id) {
            if let Some(fuel_type) = FuelType::from_db_str(&row.fuel_type) {
                stations[index].latest_fuel_prices.insert(
                    fuel_type,
                    FuelPriceSample {
                        price: row.price as f64 / 10.0,
                        effective_date: row.effective_date,
                    },
                );
            }
            continue;
        }

        let amenities: Vec<Amenity> = serde_json::from_str(&row.amenities).unwrap_or_default();
        let opening_hours: OpeningHours = serde_json::from_str(&row.opening_hours).unwrap_or_default();

        let mut latest_fuel_prices = std::collections::HashMap::new();
        if let Some(fuel_type) = FuelType::from_db_str(&row.fuel_type) {
            latest_fuel_prices.insert(
                fuel_type,
                FuelPriceSample {
                    price: row.price as f64 / 10.0,
                    effective_date: row.effective_date,
                },
            );
        }

        let station_id = row.station_id.clone();

        stations.push(Station {
            info: StationInfo {
                station_id: row.station_id,
                phone_number: row.phone_number.unwrap_or_default(),
                trading_name: row.trading_name,
                brand_name: row.brand_name,
                trading_as_brand: row.trading_as_brand != 0,
                temporary_closure: row.temporary_closure != 0,
                permanent_closure: row.permanent_closure != 0,
                motorway: row.motorway != 0,
                supermarket: row.supermarket != 0,
                address_line_1: row.address_line_1,
                address_line_2: row.address_line_2,
                city: row.city,
                county: row.county,
                country: row.country,
                postcode: row.postcode,
                latitude: row.latitude,
                longitude: row.longitude,
                h3_index_r6: row.h3_index_r6,
                h3_index_r3: row.h3_index_r3,
                amenities,
                opening_hours,
            },
            latest_fuel_prices,
        });

        station_indices.insert(station_id, stations.len() - 1);
    }

    Response::from_json(&StationsListResponse { results: stations })
}

async fn get_price_history(
    mut req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let db = ctx.d1("DB")?;

    let body = match req.json::<PriceHistoryRequest>().await {
        Ok(b) => b,
        Err(_) => {
            return Response::builder()
                .with_status(400)
                .from_json(&ErrorResponse::new("Invalid request body"));
        }
    };

    let days = body.interval.days() as i64;
    let now_ms = Date::now().as_millis() as i64;
    let cutoff_date = chrono::DateTime::from_timestamp_millis(now_ms - days * 24 * 60 * 60 * 1000)
        .unwrap_or_default()
        .format("%Y-%m-%dT%H:%M:%SZ")
        .to_string();

    let fuel_type_str = body.fuel_type.as_db_str();

    let sql = "
        SELECT price, effective_date
        FROM fuel_prices
        WHERE station_id = ?
          AND fuel_type = ?
          AND effective_date >= ?
        ORDER BY effective_date ASC
    ";

    let bind_params: Vec<wasm_bindgen::JsValue> = vec![
        body.station_id.into(),
        fuel_type_str.into(),
        cutoff_date.into(),
    ];

    let rows = db.prepare(sql).bind(&bind_params)?.all().await?;

    #[derive(Deserialize)]
    struct PriceRow {
        price: i64,
        effective_date: String,
    }

    let samples = rows.results::<PriceRow>()?
        .into_iter()
        .map(|r| FuelPriceSample {
            price: r.price as f64 / 10.0,
            effective_date: r.effective_date,
        })
        .collect();

    Response::from_json(&PriceHistoryResponse { samples })
}

// --- Error response ---

#[derive(serde::Serialize)]
struct ErrorResponse {
    success: bool,
    message: String,
}

impl ErrorResponse {
    fn new(message: impl Into<String>) -> Self {
        Self {
            success: false,
            message: message.into(),
        }
    }
}
