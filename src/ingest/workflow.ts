import {env, WorkflowEntrypoint, WorkflowEvent, WorkflowStep} from 'cloudflare:workers';
import {fetchPFSBearerToken, fetchPFSFuelPrices, fetchPFSInformation} from '../fuelfinder/fetch';
import {cellToParent, latLngToCell} from 'h3-js';
import {DayHours} from '../fuelfinder/types';
import {DaySchedule, OpeningHours} from '../api/types';

type StepParams = {
	batchNumber: number,
	incrementalFrom: string | null,
	parentInstanceId: string,
	parentType: 'orchestrator' | 'info' | 'prices',
}

export class OrchestratorWorkflow extends WorkflowEntrypoint<Env, {}> {
	async run(event: WorkflowEvent<{}>, step: WorkflowStep) {
		await step.do('dispatch information stage', async () => {
			const lastSyncDate = await env.fuelify_ingest.get('last_sync_date');

			await env.INFORMATION_STEP.create({
				params: {
					batchNumber: 1,
					incrementalFrom: lastSyncDate,
					parentInstanceId: event.instanceId,
					parentType: 'orchestrator',
				}
			});
		});

		await waitForChildren(step);
	}
}

abstract class StepWorkflow extends WorkflowEntrypoint<Env, StepParams> {
	async run(event: WorkflowEvent<StepParams>, step: WorkflowStep) {
		try {
			await this.run0(event, step);
		} finally {
			// each workflow waits for an event sent from its child to finish
			// we need to ensure that this event is always sent so we don't time out

			let parentWorkflowBinding: Workflow<Readonly<StepParams>>;
			switch (event.payload.parentType) {
				case 'orchestrator':
					parentWorkflowBinding = env.INGESTION_ORCHESTRATOR;
					break;
				case 'info':
					parentWorkflowBinding = env.INFORMATION_STEP;
					break;
				case 'prices':
					parentWorkflowBinding = env.FUEL_PRICES_STEP;
					break;
			}
			const parentWorkflow = await parentWorkflowBinding.get(event.payload.parentInstanceId);
			await parentWorkflow.sendEvent({
				type: 'children-complete',
				payload: {},
			})
		}
	}

	abstract run0(event: Readonly<WorkflowEvent<StepParams>>, step: WorkflowStep): Promise<unknown>;
}

export class InformationStepWorkflow extends StepWorkflow {
	async run0(event: WorkflowEvent<StepParams>, step: WorkflowStep) {
		// get the data from the Fuel Finder API.
		const infoData = await step.do(
			'get batch from gov.uk',
			{ retries: { limit: 3, delay: '10 seconds', backoff: 'linear' } },
			async () => {
				const token = await getOrFetchToken();
				return await fetchPFSInformation(token, event.payload.batchNumber, event.payload.incrementalFrom);
			}
		);

		// if there are no more batches, we begin the next phase: fetching the prices
		// the reason we can't do information and prices concurrently is because
		// price rows hold a foreign key reference to the stations table.
		if (infoData === 'no_more_batches') {
			await step.do('dispatch prices stage', async () => {
				await env.FUEL_PRICES_STEP.create({
					params: {
						batchNumber: 1,
						incrementalFrom: event.payload.incrementalFrom,
						parentInstanceId: event.instanceId,
						parentType: 'info',
					}
				});
			});

			await waitForChildren(step);

			return;
		}

		// process and submit this information to the database
		await step.do('store information', async () => {
			const statement = env.DB.prepare(`
				INSERT INTO stations (id, phone_number, trading_name, brand_name, trading_as_brand,
				                      temporary_closure, permanent_closure, motorway, supermarket,
				                      address_line_1, address_line_2, city, country, county, postcode,
				                      latitude, longitude, amenities, opening_hours, h3_index_r6, h3_index_r3)
				VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9,
				        ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)
				ON CONFLICT (id) DO UPDATE SET phone_number      = EXCLUDED.phone_number,
				                               trading_name      = EXCLUDED.trading_name,
				                               brand_name        = EXCLUDED.brand_name,
				                               trading_as_brand  = EXCLUDED.trading_as_brand,
				                               temporary_closure = EXCLUDED.temporary_closure,
				                               permanent_closure = EXCLUDED.permanent_closure,
				                               motorway          = EXCLUDED.motorway,
				                               supermarket       = EXCLUDED.supermarket,
				                               address_line_1    = EXCLUDED.address_line_1,
				                               address_line_2    = EXCLUDED.address_line_2,
				                               city              = EXCLUDED.city,
				                               country           = EXCLUDED.country,
				                               county            = EXCLUDED.county,
				                               postcode          = EXCLUDED.postcode,
				                               latitude          = EXCLUDED.latitude,
				                               longitude         = EXCLUDED.longitude,
				                               amenities         = EXCLUDED.amenities,
				                               opening_hours     = EXCLUDED.opening_hours,
				                               h3_index_r6       = EXCLUDED.h3_index_r6,
				                               h3_index_r3       = EXCLUDED.h3_index_r3
			`);

			const statements: D1PreparedStatement[] = [];

			for (const station of infoData) {
				const cellR6 = latLngToCell(station.location.latitude, station.location.longitude, 6);
				const cellR3 = cellToParent(cellR6, 3);

				// to prevent requiring extra tables for amenities and opening hours,
				// we submit them to the main table as json strings
				// we do not need to ever select by these properties, so it's okay.
				const amenities = JSON.stringify(station.amenities ?? []);

				const convertHours = (hours: DayHours): DaySchedule => {
					return {
						open: hours.open,
						close: hours.close,
						is_24_hours: hours.is_24_hours,
					}
				};
				const opening_hours = JSON.stringify({
					monday: convertHours(station.opening_times.usual_days.monday),
					tuesday: convertHours(station.opening_times.usual_days.tuesday),
					wednesday: convertHours(station.opening_times.usual_days.wednesday),
					thursday: convertHours(station.opening_times.usual_days.thursday),
					friday: convertHours(station.opening_times.usual_days.friday),
					saturday: convertHours(station.opening_times.usual_days.saturday),
					sunday: convertHours(station.opening_times.usual_days.sunday),
					bank_holiday: {
						open: station.opening_times.bank_holiday.open_time,
						close: station.opening_times.bank_holiday.close_time,
						is_24_hours: station.opening_times.bank_holiday.is_24_hours,
					},
				} satisfies OpeningHours);

				statements.push(
					statement.bind(
						station.node_id,
						station.public_phone_number ?? null,
						station.trading_name.trim().toUpperCase(),
						station.brand_name.trim().toUpperCase(),
						station.is_same_trading_and_brand_name ?? false,
						station.temporary_closure ?? false,
						station.permanent_closure ?? false,
						station.is_motorway_service_station ?? false,
						station.is_supermarket_service_station ?? false,
						station.location.address_line_1?.trim().toUpperCase() ?? '',
						station.location.address_line_2?.trim().toUpperCase() ?? '',
						station.location.city?.trim().toUpperCase() ?? '',
						station.location.country?.trim().toUpperCase() ?? '',
						station.location.county?.trim().toUpperCase() ?? '',
						station.location.postcode?.trim().toUpperCase() ?? '',
						station.location.latitude,
						station.location.longitude,
						amenities,
						opening_hours,
						cellR6,
						cellR3,
					)
				);
			}

			if (statements.length !== 0) {
				await env.DB.batch(statements);
			}
		});

		await step.do('dispatch next step', async () => {
			await env.INFORMATION_STEP.create({
				params: {
					batchNumber: event.payload.batchNumber + 1,
					incrementalFrom: event.payload.incrementalFrom,
					parentInstanceId: event.instanceId,
					parentType: 'info',
				}
			});
		});
	}
}

