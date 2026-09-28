import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { getSupabase } from "../../config/database.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();

router.use(authenticate);

const VIEW = "attendance.view";
const MANAGE = "attendance.manage";

router.post("/", requirePermission(MANAGE), async (req,res,next)=>{try{
  const db=getSupabase(),offeringId=String(req.body?.courseOfferingId??"").trim();
  if(!offeringId)return res.status(400).json({success:false,message:"Course Offering is required."});
  const offering=await db.from("course_offerings").select("id,offering_code,capacity,status").eq("id",offeringId).maybeSingle();
  if(offering.error)throw offering.error;if(!offering.data)return res.status(404).json({success:false,message:"Selected Course Offering no longer exists."});
  if(["CANCELLED","CLOSED"].includes(offering.data.status))return res.status(409).json({success:false,message:`Attendance cannot be created for a ${offering.data.status} offering.`});
  let classResult=await db.from("classes").select("id").eq("course_offering_id",offeringId).eq("status","ACTIVE").order("created_at").limit(1).maybeSingle();
  if(classResult.error)throw classResult.error;
  if(!classResult.data){
    const code=`${String(offering.data.offering_code||offeringId.slice(0,8)).slice(0,65)}-MAIN`;
    const created=await db.from("classes").insert({course_offering_id:offeringId,class_code:code,class_name:`${offering.data.offering_code||"Course"} Main Class`,class_type:"LECTURE",capacity:Number(offering.data.capacity||0),status:"ACTIVE",created_by:req.user!.id,updated_by:req.user!.id}).select("id").single();
    if(created.error){if(created.error.code==="23505")classResult=await db.from("classes").select("id").eq("class_code",code).maybeSingle();else throw created.error;}else classResult={data:created.data,error:null} as any;
  }
  const sessionDate=String(req.body?.sessionDate??"").trim(),startTime=String(req.body?.startTime??"").trim(),endTime=String(req.body?.endTime??"").trim();
  if(!sessionDate||!startTime||!endTime)return res.status(400).json({success:false,message:"Session Date, Start Time and End Time are required."});
  if(endTime<=startTime)return res.status(400).json({success:false,message:"End Time must be later than Start Time."});
  const saved=await db.from("attendance_sessions").insert({class_id:classResult.data!.id,course_offering_id:offeringId,timetable_entry_id:req.body?.timetableEntryId||null,session_date:sessionDate,start_time:startTime,end_time:endTime,session_type:String(req.body?.sessionType??"LECTURE").toUpperCase(),topic:req.body?.topic?String(req.body.topic).trim():null,venue_room_id:req.body?.venueRoomId||null,conducted_by:req.body?.conductedBy||req.user!.id,status:"DRAFT",notes:req.body?.notes?String(req.body.notes).trim():null,created_by:req.user!.id,updated_by:req.user!.id}).select("*").single();
  if(saved.error)throw saved.error;return res.status(201).json({success:true,data:saved.data,message:"Attendance session created; student list can now be loaded from registrations."});
}catch(error){next(error);}});

registerCrudResource(
  router,
  {
    moduleCode: "ATTENDANCE",
    entityType: "attendance_sessions",
    table: "attendance_sessions",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "session_type",
      "topic",
      "status",
      "notes"
    ],

    filterFields: [
      "class_id",
      "course_offering_id",
      "timetable_entry_id",
      "session_date",
      "session_type",
      "venue_room_id",
      "conducted_by",
      "status"
    ],

    defaultOrderField: "session_date",

    fields: {
      classId: "class_id",
      courseOfferingId: "course_offering_id",
      timetableEntryId: "timetable_entry_id",
      sessionDate: "session_date",
      startTime: "start_time",
      endTime: "end_time",
      sessionType: "session_type",
      topic: "topic",
      venueRoomId: "venue_room_id",
      conductedBy: "conducted_by",
      status: "status",
      openedAt: "opened_at",
      submittedAt: "submitted_at",
      lockedAt: "locked_at",
      lockedBy: "locked_by",
      notes: "notes",
      createdBy: "created_by",
      updatedBy: "updated_by"
    }
  },
  "/"
);

registerCrudResource(
  router,
  {
    moduleCode: "ATTENDANCE",
    entityType: "attendance_records",
    table: "attendance_records",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "attendance_status",
      "remarks"
    ],

    filterFields: [
      "attendance_session_id",
      "student_id",
      "course_registration_id",
      "attendance_status",
      "correction_required"
    ],

    defaultOrderField: "created_at",

    fields: {
      attendanceSessionId: "attendance_session_id",
      studentId: "student_id",
      courseRegistrationId: "course_registration_id",
      attendanceStatus: "attendance_status",
      checkInTime: "check_in_time",
      minutesLate: "minutes_late",
      remarks: "remarks",
      markedBy: "marked_by",
      markedAt: "marked_at",
      correctionRequired: "correction_required"
    }
  },
  "/records"
);

registerCrudResource(
  router,
  {
    moduleCode: "ATTENDANCE",
    entityType: "attendance_corrections",
    table: "attendance_corrections",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "old_status",
      "new_status",
      "reason",
      "status",
      "review_comment"
    ],

    filterFields: [
      "attendance_record_id",
      "requested_by",
      "status",
      "reviewed_by"
    ],

    defaultOrderField: "requested_at",

    fields: {
      attendanceRecordId: "attendance_record_id",
      requestedBy: "requested_by",
      requestedAt: "requested_at",
      oldStatus: "old_status",
      newStatus: "new_status",
      oldCheckInTime: "old_check_in_time",
      newCheckInTime: "new_check_in_time",
      reason: "reason",
      evidenceFileId: "evidence_file_id",
      status: "status",
      reviewedBy: "reviewed_by",
      reviewedAt: "reviewed_at",
      reviewComment: "review_comment"
    }
  },
  "/corrections"
);

export default router;
