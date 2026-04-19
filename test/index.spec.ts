import { SELF, env, createScheduledController } from "cloudflare:test";
import { describe, it, expect, vi, beforeEach } from "vitest";
import worker from "../src/index";
import { resetDatabase } from "./helpers";

beforeEach(async () => {
	await resetDatabase();
});

describe("worker entrypoint", () => {
	it("delegates fetch to the API router", async () => {
		const res = await SELF.fetch("https://example.com/no-such-route");
		expect(res.status).toBe(404);
	});

	it("ignores cron triggers that don't match either schedule", async () => {
		const ctx = new (class {
			waitUntil() {}
			passThroughOnException() {}
			props = {};
		})() as unknown as ExecutionContext;

		const controller = createScheduledController({
			cron: "* * * * *",
			scheduledTime: Date.now(),
		});

		await expect(
			worker.scheduled!(controller, env, ctx),
		).resolves.toBeUndefined();
	});

	it("runs the snapshot job when the daily cron fires", async () => {
		const ctx = new (class {
			waitUntil() {}
			passThroughOnException() {}
			props = {};
		})() as unknown as ExecutionContext;

		const controller = createScheduledController({
			cron: "0 0 * * *",
			scheduledTime: Date.now(),
		});

		// No stations seeded → snapshot inserts nothing, but should not throw.
		await worker.scheduled!(controller, env, ctx);

		const { results } = await env.DB.prepare(
			`SELECT COUNT(*) AS n FROM regional_statistics`,
		).all<{ n: number }>();
		expect(results[0].n).toBe(0);
	});
});

// Avoid an unused-warning for the imported helper.
void vi;
