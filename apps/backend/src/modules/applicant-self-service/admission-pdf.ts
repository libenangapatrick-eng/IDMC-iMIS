type DocumentKind = "ACKNOWLEDGEMENT" | "JOINING_INSTRUCTIONS";

export type AdmissionPdfInput = {
  kind: DocumentKind;
  applicantName: string;
  applicantNumber: string;
  applicationNumber: string;
  programmeName: string;
  academicYear: string;
  indexNumber: string;
  generatedAt?: Date;
};

type PdfLine = { text: string; bold?: boolean; size?: number; gapBefore?: number; maroon?: boolean };

function ascii(input: unknown): string {
  return String(input ?? "").normalize("NFKD").replace(/[^\x20-\x7E]/g, "").replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)");
}

function wrap(text: string, width = 92): string[] {
  const words = String(text).trim().split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let line = "";
  for (const word of words) {
    if (!line) { line = word; continue; }
    if (`${line} ${word}`.length <= width) line += ` ${word}`;
    else { lines.push(line); line = word; }
  }
  if (line) lines.push(line);
  return lines.length ? lines : [""];
}

function section(title: string, paragraphs: string[]): PdfLine[] {
  const result: PdfLine[] = [{ text: title, bold: true, size: 12, gapBefore: 10, maroon: true }];
  for (const paragraph of paragraphs) {
    for (const line of wrap(paragraph)) result.push({ text: line, size: 9.5 });
    result.push({ text: "", size: 5 });
  }
  return result;
}

function documentLines(input: AdmissionPdfInput): PdfLine[] {
  const identity: PdfLine[] = [
    { text: input.kind === "JOINING_INSTRUCTIONS" ? "JOINING INSTRUCTIONS AND ADMISSION GUIDELINES" : "ONLINE APPLICATION ACKNOWLEDGEMENT", bold: true, size: 16, maroon: true },
    { text: `ACADEMIC YEAR ${input.academicYear}`, bold: true, size: 12 },
    { text: "", size: 5 },
    { text: `Applicant: ${input.applicantName}`, bold: true, size: 10 },
    { text: `Applicant Number: ${input.applicantNumber}`, size: 10 },
    { text: `Application Number: ${input.applicationNumber}`, size: 10 },
    { text: `NECTA / Examination Index: ${input.indexNumber || "Not supplied"}`, size: 10 },
    { text: `Programme: ${input.programmeName || "Pending programme confirmation"}`, size: 10 },
  ];

  if (input.kind === "ACKNOWLEDGEMENT") {
    return identity.concat(
      section("1. APPLICATION RECEIVED", ["Thank you for applying to the Institute of Development and Medical Sciences (IDMC). Your online application has been received and will be reviewed by the Admissions Office.", "This acknowledgement is not an admission offer. Keep the application number above when communicating with the Institute."]),
      section("2. VERIFICATION", ["Academic qualifications, examination index details, uploaded certificates and programme eligibility will be verified. The Admissions Office may request corrections through the applicant portal."]),
      section("3. APPLICATION STATUS", ["Sign in to the applicant portal to follow the status of your application. Joining instructions become available only after the application is selected or converted to a student record."]),
      section("4. IMPORTANT NOTICE", ["Do not pay cash to an individual. Official payments must use an institutional invoice or control number displayed in the authorised portal."])
    );
  }

  return identity.concat(
    section("1. INTRODUCTION AND WELCOME", ["Congratulations and welcome to the Institute of Development and Medical Sciences (IDMC). Read these joining instructions carefully and retain a copy for registration."]),
    section("2. REPORTING AND REGISTRATION", ["The Admissions Office will publish the official reporting date, orientation timetable, lecture commencement date and registration deadline in the applicant or student portal. Report within the stated period or request written permission before the deadline."]),
    section("3. MANDATORY REGISTRATION REQUIREMENTS", ["Present original academic certificates and certified copies, a birth certificate or NIDA card/passport, recent passport photographs, a completed medical examination form and official payment evidence."]),
    section("4. FINANCIAL REQUIREMENTS", ["Annual tuition fee: TZS 650,000. The Institute may permit payment by approved instalments. Any registration, examination, identity-card, health-insurance, student-union or accommodation charges must appear on an official invoice before payment.", "Payments must use the official institutional control number or another authorised payment channel shown in the portal. Cash payment to an individual is prohibited."]),
    section("5. ACCOMMODATION", ["Hostel places are limited and allocated according to the approved institutional procedure. Students without a hostel place should use accommodation verified by the Student Welfare Office."]),
    section("6. MEDICAL EXAMINATION", ["A registered medical practitioner should confirm general fitness, visual acuity, hearing, blood group, relevant test results and any chronic illness or disability requiring institutional support.", "Medical Officer: ______________________________  Signature/Stamp: __________________  Date: ____________"]),
    section("7. STUDENT DECLARATION", ["I confirm that I have read these instructions and agree to comply with academic, financial and conduct requirements of IDMC.", "Student Name: ______________________________  Signature: __________________  Date: ____________", "Parent/Guardian: ___________________________  Phone: _____________________  Signature: ____________"]),
    section("8. FINAL NOTICE", ["This document must be read together with the formal admission decision and the latest notices in the IDMC portal. Where information differs, a later authorised notice issued by the Institute takes precedence."])
  );
}

