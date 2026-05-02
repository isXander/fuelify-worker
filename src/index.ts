/**
 * Welcome to Cloudflare Workers! This is your first worker.
 *
 * - Run `bun run dev` in your terminal to start a development server
 * - Open a browser tab at http://localhost:8787/ to see your worker in action
 * - Run `bun run deploy` to publish your worker
 *
 * Bind resources to your worker in `wrangler.jsonc`. After adding bindings, a type definition for the
 * `Env` object can be regenerated with `bun run cf-typegen`.
 *
 * Learn more at https://developers.cloudflare.com/workers/
 */
import { onApiFetch } from './api/fetch';
import { onIngestScheduleTemp } from './ingest/schedule';
import { OrchestratorWorkflow, InformationStepWorkflow, FuelPricesStepWorkflow } from './ingest/workflow';
import { scheduledTakeSnapshot } from './statistics/statistics';

export { OrchestratorWorkflow, InformationStepWorkflow, FuelPricesStepWorkflow };

export default {
	fetch: onApiFetch,

	async scheduled(controller, env, ctx) {
		switch (controller.cron) {
			case "*/15 * * * *":
				await onIngestScheduleTemp();
				break;
			case "0 0 * * *":
				await scheduledTakeSnapshot();
				break;
		}
	},
} satisfies ExportedHandler<Env>;
