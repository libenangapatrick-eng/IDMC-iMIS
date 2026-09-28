import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();

router.use(authenticate);

const VIEW = "transcripts.view";
const MANAGE = "transcripts.manage";

registerCrudResource(
  router,
  {
    moduleCode: "TRANSCRIPTS",
    entityType: "student_transcripts",
    table: "student_transcripts",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "transcript_number",
      "transcript_type",
      "issue_reason",
      "final_academic_standing",
      "transcript_status",
      "verification_code",
      "remarks"
    ],

    filterFields: [
      "student_id",
      "programme_version_id",
      "transcript_type",
      "transcript_status",
      "replacement_of"
    ],

    defaultOrderField: "created_at",

    fields: {
      transcriptNumber: "transcript_number",
      studentId: "student_id",
      programmeVersionId: "programme_version_id",
      transcriptType: "transcript_type",
      issueReason: "issue_reason",
      cumulativeCredits: "cumulative_credits",
      cumulativeEarnedCredits: "cumulative_earned_credits",
      cumulativeQualityPoints: "cumulative_quality_points",
      cgpa: "cgpa",
      finalAcademicStanding: "final_academic_standing",
      transcriptStatus: "transcript_status",
      generatedAt: "generated_at",
      generatedBy: "generated_by",
      approvedAt: "approved_at",
      approvedBy: "approved_by",
      issuedAt: "issued_at",
      issuedBy: "issued_by",
      revokedAt: "revoked_at",
      revokedBy: "revoked_by",
      replacementOf: "replacement_of",
      documentFileId: "document_file_id",
      verificationCode: "verification_code",
      remarks: "remarks"
    }
  },
  "/"
);

registerCrudResource(
  router,
  {
    moduleCode: "TRANSCRIPTS",
    entityType: "student_transcript_semesters",
    table: "student_transcript_semesters",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [],

    filterFields: [
      "transcript_id",
      "academic_year_id",
      "semester_id",
      "semester_result_id"
    ],

    defaultOrderField: "created_at",

    fields: {
      transcriptId: "transcript_id",
      academicYearId: "academic_year_id",
      semesterId: "semester_id",
      semesterResultId: "semester_result_id"
    }
  },
  "/semesters"
);

registerCrudResource(
  router,
  {
    moduleCode: "TRANSCRIPTS",
    entityType: "student_transcript_courses",
    table: "student_transcript_courses",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "course_code",
      "course_title",
      "grade"
    ],

    filterFields: [
      "transcript_id",
      "transcript_semester_id"
    ],

    defaultOrderField: "created_at",

    fields: {
      transcriptId: "transcript_id",
      transcriptSemesterId: "transcript_semester_id",
      courseCode: "course_code",
      courseTitle: "course_title",
      grade: "grade"
    }
  },
  "/courses"
);

export default router;
