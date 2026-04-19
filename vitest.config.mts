import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	defineWorkersConfig,
	readD1Migrations,
} from "@cloudflare/vitest-pool-workers/config";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineWorkersConfig(async () => {
	const migrationsPath = path.join(__dirname, "migrations");
	const migrations = await readD1Migrations(migrationsPath);

	return {
		test: {
			setupFiles: ["./test/apply-migrations.ts"],
			poolOptions: {
				workers: {
					singleWorker: true,
					wrangler: { configPath: "./wrangler.jsonc" },
					miniflare: {
						bindings: {
							TEST_MIGRATIONS: migrations,
							PROXY_URL: "https://proxy.test",
							PROXY_SECRET: "test-secret",
							GOVUK_CLIENT_ID: "test-client-id",
							GOVUK_CLIENT_SECRET: "test-client-secret",
							FCM_SERVICE_ACCOUNT: "{}",
						},
					},
				},
			},
		},
	};
});
