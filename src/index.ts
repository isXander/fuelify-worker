/**
 * Welcome to Cloudflare Workers! This is your first worker.
 *
 * - Run `npm run dev` in your terminal to start a development server
 * - Open a browser tab at http://localhost:8787/ to see your worker in action
 * - Run `npm run deploy` to publish your worker
 *
 * Bind resources to your worker in `wrangler.jsonc`. After adding bindings, a type definition for the
 * `Env` object can be regenerated with `npm run cf-typegen`.
 *
 * Learn more at https://developers.cloudflare.com/workers/
 */
import { onApiFetch } from './api/fetch';
import { onIngestSchedule } from './ingest/schedule';
import { OrchestratorWorkflow, InformationStepWorkflow, FuelPricesStepWorkflow } from './ingest/workflow';

export { OrchestratorWorkflow, InformationStepWorkflow, FuelPricesStepWorkflow };

export default {
	fetch: onApiFetch,

	async scheduled(controller, env, ctx) {
		switch (controller.cron) {
			case "*/15 * * * *":
				await onIngestSchedule();
				break;
			case "0 0 * * *":
				break;
		}
	},
} satisfies ExportedHandler<Env>;
