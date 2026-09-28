import { getSupabase } from "../../../config/database.js";
import { createAuditLog } from "../../../services/audit.service.js";
import { logError } from "../../../utils/logger.js";

/*
 * ============================================================
 * IDMC iMIS - Student sign-in by Student Number
 * ============================================================
 *
 * Students type only their Student Number (students.student_number).
 *
 * - Username           = Registration Number
 * - Initial password   = Registration Number (exactly as issued)
 * - The Supabase Auth account, the public.users row, the STUDENT
 *   role and students.user_id are created automatically the FIRST
 *   time a student signs in with the correct initial password.
 * - Later sign-ins go through the normal Supabase password check,
 *   so a student who changes the password is never affected.
 *
 * Staff are not affected: they keep signing in with their email.
 */

const STUDENT_ROLE_CODE = "STUDENT";

/* Students in these statuses cannot sign in. */
const BLOCKED_STUDENT_STATUSES = new Set([
  "PENDING_ACTIVATION",
  "SUSPENDED",
  "WITHDRAWN",
  "EXPELLED",
  "DECEASED",
  "INACTIVE",
]);

const STUDENT_COLUMNS = [
  "id",
  "student_number",
  "registration_number",
  "applicant_id",
  "user_id",
  "student_status",
  "first_name",
  "middle_name",
  "last_name",
  "email",
  "phone",
].join(", ");

interface StudentRow {
  id: string;
  student_number: string;
  registration_number: string | null;
  applicant_id: string | null;
  user_id: string | null;
  student_status: string | null;
  first_name: string | null;
  middle_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
}

const INVALID = "Invalid login credentials";

/* Make a typed identifier match literally (no % _ wildcards) in ILIKE. */
function escapeLike(value: string): string {
  return value.replace(/[\\%_]/g, (character) => `\\${character}`);
}

async function findStudentByIdentifier(
  value: string
): Promise<StudentRow | null> {
  /* "*" is a wildcard in PostgREST filters; no real number contains it. */
  if (!value || value.includes("*")) {
    return null;
  }

  const supabase = getSupabase();
  const pattern = escapeLike(value);

  /* Official Registration Number or retained legacy Student Number. */
  const { data: byNumber, error: numberError } = await supabase
    .from("students")
    .select(STUDENT_COLUMNS)
    .or(`registration_number.ilike.${pattern},student_number.ilike.${pattern}`)
    .limit(2);

  if (numberError) throw numberError;

  if (byNumber && byNumber.length === 1) {
    return byNumber[0] as unknown as StudentRow;
  }

  if (byNumber && byNumber.length > 1) {
    return null;
  }

  return null;
}

export function normaliseStudentNumber(value: string): string {
  return String(value ?? "").trim().toUpperCase();
}

export function isValidStudentNumber(value: string): boolean {
  return /^N[A-Z]\d{4}\/\d{4}\/\d{4}$/.test(normaliseStudentNumber(value)) || /^IDMC\/\d{4}\/\d{5}$/.test(normaliseStudentNumber(value));
}

