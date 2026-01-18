use worker::{event, Env, Fetch, Method, Request, RequestInit, Response, Result};

const BASE10_API_URL: &str =
    "https://model-232nj723.api.baseten.co/environments/production/predict";

#[event(fetch)]
pub async fn main(mut req: Request, env: Env, _ctx: worker::Context) -> Result<Response> {
    if req.method() != Method::Post {
        return Response::error("Method Not Allowed", 405);
    }

    let api_key = match env.var("BASETEN_API_KEY") {
        Ok(value) => value.to_string(),
        Err(_) => return Response::error("Missing BASETEN_API_KEY", 500),
    };

    let body = req.bytes().await?;

    let mut init = RequestInit::new();
    init.with_method(Method::Post);
    init.with_body(Some(body.into()));

    let mut upstream = Request::new_with_init(BASE10_API_URL, &init)?;
    let headers = upstream.headers_mut();
    headers.set("Authorization", &format!("Api-Key {}", api_key))?;

    match req.headers().get("Content-Type")? {
        Some(content_type) => headers.set("Content-Type", &content_type)?,
        None => headers.set("Content-Type", "application/json")?,
    }

    Fetch::Request(upstream).send().await
}
