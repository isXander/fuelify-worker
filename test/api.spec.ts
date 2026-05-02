import { SELF } from "cloudflare:test";
import { describe, it, expect, beforeEach } from "vitest";
import { gridDisk } from "h3-js";
import {
	insertPrice,
	insertStation,
	resetDatabase,
	LONDON_R6,
	LONDON_R3,
	MANCHESTER_R6,
} from "./helpers";
import type {
	FetchH3CellsRequest,
	GetStationsRequest,
	NearbyStationsRequest,
	PriceHistoryRequest,
	PriceHistoryResponse,
	StationsListResponse,
} from "../src/api/types";

const POST = (path: string, body: unknown) =>
	SELF.fetch(`https://example.com${path}`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(body),
	});

beforeEach(async () => {
	await resetDatabase();
});

describe("POST /nearby", () => {
	it("returns 400 when body is not JSON", async () => {
		const res = await SELF.fetch("https://example.com/nearby", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: "not-json",
		});
		expect(res.status).toBe(400);
		expect(await res.json()).toEqual({
			success: false,
			message: "Invalid request body",
		});
	});

	it("returns 400 when origin is not a valid h3 cell", async () => {
		const res = await POST("/nearby", {
			fuel_type: "E10",
			origin: "not-an-h3-cell",
			k_rings: 1,
		} satisfies NearbyStationsRequest);
		expect(res.status).toBe(400);
	});

	it("returns 400 when origin is at the wrong resolution", async () => {
		// LONDON_R6 is at res 6; res 3 parent should fail.
		const r3Cell = "831970fffffffff";
		const res = await POST("/nearby", {
			fuel_type: "E10",
			origin: r3Cell,
			k_rings: 1,
		} satisfies NearbyStationsRequest);
		expect(res.status).toBe(400);
	});

	it("returns 400 when k_rings exceeds the limit", async () => {
		const res = await POST("/nearby", {
			fuel_type: "E10",
			origin: LONDON_R6,
			k_rings: 999,
		} satisfies NearbyStationsRequest);
		expect(res.status).toBe(400);
		const body = (await res.json()) as { message: string };
		expect(body.message).toContain("k_rings");
	});

	it("returns matching stations with their latest fuel price", async () => {
		await insertStation({ id: "S1", trading_name: "ALPHA" });
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1450,
			effective_date: "2026-04-10T12:00:00Z",
		});
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1399,
			effective_date: "2026-04-15T12:00:00Z",
		});
		await insertPrice({
			station_id: "S1",
			fuel_type: "B7Standard",
			price: 1550,
			effective_date: "2026-04-12T12:00:00Z",
		});

		const res = await POST("/nearby", {
			fuel_type: "E10",
			origin: LONDON_R6,
			k_rings: 1,
		} satisfies NearbyStationsRequest);

		expect(res.status).toBe(200);
		const body = (await res.json()) as StationsListResponse;
		expect(body.results).toHaveLength(1);

		const station = body.results[0];
		expect(station.info.station_id).toBe("S1");
		expect(station.info.trading_name).toBe("ALPHA");
		expect(station.latest_fuel_prices.E10).toEqual({
			price: 139.9,
			effective_date: "2026-04-15T12:00:00Z",
		});
		expect(station.latest_fuel_prices.B7STANDARD).toEqual({
			price: 155.0,
			effective_date: "2026-04-12T12:00:00Z",
		});
	});

	it("excludes stations without a price for the requested fuel type", async () => {
		await insertStation({ id: "S1" });
		await insertPrice({
			station_id: "S1",
			fuel_type: "B7Standard",
			price: 1500,
			effective_date: "2026-04-15T12:00:00Z",
		});

		const res = await POST("/nearby", {
			fuel_type: "E10",
			origin: LONDON_R6,
			k_rings: 1,
		} satisfies NearbyStationsRequest);

		const body = (await res.json()) as StationsListResponse;
		expect(body.results).toHaveLength(0);
	});

	it("excludes closed stations", async () => {
		await insertStation({ id: "OPEN" });
		await insertStation({ id: "TEMP", temporary_closure: true });
		await insertStation({ id: "PERM", permanent_closure: true });

		for (const id of ["OPEN", "TEMP", "PERM"]) {
			await insertPrice({
				station_id: id,
				fuel_type: "E10",
				price: 1400,
				effective_date: "2026-04-15T12:00:00Z",
			});
		}

		const res = await POST("/nearby", {
			fuel_type: "E10",
			origin: LONDON_R6,
			k_rings: 1,
		} satisfies NearbyStationsRequest);

		const body = (await res.json()) as StationsListResponse;
		expect(body.results.map((s) => s.info.station_id)).toEqual(["OPEN"]);
	});

	it("excludes stations outside the search radius", async () => {
		await insertStation({
			id: "MANCHESTER",
			latitude: 53.48,
			longitude: -2.24,
		});
		await insertPrice({
			station_id: "MANCHESTER",
			fuel_type: "E10",
			price: 1400,
			effective_date: "2026-04-15T12:00:00Z",
		});

		const res = await POST("/nearby", {
			fuel_type: "E10",
			origin: LONDON_R6,
			k_rings: 1,
		} satisfies NearbyStationsRequest);

		const body = (await res.json()) as StationsListResponse;
		expect(body.results).toHaveLength(0);
	});
});

