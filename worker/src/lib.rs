use worker::{event, Env, ScheduleContext, ScheduledEvent};

pub mod models;
pub mod ingestion;
pub mod api;
pub mod statistics;

#[event(scheduled)]
pub async fn scheduled(event: ScheduledEvent, env: Env, ctx: ScheduleContext) -> worker::Result<()> {
    match event.cron().as_str() {
        "*/15 * * * *" => ingestion::scheduled(&event, &env, &ctx).await,
        "0 0 * * *" => statistics::scheduled_take_snapshot(&event, &env, &ctx).await,
        _ => Err(worker::Error::RustError("Unknown cron trigger".to_string()))
    }
}
