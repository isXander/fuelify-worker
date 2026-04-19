import { env } from "cloudflare:test";
import { latLngToCell, cellToParent } from "h3-js";
import type { Amenity, OpeningHours } from "../src/api/types";

export const LONDON_LAT = 51.5;
export const LONDON_LNG = -0.1;

export const LONDON_R6 = latLngToCell(LONDON_LAT, LONDON_LNG, 6);
export const LONDON_R3 = cellToParent(LONDON_R6, 3);

// A different region (Manchester) for negative-result assertions.
export const MANCHESTER_R6 = latLngToCell(53.48, -2.24, 6);
export const MANCHESTER_R3 = cellToParent(MANCHESTER_R6, 3);

export const DEFAULT_OPENING_HOURS: OpeningHours = {
	monday: { open: "00:00:00", close: "00:00:00", is_24_hours: true },
	tuesday: { open: "00:00:00", close: "00:00:00", is_24_hours: true },
	wednesday: { open: "00:00:00", close: "00:00:00", is_24_hours: true },
	thursday: { open: "00:00:00", close: "00:00:00", is_24_hours: true },
	friday: { open: "00:00:00", close: "00:00:00", is_24_hours: true },
	saturday: { open: "00:00:00", close: "00:00:00", is_24_hours: true },
	sunday: { open: "00:00:00", close: "00:00:00", is_24_hours: true },
	bank_holiday: { open: "00:00:00", close: "00:00:00", is_24_hours: true },
};

export interface SeedStation {
	id: string;
	trading_name?: string;
	brand_name?: string;
	temporary_closure?: boolean;
	permanent_closure?: boolean;
	motorway?: boolean;
	supermarket?: boolean;
	latitude?: number;
	longitude?: number;
	h3_index_r6?: string;
	h3_index_r3?: string;
	amenities?: Amenity[];
	opening_hours?: OpeningHours;
	postcode?: string;
}

export async function resetDatabase(): Promise<void> {
	await env.DB.batch([
		env.DB.prepare("DELETE FROM fuel_prices"),
		env.DB.prepare("DELETE FROM stations"),
		env.DB.prepare("DELETE FROM regional_statistics"),
	]);
}

export async function insertStation(s: SeedStation): Promise<void> {
	const lat = s.latitude ?? LONDON_LAT;
	const lng = s.longitude ?? LONDON_LNG;
	const r6 = s.h3_index_r6 ?? latLngToCell(lat, lng, 6);
	const r3 = s.h3_index_r3 ?? cellToParent(r6, 3);

	await env.DB.prepare(
		`INSERT INTO stations (
			id, phone_number, trading_name, brand_name, trading_as_brand,
			temporary_closure, permanent_closure, motorway, supermarket,
			address_line_1, address_line_2, city, country, county, postcode,
			latitude, longitude, h3_index_r6, h3_index_r3, amenities, opening_hours
		) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)`,
	)
		.bind(
			s.id,
			"01234567890",
			s.trading_name ?? "TEST STATION",
			s.brand_name ?? "TEST BRAND",
			0,
			s.temporary_closure ? 1 : 0,
			s.permanent_closure ? 1 : 0,
			s.motorway ? 1 : 0,
			s.supermarket ? 1 : 0,
			"1 TEST STREET",
			"",
			"LONDON",
			"UK",
			"GREATER LONDON",
			s.postcode ?? "SW1A 1AA",
			lat,
			lng,
			r6,
			r3,
			JSON.stringify(s.amenities ?? []),
			JSON.stringify(s.opening_hours ?? DEFAULT_OPENING_HOURS),
		)
		.run();
}

export interface SeedPrice {
	station_id: string;
	/** Database fuel type (e.g. "B7Standard"). */
	fuel_type: string;
	/** Price in tenths of pence. */
	price: number;
	effective_date: string;
}

export async function insertPrice(p: SeedPrice): Promise<void> {
	await env.DB.prepare(
		`INSERT INTO fuel_prices (station_id, fuel_type, price, effective_date)
		 VALUES (?1, ?2, ?3, ?4)`,
	)
		.bind(p.station_id, p.fuel_type, p.price, p.effective_date)
		.run();
}