describe("POST /h3_cells", () => {
	it("returns 400 when body is not JSON", async () => {
		const res = await SELF.fetch("https://example.com/h3_cells", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: "not-json",
		});
		expect(res.status).toBe(400);
		expect(await res.json()).toEqual({
			success: false,
			message: "Invalid request body",
		});
	});

	it("returns 400 when h3_cells is missing or empty", async () => {
		const res = await POST("/h3_cells", {
			fuel_type: "E10",
			h3_cells: [],
		} satisfies FetchH3CellsRequest);
		expect(res.status).toBe(400);
		const body = (await res.json()) as { message: string };
		expect(body.message).toContain("h3_cells");
	});

	it("returns 400 when h3_cells exceeds the k-ring 5 disk size", async () => {
		const cells = [...gridDisk(LONDON_R6, 5), MANCHESTER_R6];
		expect(cells).toHaveLength(92);

		const res = await POST("/h3_cells", {
			fuel_type: "E10",
			h3_cells: cells,
		} satisfies FetchH3CellsRequest);

		expect(res.status).toBe(400);
		const body = (await res.json()) as { message: string };
		expect(body.message).toContain("91");
	});

	it("returns 400 when any cell is invalid or at the wrong resolution", async () => {
		const invalid = await POST("/h3_cells", {
			fuel_type: "E10",
			h3_cells: [LONDON_R6, "not-an-h3-cell"],
		} satisfies FetchH3CellsRequest);
		expect(invalid.status).toBe(400);

		const wrongResolution = await POST("/h3_cells", {
			fuel_type: "E10",
			h3_cells: [LONDON_R3],
		} satisfies FetchH3CellsRequest);
		expect(wrongResolution.status).toBe(400);
	});

	it("returns matching stations with their latest fuel price", async () => {
		await insertStation({ id: "S1", trading_name: "ALPHA" });
		await insertStation({ id: "S2", trading_name: "BETA", h3_index_r6: MANCHESTER_R6 });
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1450,
			effective_date: "2026-04-10T12:00:00Z",
		});
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1399,
			effective_date: "2026-04-15T12:00:00Z",
		});
		await insertPrice({
			station_id: "S1",
			fuel_type: "B7Standard",
			price: 1550,
			effective_date: "2026-04-12T12:00:00Z",
		});
		await insertPrice({
			station_id: "S2",
			fuel_type: "E10",
			price: 1500,
			effective_date: "2026-04-15T12:00:00Z",
		});

		const res = await POST("/h3_cells", {
			fuel_type: "E10",
			h3_cells: [LONDON_R6],
		} satisfies FetchH3CellsRequest);

		expect(res.status).toBe(200);
		const body = (await res.json()) as StationsListResponse;
		expect(body.results.map((s) => s.info.station_id)).toEqual(["S1"]);

		const station = body.results[0];
		expect(station.latest_fuel_prices.E10).toEqual({
			price: 139.9,
			effective_date: "2026-04-15T12:00:00Z",
		});
		expect(station.latest_fuel_prices.B7STANDARD).toEqual({
			price: 155.0,
			effective_date: "2026-04-12T12:00:00Z",
		});
	});

	it("excludes stations without a price for the requested fuel type", async () => {
		await insertStation({ id: "S1" });
		await insertPrice({
			station_id: "S1",
			fuel_type: "B7Standard",
			price: 1500,
			effective_date: "2026-04-15T12:00:00Z",
		});

		const res = await POST("/h3_cells", {
			fuel_type: "E10",
			h3_cells: [LONDON_R6],
		} satisfies FetchH3CellsRequest);

		const body = (await res.json()) as StationsListResponse;
		expect(body.results).toEqual([]);
	});
});

