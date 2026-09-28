import { getSupabase } from '../../../config/database.js';

function db() {
  const client = getSupabase();

  if (!client) {
    throw new Error('Supabase database is not configured.');
  }

  return client;
}

export async function getFeeStructures() {
  const { data, error } = await db()
    .from('fee_structures')
    .select(`
      id,
      fee_structure_code,
      fee_structure_name,
      academic_year,
      semester,
      description,
      status,
      currency_code,
      effective_from,
      effective_to,
      created_at,
      updated_at,
      fee_items (
        id,
        fee_item_code,
        fee_item_name,
        category,
        description,
        amount,
        is_mandatory,
        is_refundable,
        display_order
      )
    `)
    .order('created_at', { ascending: false });

  if (error) throw error;

  return data ?? [];
}

export async function getFeeStructureById(id: string) {
  const { data, error } = await db()
    .from('fee_structures')
    .select(`
      id,
      fee_structure_code,
      fee_structure_name,
      academic_year,
      semester,
      description,
      status,
      currency_code,
      effective_from,
      effective_to,
      created_at,
      updated_at,
      fee_items (
        id,
        fee_item_code,
        fee_item_name,
        category,
        description,
        amount,
        is_mandatory,
        is_refundable,
        display_order
      )
    `)
    .eq('id', id)
    .maybeSingle();

  if (error) throw error;

  return data;
}

export async function getStudentFinancialAccount(studentId: string) {
  const { data, error } = await db()
    .from('student_financial_accounts')
    .select(`
      id,
      student_id,
      total_charged,
      total_paid,
      total_refunded,
      total_scholarship,
      total_waiver,
      total_adjustments,
      current_balance,
      account_status,
      last_calculated_at,
      created_at,
      updated_at
    `)
    .eq('student_id', studentId)
    .maybeSingle();

  if (error) throw error;

  return data;
}

export async function getStudentCharges(studentId: string) {
  const { data, error } = await db()
    .from('student_charges')
    .select(`
      id,
      student_id,
      fee_structure_id,
      fee_item_id,
      charge_number,
      description,
      academic_year,
      semester,
      original_amount,
      scholarship_amount,
      waiver_amount,
      adjustment_amount,
      net_amount,
      status,
      charge_date,
      due_date,
      created_at,
      updated_at
    `)
    .eq('student_id', studentId)
    .order('charge_date', { ascending: false });

  if (error) throw error;

  return data ?? [];
}

export async function getStudentInvoices(studentId: string) {
  const { data, error } = await db()
    .from('invoices')
    .select(`
      id,
      student_id,
      invoice_number,
      invoice_date,
      due_date,
      academic_year,
      semester,
      subtotal,
      discount_amount,
      scholarship_amount,
      adjustment_amount,
      total_amount,
      amount_paid,
      balance_amount,
      status,
      currency_code,
      notes,
      issued_by,
      issued_at,
      created_at,
      updated_at,
      invoice_items (
        id,
        student_charge_id,
        description,
        quantity,
        unit_amount,
        discount_amount,
        line_total
      )
    `)
    .eq('student_id', studentId)
    .order('invoice_date', { ascending: false });

  if (error) throw error;

  return data ?? [];
}

export async function getStudentPayments(studentId: string) {
  const { data, error } = await db()
    .from('payments')
    .select(`
      id,
      student_id,
      payment_number,
      external_reference,
      control_number,
      payment_method,
      provider,
      amount,
      currency_code,
      payment_date,
      status,
      payer_name,
      payer_phone,
      payer_email,
      provider_transaction_id,
      receipt_number,
      confirmed_by,
      confirmed_at,
      created_at,
      updated_at,
      payment_allocations (
        id,
        invoice_id,
        student_charge_id,
        allocated_amount,
        allocation_date,
        allocation_reference,
        status
      )
    `)
    .eq('student_id', studentId)
    .order('payment_date', { ascending: false });

  if (error) throw error;

  return data ?? [];
}

export async function getStudentRefunds(studentId: string) {
  const { data, error } = await db()
    .from('refunds')
    .select(`
      id,
      payment_id,
      student_id,
      refund_number,
      amount,
      reason,
      refund_method,
      status,
      requested_by,
      approved_by,
      processed_by,
      requested_at,
      approved_at,
      processed_at,
      external_reference,
      created_at,
      updated_at
    `)
    .eq('student_id', studentId)
    .order('requested_at', { ascending: false });

  if (error) throw error;

  return data ?? [];
}

export async function getStudentScholarships(studentId: string) {
  const { data, error } = await db()
    .from('student_scholarships')
    .select(`
      id,
      student_id,
      scholarship_code,
      scholarship_name,
      sponsor_name,
      scholarship_type,
      amount,
      percentage,
      academic_year,
      semester,
      start_date,
      end_date,
      status,
      approval_reference,
      approved_by,
      approved_at,
      notes,
      created_at,
      updated_at
    `)
    .eq('student_id', studentId)
    .order('created_at', { ascending: false });

  if (error) throw error;

  return data ?? [];
}

export async function getStudentAdjustments(studentId: string) {
  const { data, error } = await db()
    .from('student_fee_adjustments')
    .select(`
      id,
      student_id,
      student_charge_id,
      adjustment_number,
      adjustment_type,
      amount,
      reason,
      status,
      requested_by,
      approved_by,
      posted_by,
      requested_at,
      approved_at,
      posted_at,
      reference_number,
      created_at,
      updated_at
    `)
    .eq('student_id', studentId)
    .order('requested_at', { ascending: false });

  if (error) throw error;

  return data ?? [];
}

export async function getStudentFinancialTransactions(studentId: string) {
  const { data, error } = await db()
    .from('financial_transactions')
    .select(`
      id,
      transaction_number,
      student_id,
      payment_id,
      invoice_id,
      charge_id,
      refund_id,
      transaction_type,
      debit_amount,
      credit_amount,
      transaction_date,
      reference_number,
      description,
      status,
      reversal_of,
      metadata,
      created_by,
      created_at
    `)
    .eq('student_id', studentId)
    .order('transaction_date', { ascending: false });

  if (error) throw error;

  return data ?? [];
}



