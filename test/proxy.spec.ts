import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { proxyFetch, XFuelifySecret } from "../src/fuelfinder/proxy";

const FAKE_ENV = {
	PROXY_SECRET: "test-secret",
} as unknown as Env;

describe("proxyFetch", () => {
	let fetchSpy: ReturnType<typeof vi.spyOn>;

	beforeEach(() => {
		fetchSpy = vi.spyOn(globalThis, "fetch") as unknown as ReturnType<
			typeof vi.spyOn
		>;
	});

	afterEach(() => {
		fetchSpy.mockRestore();
	});

	it("returns 403 when the secret header is missing", async () => {
		fetchSpy.mockResolvedValue(new Response("should-not-be-called"));
		const req = new Request("https://worker.test/fuel-finder-proxy/foo");
		const res = await proxyFetch(req, "/foo", FAKE_ENV);
		expect(res.status).toBe(403);
		expect(await res.text()).toContain("secret mismatch");
		expect(fetchSpy).not.toHaveBeenCalled();
	});

	it("returns 403 when the secret header is wrong", async () => {
		fetchSpy.mockResolvedValue(new Response("should-not-be-called"));
		const req = new Request("https://worker.test/fuel-finder-proxy/foo", {
			headers: { [XFuelifySecret]: "wrong" },
		});
		const res = await proxyFetch(req, "/foo", FAKE_ENV);
		expect(res.status).toBe(403);
		expect(fetchSpy).not.toHaveBeenCalled();
	});

	it("forwards GET requests to the upstream Fuel Finder API with query string", async () => {
		fetchSpy.mockResolvedValue(new Response("ok"));

		const req = new Request(
			"https://worker.test/fuel-finder-proxy/pfs?batch-number=2",
			{
				method: "GET",
				headers: { [XFuelifySecret]: "test-secret" },
			},
		);

		const res = await proxyFetch(req, "/pfs", FAKE_ENV);
		expect(res.status).toBe(200);
		expect(fetchSpy).toHaveBeenCalledOnce();

		const upstreamReq = fetchSpy.mock.calls[0][0] as Request;
		expect(upstreamReq.url).toBe(
			"https://www.fuel-finder.service.gov.uk/api/v1/pfs?batch-number=2",
		);
		expect(upstreamReq.method).toBe("GET");
	});

	it("forwards POST request bodies", async () => {
		fetchSpy.mockResolvedValue(new Response("ok"));

		const req = new Request("https://worker.test/fuel-finder-proxy/oauth", {
			method: "POST",
			headers: {
				[XFuelifySecret]: "test-secret",
				"Content-Type": "application/json",
			},
			body: JSON.stringify({ a: 1 }),
		});

		await proxyFetch(req, "/oauth", FAKE_ENV);

		const upstreamReq = fetchSpy.mock.calls[0][0] as Request;
		expect(upstreamReq.method).toBe("POST");
		expect(upstreamReq.url).toBe(
			"https://www.fuel-finder.service.gov.uk/api/v1/oauth",
		);
		expect(await upstreamReq.text()).toBe('{"a":1}');
	});
});
