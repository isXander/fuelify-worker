import {Context, Hono} from 'hono';
import { proxyFetch } from '../fuelfinder/proxy';
import { gridDisk, isValidCell, getResolution } from 'h3-js';
import {
	Amenity, FuelPriceSample, FuelType, OpeningHours,
	Station, StationsListResponse, PriceHistoryResponse,
	NearbyStationsRequest, GetStationsRequest, PriceHistoryRequest,
	historyIntervalDays, fuelTypeFromDb, fuelTypeToDb,
	isFuelType, isHistoryInterval,
} from './types';
import { getRegionStatistics } from '../statistics/statistics';

const MAX_SEARCH_RADIUS = 10;

export function onApiFetch(request: Request, env: Env, ctx: ExecutionContext): Response | Promise<Response> {
	const app = new Hono<{ Bindings: Env }>()
		.post("/nearby", getNearbyStations)
		.post("/stations", getStationsById)
		.post("/price_history", getPriceHistory)
		.post("/region_statistics", getRegionStatistics)
		.all("/fuel-finder-proxy/:path{.+}", fuelFinderProxy);

	return app.fetch(request, env, ctx);
}

interface StationRow {
	station_id: string;
	phone_number: string | null;
	trading_name: string;
	brand_name: string;
	trading_as_brand: number;
	temporary_closure: number;
	permanent_closure: number;
	motorway: number;
	supermarket: number;
	address_line_1: string;
	address_line_2: string;
	city: string;
	county: string;
	country: string;
	postcode: string;
	latitude: number;
	longitude: number;
	h3_index_r6: string;
	h3_index_r3: string;
	amenities: string;
	opening_hours: string;
	fuel_type: string;
	price: number;
	effective_date: string;
}

function buildStations(rows: StationRow[]): Station[] {
	const stations: Station[] = [];
	const stationIndex = new Map<string, number>();

	for (const row of rows) {
		const fuelType = fuelTypeFromDb(row.fuel_type);
		const sample: FuelPriceSample = { price: row.price / 10, effective_date: row.effective_date };

		const idx = stationIndex.get(row.station_id);
		if (idx !== undefined) {
			if (fuelType) stations[idx].latest_fuel_prices[fuelType] = sample;
			continue;
		}

		const amenities: Amenity[] = JSON.parse(row.amenities ?? '[]');
		const opening_hours: OpeningHours = JSON.parse(row.opening_hours ?? '{}');

		const station: Station = {
			info: {
				station_id: row.station_id,
				phone_number: row.phone_number ?? '',
				trading_name: row.trading_name,
				brand_name: row.brand_name,
				trading_as_brand: row.trading_as_brand !== 0,
				temporary_closure: row.temporary_closure !== 0,
				permanent_closure: row.permanent_closure !== 0,
				motorway: row.motorway !== 0,
				supermarket: row.supermarket !== 0,
				address_line_1: row.address_line_1,
				address_line_2: row.address_line_2,
				city: row.city,
				county: row.county,
				country: row.country,
				postcode: row.postcode,
				latitude: row.latitude,
				longitude: row.longitude,
				h3_index_r6: row.h3_index_r6,
				h3_index_r3: row.h3_index_r3,
				amenities,
				opening_hours,
			},
			latest_fuel_prices: fuelType ? { [fuelType]: sample } : {},
		};

		stationIndex.set(row.station_id, stations.length);
		stations.push(station);
	}

	return stations;
}

const LATEST_FUEL_PRICE_FILTER = `
	fp.effective_date = (
		SELECT MAX(fp2.effective_date) FROM fuel_prices fp2
		WHERE fp2.station_id = fp.station_id AND fp2.fuel_type = fp.fuel_type
	)
`;

type AppContext = { Bindings: Env };