describe("POST /stations", () => {
	it("returns 400 when body is not JSON", async () => {
		const res = await SELF.fetch("https://example.com/stations", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: "not-json",
		});
		expect(res.status).toBe(400);
	});

	it("returns the requested stations with all latest fuel prices", async () => {
		await insertStation({ id: "S1", trading_name: "ALPHA" });
		await insertStation({ id: "S2", trading_name: "BETA" });
		await insertStation({ id: "S3", trading_name: "GAMMA" });
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1400,
			effective_date: "2026-04-10T00:00:00Z",
		});
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1410,
			effective_date: "2026-04-15T00:00:00Z",
		});
		await insertPrice({
			station_id: "S2",
			fuel_type: "B7Standard",
			price: 1500,
			effective_date: "2026-04-15T00:00:00Z",
		});

		const res = await POST("/stations", {
			station_ids: ["S1", "S2"],
		} satisfies GetStationsRequest);

		expect(res.status).toBe(200);
		const body = (await res.json()) as StationsListResponse;
		const ids = body.results.map((s) => s.info.station_id).sort();
		expect(ids).toEqual(["S1", "S2"]);

		const s1 = body.results.find((s) => s.info.station_id === "S1")!;
		expect(s1.latest_fuel_prices.E10).toEqual({
			price: 141,
			effective_date: "2026-04-15T00:00:00Z",
		});
	});

	it("returns an empty list when no station ids match", async () => {
		await insertStation({ id: "S1" });
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1400,
			effective_date: "2026-04-15T00:00:00Z",
		});

		const res = await POST("/stations", {
			station_ids: ["DOES_NOT_EXIST"],
		} satisfies GetStationsRequest);

		const body = (await res.json()) as StationsListResponse;
		expect(body.results).toEqual([]);
	});
});

describe("POST /price_history", () => {
	it("returns 400 when body is not JSON", async () => {
		const res = await SELF.fetch("https://example.com/price_history", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: "{",
		});
		expect(res.status).toBe(400);
	});

	it("returns samples within the requested window in ascending order", async () => {
		await insertStation({ id: "S1" });

		const now = Date.now();
		const day = 24 * 60 * 60 * 1000;
		const recent = new Date(now - 2 * day).toISOString().replace(/\.\d{3}Z$/, "Z");
		const middle = new Date(now - 5 * day).toISOString().replace(/\.\d{3}Z$/, "Z");
		const old = new Date(now - 100 * day).toISOString().replace(/\.\d{3}Z$/, "Z");

		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1500,
			effective_date: middle,
		});
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 1450,
			effective_date: recent,
		});
		await insertPrice({
			station_id: "S1",
			fuel_type: "E10",
			price: 9999,
			effective_date: old,
		});

		const res = await POST("/price_history", {
			station_id: "S1",
			interval: "last_7_days",
			fuel_type: "E10",
		} satisfies PriceHistoryRequest);

		expect(res.status).toBe(200);
		const body = (await res.json()) as PriceHistoryResponse;
		expect(body.samples).toEqual([
			{ price: 150.0, effective_date: middle },
			{ price: 145.0, effective_date: recent },
		]);
	});

	it("ignores samples for other fuel types", async () => {
		await insertStation({ id: "S1" });
		const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
		await insertPrice({
			station_id: "S1",
			fuel_type: "B7Standard",
			price: 1500,
			effective_date: date,
		});

		const res = await POST("/price_history", {
			station_id: "S1",
			interval: "last_30_days",
			fuel_type: "E10",
		} satisfies PriceHistoryRequest);

		const body = (await res.json()) as PriceHistoryResponse;
		expect(body.samples).toEqual([]);
	});
});

describe("unknown routes", () => {
	it("returns 404 for unknown paths", async () => {
		const res = await SELF.fetch("https://example.com/no-such-route");
		expect(res.status).toBe(404);
	});
});
