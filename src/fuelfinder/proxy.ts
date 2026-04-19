const FUEL_FINDER_API_ENDPOINT = 'https://www.fuel-finder.service.gov.uk/api/v1';

export const XFuelifySecret = 'X-Fuelify-Secret';

export async function proxyFetch(request: Request, path: string, env: Env): Promise<Response> {
	if (request.headers.get(XFuelifySecret) !== env.PROXY_SECRET) {
		return new Response('Proxy: secret mismatch', { status: 403 });
	}

	const url = new URL(request.url);
	const upstreamUrl = `${FUEL_FINDER_API_ENDPOINT}${path}${url.search}`;

	// Don't forward client-side auth headers or Host to GOV.UK. In particular, the
	// internal X-Fuelify-Secret validated above must not leak into upstream access logs.
	const upstreamHeaders = new Headers();
	for (const [name, value] of request.headers) {
		const lower = name.toLowerCase();
		if (lower === XFuelifySecret.toLowerCase()) continue;
		if (lower === 'authorization') continue;
		if (lower === 'cookie') continue;
		if (lower === 'host') continue;
		upstreamHeaders.set(name, value);
	}

	const hasBody = request.method !== 'GET' && request.method !== 'HEAD';
	const upstream = new Request(upstreamUrl, {
		method: request.method,
		headers: upstreamHeaders,
		body: hasBody ? request.body : null,
	});

	return fetch(upstream);
}
