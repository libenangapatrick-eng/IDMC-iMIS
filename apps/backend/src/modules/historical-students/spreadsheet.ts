import { inflateRawSync } from "node:zlib";

export type SpreadsheetRow = Record<string, string>;

function decodeXml(value: string): string {
  return value
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&")
    .trim();
}

function parseCsv(text: string): SpreadsheetRow[] {
  const matrix: string[][] = [];
  let row: string[] = [];
  let value = "";
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    const next = text[index + 1];
    if (character === '"' && quoted && next === '"') {
      value += '"';
      index += 1;
    } else if (character === '"') {
      quoted = !quoted;
    } else if (character === "," && !quoted) {
      row.push(value.trim()); value = "";
    } else if ((character === "\n" || character === "\r") && !quoted) {
      if (character === "\r" && next === "\n") index += 1;
      row.push(value.trim()); value = "";
      if (row.some((cell) => cell !== "")) matrix.push(row);
      row = [];
    } else {
      value += character;
    }
  }
  row.push(value.trim());
  if (row.some((cell) => cell !== "")) matrix.push(row);
  return matrixToRows(matrix);
}

function unzipEntry(buffer: Buffer, wantedName: string): Buffer | null {
  let eocd = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 65558); i -= 1) {
    if (buffer.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("Invalid XLSX file: ZIP directory was not found.");
  const entries = buffer.readUInt16LE(eocd + 10);
  let offset = buffer.readUInt32LE(eocd + 16);
  for (let index = 0; index < entries; index += 1) {
    if (buffer.readUInt32LE(offset) !== 0x02014b50) throw new Error("Invalid XLSX central directory.");
    const method = buffer.readUInt16LE(offset + 10);
    const compressedSize = buffer.readUInt32LE(offset + 20);
    const fileNameLength = buffer.readUInt16LE(offset + 28);
    const extraLength = buffer.readUInt16LE(offset + 30);
    const commentLength = buffer.readUInt16LE(offset + 32);
    const localOffset = buffer.readUInt32LE(offset + 42);
    const name = buffer.subarray(offset + 46, offset + 46 + fileNameLength).toString("utf8");
    if (name === wantedName) {
      if (buffer.readUInt32LE(localOffset) !== 0x04034b50) throw new Error("Invalid XLSX local entry.");
      const localNameLength = buffer.readUInt16LE(localOffset + 26);
      const localExtraLength = buffer.readUInt16LE(localOffset + 28);
      const start = localOffset + 30 + localNameLength + localExtraLength;
      const compressed = buffer.subarray(start, start + compressedSize);
      if (method === 0) return Buffer.from(compressed);
      if (method === 8) return inflateRawSync(compressed);
      throw new Error(`Unsupported XLSX compression method ${method}.`);
    }
    offset += 46 + fileNameLength + extraLength + commentLength;
  }
  return null;
}

function columnIndex(reference: string): number {
  const letters = reference.replace(/[^A-Z]/gi, "").toUpperCase();
  let result = 0;
  for (const letter of letters) result = result * 26 + letter.charCodeAt(0) - 64;
  return result - 1;
}

function matrixToRows(matrix: string[][]): SpreadsheetRow[] {
  if (!matrix.length) return [];
  const headers = matrix[0]!.map((value) => value.trim());
  if (headers.some((header) => !header)) throw new Error("Every spreadsheet column must have a header.");
  return matrix.slice(1).filter((row) => row.some(Boolean)).map((row) =>
    Object.fromEntries(headers.map((header, index) => [header, String(row[index] ?? "").trim()]))
  );
}

function parseXlsx(buffer: Buffer): SpreadsheetRow[] {
  const sharedXml = unzipEntry(buffer, "xl/sharedStrings.xml")?.toString("utf8") ?? "";
  const sharedStrings = [...sharedXml.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)].map((match) =>
    decodeXml([...match[1]!.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map((part) => part[1]).join(""))
  );
  const workbookXml = unzipEntry(buffer, "xl/workbook.xml")?.toString("utf8") ?? "";
  const firstSheet = workbookXml.match(/<sheet\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"/);
  if (!firstSheet) throw new Error("XLSX workbook has no worksheet.");
  const relationships = unzipEntry(buffer, "xl/_rels/workbook.xml.rels")?.toString("utf8") ?? "";
  const relationship = [...relationships.matchAll(/<Relationship\b([^>]*)\/?\s*>/g)].find((match) =>
    new RegExp(`Id="${firstSheet[2]}"`).test(match[1]!)
  );
  const target = relationship?.[1]?.match(/Target="([^"]+)"/)?.[1] ?? "worksheets/sheet1.xml";
  const sheetPath = target.startsWith("/") ? target.slice(1) : `xl/${target.replace(/^\.\//, "")}`;
  const sheetXml = unzipEntry(buffer, sheetPath)?.toString("utf8");
  if (!sheetXml) throw new Error("The first XLSX worksheet could not be read.");
  const matrix: string[][] = [];
  for (const rowMatch of sheetXml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
    const row: string[] = [];
    for (const cellMatch of rowMatch[1]!.matchAll(/<c\b([^>]*)>([\s\S]*?)<\/c>/g)) {
      const attrs = cellMatch[1]!;
      const body = cellMatch[2]!;
      const reference = attrs.match(/\br="([A-Z]+\d+)"/)?.[1] ?? `A${matrix.length + 1}`;
      const type = attrs.match(/\bt="([^"]+)"/)?.[1] ?? "n";
      let cellValue = body.match(/<v>([\s\S]*?)<\/v>/)?.[1] ?? "";
      if (type === "s") cellValue = sharedStrings[Number(cellValue)] ?? "";
      if (type === "inlineStr") cellValue = [...body.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map((m) => m[1]).join("");
      row[columnIndex(reference)] = decodeXml(cellValue);
    }
    matrix.push(row);
  }
  return matrixToRows(matrix);
}

export function parseSpreadsheet(fileName: string, fileBase64: string): SpreadsheetRow[] {
  const safeName = String(fileName || "").toLowerCase();
  const buffer = Buffer.from(String(fileBase64 || "").replace(/^data:[^,]+,/, ""), "base64");
  if (!buffer.length) throw new Error("The uploaded file is empty.");
  if (buffer.length > 8 * 1024 * 1024) throw new Error("The import file exceeds the 8 MB limit.");
  if (safeName.endsWith(".csv")) return parseCsv(buffer.toString("utf8").replace(/^\uFEFF/, ""));
  if (safeName.endsWith(".xlsx")) return parseXlsx(buffer);
  throw new Error("Only .csv and .xlsx historical import files are accepted.");
}
