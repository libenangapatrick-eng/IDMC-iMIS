import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";
import { getSupabase } from "../../config/database.js";

const router = Router();
router.use(authenticate);

const VIEW = "academics.view";
const MANAGE = "academics.manage";
const REG_VIEW = "registration.view";
const REG_MANAGE = "registration.manage";
const REG_APPROVE = "registration.approve";
const TT_VIEW = "timetable.view";
const TT_MANAGE = "timetable.manage";
const TT_PUBLISH = "timetable.publish";

// Shared, read-only labels used by authorised module forms. Authentication is
// still required by the router; this avoids forcing an Examination Officer to
// also hold the broader academics.view permission just to select a semester.
router.get("/reference-data", async (req, res, next) => {
  try {
    const resource = String(req.query.resource || "all");
    const tables: Record<string, string> = { years:"academic_years", semesters:"semesters", programmes:"programmes", courses:"courses", offerings:"course_offerings", campuses:"campuses", students:"students" };
    if (resource !== "all" && !tables[resource]) return res.status(400).json({ success:false, message:"Unsupported reference-data resource." });
    const db=getSupabase();
    if(resource !== "all") { const table=tables[resource]; if(!table)return res.status(400).json({success:false,message:"Unsupported reference-data resource."}); const result=await db.from(table).select("*").limit(2000); if(result.error)throw result.error; return res.json({success:true,data:result.data??[]}); }
    const entries=await Promise.all(Object.entries(tables).map(async ([key,table])=>{const result=await db.from(table).select("*").limit(2000);if(result.error)throw result.error;return [key,result.data??[]] as const;}));
    res.json({success:true,data:Object.fromEntries(entries)});
  } catch(error){ next(error); }
});

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"academic_years", table:"academic_years", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["year_code","year_name","status"], filterFields:["status"], defaultOrderField:"start_date",
  fields:{ yearCode:"year_code", yearName:"year_name", startDate:"start_date", endDate:"end_date", status:"status" } }, "/years");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"semesters", table:"semesters", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["semester_code","semester_name","status"], filterFields:["academic_year_id","semester_number","status"], defaultOrderField:"start_date",
  fields:{ academicYearId:"academic_year_id", semesterCode:"semester_code", semesterName:"semester_name", semesterNumber:"semester_number", startDate:"start_date", endDate:"end_date", status:"status" } }, "/semesters");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"programmes", table:"programmes", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["programme_code","programme_name","programme_type","award_level"], filterFields:["institution_id","school_id","department_id","programme_type","award_level","mode_of_study","status"], defaultOrderField:"created_at",
  fields:{ institutionId:"institution_id", schoolId:"school_id", departmentId:"department_id", programmeCode:"programme_code", programmeName:"programme_name", programmeType:"programme_type", awardLevel:"award_level", durationYears:"duration_years", modeOfStudy:"mode_of_study", description:"description", status:"status" } }, "/programmes");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"programme_versions", table:"programme_versions", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["version_code","version_name","status"], filterFields:["programme_id","status"], defaultOrderField:"effective_from",
  fields:{ programmeId:"programme_id", versionCode:"version_code", versionName:"version_name", effectiveFrom:"effective_from", effectiveTo:"effective_to", totalCredits:"total_credits", status:"status" } }, "/programme-versions");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"courses", table:"courses", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["course_code","course_name","course_short_name"], filterFields:["institution_id","department_id","course_type","level","status"], defaultOrderField:"course_code",
  fields:{ institutionId:"institution_id", departmentId:"department_id", courseCode:"course_code", courseName:"course_name", courseShortName:"course_short_name", creditUnits:"credit_units", contactHours:"contact_hours", courseType:"course_type", level:"level", description:"description", status:"status" } }, "/courses");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"curricula", table:"curricula", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["curriculum_code","curriculum_name","status"], filterFields:["programme_version_id","status"], defaultOrderField:"effective_from",
  fields:{ programmeVersionId:"programme_version_id", curriculumCode:"curriculum_code", curriculumName:"curriculum_name", effectiveFrom:"effective_from", effectiveTo:"effective_to", totalCredits:"total_credits", status:"status" } }, "/curricula");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"curriculum_courses", table:"curriculum_courses", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["course_category"], filterFields:["curriculum_id","course_id","semester_number","year_number","course_category","is_compulsory"], defaultOrderField:"semester_number",
  fields:{ curriculumId:"curriculum_id", courseId:"course_id", semesterNumber:"semester_number", yearNumber:"year_number", courseCategory:"course_category", isCompulsory:"is_compulsory", creditUnits:"credit_units" } }, "/curriculum-courses");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"course_prerequisites", table:"course_prerequisites", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["minimum_grade"], filterFields:["course_id","prerequisite_course_id"], defaultOrderField:"created_at", fields:{ courseId:"course_id", prerequisiteCourseId:"prerequisite_course_id", minimumGrade:"minimum_grade" } }, "/course-prerequisites");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"course_offerings", table:"course_offerings", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["offering_code","section_name","delivery_mode","status"], filterFields:["academic_year_id","semester_id","programme_id","programme_version_id","course_id","status"], defaultOrderField:"created_at",
  fields:{ academicYearId:"academic_year_id", semesterId:"semester_id", programmeId:"programme_id", programmeVersionId:"programme_version_id", courseId:"course_id", offeringCode:"offering_code", sectionName:"section_name", capacity:"capacity", minimumStudents:"minimum_students", deliveryMode:"delivery_mode", status:"status", registrationOpenAt:"registration_open_at", registrationCloseAt:"registration_close_at", createdBy:"created_by", updatedBy:"updated_by" } }, "/course-offerings");