async function getNearbyStations(c: Context<AppContext>): Promise<Response> {
	let body: NearbyStationsRequest;
	try {
		body = await c.req.json<NearbyStationsRequest>();
	} catch {
		return errorResponse(400, 'Invalid request body');
	}

	if (!isValidCell(body.origin) || getResolution(body.origin) !== 6) {
		return errorResponse(400, 'origin must be a valid H3 cell at resolution 6');
	}

	if (!isFuelType(body.fuel_type)) {
		return errorResponse(400, 'fuel_type must be a valid fuel type');
	}

	if (!Number.isInteger(body.k_rings) || body.k_rings < 0) {
		return errorResponse(400, 'k_rings must be a non-negative integer');
	}

	if (body.k_rings > MAX_SEARCH_RADIUS) {
		return errorResponse(400, `k_rings must be <= ${MAX_SEARCH_RADIUS}`);
	}

	const searchCellsJson = JSON.stringify(gridDisk(body.origin, body.k_rings));
	const fuelTypeDb = fuelTypeToDb(body.fuel_type);

	const { results } = await c.env.DB.prepare(`
		WITH requested_latest AS (
			SELECT fp.station_id, MAX(fp.effective_date) AS requested_effective_date
			FROM fuel_prices fp
			WHERE fp.fuel_type = ?1
			GROUP BY fp.station_id
		),
		selected_stations AS (
			SELECT s.id AS station_id, s.phone_number, s.trading_name, s.brand_name,
			       s.trading_as_brand, s.temporary_closure, s.permanent_closure, s.motorway, s.supermarket,
			       s.address_line_1, s.address_line_2, s.city, s.county, s.country, s.postcode,
			       s.latitude, s.longitude, s.h3_index_r6, s.h3_index_r3, s.amenities, s.opening_hours,
			       rl.requested_effective_date
			FROM stations s
			INNER JOIN requested_latest rl ON rl.station_id = s.id
			WHERE s.h3_index_r6 IN (SELECT value FROM json_each(?2))
			AND s.temporary_closure = FALSE
			AND s.permanent_closure = FALSE
			ORDER BY rl.requested_effective_date DESC, s.trading_name ASC
			LIMIT 200
		)
		SELECT ss.station_id, ss.phone_number, ss.trading_name, ss.brand_name,
		       ss.trading_as_brand, ss.temporary_closure, ss.permanent_closure, ss.motorway, ss.supermarket,
		       ss.address_line_1, ss.address_line_2, ss.city, ss.county, ss.country, ss.postcode,
		       ss.latitude, ss.longitude, ss.h3_index_r6, ss.h3_index_r3, ss.amenities, ss.opening_hours,
		       fp.fuel_type, fp.price, fp.effective_date
		FROM selected_stations ss
		INNER JOIN fuel_prices fp ON fp.station_id = ss.station_id
		WHERE ${LATEST_FUEL_PRICE_FILTER}
		ORDER BY ss.requested_effective_date DESC, ss.trading_name ASC, fp.fuel_type ASC
	`).bind(fuelTypeDb, searchCellsJson).all<StationRow>();

	return Response.json({ results: buildStations(results) } satisfies StationsListResponse);
}

async function getStationsById(c: Context<AppContext>): Promise<Response> {
	let body: GetStationsRequest;
	try {
		body = await c.req.json<GetStationsRequest>();
	} catch {
		return errorResponse(400, 'Invalid request body');
	}

	if (!Array.isArray(body.station_ids) || body.station_ids.length === 0) {
		return errorResponse(400, 'station_ids must be a non-empty array');
	}

	if (body.station_ids.some((id) => typeof id !== 'string' || id.length === 0)) {
		return errorResponse(400, 'station_ids must be an array of non-empty strings');
	}

	const { results } = await c.env.DB.prepare(`
		SELECT s.id AS station_id, s.phone_number, s.trading_name, s.brand_name,
		       s.trading_as_brand, s.temporary_closure, s.permanent_closure, s.motorway, s.supermarket,
		       s.address_line_1, s.address_line_2, s.city, s.county, s.country, s.postcode,
		       s.latitude, s.longitude, s.h3_index_r6, s.h3_index_r3, s.amenities, s.opening_hours,
		       fp.fuel_type, fp.price, fp.effective_date
		FROM stations s
		INNER JOIN fuel_prices fp ON fp.station_id = s.id
		WHERE s.id IN (SELECT value FROM json_each(?1))
		AND ${LATEST_FUEL_PRICE_FILTER}
		ORDER BY s.trading_name ASC, fp.fuel_type ASC
	`).bind(JSON.stringify(body.station_ids)).all<StationRow>();

	return Response.json({ results: buildStations(results) } satisfies StationsListResponse);
}

async function getPriceHistory(c: Context<AppContext>): Promise<Response> {
	let body: PriceHistoryRequest;
	try {
		body = await c.req.json<PriceHistoryRequest>();
	} catch {
		return errorResponse(400, 'Invalid request body');
	}

	if (typeof body.station_id !== 'string' || body.station_id.length === 0) {
		return errorResponse(400, 'station_id must be a non-empty string');
	}
	if (!isFuelType(body.fuel_type)) {
		return errorResponse(400, 'fuel_type must be a valid fuel type');
	}
	if (!isHistoryInterval(body.interval)) {
		return errorResponse(400, 'interval must be a valid history interval');
	}

	const days = historyIntervalDays(body.interval);
	const cutoffDate = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
		.toISOString()
		.replace(/\.\d{3}Z$/, 'Z');

	const { results } = await c.env.DB.prepare(`
		SELECT price, effective_date
		FROM fuel_prices
		WHERE station_id = ?1
		  AND fuel_type = ?2
		  AND effective_date >= ?3
		ORDER BY effective_date ASC
	`).bind(body.station_id, fuelTypeToDb(body.fuel_type), cutoffDate).all<{ price: number; effective_date: string }>();

	const samples: FuelPriceSample[] = results.map((r: { price: number; effective_date: string }) => ({
		price: r.price / 10,
		effective_date: r.effective_date,
	}));

	return Response.json({ samples } satisfies PriceHistoryResponse);
}

async function fuelFinderProxy(c: Context<AppContext>): Promise<Response> {
	const subPath = c.req.param('path');
	return proxyFetch(c.req.raw, '/' + subPath, c.env);
}

function errorResponse(status: number, message: string): Response {
	return Response.json({ success: false, message }, { status });
}
