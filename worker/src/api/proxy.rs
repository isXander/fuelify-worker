use worker::*;
use crate::api::ErrorResponse;

const FUEL_FINDER_API_ENDPOINT: &str = "https://www.fuel-finder.service.gov.uk/api/v1";

pub(super) async fn on_fuel_finder_proxy(
    mut req: Request, ctx: RouteContext<()>
) -> Result<Response> {
    let shared_secret = get_shared_secret(&ctx).await?;
    match req.headers().get("X-Fuelify-Secret")? {
        Some(secret) if secret == shared_secret => {
            // Authorised.
        }
        _ => return Response::builder()
            .with_status(403)
            .from_json(&ErrorResponse::new("Proxy: Secret mismatch"))
    }

    let path = ctx.param("path").map(|p| p.as_str()).unwrap_or("");
    let url = req.url()?;
    let query = url.query().map(|q| format!("?{}", q)).unwrap_or_default();
    let upstream_url = format!("{}/{}{}", FUEL_FINDER_API_ENDPOINT, path, query);

    let method = req.method();
    let headers = req.headers().clone();
    let body = match method {
        Method::Get | Method::Head => None,
        _ => req.bytes().await.ok().and_then(|b| {
            if b.is_empty() {
                None
            } else {
                let js_val: wasm_bindgen::JsValue = js_sys::Uint8Array::from(b.as_slice()).into();
                Some(js_val)
            }
        }),
    };

    let upstream_req = Request::new_with_init(
        &upstream_url,
        &RequestInit {
            method,
            headers,
            body,
            ..Default::default()
        },
    )?;

    Fetch::Request(upstream_req).send().await
}

async fn get_shared_secret(ctx: &RouteContext<()>) -> Result<String> {
    Ok(ctx.secret("PROXY_SECRET")?.to_string())
}