export class FuelPricesStepWorkflow extends StepWorkflow {
	async run0(event: WorkflowEvent<StepParams>, step: WorkflowStep) {
		const pricesData = await step.do(
			'get batch from gov.uk',
			{ retries: { limit: 3, delay: '10 seconds', backoff: 'linear' } },
			async () => {
				const token = await getOrFetchToken();
				return await fetchPFSFuelPrices(token, event.payload.batchNumber, event.payload.incrementalFrom);
			}
		);

		if (pricesData === 'no_more_batches') {
			await step.do('conclude sync', async () => {
				const now = new Date().toISOString();
				await env.fuelify_ingest.put('last_sync_date', now);

				console.log({ 'type': 'sync_complete', 'timestamp': now });
			});

			return;
		}

		await step.do('store prices', async () => {
			const statement = env.DB.prepare(`
				INSERT INTO fuel_prices (station_id, fuel_type, price, effective_date)
				VALUES (?1, ?2, ?3, ?4)
				ON CONFLICT (station_id, fuel_type, effective_date) DO UPDATE SET price = EXCLUDED.price
				WHERE fuel_prices.price != EXCLUDED.price
			`);

			const statements: D1PreparedStatement[] = [];

			for (const station of pricesData) {
				for (const fuelPrice of station.fuel_prices) {
					const priceTenths = this.normalizePrice(fuelPrice.price);

					statements.push(
						statement.bind(
							station.node_id,
							fuelPrice.fuel_type,
							priceTenths,
							fuelPrice.price_change_effective_timestamp
						)
					);
				}
			}

			if (statements.length !== 0) {
				await env.DB.batch(statements);
			}
		});

		await step.do('dispatch next step', async () => {
			await env.FUEL_PRICES_STEP.create({
				params: {
					batchNumber: event.payload.batchNumber + 1,
					incrementalFrom: event.payload.incrementalFrom,
					parentInstanceId: event.instanceId,
					parentType: 'prices',
				}
			});
		});

		await waitForChildren(step);
	}

	private normalizePrice(price: number): number {
		if (price < 5.0) {
			// In £, not p
			return Math.round(price * 100.0 * 10.0);
		} else if (price > 500.0) {
			// Already in tenths of pence -- just round off any fractional noise
			return Math.round(price);
		} else {
			return Math.round(price * 10.0);
		}
	}
}

async function waitForChildren(step: WorkflowStep) {
	try {
		await step.waitForEvent<{}>('wait for children to complete', {
			type: 'children-complete',
			timeout: '30 minutes',
		});
	} catch (e) {
		console.log({ 'type':'children-wait-timeout' })
	}
}

async function getOrFetchToken(): Promise<string> {
	const cachedToken = await env.fuelify_ingest.get('access_token');
	if (cachedToken) return cachedToken;

	console.log({ type: 'token_fetch_required' });

	const newToken = await fetchPFSBearerToken();
	await env.fuelify_ingest.put(
		'access_token',
		newToken.access_token,
		{ expiration: Math.floor(Date.now() / 1000) + newToken.expires_in - 100 }
	);

	return newToken.access_token;
}


