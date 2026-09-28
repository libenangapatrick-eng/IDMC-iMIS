import { Router } from "express";
import { getSupabase } from "../../config/database.js";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";

const router = Router();
router.use(authenticate);

const visibleStatuses = ["PUBLISHED", "LOCKED"];

function ordinal(value: number): string {
  const mod100 = value % 100;
  if (mod100 >= 11 && mod100 <= 13) return `${value}th`;
  if (value % 10 === 1) return `${value}st`;
  if (value % 10 === 2) return `${value}nd`;
  if (value % 10 === 3) return `${value}rd`;
  return `${value}th`;
}

router.get(
  "/me",
  requirePermission("results.self.view"),
  async (req, res, next) => {
    try {
      const db = getSupabase();
      const warnings: string[] = [];
      const { data: student, error: studentError } = await db
        .from("students")
        .select("id,student_number,programme_id,first_name,middle_name,last_name")
        .eq("user_id", req.user!.id)
        .maybeSingle();

      if (studentError) throw studentError;
      if (!student) {
        return res.status(404).json({ success: false, message: "Authenticated account has no linked student record." });
      }

      const [resultQuery, semesterQuery, profileQuery, programmeQuery, userQuery] = await Promise.all([
        db.from("course_results").select("*").eq("student_id", student.id).in("result_status", visibleStatuses).order("created_at", { ascending: true }),
        db.from("student_semester_results").select("*").eq("student_id", student.id).in("result_status", visibleStatuses),
        db.from("student_profiles").select("first_name,middle_name,last_name").eq("student_id", student.id).maybeSingle(),
        student.programme_id
          ? db.from("programmes").select("programme_code,programme_name").eq("id", student.programme_id).maybeSingle()
          : Promise.resolve({ data: null, error: null }),
        db.from("users").select("last_login_at").eq("id", req.user!.id).maybeSingle(),
      ]);

      if (resultQuery.error) throw resultQuery.error;
      for (const [label, error] of [
        ["semester summaries", semesterQuery.error],
        ["student profile", profileQuery.error],
        ["programme", programmeQuery.error],
        ["last login", userQuery.error],
      ] as const) {
        if (error) warnings.push(`${label} could not be loaded`);
      }

      const results = (resultQuery.data ?? []) as any[];
      const offeringIds = [...new Set(results.map((row) => row.course_offering_id).filter(Boolean))];
      const yearIds = [...new Set(results.map((row) => row.academic_year_id).filter(Boolean))];
      const semesterIds = [...new Set(results.map((row) => row.semester_id).filter(Boolean))];

      const [offeringQuery, yearQuery, semesterLookupQuery] = await Promise.all([
        offeringIds.length ? db.from("course_offerings").select("id,course_id").in("id", offeringIds) : Promise.resolve({ data: [], error: null }),
        yearIds.length ? db.from("academic_years").select("id,year_code,year_name,start_date,end_date,status").in("id", yearIds) : Promise.resolve({ data: [], error: null }),
        semesterIds.length ? db.from("semesters").select("id,semester_name,semester_number").in("id", semesterIds) : Promise.resolve({ data: [], error: null }),
      ]);
      for (const [label, error] of [
        ["course offerings", offeringQuery.error],
        ["academic years", yearQuery.error],
        ["semesters", semesterLookupQuery.error],
      ] as const) {
        if (error) warnings.push(`${label} could not be loaded`);
      }

      const offerings = (offeringQuery.data ?? []) as any[];
      const courseIds = [...new Set(offerings.map((row) => row.course_id).filter(Boolean))];
      const courseQuery = courseIds.length
        ? await db.from("courses").select("id,course_code,course_name,course_type,credit_units").in("id", courseIds)
        : { data: [], error: null };
      if (courseQuery.error) warnings.push("course names could not be loaded");

      const offeringMap = new Map(offerings.map((row) => [row.id, row]));
      const courseMap = new Map(((courseQuery.data ?? []) as any[]).map((row) => [row.id, row]));
      const yearMap = new Map(((yearQuery.data ?? []) as any[]).map((row) => [row.id, row]));
      const semesterMap = new Map(((semesterLookupQuery.data ?? []) as any[]).map((row) => [row.id, row]));
      const summaryMap = new Map(((semesterQuery.data ?? []) as any[]).map((row) => [`${row.academic_year_id}:${row.semester_id}`, row]));

      const orderedYears = [...yearMap.values()].sort((a, b) => String(a.start_date).localeCompare(String(b.start_date)));
      const years = orderedYears.map((year, index) => {
        const yearRows = results.filter((row) => row.academic_year_id === year.id);
        const semesterNumbers = [...new Set(yearRows.map((row) => row.semester_id))]
          .map((id) => semesterMap.get(id))
          .filter(Boolean)
          .sort((a, b) => Number(a.semester_number) - Number(b.semester_number));

        return {
          id: year.id,
          code: year.year_code,
          name: year.year_name,
          status: year.status,
          studyYear: index + 1,
          studyYearLabel: `${ordinal(index + 1)} Year Results - ${year.year_name || year.year_code}`,
          semesters: semesterNumbers.map((semester) => {
            const semesterRows = yearRows.filter((row) => row.semester_id === semester.id);
            const summary = summaryMap.get(`${year.id}:${semester.id}`) ?? {};
            return {
              id: semester.id,
              name: semester.semester_name,
              number: semester.semester_number,
              gpa: summary.gpa ?? null,
              credits: summary.total_attempted_credits ?? semesterRows.reduce((sum, row) => sum + Number(row.credits || 0), 0),
              qualityPoints: summary.total_quality_points ?? semesterRows.reduce((sum, row) => sum + (Number(row.grade_point || 0) * Number(row.credits || 0)), 0),
              academicStanding: summary.academic_standing ?? null,
              results: semesterRows.map((row) => {
                const offering = offeringMap.get(row.course_offering_id) ?? {};
                const course = courseMap.get(offering.course_id) ?? {};
                return {
                  id: row.id,
                  code: course.course_code ?? "—",
                  moduleName: course.course_name ?? "Unknown module",
                  type: course.course_type ?? "—",
                  coursework: row.coursework_mark,
                  semesterExam: row.examination_mark,
                  supplementary: row.supplementary_mark ?? null,
                  total: row.total_mark,
                  credits: row.credits ?? course.credit_units,
                  grade: row.grade_code,
                  points: Number(row.grade_point || 0) * Number(row.credits || 0),
                  remarks: row.remarks || row.pass_status,
                  resultType: row.result_type,
                };
              }),
            };
          }),
        };
      });

      const profile = profileQuery.data as any;
      const fullName = [student.first_name || profile?.first_name, student.middle_name || profile?.middle_name, student.last_name || profile?.last_name]
        .filter(Boolean).join(" ");
      const currentYear = orderedYears.find((year) => year.status === "ACTIVE") ?? orderedYears.at(-1) ?? null;

      return res.json({
        success: true,
        data: {
          student: {
            id: student.id,
            studentNumber: student.student_number,
            fullName: fullName || req.user!.email,
            programmeCode: (programmeQuery.data as any)?.programme_code ?? null,
            programmeName: (programmeQuery.data as any)?.programme_name ?? null,
          },
          currentAcademicYear: currentYear ? (currentYear.year_name || currentYear.year_code) : null,
          lastLoginAt: (userQuery.data as any)?.last_login_at ?? null,
          generatedAt: new Date().toISOString(),
          warnings,
          years,
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

export default router;
