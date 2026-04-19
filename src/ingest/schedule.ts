import { env } from 'cloudflare:workers';

export async function onIngestSchedule() {
	const workflow = await env.INGESTION_ORCHESTRATOR.get("only-orchestrator").catch(() => null);

	if (workflow) {
		const status = await workflow.status();
		const ongoingStatuses = ['running', 'queued', 'waiting', 'waitingForPause', 'paused'];
		const restartableStatuses = ['complete', 'errored', 'terminated'];

		if (ongoingStatuses.includes(status.status)) {
			console.log({ "type": "workflow_already_ongoing", "status": status.status });
			return;
		}

		if (restartableStatuses.includes(status.status)) {
			await workflow.restart();
			return;
		}

		console.log({ "type": "workflow_status_not_restartable", "status": status.status });
		return;
	} else {
		await env.INGESTION_ORCHESTRATOR.create({
			id: "only-orchestrator",
			params: {}
		});
	}
}
