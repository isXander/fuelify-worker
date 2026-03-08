use worker::*;
use crate::ingestion::apitypes::*;
use crate::ingestion::fetch::FetchError::RequestError;

const FUEL_FINDER_API_ENDPOINT: &str = "https://www.fuel-finder.service.gov.uk/api/v1";

pub(crate) async fn fetch_bearer_token(env: &Env) -> Result<PFSToken> {
    let grant_type = "client_credentials";
    let client_id = env.secret("GOVUK_CLIENT_ID")?.to_string();
    let client_secret = env.secret("GOVUK_CLIENT_SECRET")?.to_string();

    // Create URL-encoded form body
    let body = format!(
        "grant_type={}&client_id={}&client_secret={}",
        urlencoding::encode(grant_type),
        urlencoding::encode(&client_id),
        urlencoding::encode(&client_secret)
    );
    console_log!("Token request body: body={}", body);

    let headers = Headers::new();
    headers.set("Content-Type", "application/x-www-form-urlencoded")?;
    headers.set("Accept", "application/json")?;
    headers.set("user-agent", "Fuelify/0.1")?;

    let request = Fetch::Request(
        Request::new_with_init(
            &format!("{}/oauth/generate_access_token", FUEL_FINDER_API_ENDPOINT),
            &RequestInit {
                method: Method::Post,
                headers: headers,
                body: Some(body.into()),
                ..Default::default()
            },
        )?,
    );

    let mut response = request.send().await?;

    match response.status_code() {
        200 => (),
        status => {
            let response_body_text = response.text().await.unwrap_or_else(|_| "<Failed to read response body>".to_string());
            return Err(worker::Error::RustError(format!("Failed to fetch token: HTTP {}: {}", status, response_body_text)));
        }
    }


    let token_response: PFSTokenResponse = response.json().await
        .map_err(|e| worker::Error::RustError(format!("failed to parse response body: {:?}", e)))?;

    if token_response.success {
        Ok(token_response.data)
    } else {
        Err(worker::Error::RustError(format!("Failed to fetch token: {}", token_response.message.unwrap_or_else(|| "".to_string()))))
    }
}

pub(crate) async fn fetch_pfs_information(
    token: &str, batch_number: u32, incremental_from: Option<chrono::NaiveDate>
) -> Result<PFSInformationResponse, FetchError> {
    let query_params = match incremental_from {
        Some(date) => format!("?batch-number={}&effective-start-timestamp={}", batch_number, date),
        None => format!("?batch-number={}", batch_number),
    };
    let url = format!("{}/pfs{}", FUEL_FINDER_API_ENDPOINT, query_params);

    let headers = Headers::new();
    headers.set("Content-Type", "application/json")?;
    headers.set("Accept", "application/json")?;
    headers.set("User-Agent", "Fuelify/0.1")?;
    headers.set("Authorization", &format!("Bearer {}", token))?;

    let request = Fetch::Request(
        Request::new_with_init(
            &url,
            &RequestInit {
                method: Method::Get,
                headers: headers,
                ..Default::default()
            },
        )?,
    );

    let mut response = request.send().await?;

    match response.status_code() {
        200 => (),
        404 => return Err(FetchError::NotFound),
        status => {
            let response_body_text = response.text().await.unwrap_or_else(|_| "<Failed to read response body>".to_string());
            return Err(RequestError(worker::Error::RustError(format!("Failed to fetch token: HTTP {}: {}", status, response_body_text))));
        }
    }

    let body: PFSInformationResponse = response.json().await
        .map_err(|e| worker::Error::RustError(format!("failed to parse response body: {:?}", e)))?;
    Ok(body)
}

pub(crate) async fn fetch_pfs_fuel_prices(
    token: &str, batch_number: u32, incremental_from: Option<chrono::NaiveDate>
) -> Result<PFSFuelPricesResponse, FetchError> {
    let query_params = match incremental_from {
        Some(date) => format!("?batch-number={}&effective-start-timestamp={}", batch_number, date),
        None => format!("?batch-number={}", batch_number),
    };
    let url = format!("{}/pfs/fuel-prices{}", FUEL_FINDER_API_ENDPOINT, query_params);

    let headers = Headers::new();
    headers.set("Content-Type", "application/json")?;
    headers.set("Accept", "application/json")?;
    headers.set("User-Agent", "Fuelify/0.1")?;
    headers.set("Authorization", &format!("Bearer {}", token))?;

    let request = Fetch::Request(
        Request::new_with_init(
            &url,
            &RequestInit {
                method: Method::Get,
                headers: headers,
                ..Default::default()
            },
        )?,
    );

    let mut response = request.send().await?;

    match response.status_code() {
        200 => (),
        404 => return Err(FetchError::NotFound),
        status => {
            let response_body_text = response.text().await.unwrap_or_else(|_| "<Failed to read response body>".to_string());
            return Err(RequestError(worker::Error::RustError(format!("Failed to fetch token: HTTP {}: {}", status, response_body_text))));
        }
    }

    let body: PFSFuelPricesResponse = response.json().await
        .map_err(|e| worker::Error::RustError(format!("failed to parse response body: {:?}", e)))?;
    Ok(body)
}

#[derive(Debug)]
pub(crate) enum FetchError {
    /// Indicates this batch is too high and there is no more data to fetch, so we can stop the sync process.
    NotFound,
    RequestError(worker::Error),
}

impl From<worker::Error> for FetchError {
    fn from(e: worker::Error) -> Self {
        FetchError::RequestError(e)
    }
}

