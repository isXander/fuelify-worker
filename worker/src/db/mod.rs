mod models;

use worker::Env;

pub(crate) trait D1Provider {
    fn d1(&self, name: &str) -> worker::Result<worker::D1Database>;
}

pub(crate) fn new_d1_connection(provider: &impl D1Provider) -> worker::Result<sqlx_d1::D1Connection> {
    let d1 = provider.d1("DB")?;
    let conn = sqlx_d1::D1Connection::new(d1);
    Ok(conn)
}

impl D1Provider for Env {
    fn d1(&self, name: &str) -> worker::Result<worker::D1Database> {
        self.d1(name)
    }
}

impl <T> D1Provider for worker::RouteContext<T> {
    fn d1(&self, name: &str) -> worker::Result<worker::D1Database> {
        self.d1(name)
    }
}
