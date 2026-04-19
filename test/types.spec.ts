import { describe, it, expect } from "vitest";
import {
	fuelTypeFromDb,
	fuelTypeToDb,
	historyIntervalDays,
	type FuelType,
	type HistoryInterval,
} from "../src/api/types";

describe("fuelTypeFromDb", () => {
	const cases: [string, FuelType][] = [
		["E10", "E10"],
		["E5", "E5"],
		["HVO", "HVO"],
		["B10", "B10"],
		["B7Standard", "B7STANDARD"],
		["B7Premium", "B7PREMIUM"],
	];

	it.each(cases)("maps %s to %s", (input, expected) => {
		expect(fuelTypeFromDb(input)).toBe(expected);
	});

	it("returns null for unknown values", () => {
		expect(fuelTypeFromDb("DIESEL")).toBeNull();
		expect(fuelTypeFromDb("")).toBeNull();
		expect(fuelTypeFromDb("b7_standard")).toBeNull();
	});
});

describe("fuelTypeToDb", () => {
	const cases: [FuelType, string][] = [
		["E10", "E10"],
		["E5", "E5"],
		["HVO", "HVO"],
		["B10", "B10"],
		["B7STANDARD", "B7Standard"],
		["B7PREMIUM", "B7Premium"],
	];

	it.each(cases)("maps %s to %s", (input, expected) => {
		expect(fuelTypeToDb(input)).toBe(expected);
	});

	it("round-trips through fuelTypeFromDb", () => {
		const apiTypes: FuelType[] = [
			"E10",
			"E5",
			"HVO",
			"B10",
			"B7STANDARD",
			"B7PREMIUM",
		];
		for (const api of apiTypes) {
			expect(fuelTypeFromDb(fuelTypeToDb(api))).toBe(api);
		}
	});
});

describe("historyIntervalDays", () => {
	const cases: [HistoryInterval, number][] = [
		["last_7_days", 7],
		["last_30_days", 30],
		["last_90_days", 90],
		["last_180_days", 180],
		["last_365_days", 365],
	];

	it.each(cases)("%s -> %d", (interval, days) => {
		expect(historyIntervalDays(interval)).toBe(days);
	});
});
