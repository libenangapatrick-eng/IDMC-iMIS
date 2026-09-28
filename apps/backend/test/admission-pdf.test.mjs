import test from "node:test";
import assert from "node:assert/strict";
import { buildAdmissionPdf } from "../dist/modules/applicant-self-service/admission-pdf.js";

test("joining instructions are generated as a valid multi-page PDF", () => {
  const pdf = buildAdmissionPdf({
    kind: "JOINING_INSTRUCTIONS",
    applicantName: "PATRICK LIBENANGA",
    applicantNumber: "APP/2026/00001",
    applicationNumber: "ADM-2026-07F00714",
    programmeName: "PPBA - Project Planning and Business Administration",
    academicYear: "2026/2027",
    indexNumber: "S4384-0269"
  });
  const source = pdf.toString("latin1");
  assert.match(source, /^%PDF-1\.4/);
  assert.match(source, /\/Type \/Pages/);
  assert.match(source, /TZS 650,000/);
  assert.match(source, /S4384-0269/);
  assert.ok(pdf.length > 4000);
});

test("draft acknowledgement labels itself as acknowledgement", () => {
  const pdf = buildAdmissionPdf({
    kind: "ACKNOWLEDGEMENT",
    applicantName: "APPLICANT NAME",
    applicantNumber: "APP-1",
    applicationNumber: "ADM-1",
    programmeName: "PROGRAMME",
    academicYear: "2026/2027",
    indexNumber: "S0000-0000"
  });
  assert.match(pdf.toString("latin1"), /ONLINE APPLICATION ACKNOWLEDGEMENT/);
});
