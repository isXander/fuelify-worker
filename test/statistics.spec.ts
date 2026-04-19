import { SELF, env } from "cloudflare:test";
import { describe, it, expect, beforeEach } from "vitest";
import { cellToLatLng, cellToParent, latLngToCell } from "h3-js";
import {
	insertPrice,
	insertStation,
	resetDatabase,
	LONDON_R6,
	LONDON_R3,
} from "./helpers";
import { scheduledTakeSnapshot } from "../src/statistics/statistics";
import type { RegionStatisticsResponse } from "../src/api/types";

// First entry from UK_CELLS in src/statistics/statistics.ts.
const KNOWN_UK_R3 = "8309a0fffffffff";
const [SNAPSHOT_LAT, SNAPSHOT_LNG] = cellToLatLng(KNOWN_UK_R3);
const SNAPSHOT_R6 = latLngToCell(SNAPSHOT_LAT, SNAPSHOT_LNG, 6);
const SNAPSHOT_R3 = cellToParent(SNAPSHOT_R6, 3);

beforeEach(async () => {
	await resetDatabase();
});

const POST = (path: string, body: unknown) =>
	SELF.fetch(`https://example.com${path}`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(body),
	});

describe("POST /region_statistics", () => {
	it("returns 400 when body is not JSON", async () => {
		const res = await SELF.fetch("https://example.com/region_statistics", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: "{",
		});
		expect(res.status).toBe(400);
	});

	it("returns 400 when h3_cells is missing or empty", async () => {
		const res = await POST("/region_statistics", {
			fuel_type: "E10",
			h3_cells: [],
		});
		expect(res.status).toBe(400);
	});

	it("returns 400 when an h3 cell is invalid", async () => {
		const res = await POST("/region_statistics", {
			fuel_type: "E10",
			h3_cells: ["not-a-cell"],
		});
		expect(res.status).toBe(400);
	});

	it("returns 400 when an h3 cell is at the wrong resolution", async () => {
		const res = await POST("/region_statistics", {
			fuel_type: "E10",
			h3_cells: [LONDON_R3],
		});
		expect(res.status).toBe(400);
	});

	it("returns null statistics when no stations match", async () => {
		const res = await POST("/region_statistics", {
			fuel_type: "E10",
			h3_cells: [LONDON_R6],
		});

		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({
			station_count: 0,
			min_price: null,
			max_price: null,
			mean_price: null,
		} satisfies RegionStatisticsResponse);
	});

	it("aggregates min/max/mean across stations in the region", async () => {
		for (const [id, price] of [
			["S1", 1400],
			["S2", 1500],
			["S3", 1600],
		] as const) {
			await insertStation({ id });
			await insertPrice({
				station_id: id,
				fuel_type: "E10",
				price,
				effective_date: "2026-04-15T00:00:00Z",
			});
		}

		const res = await POST("/region_statistics", {
			fuel_type: "E10",
			h3_cells: [LONDON_R6],
		});

		const body = (await res.json()) as RegionStatisticsResponse;
		expect(body.station_count).toBe(3);
		expect(body.min_price).toBe(140.0);
		expect(body.max_price).toBe(160.0);
		expect(body.mean_price).toBe(150.0);
	});

	it("uses the latest price per station, ignoring older samples", async () => {
		await insertStation({ id: "S1" });
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 9999,
			effective_date: "2026-01-01T00:00:00Z",
		});
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1400,
			effective_date: "2026-04-15T00:00:00Z",
		});

		const res = await POST("/region_statistics", {
			fuel_type: "E10",
			h3_cells: [LONDON_R6],
		});

		const body = (await res.json()) as RegionStatisticsResponse;
		expect(body.station_count).toBe(1);
		expect(body.min_price).toBe(140.0);
		expect(body.max_price).toBe(140.0);
	});

	it("excludes motorway stations", async () => {
		await insertStation({ id: "REGULAR" });
		await insertStation({ id: "MOTORWAY", motorway: true });
		await insertPrice({
			station_id: "REGULAR",
			fuel_type: "E10",
			price: 1400,
			effective_date: "2026-04-15T00:00:00Z",
		});
		await insertPrice({
			station_id: "MOTORWAY",
			fuel_type: "E10",
			price: 1900,
			effective_date: "2026-04-15T00:00:00Z",
		});

		const res = await POST("/region_statistics", {
			fuel_type: "E10",
			h3_cells: [LONDON_R6],
		});

		const body = (await res.json()) as RegionStatisticsResponse;
		expect(body.station_count).toBe(1);
		expect(body.min_price).toBe(140.0);
	});
});

describe("scheduledTakeSnapshot", () => {
	it("inserts a regional_statistics row for cells with stations", async () => {
		await insertStation({
			id: "L1",
			latitude: SNAPSHOT_LAT,
			longitude: SNAPSHOT_LNG,
		});
		await insertStation({
			id: "L2",
			latitude: SNAPSHOT_LAT,
			longitude: SNAPSHOT_LNG,
		});
		await insertPrice({
			station_id: "L1",
			fuel_type: "E10",
			price: 1400,
			effective_date: "2026-04-15T00:00:00Z",
		});
		await insertPrice({
			station_id: "L2",
			fuel_type: "E10",
			price: 1500,
			effective_date: "2026-04-15T00:00:00Z",
		});

		await scheduledTakeSnapshot();

		const today = new Date().toISOString().slice(0, 10);
		const row = await env.DB.prepare(
			`SELECT * FROM regional_statistics
			 WHERE h3_res3 = ?1 AND fuel_type = ?2 AND date = ?3`,
		)
			.bind(SNAPSHOT_R3, "E10", today)
			.first<{
				station_count: number;
				min_price: number;
				max_price: number;
				mean_price: number;
			}>();

		expect(row).not.toBeNull();
		expect(row!.station_count).toBe(2);
		expect(row!.min_price).toBe(1400);
		expect(row!.max_price).toBe(1500);
		expect(row!.mean_price).toBe(1450);
	});

	it("upserts on conflict (h3_res3, fuel_type, date)", async () => {
		await insertStation({
			id: "L1",
			latitude: SNAPSHOT_LAT,
			longitude: SNAPSHOT_LNG,
		});
		await insertPrice({
			station_id: "L1",
			fuel_type: "E10",
			price: 1400,
			effective_date: "2026-04-15T00:00:00Z",
		});

		await scheduledTakeSnapshot();

		await env.DB.prepare(
			`UPDATE fuel_prices SET price = ?1 WHERE station_id = ?2`,
		)
			.bind(1700, "L1")
			.run();

		await scheduledTakeSnapshot();

		const today = new Date().toISOString().slice(0, 10);
		const rows = await env.DB.prepare(
			`SELECT * FROM regional_statistics
			 WHERE h3_res3 = ?1 AND fuel_type = ?2 AND date = ?3`,
		)
			.bind(SNAPSHOT_R3, "E10", today)
			.all<{ mean_price: number }>();

		expect(rows.results).toHaveLength(1);
		expect(rows.results[0].mean_price).toBe(1700);
	});
});

void LONDON_R3;
