use worker::{wasm_bindgen, Env, ScheduleContext, ScheduledEvent};
use crate::api::apitypes::FuelType;
use std::sync::LazyLock;
use serde::Deserialize;
use crate::models::TenthsOfPence;

macro_rules! h3_cells {
    ($($hex:literal),* $(,)?) => {
        [$(h3o::CellIndex::try_from($hex).unwrap()),*]
    };
}

static UK_CELLS: LazyLock<[h3o::CellIndex; 53]> = LazyLock::new(|| h3_cells![
    0x8309a0fffffffff_u64,
    0x8309a4fffffffff_u64,
    0x8309a5fffffffff_u64,
    0x8309a6fffffffff_u64,
    0x831821fffffffff_u64,
    0x831825fffffffff_u64,
    0x831829fffffffff_u64,
    0x83182dfffffffff_u64,
    0x831870fffffffff_u64,
    0x831874fffffffff_u64,
    0x831875fffffffff_u64,
    0x831876fffffffff_u64,
    0x831901fffffffff_u64,
    0x831908fffffffff_u64,
    0x831909fffffffff_u64,
    0x83190afffffffff_u64,
    0x83190bfffffffff_u64,
    0x83190cfffffffff_u64,
    0x83190dfffffffff_u64,
    0x83190efffffffff_u64,
    0x83191dfffffffff_u64,
    0x831928fffffffff_u64,
    0x831929fffffffff_u64,
    0x83192afffffffff_u64,
    0x83192bfffffffff_u64,
    0x83192cfffffffff_u64,
    0x831940fffffffff_u64,
    0x831941fffffffff_u64,
    0x831942fffffffff_u64,
    0x831943fffffffff_u64,
    0x831946fffffffff_u64,
    0x831948fffffffff_u64,
    0x83194afffffffff_u64,
    0x83194cfffffffff_u64,
    0x83194efffffffff_u64,
    0x831950fffffffff_u64,
    0x831951fffffffff_u64,
    0x831952fffffffff_u64,
    0x831953fffffffff_u64,
    0x831954fffffffff_u64,
    0x831955fffffffff_u64,
    0x831956fffffffff_u64,
    0x831958fffffffff_u64,
    0x831959fffffffff_u64,
    0x83195afffffffff_u64,
    0x83195bfffffffff_u64,
    0x83195cfffffffff_u64,
    0x83195dfffffffff_u64,
    0x83195efffffffff_u64,
    0x831972fffffffff_u64,
    0x831973fffffffff_u64,
    0x831976fffffffff_u64,
    0x8319adfffffffff_u64,
]);

pub async fn scheduled_take_snapshot(_event: &ScheduledEvent, env: &Env, _ctx: &ScheduleContext) -> worker::Result<()> {
    for &cell in UK_CELLS.iter() {
        snapshot_region_fuel(env, cell, FuelType::E5).await?;
        snapshot_region_fuel(env, cell, FuelType::E10).await?;
        snapshot_region_fuel(env, cell, FuelType::HVO).await?;
        snapshot_region_fuel(env, cell, FuelType::B10).await?;
        snapshot_region_fuel(env, cell, FuelType::B7Standard).await?;
        snapshot_region_fuel(env, cell, FuelType::B7Premium).await?;
    }

    Ok(())
}

async fn snapshot_region_fuel(env: &Env, region: h3o::CellIndex, fuel_type: FuelType) -> worker::Result<()> {
    let db = env.d1("DB")?;

    // 1. Get all stations in the region, excluding motorways, and get their latest price
    let sql = "
    SELECT fp.price
    FROM stations s
    JOIN fuel_prices fp ON fp.station_id = s.id
    WHERE s.h3_index_r3 = ?1
        AND s.motorway = 0
        AND fp.fuel_type = ?2
        AND fp.effective_date = (
            SELECT MAX(fp2.effective_date)
            FROM fuel_prices fp2
            WHERE fp2.station_id = s.id
                AND fp2.fuel_type = ?2
        );
    ";

    let bind_params: Vec<wasm_bindgen::JsValue> = vec![
        region.to_string().into(),
        fuel_type.as_db_str().into(),
    ];

    let rows = db.prepare(sql).bind(&bind_params)?.all().await?;

    #[derive(Deserialize)]
    struct ResultRow {
        price: TenthsOfPence,
    }

    let result_rows = rows.results::<ResultRow>()?;
    let prices = result_rows.iter().map(|row| row.price).collect::<Vec<_>>();

    if prices.is_empty() {
        return Ok(());
    }

    // 2. Calculate the mean, min, and max
    let count = prices.len() as u64;
    let min_price = *prices.iter().min().unwrap();
    let max_price = *prices.iter().max().unwrap();
    let mean_price = prices.iter().sum::<TenthsOfPence>() / count as i64;

    // 3. Put results in db
    let today = chrono::Utc::now().date_naive().to_string();

    let insert_sql = "
    INSERT INTO regional_statistics (h3_res3, fuel_type, station_count, min_price, max_price, mean_price, date)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
    ON CONFLICT (h3_res3, fuel_type, date) DO UPDATE SET
        station_count = excluded.station_count,
        min_price     = excluded.min_price,
        max_price     = excluded.max_price,
        mean_price    = excluded.mean_price;
    ";

    let insert_params: Vec<wasm_bindgen::JsValue> = vec![
        region.to_string().into(),
        fuel_type.as_db_str().into(),
        (count as f64).into(),
        (min_price as f64).into(),
        (max_price as f64).into(),
        (mean_price as f64).into(),
        today.into(),
    ];

    db.prepare(insert_sql).bind(&insert_params)?.run().await?;

    Ok(())
}