registerCrudResource(router, { moduleCode:"REGISTRATION", entityType:"student_registrations", table:"student_registrations", permissionView:REG_VIEW, permissionManage:REG_MANAGE,
  searchFields:["registration_number","registration_status","academic_eligibility_status","finance_eligibility_status","document_eligibility_status"], filterFields:["student_id","academic_year_id","semester_id","programme_id","programme_version_id","registration_status"], defaultOrderField:"created_at",
  fields:{ studentId:"student_id", academicYearId:"academic_year_id", semesterId:"semester_id", programmeId:"programme_id", programmeVersionId:"programme_version_id", registrationNumber:"registration_number", registrationStatus:"registration_status", academicEligibilityStatus:"academic_eligibility_status", financeEligibilityStatus:"finance_eligibility_status", documentEligibilityStatus:"document_eligibility_status", totalRegisteredCredits:"total_registered_credits", minimumCredits:"minimum_credits", maximumCredits:"maximum_credits", submittedAt:"submitted_at", approvedAt:"approved_at", approvedBy:"approved_by", lockedAt:"locked_at", lockedBy:"locked_by", rejectionReason:"rejection_reason", notes:"notes", createdBy:"created_by", updatedBy:"updated_by" } }, "/registrations");

registerCrudResource(router, { moduleCode:"REGISTRATION", entityType:"registration_approvals", table:"registration_approvals", permissionView:REG_VIEW, permissionManage:REG_APPROVE,
  searchFields:["approval_level","approval_role","approval_status","comments"], filterFields:["student_registration_id","approval_level","approval_role","approval_status"], defaultOrderField:"created_at",
  fields:{ studentRegistrationId:"student_registration_id", approvalLevel:"approval_level", approvalRole:"approval_role", approvalStatus:"approval_status", comments:"comments", approvedBy:"approved_by", approvedAt:"approved_at", rejectedAt:"rejected_at" } }, "/registration-approvals");

registerCrudResource(router, { moduleCode:"REGISTRATION", entityType:"course_registrations", table:"course_registrations", permissionView:REG_VIEW, permissionManage:REG_MANAGE,
  searchFields:["registration_type","registration_status","eligibility_status","prerequisite_status"], filterFields:["student_registration_id","student_id","course_id","course_offering_id","registration_type","registration_status"], defaultOrderField:"created_at",
  fields:{ studentRegistrationId:"student_registration_id", studentId:"student_id", courseId:"course_id", courseOfferingId:"course_offering_id", registrationType:"registration_type", registrationStatus:"registration_status", credits:"credits", attemptNumber:"attempt_number", isCore:"is_core", isElective:"is_elective", prerequisiteStatus:"prerequisite_status", eligibilityStatus:"eligibility_status", selectedAt:"selected_at", approvedAt:"approved_at", approvedBy:"approved_by", droppedAt:"dropped_at", dropReason:"drop_reason", notes:"notes", createdBy:"created_by", updatedBy:"updated_by" } }, "/course-registrations");

