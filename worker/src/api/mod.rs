mod apitypes;
mod proxy;

use apitypes::*;
use serde::Deserialize;
use worker::*;
use crate::api::proxy::on_fuel_finder_proxy;

#[event(fetch)]
async fn fetch(
    req: Request,
    env: Env,
    _ctx: Context,
) -> Result<Response> {
    let app = Router::new()
        .post_async("/nearby", get_stations)
        .post_async("/price_history", get_price_history)
        .post_async("/users/register", register_user)
        .post_async("/devices/register", register_device)
        .post_async("/watch/station", watch_station)
        .delete_async("/watch/station", unwatch_station)
        .get_async("/watches", list_watches)
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

    let half_span_lat = body.span_lat / 2.0;
    let half_span_lon = body.span_lon / 2.0;

    // ?1 fuel_type, ?2 bbox south, ?3 bbox north, ?4 bbox west, ?5 bbox east
    let sql = "
        WITH filtered_stations AS (
            SELECT s.id AS station_id
            FROM stations s
            INNER JOIN fuel_prices fp ON fp.station_id = s.id
            WHERE s.latitude  BETWEEN ?2 AND ?3
              AND s.longitude BETWEEN ?4 AND ?5
              AND s.temporary_closure = FALSE
              AND s.permanent_closure = FALSE
              AND fp.fuel_type = ?1
              AND fp.effective_date = (
                  SELECT MAX(fp2.effective_date)
                  FROM fuel_prices fp2
                  WHERE fp2.station_id = s.id
                    AND fp2.fuel_type = ?1
              )
            GROUP BY s.id
        ),
        latest_prices AS (
            SELECT
                fp.station_id,
                fp.fuel_type,
                fp.price,
                fp.effective_date
            FROM fuel_prices fp
            INNER JOIN filtered_stations fs ON fs.station_id = fp.station_id
            WHERE fp.effective_date = (
                SELECT MAX(fp2.effective_date)
                FROM fuel_prices fp2
                WHERE fp2.station_id = fp.station_id
                  AND fp2.fuel_type = fp.fuel_type
            )
        )
        SELECT
            s.id              AS station_id,
            s.trading_name,
            s.brand_name,
            s.motorway,
            s.supermarket,
            s.latitude,
            s.longitude,
            s.address_line_1,
            s.address_line_2,
            s.city,
            s.county,
            s.postcode,
            s.amenities,
            GROUP_CONCAT(DISTINCT lp.fuel_type || '|' || lp.price || '|' || lp.effective_date) AS fuel_prices
        FROM filtered_stations fs
        INNER JOIN stations s      ON s.id          = fs.station_id
        INNER JOIN latest_prices lp ON lp.station_id = fs.station_id
        GROUP BY s.id
        LIMIT 200
    ";

    let bind_params: Vec<wasm_bindgen::JsValue> = vec![
        fuel_type_str.into(),
        (body.origin_lat - half_span_lat).into(),
        (body.origin_lat + half_span_lat).into(),
        (body.origin_lon - half_span_lon).into(),
        (body.origin_lon + half_span_lon).into(),
    ];

    let rows = db.prepare(sql).bind(&bind_params)?.all().await?;

    #[derive(Deserialize)]
    struct ResultRow {
        station_id: String,
        trading_name: String,
        brand_name: String,
        motorway: i64,
        supermarket: i64,
        latitude: f64,
        longitude: f64,
        address_line_1: String,
        address_line_2: String,
        city: String,
        county: String,
        postcode: String,
        amenities: String,
        fuel_prices: String,
    }

    let result_rows = rows.results::<ResultRow>()?;

    let mut stations: Vec<Station> = Vec::with_capacity(result_rows.len());
    for row in result_rows {
        let amenities: Vec<Amenity> = serde_json::from_str(&row.amenities).unwrap_or_default();

        let mut latest_fuel_prices = std::collections::HashMap::new();
        for entry in row.fuel_prices.split(',') {
            let mut parts = entry.splitn(3, '|');
            let (Some(fuel_type_str), Some(price_str), Some(effective_date)) =
                (parts.next(), parts.next(), parts.next())
            else {
                continue;
            };
            let (Some(ft), Ok(price_tenths)) = (
                FuelType::from_db_str(fuel_type_str),
                price_str.parse::<i64>(),
            ) else {
                continue;
            };
            latest_fuel_prices.insert(ft, FuelPriceSample {
                price: price_tenths as f64 / 10.0,
                effective_date: effective_date.to_string(),
            });
        }

        stations.push(Station {
            info: StationInfo {
                station_id: row.station_id,
                trading_name: row.trading_name,
                brand_name: row.brand_name,
                motorway: row.motorway != 0,
                supermarket: row.supermarket != 0,
            },
            location: StationLocation {
                latitude: row.latitude,
                longitude: row.longitude,
                address_line_1: row.address_line_1,
                address_line_2: row.address_line_2,
                city: row.city,
                county: row.county,
                postcode: row.postcode,
            },
            amenities,
            latest_fuel_prices,
        });
    }

    Response::from_json(&NearbyStationsResponse { results: stations })
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
        .format("%Y-%m-%d")
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

// --- User & device registration ---

async fn register_user(
    _req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let db = ctx.d1("DB")?;

    let user_id = uuid::Uuid::new_v4().to_string();

    db.prepare("INSERT INTO users (id) VALUES (?)")
        .bind(&[user_id.clone().into()])?
        .run()
        .await?;

    Response::from_json(&RegisterUserResponse { user_id })
}

async fn register_device(
    mut req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let db = ctx.d1("DB")?;

    let body = match req.json::<RegisterDeviceRequest>().await {
        Ok(b) => b,
        Err(_) => {
            return Response::builder()
                .with_status(400)
                .from_json(&ErrorResponse::new("Invalid request body"));
        }
    };

    db.prepare(
        "INSERT INTO devices (device_token, user_id) VALUES (?, ?)
         ON CONFLICT (device_token) DO UPDATE SET
             user_id = EXCLUDED.user_id,
             last_seen_at = datetime('now')"
    )
        .bind(&[body.device_token.into(), body.user_id.into()])?
        .run()
        .await?;

    Ok(Response::builder().with_status(200).empty())
}

// --- Station watches ---

async fn watch_station(
    mut req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let db = ctx.d1("DB")?;

    let body = match req.json::<WatchStationRequest>().await {
        Ok(b) => b,
        Err(_) => {
            return Response::builder()
                .with_status(400)
                .from_json(&ErrorResponse::new("Invalid request body"));
        }
    };

    let fuel_type_str = body.fuel_type.as_db_str();

    // Seed last_notified_price with current price to avoid immediate spurious notification.
    let latest_price_row = db.prepare(
        "SELECT price FROM fuel_prices
         WHERE station_id = ? AND fuel_type = ?
         ORDER BY effective_date DESC LIMIT 1"
    )
        .bind(&[body.station_id.clone().into(), fuel_type_str.into()])?
        .first::<serde_json::Value>(None)
        .await?;

    let latest_price: wasm_bindgen::JsValue = match latest_price_row.and_then(|r| r.get("price").and_then(|v| v.as_i64())) {
        Some(p) => wasm_bindgen::JsValue::from_f64(p as f64),
        None => wasm_bindgen::JsValue::NULL,
    };

    db.prepare(
        "INSERT INTO watched_stations (user_id, station_id, fuel_type, last_notified_price) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (user_id, station_id, fuel_type) DO NOTHING"
    )
        .bind(&[body.user_id.into(), body.station_id.into(), fuel_type_str.into(), latest_price])?
        .run()
        .await?;

    Ok(Response::builder().with_status(200).empty())
}

async fn unwatch_station(
    mut req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let db = ctx.d1("DB")?;

    let body = match req.json::<WatchStationRequest>().await {
        Ok(b) => b,
        Err(_) => {
            return Response::builder()
                .with_status(400)
                .from_json(&ErrorResponse::new("Invalid request body"));
        }
    };

    let fuel_type_str = body.fuel_type.as_db_str();

    db.prepare("DELETE FROM watched_stations WHERE user_id = ? AND station_id = ? AND fuel_type = ?")
        .bind(&[body.user_id.into(), body.station_id.into(), fuel_type_str.into()])?
        .run()
        .await?;

    Ok(Response::builder().with_status(200).empty())
}

async fn list_watches(
    req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let db = ctx.d1("DB")?;

    let url = req.url()?;
    let user_id = match url.query_pairs().find(|(k, _)| k == "user_id").map(|(_, v)| v.to_string()) {
        Some(id) => id,
        None => {
            return Response::builder()
                .with_status(400)
                .from_json(&ErrorResponse::new("Missing user_id query parameter"));
        }
    };

    let rows = db.prepare(
        "SELECT ws.station_id, ws.fuel_type, s.trading_name, s.brand_name
         FROM watched_stations ws
         JOIN stations s ON s.id = ws.station_id
         WHERE ws.user_id = ?"
    )
        .bind(&[user_id.into()])?
        .all()
        .await?;

    #[derive(Deserialize)]
    struct Row {
        station_id: String,
        fuel_type: String,
        trading_name: String,
        brand_name: String,
    }

    let stations = rows.results::<Row>()?
        .into_iter()
        .filter_map(|r| {
            Some(WatchedStation {
                station_id: r.station_id,
                trading_name: r.trading_name,
                brand_name: r.brand_name,
                fuel_type: FuelType::from_db_str(&r.fuel_type)?,
            })
        })
        .collect();

    Response::from_json(&ListWatchesResponse { stations })
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
