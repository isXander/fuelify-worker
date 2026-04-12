import { env } from 'cloudflare:workers';

export async function onIngestSchedule() {
	const workflow = await env.INGESTION_ORCHESTRATOR.get("only-orchestrator").catch(() => null);

	if (workflow) {
		const status = await workflow.status();
		if (['running', 'queued'].includes(status.status)) {
			console.log({ "type": "workflow_already_ongoing", "status": status.status });
			return;
		}

		await workflow.restart();
	} else {
		await env.INGESTION_ORCHESTRATOR.create({
			id: "only-orchestrator",
			params: {}
		});
	}
}
