import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();

router.use(authenticate);

const VIEW = "timetable.view";
const MANAGE = "timetable.manage";

registerCrudResource(
  router,
  {
    moduleCode: "TIMETABLE",
    entityType: "timetables",
    table: "timetables",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "timetable_code",
      "timetable_name",
      "status"
    ],

    filterFields: [
      "academic_year_id",
      "semester_id",
      "campus_id",
      "status"
    ],

    defaultOrderField: "created_at",

    fields: {
      academicYearId: "academic_year_id",
      semesterId: "semester_id",
      campusId: "campus_id",
      timetableCode: "timetable_code",
      timetableName: "timetable_name",
      status: "status",
      publishedAt: "published_at",
      publishedBy: "published_by",
      lockedAt: "locked_at",
      lockedBy: "locked_by",
      createdBy: "created_by",
      updatedBy: "updated_by"
    }
  },
  "/"
);

registerCrudResource(
  router,
  {
    moduleCode: "TIMETABLE",
    entityType: "timetable_entries",
    table: "timetable_entries",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "status"
    ],

    filterFields: [
      "timetable_id",
      "class_id",
      "course_offering_id",
      "lecturer_assignment_id",
      "room_id",
      "timetable_slot_id",
      "status"
    ],

    defaultOrderField: "created_at",

    fields: {
      timetableId: "timetable_id",
      classId: "class_id",
      courseOfferingId: "course_offering_id",
      lecturerAssignmentId: "lecturer_assignment_id",
      roomId: "room_id",
      timetableSlotId: "timetable_slot_id",
      status: "status",
      createdBy: "created_by",
      updatedBy: "updated_by"
    }
  },
  "/entries"
);

registerCrudResource(
  router,
  {
    moduleCode: "TIMETABLE",
    entityType: "timetable_slots",
    table: "timetable_slots",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "slot_name"
    ],

    filterFields: [
      "day_of_week"
    ],

    defaultOrderField: "created_at",

    fields: {
      slotName: "slot_name",
      dayOfWeek: "day_of_week",
      startTime: "start_time",
      endTime: "end_time"
    }
  },
  "/slots"
);

registerCrudResource(
  router,
  {
    moduleCode: "TIMETABLE",
    entityType: "rooms",
    table: "rooms",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "room_code",
      "room_name",
      "room_type"
    ],

    filterFields: [
      "campus_id",
      "room_type"
    ],

    defaultOrderField: "created_at",

    fields: {
      campusId: "campus_id",
      roomCode: "room_code",
      roomName: "room_name",
      roomType: "room_type",
      capacity: "capacity"
    }
  },
  "/rooms"
);

registerCrudResource(
  router,
  {
    moduleCode: "TIMETABLE",
    entityType: "classes",
    table: "classes",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "class_code",
      "class_name",
      "status"
    ],

    filterFields: [
      "course_offering_id",
      "status"
    ],

    defaultOrderField: "created_at",

    fields: {
      courseOfferingId: "course_offering_id",
      classCode: "class_code",
      className: "class_name",
      status: "status"
    }
  },
  "/classes"
);

export default router;
