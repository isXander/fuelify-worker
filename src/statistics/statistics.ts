import { env } from 'cloudflare:workers';
import { Context } from 'hono';
import { isValidCell, getResolution } from 'h3-js';
import {
	FuelType, fuelTypeToDb, isFuelType,
	RegionStatisticsRequest, RegionStatisticsResponse,
} from '../api/types';

type AppContext = { Bindings: Env };

const UK_CELLS: string[] = [
	'8309a0fffffffff',
	'8309a4fffffffff',
	'8309a5fffffffff',
	'8309a6fffffffff',
	'831821fffffffff',
	'831825fffffffff',
	'831829fffffffff',
	'83182dfffffffff',
	'831870fffffffff',
	'831874fffffffff',
	'831875fffffffff',
	'831876fffffffff',
	'831901fffffffff',
	'831908fffffffff',
	'831909fffffffff',
	'83190afffffffff',
	'83190bfffffffff',
	'83190cfffffffff',
	'83190dfffffffff',
	'83190efffffffff',
	'83191dfffffffff',
	'831928fffffffff',
	'831929fffffffff',
	'83192afffffffff',
	'83192bfffffffff',
	'83192cfffffffff',
	'831940fffffffff',
	'831941fffffffff',
	'831942fffffffff',
	'831943fffffffff',
	'831946fffffffff',
	'831948fffffffff',
	'83194afffffffff',
	'83194cfffffffff',
	'83194efffffffff',
	'831950fffffffff',
	'831951fffffffff',
	'831952fffffffff',
	'831953fffffffff',
	'831954fffffffff',
	'831955fffffffff',
	'831956fffffffff',
	'831958fffffffff',
	'831959fffffffff',
	'83195afffffffff',
	'83195bfffffffff',
	'83195cfffffffff',
	'83195dfffffffff',
	'83195efffffffff',
	'831972fffffffff',
	'831973fffffffff',
	'831976fffffffff',
	'8319adfffffffff',
];

const FUEL_TYPES: FuelType[] = ['E5', 'E10', 'HVO', 'B10', 'B7STANDARD', 'B7PREMIUM'];

interface RegionStatistics {
	count: number;
	/** Prices in tenths of pence. */
	min: number;
	max: number;
	mean: number;
}

export async function scheduledTakeSnapshot(): Promise<void> {
	for (const cell of UK_CELLS) {
		for (const fuelType of FUEL_TYPES) {
			await snapshotRegionFuel(cell, fuelType);
		}
	}
}

async function snapshotRegionFuel(region: string, fuelType: FuelType): Promise<void> {
	const stats = await computeRegionStatistics([region], fuelType, 3);
	if (!stats) return;

	const today = new Date().toISOString().slice(0, 10);

	await env.DB.prepare(`
		INSERT INTO regional_statistics (h3_res3, fuel_type, station_count, min_price, max_price, mean_price, date)
		VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
		ON CONFLICT (h3_res3, fuel_type, date) DO UPDATE SET
			station_count = excluded.station_count,
			min_price     = excluded.min_price,
			max_price     = excluded.max_price,
			mean_price    = excluded.mean_price
	`).bind(region, fuelTypeToDb(fuelType), stats.count, stats.min, stats.max, stats.mean, today).run();
}

async function computeRegionStatistics(
	cells: string[],
	fuelType: FuelType,
	resolution: 3 | 6,
): Promise<RegionStatistics | null> {
	const column = resolution === 3 ? 'h3_index_r3' : 'h3_index_r6';

	const { results } = await env.DB.prepare(`
		SELECT fp.price
		FROM stations s
		JOIN fuel_prices fp ON fp.station_id = s.id
		WHERE s.${column} IN (SELECT value FROM json_each(?1))
			AND s.motorway = 0
			AND fp.fuel_type = ?2
			AND fp.effective_date = (
				SELECT MAX(fp2.effective_date)
				FROM fuel_prices fp2
				WHERE fp2.station_id = s.id
					AND fp2.fuel_type = ?2
			)
	`).bind(JSON.stringify(cells), fuelTypeToDb(fuelType)).all<{ price: number }>();

	if (results.length === 0) return null;

	const prices = results.map(r => r.price);
	const count = prices.length;
	const sum = prices.reduce((acc, p) => acc + p, 0);

	return {
		count,
		min: Math.min(...prices),
		max: Math.max(...prices),
		mean: Math.floor(sum / count),
	};
}

export async function getRegionStatistics(c: Context<AppContext>): Promise<Response> {
	let body: RegionStatisticsRequest;
	try {
		body = await c.req.json<RegionStatisticsRequest>();
	} catch {
		return Response.json({ success: false, message: 'Invalid request body' }, { status: 400 });
	}

	if (!Array.isArray(body.h3_cells) || body.h3_cells.length === 0) {
		return Response.json({ success: false, message: 'h3_cells must be a non-empty array' }, { status: 400 });
	}

	for (const cell of body.h3_cells) {
		if (!isValidCell(cell) || getResolution(cell) !== 6) {
			return Response.json({ success: false, message: 'h3_cells must all be valid H3 cells at resolution 6' }, { status: 400 });
		}
	}

	if (!isFuelType(body.fuel_type)) {
		return Response.json({ success: false, message: 'fuel_type must be a valid fuel type' }, { status: 400 });
	}

	const stats = await computeRegionStatistics(body.h3_cells, body.fuel_type, 6);

	if (!stats) {
		return Response.json({
			station_count: 0,
			min_price: null,
			max_price: null,
			mean_price: null,
		} satisfies RegionStatisticsResponse);
	}

	return Response.json({
		station_count: stats.count,
		min_price: stats.min / 10,
		max_price: stats.max / 10,
		mean_price: stats.mean / 10,
	} satisfies RegionStatisticsResponse);
}