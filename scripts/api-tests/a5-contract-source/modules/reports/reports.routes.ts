import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

registerCrudResource(router, {
  moduleCode: "REPORTS", entityType: "report_definitions", table: "report_definitions",
  permissionView: "reports.view", permissionManage: "reports.manage",
  searchFields: ["report_code","report_name","module_code","description","source_name"],
  filterFields: ["institution_id","module_code","source_type","status","is_scheduled"],
  defaultOrderField: "created_at",
  fields: {
    institutionId:"institution_id", reportCode:"report_code", reportName:"report_name", moduleCode:"module_code",
    description:"description", sourceType:"source_type", sourceName:"source_name", parameterSchema:"parameter_schema",
    outputFormats:"output_formats", requiredPermission:"required_permission", status:"status",
    isScheduled:"is_scheduled", createdBy:"created_by", updatedBy:"updated_by"
  }
}, "/definitions");

registerCrudResource(router, {
  moduleCode: "REPORTS", entityType: "report_runs", table: "report_runs",
  permissionView: "reports.view", permissionManage: "reports.run",
  searchFields: ["run_number","status","output_format","error_message"],
  filterFields: ["report_id","requested_by","status","output_format"],
  defaultOrderField: "created_at",
  fields: {
    reportId:"report_id", runNumber:"run_number", requestedBy:"requested_by", startedAt:"started_at",
    completedAt:"completed_at", status:"status", parameters:"parameters", outputFormat:"output_format",
    resultLocation:"result_location", rowCount:"row_count", errorMessage:"error_message"
  }
}, "/runs");

registerCrudResource(router, {
  moduleCode: "REPORTS", entityType: "report_schedules", table: "report_schedules",
  permissionView: "reports.view", permissionManage: "reports.schedule",
  searchFields: ["schedule_code","cron_expression","timezone"],
  filterFields: ["report_id","is_active","output_format"],
  defaultOrderField: "created_at",
  fields: {
    reportId:"report_id", scheduleCode:"schedule_code", cronExpression:"cron_expression",
    timezone:"timezone", outputFormat:"output_format", recipients:"recipients", isActive:"is_active",
    nextRunAt:"next_run_at", lastRunAt:"last_run_at", createdBy:"created_by"
  }
}, "/schedules");

registerCrudResource(router, {
  moduleCode: "DASHBOARD", entityType: "dashboard_widgets", table: "dashboard_widgets",
  permissionView: "dashboard.widgets.view", permissionManage: "dashboard.widgets.manage",
  searchFields: ["widget_code","widget_name","dashboard_code","module_code","data_source_name"],
  filterFields: ["institution_id","dashboard_code","module_code","widget_type","data_source_type","is_active"],
  defaultOrderField: "position_index",
  fields: {
    institutionId:"institution_id", widgetCode:"widget_code", widgetName:"widget_name",
    dashboardCode:"dashboard_code", moduleCode:"module_code", widgetType:"widget_type",
    dataSourceType:"data_source_type", dataSourceName:"data_source_name", configuration:"configuration",
    requiredPermission:"required_permission", positionIndex:"position_index", widthUnits:"width_units",
    isActive:"is_active", createdBy:"created_by", updatedBy:"updated_by"
  }
}, "/widgets");

export default router;
