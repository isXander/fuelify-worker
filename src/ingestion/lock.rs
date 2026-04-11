use crate::ingestion::wasm_bindgen;
use worker::*;

#[durable_object(fetch)]
struct IngestionLock {
    state: State,
    env: Env,
}

impl DurableObject for IngestionLock {
    fn new(state: State, env: Env) -> Self {
        Self {
            state,
            env,
        }
    }

    async fn fetch(&self, req: Request) -> Result<Response> {
        let url = req.url()?;
        let path = url.path();

        let kv = self.env.kv("fuelify_ingest")?;

        match path {
            "/lock" => {
                //let locked = self.state.storage().get::<bool>("locked").await?.unwrap_or(false);
                let locked = kv.get("lock").text().await?.unwrap_or_else(|| "false".to_string()) == "true";
                if locked {
                    return Response::error("Locked", 423);
                }

                // self.state.storage().put("locked", true).await?;
                kv.put("lock", "true")?.execute().await?;
                Response::ok("Locked")
            }
            "/unlock" => {
                // self.state.storage().delete("locked").await?;
                kv.delete("lock").await?;
                Response::ok("Unlocked")
            }
            "/heartbeat" => {

            }
            _ => Response::error("Not Found", 404),
        }
    }
}