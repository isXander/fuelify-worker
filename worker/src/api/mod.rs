mod apitypes;

use apitypes::*;
use serde::Deserialize;
use worker::*;


#[event(fetch)]
async fn fetch(
    req: Request,
    env: Env,
    _ctx: Context,
) -> Result<Response> {
    let app = Router::new()
        .post_async("/nearby", get_stations)
        .post_async("/price_history", get_price_history);

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

    // Bind params:
    //   ?1: fuel_type
    //   ?2: origin_lat - half_span_lat  (bbox south)
    //   ?3: origin_lat + half_span_lat  (bbox north)
    //   ?4: origin_lon - half_span_lon  (bbox west)
    //   ?5: origin_lon + half_span_lon  (bbox east)
    //   ?6: fuel_type (repeated for latest_prices CTE)
    let sql = "
        WITH filtered_stations AS (
            SELECT l.station_id
            FROM pfs_locations l
            INNER JOIN pfs p ON p.id = l.station_id
            INNER JOIN pfs_fuel_prices fp ON fp.station_id = l.station_id
            WHERE l.latitude  BETWEEN ?2 AND ?3
              AND l.longitude BETWEEN ?4 AND ?5
              AND p.temporary_closure = FALSE
              AND p.permanent_closure = FALSE
              AND fp.fuel_type = ?1
              AND fp.effective_date = (
                  SELECT MAX(fp2.effective_date)
                  FROM pfs_fuel_prices fp2
                  WHERE fp2.station_id = l.station_id
                    AND fp2.fuel_type = ?1
              )
            GROUP BY l.station_id
        ),
        latest_prices AS (
            SELECT
                fp.station_id,
                fp.fuel_type,
                fp.price,
                fp.effective_date
            FROM pfs_fuel_prices fp
            INNER JOIN filtered_stations fs ON fs.station_id = fp.station_id
            WHERE fp.effective_date = (
                SELECT MAX(fp2.effective_date)
                FROM pfs_fuel_prices fp2
                WHERE fp2.station_id = fp.station_id
                  AND fp2.fuel_type = fp.fuel_type
            )
        )
        SELECT
            p.id              AS station_id,
            p.trading_name,
            p.brand_name,
            p.motorway,
            p.supermarket,
            l.latitude,
            l.longitude,
            l.address_line_1,
            l.address_line_2,
            l.city,
            l.county,
            l.postcode,
            GROUP_CONCAT(DISTINCT a.type)                                                      AS amenities,
            GROUP_CONCAT(DISTINCT lp.fuel_type || '|' || lp.price || '|' || lp.effective_date) AS fuel_prices
        FROM filtered_stations fs
        INNER JOIN pfs p           ON p.id          = fs.station_id
        INNER JOIN pfs_locations l ON l.station_id  = fs.station_id
        LEFT  JOIN pfs_amenities a ON a.station_id  = fs.station_id
        INNER JOIN latest_prices lp ON lp.station_id = fs.station_id
        GROUP BY p.id
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
        amenities: Option<String>,
        fuel_prices: String,
    }

    let result_rows = rows.results::<ResultRow>()?;

    let mut stations: Vec<Station> = Vec::with_capacity(result_rows.len());
    for row in result_rows {
        let amenities = row.amenities
            .as_deref()
            .unwrap_or("")
            .split(',')
            .filter(|s| !s.is_empty())
            .filter_map(Amenity::from_db_str)
            .collect();

        let mut latest_fuel_prices = std::collections::HashMap::new();
        for entry in row.fuel_prices.split(',') {
            let mut parts = entry.splitn(3, '|');
            let (Some(fuel_type_str), Some(price_str), Some(effective_date)) =
                (parts.next(), parts.next(), parts.next())
            else {
                continue;
            };
            let (Some(ft), Ok(price)) = (
                FuelType::from_db_str(fuel_type_str),
                price_str.parse::<f64>(),
            ) else {
                continue;
            };
            latest_fuel_prices.insert(ft, FuelPriceSample {
                price,
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

    console_log!("Found {} stations matching criteria", stations.len());

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
        FROM pfs_fuel_prices
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
        price: f64,
        effective_date: String,
    }

    let samples = rows.results::<PriceRow>()?
        .into_iter()
        .map(|r| FuelPriceSample {
            price: r.price,
            effective_date: r.effective_date,
        })
        .collect();

    Response::from_json(&PriceHistoryResponse { samples })
}

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




