use serde::{Deserialize, Serialize};
use worker::*;
use crate::db::new_d1_connection;

#[event(fetch)]
async fn fetch(
    req: Request,
    env: Env,
    ctx: Context,
) -> Result<Response> {
    let app = Router::new()
        .get_async("/stations", get_stations);

    app.run(req, env).await
}

async fn get_stations(
    mut req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let db = new_d1_connection(&ctx)?;

    #[derive(Serialize, Deserialize)]
    struct RequestBody {
        fuel_types: Vec<String>,
        origin_lat: f64,
        origin_lon: f64,
        radius_km: f64
    }

    let body = req.json::<RequestBody>().await;
    if body.is_err() {
        return Response::error("Invalid JSON body", 400);
    }
    let body = body.unwrap();

    Response::from_json(&body.fuel_types)
}




