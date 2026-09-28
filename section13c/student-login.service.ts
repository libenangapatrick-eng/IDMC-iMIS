import { getSupabase } from "../../../config/database.js";
import { createAuditLog } from "../../../services/audit.service.js";
import { logError } from "../../../utils/logger.js";

/*
 * ============================================================
 * IDMC iMIS - Student sign-in by Registration No / Application No
 * ============================================================
 *
 * Students type their Registration Number (students.student_number)
 * or their Application Number (applications.application_number)
 * in the normal login form.
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
  "SUSPENDED",
  "WITHDRAWN",
  "EXPELLED",
  "DECEASED",
  "INACTIVE",
]);

const STUDENT_COLUMNS = [
  "id",
  "student_number",
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

  /* 1. Registration Number */
  const { data: byNumber, error: numberError } = await supabase
    .from("students")
    .select(STUDENT_COLUMNS)
    .ilike("student_number", pattern)
    .limit(2);

  if (numberError) throw numberError;

  if (byNumber && byNumber.length === 1) {
    return byNumber[0] as unknown as StudentRow;
  }

  if (byNumber && byNumber.length > 1) {
    return null;
  }

  /* 2. Application Number -> the student created from that application */
  const { data: applications, error: applicationError } = await supabase
    .from("applications")
    .select("id")
    .ilike("application_number", pattern)
    .limit(2);

  if (applicationError) throw applicationError;

  const application = applications?.[0];

  if (!applications || applications.length !== 1 || !application) {
    return null;
  }

  const { data: byApplication, error: byApplicationError } = await supabase
    .from("students")
    .select(STUDENT_COLUMNS)
    .eq("source_application_id", application.id)
    .maybeSingle();

  if (byApplicationError) throw byApplicationError;

  return (byApplication as unknown as StudentRow | null) ?? null;
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

    const contactEmail = String(student.email || applicant?.email || "")
      .trim()
      .toLowerCase();

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

    const registrationNumber = student.student_number.trim();
    const username = registrationNumber.toLowerCase();

    /*
     * A student may share a contact email with an existing staff/admin
     * identity.  Login is by registration number, so use a deterministic
     * internal Auth email whenever the contact email is unavailable or is
     * already owned.  This keeps the two identities separate and prevents a
     * student first-login from resetting or taking over the existing account.
     */
    const safeStudentNumber = registrationNumber
      .replace(/[^a-zA-Z0-9._-]/g, "")
      .toLowerCase();
    const internalEmail = `${safeStudentNumber}@students.idmc.local`;
    let authEmail = contactEmail || internalEmail;

    /* Never take over an account that already exists. */
    if (contactEmail) {
      const { data: emailOwner, error: emailError } = await supabase
        .from("users")
        .select("id")
        .ilike("email", contactEmail)
        .maybeSingle();

      if (emailError) throw emailError;

      if (emailOwner) {
        authEmail = internalEmail;
      }
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
    let { data: authData, error: authError } =
      await supabase.auth.admin.createUser({
        email: authEmail,
        password: registrationNumber,
        email_confirm: true,
        user_metadata: {
          account_type: "STUDENT",
          first_name: firstName,
          middle_name: middleName,
          last_name: lastName,
          display_name: displayName,
          username,
          student_number: registrationNumber,
          contact_email: contactEmail || null,
        },
      });

    /* The contact email can exist in Auth without a public.users row. */
    if (authError && contactEmail && authEmail === contactEmail) {
      authEmail = internalEmail;
      ({ data: authData, error: authError } =
        await supabase.auth.admin.createUser({
          email: authEmail,
          password: registrationNumber,
          email_confirm: true,
          user_metadata: {
            account_type: "STUDENT",
            first_name: firstName,
            middle_name: middleName,
            last_name: lastName,
            display_name: displayName,
            username,
            student_number: registrationNumber,
            contact_email: contactEmail,
          },
        }));
    }

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
        email: authEmail,
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
          email: authEmail,
          contact_email: contactEmail || null,
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
  const student = await findStudentByIdentifier(identifier);

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
    if (password !== student.student_number) {
      throw new Error(INVALID);
    }

    userId = await provisionStudentAccount(student);
  }

  const { data: user, error } = await getSupabase()
    .from("users")
    .select("email, status")
    .eq("id", userId)
    .maybeSingle();

  if (error) throw error;

  if (!user || user.status !== "ACTIVE") {
    throw new Error(INVALID);
  }

  return String(user.email).toLowerCase();
}

