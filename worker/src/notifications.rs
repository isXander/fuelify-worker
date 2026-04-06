use serde::{Deserialize, Serialize};
use worker::*;

/// Called once at the end of each sync cycle. Finds watched stations whose latest
/// price differs from `last_notified_price`, sends FCM data pushes, and updates
/// the stored price so we don't re-notify.
pub async fn check_and_notify(env: &Env) -> Result<()> {
    let db = env.d1("DB")?;

    let changed = db.prepare(
        "SELECT ws.user_id, ws.station_id, ws.fuel_type,
                fp.price AS new_price, ws.last_notified_price AS old_price,
                s.trading_name
         FROM watched_stations ws
         JOIN stations s ON s.id = ws.station_id
         JOIN fuel_prices fp ON fp.station_id = ws.station_id
             AND fp.fuel_type = ws.fuel_type
             AND fp.effective_date = (
                 SELECT MAX(fp2.effective_date) FROM fuel_prices fp2
                 WHERE fp2.station_id = ws.station_id AND fp2.fuel_type = ws.fuel_type
             )
         WHERE ws.last_notified_price IS NOT NULL
           AND ws.last_notified_price != fp.price"
    )
        .bind(&[])?
        .all()
        .await?;

    #[derive(Deserialize)]
    struct ChangeRow {
        user_id: String,
        station_id: String,
        fuel_type: String,
        new_price: i64,
        old_price: i64,
        trading_name: String,
    }

    let changes = changed.results::<ChangeRow>()?;
    if changes.is_empty() {
        return Ok(());
    }

    let fcm_token = get_fcm_access_token(env).await?;

    let kv = env.kv("fuelify_ingest")?;
    let project_id = match kv.get("fcm_project_id").text().await? {
        Some(id) => id,
        None => {
            // Extract project_id from service account on first run and cache it.
            let sa = get_service_account(env)?;
            kv.put("fcm_project_id", &sa.project_id)?.execute().await?;
            sa.project_id
        }
    };

    for change in &changes {
        // Look up all device tokens for this user.
        let devices = db.prepare("SELECT device_token FROM devices WHERE user_id = ?")
            .bind(&[change.user_id.clone().into()])?
            .all()
            .await?;

        #[derive(Deserialize)]
        struct DeviceRow {
            device_token: String,
        }

        let device_rows = devices.results::<DeviceRow>()?;

        let old_pence = change.old_price as f64 / 10.0;
        let new_pence = change.new_price as f64 / 10.0;

        for device in &device_rows {
            let result = send_fcm_data_message(
                &fcm_token,
                &project_id,
                &device.device_token,
                &change.station_id,
                &change.trading_name,
                &change.fuel_type,
                old_pence,
                new_pence,
            ).await;

            match result {
                Ok(FcmOutcome::Success) => {}
                Ok(FcmOutcome::Unregistered) => {
                    console_log!("Removing stale device token: {}", &device.device_token);
                    db.prepare("DELETE FROM devices WHERE device_token = ?")
                        .bind(&[device.device_token.clone().into()])?
                        .run()
                        .await?;
                }
                Err(e) => {
                    console_error!("FCM send error for token {}: {:?}", &device.device_token, e);
                }
            }
        }

        // Update last_notified_price so we don't re-notify.
        db.prepare("UPDATE watched_stations SET last_notified_price = ? WHERE user_id = ? AND station_id = ? AND fuel_type = ?")
            .bind(&[
                wasm_bindgen::JsValue::from_f64(change.new_price as f64),
                change.user_id.clone().into(),
                change.station_id.clone().into(),
                change.fuel_type.clone().into(),
            ])?
            .run()
            .await?;
    }

    console_log!("Sent price change notifications for {} watch entries", changes.len());
    Ok(())
}

// --- FCM HTTP v1 API ---

enum FcmOutcome {
    Success,
    Unregistered,
}

