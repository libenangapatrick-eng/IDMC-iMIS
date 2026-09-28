import { timingSafeEqual } from "node:crypto";
import { Router, type Request, type Response } from "express";
import { getSupabase } from "../../config/database.js";
import { env } from "../../config/env.js";
const router=Router();
function authorized(req:Request){const expected=env.PAYMENT_PROVIDER_CALLBACK_SECRET,received=String(req.get("x-idmc-provider-secret")??"");if(!expected||!received)return false;const a=Buffer.from(expected),b=Buffer.from(received);return a.length===b.length&&timingSafeEqual(a,b);}
router.post("/callback",async(req:Request,res:Response)=>{
  if(!env.PAYMENT_PROVIDER_CALLBACK_SECRET){res.status(503).json({success:false,message:"Payment provider callback is not configured."});return;}
  if(!authorized(req)){res.status(401).json({success:false,message:"Invalid provider callback credential."});return;}
  const b=req.body??{};
  try{const result=await getSupabase().rpc("process_student_payment_provider_event",{p_provider:b.provider,p_event_reference:b.eventReference,p_request_number:b.requestNumber,p_status:b.status,p_amount:b.amount??null,p_control_number:b.controlNumber??null,p_provider_reference:b.providerReference??null,p_message:b.message??null,p_payload:b});if(result.error)throw result.error;res.json({success:true,data:result.data});}
  catch(error){res.status(400).json({success:false,message:error instanceof Error?error.message:"Provider callback failed."});}
});
export default router;
