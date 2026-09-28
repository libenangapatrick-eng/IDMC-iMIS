import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "hostels", table: "hostels", permissionView: "hostel.view", permissionManage: "hostel.manage",
  searchFields: ["hostel_code", "hostel_name", "location"], filterFields: ["institution_id", "hostel_type", "status"],
  fields: { institutionId: "institution_id", hostelCode: "hostel_code", hostelName: "hostel_name", hostelType: "hostel_type", capacity: "capacity", location: "location", wardenUserId: "warden_user_id", status: "status", description: "description" }
}, "/hostels");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "hostel_rooms", table: "hostel_rooms", permissionView: "hostel.view", permissionManage: "hostel.manage",
  searchFields: ["room_number", "room_type", "notes"], filterFields: ["hostel_id", "status"],
  fields: { hostelId: "hostel_id", roomNumber: "room_number", floorNumber: "floor_number", roomType: "room_type", capacity: "capacity", status: "status", notes: "notes" }
}, "/rooms");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "hostel_beds", table: "hostel_beds", permissionView: "hostel.view", permissionManage: "hostel.manage",
  searchFields: ["bed_number"], filterFields: ["room_id", "bed_status"],
  fields: { roomId: "room_id", bedNumber: "bed_number", bedStatus: "bed_status" }
}, "/beds");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "hostel_allocations", table: "hostel_allocations", permissionView: "hostel.view", permissionManage: "hostel.allocate",
  searchFields: ["academic_year", "allocation_status", "remarks"], filterFields: ["student_id", "hostel_id", "room_id", "academic_year", "allocation_status"], defaultOrderField: "allocation_date",
  fields: { studentId: "student_id", hostelId: "hostel_id", roomId: "room_id", bedId: "bed_id", academicYear: "academic_year", allocationDate: "allocation_date", moveInDate: "move_in_date", moveOutDate: "move_out_date", allocationStatus: "allocation_status", remarks: "remarks", allocatedBy: "allocated_by" }
}, "/allocations");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "hostel_fees", table: "hostel_fees", permissionView: "hostel.view", permissionManage: "hostel.manage",
  searchFields: ["fee_name", "academic_year"], filterFields: ["institution_id", "hostel_id", "academic_year", "status"],
  fields: { institutionId: "institution_id", hostelId: "hostel_id", academicYear: "academic_year", feeName: "fee_name", amount: "amount", currency: "currency", status: "status" }
}, "/fees");

export default router;