async fn send_fcm_data_message(
    access_token: &str,
    project_id: &str,
    device_token: &str,
    station_id: &str,
    station_name: &str,
    fuel_type: &str,
    old_price: f64,
    new_price: f64,
) -> Result<FcmOutcome> {
    let url = format!(
        "https://fcm.googleapis.com/v1/projects/{}/messages:send",
        project_id
    );

    let payload = serde_json::json!({
        "message": {
            "token": device_token,
            "data": {
                "type": "price_change",
                "station_id": station_id,
                "station_name": station_name,
                "fuel_type": fuel_type,
                "old_price": format!("{:.1}", old_price),
                "new_price": format!("{:.1}", new_price),
            }
        }
    });

    let headers = Headers::new();
    headers.set("Authorization", &format!("Bearer {}", access_token))?;
    headers.set("Content-Type", "application/json")?;

    let mut init = RequestInit::new();
    init.with_method(Method::Post)
        .with_headers(headers)
        .with_body(Some(wasm_bindgen::JsValue::from_str(&payload.to_string())));

    let req = Request::new_with_init(&url, &init)?;
    let mut resp = Fetch::Request(req).send().await?;

    if resp.status_code() == 200 {
        return Ok(FcmOutcome::Success);
    }

    // Check for UNREGISTERED / NOT_FOUND errors indicating stale token.
    let body = resp.text().await.unwrap_or_default();
    if body.contains("UNREGISTERED") || body.contains("NOT_FOUND") {
        return Ok(FcmOutcome::Unregistered);
    }

    console_error!("FCM error ({}): {}", resp.status_code(), body);
    Ok(FcmOutcome::Success) // Don't retry on unknown errors — log and move on.
}

// --- FCM OAuth2 token via service account JWT ---

#[derive(Deserialize)]
struct ServiceAccount {
    project_id: String,
    client_email: String,
    private_key: String,
}

fn get_service_account(env: &Env) -> Result<ServiceAccount> {
    let json_str = env.secret("FCM_SERVICE_ACCOUNT")?.to_string();
    serde_json::from_str(&json_str)
        .map_err(|e| worker::Error::RustError(format!("Failed to parse FCM service account: {}", e)))
}

async fn get_fcm_access_token(env: &Env) -> Result<String> {
    let kv = env.kv("fuelify_ingest")?;

    // Check cache first.
    if let Some(token) = kv.get("fcm_access_token").text().await? {
        return Ok(token);
    }

    let sa = get_service_account(env)?;

    let now = (Date::now().as_millis() / 1000) as u64;
    let claims = FcmJwtClaims {
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging".to_string(),
        aud: "https://oauth2.googleapis.com/token".to_string(),
        iat: now,
        exp: now + 3600,
    };

    let key = jsonwebtoken::EncodingKey::from_rsa_pem(sa.private_key.as_bytes())
        .map_err(|e| worker::Error::RustError(format!("Invalid RSA key: {}", e)))?;

    let header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256);
    let jwt = jsonwebtoken::encode(&header, &claims, &key)
        .map_err(|e| worker::Error::RustError(format!("JWT encode failed: {}", e)))?;

    // Exchange JWT for access token.
    let token_body = format!(
        "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion={}",
        jwt
    );

    let headers = Headers::new();
    headers.set("Content-Type", "application/x-www-form-urlencoded")?;

    let mut init = RequestInit::new();
    init.with_method(Method::Post)
        .with_headers(headers)
        .with_body(Some(wasm_bindgen::JsValue::from_str(&token_body)));

    let req = Request::new_with_init("https://oauth2.googleapis.com/token", &init)?;
    let mut resp = Fetch::Request(req).send().await?;
    let token_resp = resp.json::<GoogleTokenResponse>().await?;

    // Cache with 55min TTL (tokens last 60min).
    kv.put("fcm_access_token", &token_resp.access_token)?
        .expiration_ttl(3300)
        .execute()
        .await?;

    Ok(token_resp.access_token)
}

#[derive(Serialize)]
struct FcmJwtClaims {
    iss: String,
    scope: String,
    aud: String,
    iat: u64,
    exp: u64,
}

#[derive(Deserialize)]
struct GoogleTokenResponse {
    access_token: String,
}
