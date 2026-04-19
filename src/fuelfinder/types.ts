export type PFSInformationResponse = PFSInformation[];
export type PFSFuelPricesResponse = PFSFuelPrices[];

export interface PFSTokenResponse {
	success: boolean;
	data: PFSToken;
	message: string | null;
}

export interface PFSFetchRequestQueryParams {
	'batch-number': number;
	/** ISO 8601 UTC timestamp, e.g. "2024-06-01T12:00:00Z". */
	'effective-start-timestamp'?: string;
}

export interface PFSInformation {
	node_id: string;
	public_phone_number: string | null;
	trading_name: string;
	is_same_trading_and_brand_name: boolean;
	brand_name: string;
	temporary_closure: boolean | null;
	permanent_closure: boolean | null;
	permanent_closure_date: string | null;
	is_motorway_service_station: boolean | null;
	is_supermarket_service_station: boolean | null;
	location: Location;
	amenities: Amenity[];
	opening_times: OpeningTimes;
	fuel_types: FuelType[];
}

export interface Location {
	address_line_1: string | null;
	address_line_2: string | null;
	city: string | null;
	country: string | null;
	county: string | null;
	postcode: string;
	latitude: number;
	longitude: number;
}

// TODO: investigate if there are more amenities
export type Amenity =
	| 'adblue_packaged'
	| 'adblue_pumps'
	| 'car_wash'
	| 'customer_toilets'
	| 'water_filling'
	| 'lpg_pumps';

export interface OpeningTimes {
	usual_days: UsualDays;
	bank_holiday: BankHoliday;
}

export interface UsualDays {
	monday: DayHours;
	tuesday: DayHours;
	wednesday: DayHours;
	thursday: DayHours;
	friday: DayHours;
	saturday: DayHours;
	sunday: DayHours;
}

export interface DayHours {
	open: string;  // HH:MM:SS
	close: string; // HH:MM:SS
	is_24_hours: boolean;
}

export interface BankHoliday {
	type: BankHolidayType;
	open_time: string;  // HH:MM:SS
	close_time: string; // HH:MM:SS
	is_24_hours: boolean;
}

export type BankHolidayType = 'standard' | 'bank holiday';

export type FuelType = 'E5' | 'E10' | 'HVO' | 'B10' | 'B7_STANDARD' | 'B7_PREMIUM';

export interface PFSFuelPrices {
	node_id: string;
	public_phone_number: string | null;
	trading_name: string;
	fuel_prices: FuelPrice[];
}

export interface FuelPrice {
	fuel_type: FuelType;
	/** Price in pence per litre */
	price: number;
	/** ISO 8601 format, e.g. "2024-06-01T12:00:00Z" */
	price_last_updated: string;
	/** ISO 8601 format, e.g. "2024-06-01T12:00:00Z" */
	price_change_effective_timestamp: string;
}

export interface PFSToken {
	access_token: string;
	token_type: string;
	expires_in: number;
	refresh_token: string;
}
