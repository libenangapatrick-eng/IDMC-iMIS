import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

registerCrudResource(router, {
  moduleCode: "SYSTEM", entityType: "system_settings", table: "system_settings",
  permissionView: "system.config.view", permissionManage: "system.config.manage",
  searchFields: ["setting_key","setting_name","description"], filterFields: ["institution_id","value_type","is_sensitive","is_editable"],
  defaultOrderField: "setting_key",
  fields: {
    institutionId:"institution_id", settingKey:"setting_key", settingName:"setting_name",
    valueType:"value_type", settingValue:"setting_value", isSensitive:"is_sensitive",
    isEditable:"is_editable", description:"description", updatedBy:"updated_by"
  }
}, "/settings");

registerCrudResource(router, {
  moduleCode: "SYSTEM", entityType: "system_feature_flags", table: "system_feature_flags",
  permissionView: "system.features.view", permissionManage: "system.features.manage",
  searchFields: ["feature_code","feature_name","description"], filterFields: ["institution_id","is_enabled"],
  defaultOrderField: "feature_code",
  fields: {
    institutionId:"institution_id", featureCode:"feature_code", featureName:"feature_name",
    isEnabled:"is_enabled", rolloutPercentage:"rollout_percentage", description:"description", updatedBy:"updated_by"
  }
}, "/features");

registerCrudResource(router, {
  moduleCode: "SYSTEM", entityType: "system_number_sequences", table: "system_number_sequences",
  permissionView: "system.config.view", permissionManage: "system.config.manage",
  searchFields: ["sequence_code","sequence_name","prefix"], filterFields: ["institution_id","sequence_code","is_active"],
  defaultOrderField: "sequence_code",
  fields: {
    institutionId:"institution_id", sequenceCode:"sequence_code", sequenceName:"sequence_name",
    prefix:"prefix", currentValue:"current_value", paddingWidth:"padding_width",
    resetPeriod:"reset_period", isActive:"is_active", updatedBy:"updated_by"
  }
}, "/number-sequences");

registerCrudResource(router, {
  moduleCode: "SYSTEM", entityType: "system_maintenance_windows", table: "system_maintenance_windows",
  permissionView: "system.maintenance.view", permissionManage: "system.maintenance.manage",
  searchFields: ["title","message"], filterFields: ["institution_id","status"], defaultOrderField: "start_at",
  fields: {
    institutionId:"institution_id", title:"title", startAt:"start_at", endAt:"end_at",
    status:"status", message:"message", createdBy:"created_by", updatedBy:"updated_by"
  }
}, "/maintenance-windows");

registerCrudResource(router, {
  moduleCode: "SYSTEM", entityType: "system_workflows", table: "system_workflows",
  permissionView: "system.workflows.view", permissionManage: "system.workflows.manage",
  searchFields: ["workflow_code","workflow_name","module_code","entity_type","description"],
  filterFields: ["institution_id","module_code","entity_type","status"],
  defaultOrderField: "created_at",
  fields: {
    institutionId:"institution_id", workflowCode:"workflow_code", workflowName:"workflow_name",
    moduleCode:"module_code", entityType:"entity_type", version:"version", status:"status",
    description:"description", createdBy:"created_by", updatedBy:"updated_by"
  }
}, "/workflows");

registerCrudResource(router, {
  moduleCode: "SYSTEM", entityType: "system_workflow_steps", table: "system_workflow_steps",
  permissionView: "system.workflows.view", permissionManage: "system.workflows.manage",
  searchFields: ["step_code","step_name","required_permission","approver_role_code"],
  filterFields: ["workflow_id","step_number"], defaultOrderField: "step_number",
  fields: {
    workflowId:"workflow_id", stepNumber:"step_number", stepCode:"step_code", stepName:"step_name",
    requiredPermission:"required_permission", approverRoleCode:"approver_role_code",
    slaHours:"sla_hours", isFinal:"is_final"
  }
}, "/workflow-steps");

export default router;
