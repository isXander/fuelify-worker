import { env } from 'cloudflare:workers';
import { PFSFuelPricesResponse, PFSInformationResponse, PFSToken, PFSTokenResponse } from './types';

export async function fetchPFSBearerToken(): Promise<PFSToken> {
	const body = new URLSearchParams();
	body.append('grant_type', 'client_credentials');
	body.append('client_id', env.GOVUK_CLIENT_ID);
	body.append('client_secret', env.GOVUK_CLIENT_SECRET);

	const response = await fetch(`${env.PROXY_URL}/oauth/generate_access_token`, {
		method: 'POST',
		headers: {
			'Content-Type': 'application/x-www-form-urlencoded',
			'Accept': 'application/json',
			'User-Agent': 'Fuelify/0.1',
			'X-Fuelify-Secret': env.PROXY_SECRET
		},
		body,
		signal: AbortSignal.timeout(30_000),
	});

	if (!response.ok) {
		const responseText = await response.text();
		throw new Error(`Failed to fetch bearer token (code ${response.status}): ${responseText}`);
	}

	const data = await response.json<PFSTokenResponse>();

	if (!data.success) {
		throw new Error(`Failed to fetch bearer token: ${data.message}`);
	}

	return data.data;
}

export type FuelFinderDataResult<T> = T | 'no_more_batches'

export async function fetchPFSInformation(token: string, batchNumber: number, incrementalFrom: string | null): Promise<FuelFinderDataResult<PFSInformationResponse>> {
	const queryParams = new URLSearchParams();
	queryParams.append('batch-number', batchNumber.toString());
	if (incrementalFrom) queryParams.append('effective-start-timestamp', incrementalFrom);

	const response = await fetch(`${env.PROXY_URL}/pfs?${queryParams}`, {
		method: 'GET',
		headers: {
			'Accept': 'application/json',
			'Authorization': `Bearer ${token}`,
			'User-Agent': 'Fuelify/0.1',
			'X-Fuelify-Secret': env.PROXY_SECRET
		},
		signal: AbortSignal.timeout(30_000),
	});

	if (response.status === 404) {
		return 'no_more_batches';
	}

	if (!response.ok) {
		if (response.status === 401 || response.status === 403) {
			await env.fuelify_ingest.delete('access_token');
		}
		const responseText = await response.text();
		throw new Error(`Failed to fetch PFS information (code ${response.status}): ${responseText}`);
	}

	return response.json<PFSInformationResponse>();
}

export async function fetchPFSFuelPrices(token: string, batchNumber: number, incrementalFrom: string | null): Promise<FuelFinderDataResult<PFSFuelPricesResponse>> {
	const queryParams = new URLSearchParams();
	queryParams.append('batch-number', batchNumber.toString());
	if (incrementalFrom) queryParams.append('effective-start-timestamp', incrementalFrom);

	const response = await fetch(`${env.PROXY_URL}/pfs/fuel-prices?${queryParams}`, {
		method: 'GET',
		headers: {
			'Accept': 'application/json',
			'Authorization': `Bearer ${token}`,
			'User-Agent': 'Fuelify/0.1',
			'X-Fuelify-Secret': env.PROXY_SECRET
		},
		signal: AbortSignal.timeout(30_000),
	});

	if (response.status === 404) {
		return 'no_more_batches';
	}

	if (!response.ok) {
		if (response.status === 401 || response.status === 403) {
			await env.fuelify_ingest.delete('access_token');
		}
		const responseText = await response.text();
		throw new Error(`Failed to fetch fuel prices (code ${response.status}): ${responseText}`);
	}

	return response.json<PFSFuelPricesResponse>();
}
