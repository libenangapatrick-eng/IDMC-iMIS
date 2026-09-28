import { Router } from "express";
import { getSupabase } from "../../config/database.js";

const router=Router();

router.get("/certificates/verify",async(req,res,next)=>{try{
  const certificateNumber=String(req.query.certificateNumber??"").trim();
  const verificationCode=String(req.query.verificationCode??"").trim();
  if(!certificateNumber||!verificationCode){res.status(400).json({success:false,message:"Certificate Number and Verification Code are required."});return;}
  const db=getSupabase();
  const {data,error}=await db.from("certificates").select("id,certificate_number,certificate_type,award_name,issue_date,status,students(student_number,first_name,middle_name,last_name),programmes(programme_code,programme_name)").eq("certificate_number",certificateNumber).eq("verification_code",verificationCode).maybeSingle();
  if(error)throw error;
  const result=!data?"INVALID":data.status==="REVOKED"?"REVOKED":data.status==="REPLACED"?"REPLACED":data.status==="ISSUED"?"VALID":"INVALID";
  if(data)await db.from("certificate_verifications").insert({certificate_id:data.id,verification_code:verificationCode,verification_result:result,ip_address:req.ip,user_agent:req.get("user-agent")??null});
  if(result!=="VALID"){res.status(result==="INVALID"?404:410).json({success:false,message:result==="INVALID"?"Certificate could not be verified.":`Certificate is ${result.toLowerCase()}.`,data:{verificationResult:result}});return;}
  const valid=data!; const student=Array.isArray(valid.students)?valid.students[0]:valid.students; const programme=Array.isArray(valid.programmes)?valid.programmes[0]:valid.programmes;
  res.json({success:true,message:"Certificate is valid.",data:{verificationResult:"VALID",certificateNumber:valid.certificate_number,award:valid.award_name,issueDate:valid.issue_date,studentName:[student?.first_name,student?.middle_name,student?.last_name].filter(Boolean).join(" "),studentNumber:student?.student_number,programme:programme?.programme_name,programmeCode:programme?.programme_code}});
}catch(e){next(e);}});

export default router;
