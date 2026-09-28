/*
 * Cloudflare Workers entry point.
 *
 * Cloudflare runs a Worker's top-level code once at deploy time (validation,
 * error 10021) WITHOUT any secrets/vars. config/env.ts parses process.env at
 * import time, so importing the Express app statically made every deploy fail
 * with a ZodError. The app is therefore imported lazily, on the first request,
 * when the Worker's runtime variables and secrets are available.
 */
import { httpServerHandler } from "cloudflare:node";

const INTERNAL_PORT = 8080;

type FetchHandler = {
  fetch: (request: Request, env: unknown, ctx: unknown) => Promise<Response> | Response;
};

let handlerPromise: Promise<FetchHandler> | undefined;

function loadHandler(): Promise<FetchHandler> {
  if (!handlerPromise) {
    handlerPromise = import("./app.js").then(({ default: app }) => {
      app.listen(INTERNAL_PORT);
      return httpServerHandler({ port: INTERNAL_PORT }) as unknown as FetchHandler;
    });
    // Allow a retry on the next request if configuration was wrong.
    handlerPromise.catch(() => {
      handlerPromise = undefined;
    });
  }
  return handlerPromise;
}

export default {
  async fetch(request: Request, env: unknown, ctx: unknown): Promise<Response> {
    try {
      const handler = await loadHandler();
      return await handler.fetch(request, env, ctx);
    } catch (error) {
      console.error("Worker startup/request failure:", error);
      const message =
        error instanceof Error && error.name === "ZodError"
          ? "Server configuration is incomplete. Check the Worker's Variables and Secrets."
          : "Internal server error.";
      return new Response(JSON.stringify({ success: false, message }), {
        status: 500,
        headers: { "content-type": "application/json" },
      });
    }
  },
};