registerCrudResource(router, { moduleCode:"REGISTRATION", entityType:"course_add_drop_requests", table:"course_add_drop_requests", permissionView:REG_VIEW, permissionManage:REG_MANAGE,
  searchFields:["request_type","request_status","reason","decision_reason"], filterFields:["student_registration_id","student_id","course_id","course_offering_id","request_type","request_status"], defaultOrderField:"created_at",
  fields:{ studentRegistrationId:"student_registration_id", studentId:"student_id", courseId:"course_id", courseOfferingId:"course_offering_id", requestType:"request_type", requestStatus:"request_status", reason:"reason", decisionReason:"decision_reason", requestedBy:"requested_by", reviewedBy:"reviewed_by", requestedAt:"requested_at", reviewedAt:"reviewed_at" } }, "/add-drop-requests");

registerCrudResource(router, { moduleCode:"TIMETABLE", entityType:"timetables", table:"timetables", permissionView:TT_VIEW, permissionManage:TT_MANAGE,
  searchFields:["timetable_code","timetable_name","status"], filterFields:["academic_year_id","semester_id","campus_id","status"], defaultOrderField:"created_at",
  fields:{ academicYearId:"academic_year_id", semesterId:"semester_id", campusId:"campus_id", timetableCode:"timetable_code", timetableName:"timetable_name", status:"status", publishedAt:"published_at", publishedBy:"published_by", lockedAt:"locked_at", lockedBy:"locked_by", createdBy:"created_by", updatedBy:"updated_by" } }, "/timetables");

registerCrudResource(router, { moduleCode:"TIMETABLE", entityType:"timetable_slots", table:"timetable_slots", permissionView:TT_VIEW, permissionManage:TT_MANAGE,
  searchFields:["slot_code","day_of_week","status"], filterFields:["day_of_week","status"], defaultOrderField:"start_time",
  fields:{ slotCode:"slot_code", dayOfWeek:"day_of_week", startTime:"start_time", endTime:"end_time", durationMinutes:"duration_minutes", status:"status" } }, "/timetable-slots");

registerCrudResource(router, { moduleCode:"TIMETABLE", entityType:"timetable_entries", table:"timetable_entries", permissionView:TT_VIEW, permissionManage:TT_MANAGE,
  searchFields:["entry_type","status","notes"], filterFields:["timetable_id","class_id","course_offering_id","lecturer_assignment_id","room_id","timetable_slot_id","entry_date","status"], defaultOrderField:"created_at",
  fields:{ timetableId:"timetable_id", classId:"class_id", courseOfferingId:"course_offering_id", lecturerAssignmentId:"lecturer_assignment_id", roomId:"room_id", timetableSlotId:"timetable_slot_id", entryDate:"entry_date", entryType:"entry_type", status:"status", notes:"notes", createdBy:"created_by", updatedBy:"updated_by" } }, "/timetable-entries");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"classes", table:"classes", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["class_code","class_name","class_type","status"], filterFields:["course_offering_id","class_type","status"], defaultOrderField:"created_at",
  fields:{ courseOfferingId:"course_offering_id", classCode:"class_code", className:"class_name", classType:"class_type", capacity:"capacity", status:"status", createdBy:"created_by", updatedBy:"updated_by" } }, "/classes");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"lecturer_assignments", table:"lecturer_assignments", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["assignment_role","assignment_status","notes"], filterFields:["course_offering_id","class_id","lecturer_user_id","assignment_role","assignment_status"], defaultOrderField:"created_at",
  fields:{ courseOfferingId:"course_offering_id", classId:"class_id", lecturerUserId:"lecturer_user_id", assignmentRole:"assignment_role", workloadHours:"workload_hours", assignmentStatus:"assignment_status", assignedAt:"assigned_at", assignedBy:"assigned_by", notes:"notes" } }, "/lecturer-assignments");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"class_students", table:"class_students", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["enrollment_status"], filterFields:["class_id","student_id","course_registration_id","enrollment_status"], defaultOrderField:"created_at",
  fields:{ classId:"class_id", studentId:"student_id", courseRegistrationId:"course_registration_id", enrollmentStatus:"enrollment_status", enrolledAt:"enrolled_at", withdrawnAt:"withdrawn_at" } }, "/class-students");

registerCrudResource(router, { moduleCode:"ACADEMICS", entityType:"joining_instructions", table:"joining_instructions", permissionView:VIEW, permissionManage:MANAGE,
  searchFields:["title","description","status"], filterFields:["academic_year_id","programme_id","status"], defaultOrderField:"created_at",
  fields:{ academicYearId:"academic_year_id", programmeId:"programme_id", title:"title", description:"description", documentUrl:"document_url", versionNumber:"version_number", status:"status", publishedAt:"published_at", publishedBy:"published_by" } }, "/joining-instructions");

export default router;