async function createStudentAccount(student: StudentRow): Promise<string> {
  const supabase = getSupabase();

  let authUserId: string | null = null;
  let publicUserId: string | null = null;
  let roleAssignmentId: string | null = null;

  try {
    /* Name / email come from the applicant record when the student row is thin. */
    let applicant: any = null;

    if (student.applicant_id) {
      const { data, error } = await supabase
        .from("applicants")
        .select("first_name, middle_name, last_name, email, phone")
        .eq("id", student.applicant_id)
        .maybeSingle();

      if (error) throw error;
      applicant = data;
    }

    /*
     * Authentication email is deliberately internal.  Contact email remains
     * on students/student_profiles, while learners sign in only with their
     * Student Number.  This avoids collisions with applicant/staff accounts.
     */
    const email = `${student.student_number.replace(/[^a-z0-9]/gi, "").toLowerCase()}@students.idmc.local`;

    const firstName = String(
      student.first_name || applicant?.first_name || "Student"
    ).trim();

    const middleName =
      String(student.middle_name || applicant?.middle_name || "").trim() ||
      null;

    const lastName = String(
      student.last_name || applicant?.last_name || student.student_number
    ).trim();

    const displayName = [firstName, middleName, lastName]
      .filter(Boolean)
      .join(" ");

    const phone =
      String(student.phone || applicant?.phone || "").trim() || null;

    const registrationNumber = String(student.registration_number || student.student_number).trim();
    const username = registrationNumber.toLowerCase();

    /* Never take over an account that already exists. */
    const { data: emailOwner, error: emailError } = await supabase
      .from("users")
      .select("id")
      .eq("email", email)
      .maybeSingle();

    if (emailError) throw emailError;

    if (emailOwner) {
      throw new Error(
        `Email ${email} already belongs to another IDMC user; student ${registrationNumber} needs a different email.`
      );
    }

    const { data: usernameOwner, error: usernameError } = await supabase
      .from("users")
      .select("id")
      .eq("username", username)
      .maybeSingle();

    if (usernameError) throw usernameError;

    if (usernameOwner) {
      throw new Error(
        `Username ${username} is already used by another IDMC user.`
      );
    }

    const { data: role, error: roleError } = await supabase
      .from("roles")
      .select("id")
      .eq("role_code", STUDENT_ROLE_CODE)
      .eq("status", "ACTIVE")
      .maybeSingle();

    if (roleError) throw roleError;

    if (!role) {
      throw new Error(
        `Role ${STUDENT_ROLE_CODE} does not exist or is not ACTIVE.`
      );
    }

    /* 1. Supabase Auth account: password = Registration Number */
    const { data: authData, error: authError } =
      await supabase.auth.admin.createUser({
        email,
        password: registrationNumber,
        email_confirm: true,
        user_metadata: {
          first_name: firstName,
          middle_name: middleName,
          last_name: lastName,
          display_name: displayName,
          username,
          student_number: registrationNumber,
        },
      });

    if (authError || !authData?.user) {
      throw new Error(
        authError?.message || "Unable to create authentication account."
      );
    }

    authUserId = authData.user.id;

    /* 2. public.users profile (password_changed_at stays NULL = still the default) */
    const { data: publicUser, error: publicUserError } = await supabase
      .from("users")
      .insert({
        auth_user_id: authUserId,
        user_number: registrationNumber,
        username,
        first_name: firstName,
        middle_name: middleName,
        last_name: lastName,
        display_name: displayName,
        email,
        phone,
        status: "ACTIVE",
        email_verified_at: new Date().toISOString(),
      })
      .select("id")
      .single();

    if (publicUserError || !publicUser) {
      throw new Error(
        publicUserError?.message || "Unable to create user profile."
      );
    }

    publicUserId = String(publicUser.id);

    /* 3. STUDENT role */
    const { data: assignment, error: assignmentError } = await supabase
      .from("user_roles")
      .insert({
        user_id: publicUserId,
        role_id: role.id,
        status: "ACTIVE",
      })
      .select("id")
      .single();

    if (assignmentError || !assignment) {
      throw new Error(
        assignmentError?.message || "Unable to assign the STUDENT role."
      );
    }

    roleAssignmentId = String(assignment.id);

    /* 4. Link the student record to the new user (only if still unlinked) */
    const { data: linked, error: linkError } = await supabase
      .from("students")
      .update({ user_id: publicUserId })
      .eq("id", student.id)
      .is("user_id", null)
      .select("id");

    if (linkError) throw linkError;

    if (!linked || linked.length !== 1) {
      throw new Error("Student record was linked by another request.");
    }

    try {
      await createAuditLog({
        actorUserId: publicUserId,
        actionCode: "STUDENT_ACCOUNT_AUTO_PROVISIONED",
        moduleCode: "students",
        entityType: "student",
        entityId: student.id,
        newValues: {
          student_number: registrationNumber,
          user_id: publicUserId,
          email,
        },
      });
    } catch (auditError) {
      /* Audit storage problems must not block a valid student sign-in. */
      logError("Student provisioning audit log failed", auditError);
    }

    return publicUserId;
  } catch (error) {
    /* Undo whatever this attempt created, newest first. */
    if (roleAssignmentId) {
      await supabase.from("user_roles").delete().eq("id", roleAssignmentId);
    }

    if (publicUserId) {
      await supabase.from("users").delete().eq("id", publicUserId);
    }

    if (authUserId) {
      await supabase.auth.admin.deleteUser(authUserId);
    }

    throw error;
  }
}

async function provisionStudentAccount(student: StudentRow): Promise<string> {
  try {
    return await createStudentAccount(student);
  } catch (error) {
    /* Two first sign-ins at the same moment: the other request may have won. */
    const { data: current } = await getSupabase()
      .from("students")
      .select("user_id")
      .eq("id", student.id)
      .maybeSingle();

    if (current?.user_id) {
      return String(current.user_id);
    }

    logError(
      `Student account could not be created for ${student.student_number}`,
      error
    );

    throw new Error(INVALID);
  }
}

/*
 * Returns the login email for a student identifier, or null when the
 * identifier does not belong to a student (staff / other users).
 * Throws "Invalid login credentials" when it IS a student but may not sign in.
 */
export async function resolveStudentLoginEmail(
  identifier: string,
  password: string
): Promise<string | null> {
  const studentNumber = normaliseStudentNumber(identifier);
  if (!isValidStudentNumber(studentNumber)) {
    return null;
  }

  const student = await findStudentByIdentifier(studentNumber);

  if (!student) {
    return null;
  }

  const status = String(student.student_status ?? "").toUpperCase();

  if (BLOCKED_STUDENT_STATUSES.has(status)) {
    throw new Error(INVALID);
  }

  let userId = student.user_id;

  if (!userId) {
    /* First sign-in: only the initial password (= Registration Number) may create the account. */
    const initialIdentity=String(student.registration_number||student.student_number).trim();
    if (password !== initialIdentity) {
      throw new Error(INVALID);
    }

    userId = await provisionStudentAccount(student);
  }

  const supabase = getSupabase();
  const { data: user, error } = await supabase
    .from("users")
    .select("auth_user_id, email, status")
    .eq("id", userId)
    .maybeSingle();

  if (error) throw error;

  if (!user || user.status !== "ACTIVE") {
    throw new Error(INVALID);
  }

  /* public.users.email can be stale. auth_user_id is authoritative. */
  const { data: authData, error: authError } =
    await supabase.auth.admin.getUserById(String(user.auth_user_id));

  const authEmail = String(authData?.user?.email ?? "").trim().toLowerCase();
  if (authError || !authEmail) {
    throw new Error(INVALID);
  }

  return authEmail;
}
