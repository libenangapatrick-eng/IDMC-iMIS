import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";
const router=Router(); router.use(authenticate);
registerCrudResource(router,{moduleCode:"ALUMNI",entityType:"alumni_records",table:"alumni_records",permissionView:"alumni.view",permissionManage:"alumni.manage",searchFields:["alumni_number","graduation_year","current_employer","current_position","phone","email","address"],filterFields:["student_id","graduation_candidate_id","graduation_award_id","graduation_year","status"],defaultOrderField:"joined_at",fields:{studentId:"student_id",graduationCandidateId:"graduation_candidate_id",graduationAwardId:"graduation_award_id",alumniNumber:"alumni_number",graduationYear:"graduation_year",status:"status",currentEmployer:"current_employer",currentPosition:"current_position",phone:"phone",email:"email",address:"address",linkedinUrl:"linkedin_url",websiteUrl:"website_url",joinedAt:"joined_at"}},"/records");
export default router;