function pageStream(lines: PdfLine[], pageNumber: number, pageCount: number): string {
  const commands: string[] = [
    "q", "0.408 0.09 0.165 rg", "0 785 595 57 re f", "Q",
    "BT", "/F2 14 Tf", "1 1 1 rg", "38 817 Td", `(INSTITUTE OF DEVELOPMENT AND MEDICAL SCIENCES) Tj`, "ET",
    "BT", "/F1 9 Tf", "1 1 1 rg", "38 800 Td", `(IDMC - INTEGRATED MANAGEMENT INFORMATION SYSTEM) Tj`, "ET"
  ];
  let y = 760;
  for (const item of lines) {
    y -= item.gapBefore ?? 0;
    const size = item.size ?? 9.5;
    if (!item.text) { y -= Math.max(4, size); continue; }
    commands.push("BT", `/${item.bold ? "F2" : "F1"} ${size} Tf`, item.maroon ? "0.408 0.09 0.165 rg" : "0.12 0.10 0.11 rg", `42 ${y.toFixed(1)} Td`, `(${ascii(item.text)}) Tj`, "ET");
    y -= size + 4;
  }
  commands.push("0.75 0.72 0.73 RG", "42 35 m 553 35 l S", "BT", "/F1 8 Tf", "0.35 0.32 0.33 rg", "42 20 Td", `(Generated by IDMC iMIS - Page ${pageNumber} of ${pageCount}) Tj`, "ET");
  return commands.join("\n");
}

function paginate(lines: PdfLine[]): PdfLine[][] {
  const pages: PdfLine[][] = [];
  let page: PdfLine[] = [];
  let used = 0;
  for (const line of lines) {
    const height = (line.size ?? 9.5) + 4 + (line.gapBefore ?? 0);
    if (page.length && used + height > 700) { pages.push(page); page = []; used = 0; }
    page.push(line); used += height;
  }
  if (page.length) pages.push(page);
  return pages;
}

export function buildAdmissionPdf(input: AdmissionPdfInput): Buffer {
  const pages = paginate(documentLines(input));
  const objects: string[] = [];
  const add = (body: string) => { objects.push(body); return objects.length; };
  const catalogId = add("");
  const pagesId = add("");
  const regularFontId = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");
  const boldFontId = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>");
  const pageIds: number[] = [];
  pages.forEach((lines, index) => {
    const stream = pageStream(lines, index + 1, pages.length);
    const contentId = add(`<< /Length ${Buffer.byteLength(stream, "latin1")} >>\nstream\n${stream}\nendstream`);
    const pageId = add(`<< /Type /Page /Parent ${pagesId} 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 ${regularFontId} 0 R /F2 ${boldFontId} 0 R >> >> /Contents ${contentId} 0 R >>`);
    pageIds.push(pageId);
  });
  objects[catalogId - 1] = `<< /Type /Catalog /Pages ${pagesId} 0 R >>`;
  objects[pagesId - 1] = `<< /Type /Pages /Kids [${pageIds.map(id => `${id} 0 R`).join(" ")}] /Count ${pageIds.length} >>`;

  let pdf = "%PDF-1.4\n%IDMC\n";
  const offsets: number[] = [0];
  objects.forEach((body, index) => { offsets.push(Buffer.byteLength(pdf, "latin1")); pdf += `${index + 1} 0 obj\n${body}\nendobj\n`; });
  const xref = Buffer.byteLength(pdf, "latin1");
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (let index = 1; index <= objects.length; index += 1) pdf += `${String(offsets[index]).padStart(10, "0")} 00000 n \n`;
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root ${catalogId} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf, "latin1");
}
