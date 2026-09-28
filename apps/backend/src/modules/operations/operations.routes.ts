import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "suppliers", table: "suppliers", permissionView: "procurement.view", permissionManage: "procurement.manage",
  searchFields: ["supplier_code", "supplier_name", "contact_person", "phone", "email"], filterFields: ["institution_id", "status"],
  fields: { institutionId: "institution_id", supplierCode: "supplier_code", supplierName: "supplier_name", supplierType: "supplier_type", registrationNumber: "registration_number", taxIdentificationNumber: "tax_identification_number", contactPerson: "contact_person", phone: "phone", email: "email", physicalAddress: "physical_address", postalAddress: "postal_address", bankName: "bank_name", bankAccountName: "bank_account_name", bankAccountNumber: "bank_account_number", status: "status", notes: "notes" }
}, "/suppliers");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "procurement_requests", table: "procurement_requests", permissionView: "procurement.view", permissionManage: "procurement.manage",
  searchFields: ["request_number", "purpose", "justification"], filterFields: ["institution_id", "department_id", "request_status", "priority"], defaultOrderField: "request_date",
  fields: { institutionId: "institution_id", requestNumber: "request_number", requestedBy: "requested_by", departmentId: "department_id", requestDate: "request_date", requiredDate: "required_date", priority: "priority", requestStatus: "request_status", purpose: "purpose", estimatedTotal: "estimated_total", justification: "justification", approvedBy: "approved_by", approvedAt: "approved_at", rejectionReason: "rejection_reason" }
}, "/procurement/requests");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "procurement_request_items", table: "procurement_request_items", permissionView: "procurement.view", permissionManage: "procurement.manage",
  searchFields: ["item_description", "specifications"], filterFields: ["procurement_request_id"],
  fields: { procurementRequestId: "procurement_request_id", itemDescription: "item_description", quantity: "quantity", unitOfMeasure: "unit_of_measure", estimatedUnitPrice: "estimated_unit_price", specifications: "specifications" }
}, "/procurement/request-items");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "purchase_orders", table: "purchase_orders", permissionView: "procurement.view", permissionManage: "procurement.manage",
  searchFields: ["purchase_order_number", "notes"], filterFields: ["institution_id", "supplier_id", "order_status"], defaultOrderField: "order_date",
  fields: { institutionId: "institution_id", procurementRequestId: "procurement_request_id", supplierId: "supplier_id", purchaseOrderNumber: "purchase_order_number", orderDate: "order_date", expectedDeliveryDate: "expected_delivery_date", currency: "currency", subtotal: "subtotal", taxAmount: "tax_amount", discountAmount: "discount_amount", totalAmount: "total_amount", orderStatus: "order_status", approvedBy: "approved_by", approvedAt: "approved_at", notes: "notes" }
}, "/procurement/orders");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "purchase_order_items", table: "purchase_order_items", permissionView: "procurement.view", permissionManage: "procurement.manage",
  searchFields: ["item_description", "specifications"], filterFields: ["purchase_order_id"],
  fields: { purchaseOrderId: "purchase_order_id", itemDescription: "item_description", quantity: "quantity", unitOfMeasure: "unit_of_measure", unitPrice: "unit_price", taxAmount: "tax_amount", discountAmount: "discount_amount", specifications: "specifications" }
}, "/procurement/order-items");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "inventory_categories", table: "inventory_categories", permissionView: "inventory.view", permissionManage: "inventory.manage",
  searchFields: ["category_code", "category_name"], filterFields: ["institution_id", "status"],
  fields: { institutionId: "institution_id", categoryCode: "category_code", categoryName: "category_name", description: "description", status: "status" }
}, "/inventory/categories");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "inventory_items", table: "inventory_items", permissionView: "inventory.view", permissionManage: "inventory.manage",
  searchFields: ["item_code", "item_name", "description", "storage_location"], filterFields: ["institution_id", "category_id", "status"],
  fields: { institutionId: "institution_id", categoryId: "category_id", itemCode: "item_code", itemName: "item_name", description: "description", unitOfMeasure: "unit_of_measure", minimumStockLevel: "minimum_stock_level", maximumStockLevel: "maximum_stock_level", reorderLevel: "reorder_level", currentQuantity: "current_quantity", unitCost: "unit_cost", storageLocation: "storage_location", status: "status" }
}, "/inventory/items");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "inventory_transactions", table: "inventory_transactions", permissionView: "inventory.view", permissionManage: "inventory.manage",
  searchFields: ["transaction_number", "reference_type", "remarks"], filterFields: ["inventory_item_id", "transaction_type"], defaultOrderField: "transaction_date",
  fields: { inventoryItemId: "inventory_item_id", transactionType: "transaction_type", transactionNumber: "transaction_number", quantity: "quantity", unitCost: "unit_cost", referenceType: "reference_type", referenceId: "reference_id", transactionDate: "transaction_date", balanceBefore: "balance_before", balanceAfter: "balance_after", performedBy: "performed_by", remarks: "remarks" }
}, "/inventory/transactions");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "asset_categories", table: "asset_categories", permissionView: "assets.view", permissionManage: "assets.manage",
  searchFields: ["category_code", "category_name", "description"], filterFields: ["institution_id", "status"],
  fields: { institutionId: "institution_id", categoryCode: "category_code", categoryName: "category_name", depreciationMethod: "depreciation_method", defaultUsefulLifeYears: "default_useful_life_years", description: "description", status: "status" }
}, "/assets/categories");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "assets", table: "assets", permissionView: "assets.view", permissionManage: "assets.manage",
  searchFields: ["asset_tag", "asset_name", "serial_number", "manufacturer", "model", "location"], filterFields: ["institution_id", "category_id", "department_id", "asset_status", "condition_status"],
  fields: { institutionId: "institution_id", categoryId: "category_id", departmentId: "department_id", assetTag: "asset_tag", assetName: "asset_name", description: "description", serialNumber: "serial_number", manufacturer: "manufacturer", model: "model", acquisitionDate: "acquisition_date", acquisitionCost: "acquisition_cost", currentValue: "current_value", usefulLifeYears: "useful_life_years", location: "location", conditionStatus: "condition_status", assetStatus: "asset_status", warrantyExpiryDate: "warranty_expiry_date", notes: "notes" }
}, "/assets");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "asset_assignments", table: "asset_assignments", permissionView: "assets.view", permissionManage: "assets.assign",
  searchFields: ["assignment_status", "notes"], filterFields: ["asset_id", "staff_id", "department_id", "assignment_status"],
  fields: { assetId: "asset_id", staffId: "staff_id", departmentId: "department_id", assignedDate: "assigned_date", returnedDate: "returned_date", assignmentStatus: "assignment_status", assignedBy: "assigned_by", receivedBy: "received_by", returnCondition: "return_condition", notes: "notes" }
}, "/assets/assignments");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "asset_maintenance", table: "asset_maintenance", permissionView: "assets.view", permissionManage: "assets.manage",
  searchFields: ["service_provider", "description", "notes"], filterFields: ["asset_id", "maintenance_type", "maintenance_status"], defaultOrderField: "maintenance_date",
  fields: { assetId: "asset_id", maintenanceType: "maintenance_type", maintenanceDate: "maintenance_date", serviceProvider: "service_provider", description: "description", cost: "cost", nextMaintenanceDate: "next_maintenance_date", maintenanceStatus: "maintenance_status", performedBy: "performed_by", notes: "notes" }
}, "/assets/maintenance");

export default router;
