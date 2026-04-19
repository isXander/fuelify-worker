const FUEL_FINDER_API_ENDPOINT = 'https://www.fuel-finder.service.gov.uk/api/v1';

export const XFuelifySecret = 'X-Fuelify-Secret';

export async function proxyFetch(request: Request, path: string, env: Env): Promise<Response> {
	if (request.headers.get(XFuelifySecret) !== env.PROXY_SECRET) {
		return new Response('Proxy: secret mismatch', { status: 403 });
	}

	const url = new URL(request.url);
	const upstreamUrl = `${FUEL_FINDER_API_ENDPOINT}${path}${url.search}`;

	// Don't leak our internal proxy secret into GOV.UK's access logs.
	const upstreamHeaders = new Headers(request.headers);
	upstreamHeaders.delete(XFuelifySecret);

	const hasBody = request.method !== 'GET' && request.method !== 'HEAD';
	const upstream = new Request(upstreamUrl, {
		method: request.method,
		headers: upstreamHeaders,
		body: hasBody ? request.body : null,
	});

	return fetch(upstream);
}
