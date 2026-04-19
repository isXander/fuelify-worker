// Request types

export interface NearbyStationsRequest {
	fuel_type: FuelType;
	origin: string;
	k_rings: number;
}

export interface GetStationsRequest {
	station_ids: string[];
}

export interface PriceHistoryRequest {
	station_id: string;
	interval: HistoryInterval;
	fuel_type: FuelType;
}

export interface RegionStatisticsRequest {
	fuel_type: FuelType;
	/** List of H3 res6 cells to aggregate as one region. */
	h3_cells: string[];
}

// Response types

export interface StationsListResponse {
	results: Station[];
}

export interface PriceHistoryResponse {
	samples: FuelPriceSample[];
}

export interface RegionStatisticsResponse {
	station_count: number;
	/** Prices in pence per litre. Null if no stations found. */
	min_price: number | null;
	max_price: number | null;
	mean_price: number | null;
}

export interface Station {
	info: StationInfo;
	/** All fuel types available at the station, along with their latest price sample. */
	latest_fuel_prices: Partial<Record<FuelType, FuelPriceSample>>;
}

export interface StationInfo {
	station_id: string;
	phone_number: string;
	trading_name: string;
	brand_name: string;
	trading_as_brand: boolean;
	temporary_closure: boolean;
	permanent_closure: boolean;
	motorway: boolean;
	supermarket: boolean;
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
	amenities: Amenity[];
	opening_hours: OpeningHours;
}

export interface DaySchedule {
	open: string;
	close: string;
	is_24_hours: boolean;
}

export interface OpeningHours {
	monday: DaySchedule;
	tuesday: DaySchedule;
	wednesday: DaySchedule;
	thursday: DaySchedule;
	friday: DaySchedule;
	saturday: DaySchedule;
	sunday: DaySchedule;
	bank_holiday: DaySchedule;
}

export interface FuelPriceSample {
	/** Price in pence per litre. */
	price: number;
	/** ISO 8601 UTC timestamp, e.g. "2026-04-07T13:45:00Z". */
	effective_date: string;
}

export type HistoryInterval =
	| 'last_7_days'
	| 'last_30_days'
	| 'last_90_days'
	| 'last_180_days'
	| 'last_365_days';

export function fuelTypeFromDb(s: string): FuelType | null {
	switch (s) {
		case 'E10':         return 'E10';
		case 'E5':          return 'E5';
		case 'HVO':         return 'HVO';
		case 'B10':         return 'B10';
		case 'B7_STANDARD': return 'B7STANDARD';
		case 'B7_PREMIUM':  return 'B7PREMIUM';
		default:            return null;
	}
}

export function fuelTypeToDb(ft: FuelType): string {
	switch (ft) {
		case 'E10':        return 'E10';
		case 'E5':         return 'E5';
		case 'HVO':        return 'HVO';
		case 'B10':        return 'B10';
		case 'B7STANDARD': return 'B7_STANDARD';
		case 'B7PREMIUM':  return 'B7_PREMIUM';
	}
}

export function historyIntervalDays(interval: HistoryInterval): number {
	switch (interval) {
		case 'last_7_days':
			return 7;
		case 'last_30_days':
			return 30;
		case 'last_90_days':
			return 90;
		case 'last_180_days':
			return 180;
		case 'last_365_days':
			return 365;
	}
}

export type FuelType = 'E10' | 'E5' | 'B7STANDARD' | 'B7PREMIUM' | 'B10' | 'HVO';

export type Amenity =
	| 'adblue_packaged'
	| 'adblue_pumps'
	| 'car_wash'
	| 'customer_toilets'
	| 'water_filling'
	| 'lpg_pumps';

export interface ErrorResponse {
	success: boolean,
	message: string,
}
