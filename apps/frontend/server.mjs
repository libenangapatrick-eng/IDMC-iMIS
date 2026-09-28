import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, normalize, resolve, sep } from "node:path";
import { pipeline } from "node:stream";
import { createGzip } from "node:zlib";

const args = process.argv.slice(2);

function argument(name, fallback) {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
}

const root = resolve(argument("--root", process.cwd()));
const host = argument("--host", "127.0.0.1");
const port = Number(argument("--port", "5500"));

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("Frontend port must be a number from 1 to 65535.");
}

const contentTypes = {
  ".css": "text/css; charset=utf-8",
  ".gif": "image/gif",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".jpeg": "image/jpeg",
  ".jpg": "image/jpeg",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml; charset=utf-8",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

const compressible = new Set([".css", ".html", ".js", ".json", ".mjs", ".svg"]);

function sendText(response, status, body) {
  response.writeHead(status, {
    "Content-Type": "text/plain; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(body);
}

function resolveRequestPath(rawUrl) {
  const pathname = decodeURIComponent(new URL(rawUrl, `http://${host}:${port}`).pathname);

  // /login and /login/ are first-class routes, not redirect placeholder pages.
  if (pathname === "/" || pathname === "/login" || pathname === "/login/") {
    return join(root, "login.html");
  }

  let relative = pathname.replace(/^\/+/, "");
  let candidate = resolve(root, normalize(relative));

  if (candidate !== root && !candidate.startsWith(`${root}${sep}`)) return null;

  if (existsSync(candidate) && statSync(candidate).isDirectory()) {
    candidate = join(candidate, "index.html");
  } else if (!existsSync(candidate) && !extname(candidate)) {
    const htmlCandidate = `${candidate}.html`;
    if (existsSync(htmlCandidate)) candidate = htmlCandidate;
  }

  return candidate;
}

const server = createServer((request, response) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    sendText(response, 405, "Method Not Allowed");
    return;
  }

  let filePath;
  try {
    filePath = resolveRequestPath(request.url || "/");
  } catch {
    sendText(response, 400, "Bad Request");
    return;
  }

  if (!filePath || !existsSync(filePath) || !statSync(filePath).isFile()) {
    sendText(response, 404, "Not Found");
    return;
  }

  const fileStat = statSync(filePath);
  const extension = extname(filePath).toLowerCase();
  const etag = `W/\"${fileStat.size.toString(16)}-${Math.trunc(fileStat.mtimeMs).toString(16)}\"`;
  const cacheControl = filePath.endsWith(".html")
    ? "no-cache"
    : "public, max-age=3600, stale-while-revalidate=86400";

  if (request.headers["if-none-match"] === etag) {
    response.writeHead(304, { ETag: etag, "Cache-Control": cacheControl });
    response.end();
    return;
  }

  const useGzip = fileStat.size >= 1024
    && compressible.has(extension)
    && /(?:^|,)\s*gzip\s*(?:,|$)/i.test(String(request.headers["accept-encoding"] || ""));

  response.writeHead(200, {
    "Content-Type": contentTypes[extension] || "application/octet-stream",
    "Cache-Control": cacheControl,
    "ETag": etag,
    ...(useGzip ? { "Content-Encoding": "gzip", "Vary": "Accept-Encoding" } : { "Content-Length": String(fileStat.size) }),
    "X-Content-Type-Options": "nosniff",
  });

  if (request.method === "HEAD") {
    response.end();
    return;
  }

  const source = createReadStream(filePath);
  pipeline(source, ...(useGzip ? [createGzip({ level: 6 })] : []), response, error => {
    if (error && !response.destroyed) response.destroy(error);
  });
});

server.on("error", (error) => {
  console.error(`Frontend failed to start on http://${host}:${port}`);
  console.error(error);
  process.exitCode = 1;
});

server.listen(port, host, () => {
  console.log(`IDMC frontend running at http://${host}:${port}/login/`);
});
