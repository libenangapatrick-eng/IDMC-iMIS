import type { Request } from "express";

import { institutionDb } from "../../institution-management/shared/institution-db.js";

import type {
    CreateStudentInput,
    UpdateStudentInput,
} from "../shared/student.types.js";

function getActorIdentity(req: Request): string {

    const user = req.user as
        | Record<string, unknown>
        | undefined;

    const value =
        user?.id ??
        user?.userId ??
        user?.auth_user_id ??
        user?.authUserId ??
        user?.sub;

    if (!value) {
        throw new Error(
            "Authenticated user identity is unavailable."
        );
    }

    return String(value);
}

async function resolvePublicUserId(
    identity: string
): Promise<string> {

    const { data, error } =
        await institutionDb
            .from("users")
            .select("id")
            .or(
                `id.eq.${identity},auth_user_id.eq.${identity}`
            )
            .maybeSingle();

    if (error) {
        throw new Error(
            `Unable to resolve authenticated user: ${error.message}`
        );
    }

    if (!data?.id) {
        throw new Error(
            "Authenticated user profile was not found."
        );
    }

    return data.id;
}

async function createStudentAudit(
    req: Request,
    actionCode: string,
    entityId: string | null,
    oldValues: unknown,
    newValues: unknown
): Promise<void> {

    const identity = getActorIdentity(req);

    const actorUserId =
        await resolvePublicUserId(identity);

    const { error } =
        await institutionDb
            .from("audit_logs")
            .insert({
                actor_user_id: actorUserId,
                action_code: actionCode,
                module_code: "students",
                entity_type: "student",
                entity_id: entityId,
                old_values: oldValues,
                new_values: newValues,
            });

    if (error) {
        throw new Error(
            `Student audit logging failed: ${error.message}`
        );
    }
}

function cleanNullable(
    value: unknown
): string | null {

    if (
        value === undefined ||
        value === null
    ) {
        return null;
    }

    const result =
        String(value).trim();

    return result || null;
}

function normalizeCreateInput(
    input: CreateStudentInput
) {

    const studentNumber =
        input.studentNumber.trim();

    const firstName =
        input.firstName.trim();

    const lastName =
        input.lastName.trim();

    if (!input.institutionId.trim()) {
        throw new Error(
            "Institution is required."
        );
    }

    if (!studentNumber) {
        throw new Error(
            "Student number is required."
        );
    }

    if (!firstName) {
        throw new Error(
            "First name is required."
        );
    }

    if (!lastName) {
        throw new Error(
            "Last name is required."
        );
    }

    return {

        institution_id:
            input.institutionId.trim(),

        user_id:
            cleanNullable(input.userId),

        student_number:
            studentNumber,

        first_name:
            firstName,

        middle_name:
            cleanNullable(input.middleName),

        last_name:
            lastName,

        gender:
            cleanNullable(input.gender),

        date_of_birth:
            cleanNullable(input.dateOfBirth),

        nationality:
            cleanNullable(input.nationality),

        national_id:
            cleanNullable(input.nationalId),

        passport_number:
            cleanNullable(input.passportNumber),

        phone:
            cleanNullable(input.phone),

        email:
            cleanNullable(input.email),

        physical_address:
            cleanNullable(input.physicalAddress),

        postal_address:
            cleanNullable(input.postalAddress),

        emergency_contact_name:
            cleanNullable(input.emergencyContactName),

        emergency_contact_phone:
            cleanNullable(input.emergencyContactPhone),

        admission_year:
            input.admissionYear ?? null,

        entry_type:
            cleanNullable(input.entryType),

        student_status:
            input.studentStatus ??
            "ACTIVE",

        profile_photo_url:
            cleanNullable(input.profilePhotoUrl),

        notes:
            cleanNullable(input.notes),
    };
}

export async function listStudents(
    page = 1,
    limit = 25,
    search?: string,
    status?: string,
    institutionId?: string
) {

    const safePage =
        Number.isInteger(page) && page > 0
            ? page
            : 1;

    const safeLimit =
        Number.isInteger(limit) &&
        limit > 0 &&
        limit <= 100
            ? limit
            : 25;

    const from =
        (safePage - 1) * safeLimit;

    const to =
        from + safeLimit - 1;

    let query =
        institutionDb
            .from("students")
            .select(
                `
                id,
                institution_id,
                user_id,
                student_number,
                registration_number,
                source_index_number,
                source_exam_year,
                first_name,
                middle_name,
                last_name,
                gender,
                date_of_birth,
                nationality,
                national_id,
                passport_number,
                phone,
                email,
                physical_address,
                postal_address,
                emergency_contact_name,
                emergency_contact_phone,
                admission_year,
                entry_type,
                cohort_id,
                programme_id,
                programme_version_id,
                curriculum_id,
                entry_academic_year_id,
                source_type,
                source_reference,
                student_status,
                profile_photo_url,
                notes,
                created_at,
                updated_at,
                programmes(programme_code, programme_name),
                programme_versions(version_code, version_name),
                student_cohorts(cohort_code, cohort_name, entry_year),
                academic_years!students_entry_academic_year_id_fkey(year_code, year_name)
                `,
                {
                    count: "exact",
                }
            )
            .order(
                "created_at",
                {
                    ascending: false,
                }
            )
            .range(from, to);

    if (search?.trim()) {

        const value =
            search.trim();

        query =
            query.or(
                [
                    `student_number.ilike.%${value}%`,
                    `registration_number.ilike.%${value}%`,
                    `source_index_number.ilike.%${value}%`,
                    `first_name.ilike.%${value}%`,
                    `middle_name.ilike.%${value}%`,
                    `last_name.ilike.%${value}%`,
                    `email.ilike.%${value}%`,
                    `phone.ilike.%${value}%`,
                ].join(",")
            );
    }

    if (status?.trim()) {

        query =
            query.eq(
                "student_status",
                status.trim()
            );
    }

    if (institutionId?.trim()) {

        query =
            query.eq(
                "institution_id",
                institutionId.trim()
            );
    }

    const {
        data,
        error,
        count,
    } = await query;

    if (error) {
        throw new Error(
            `Unable to load students: ${error.message}`
        );
    }

    return {
        rows: data ?? [],
        page: safePage,
        limit: safeLimit,
        total: count ?? 0,
    };
}

export async function getStudentsSummary() {
    const [total, active, pending, linked] = await Promise.all([
        institutionDb.from("students").select("id", { count: "exact", head: true }).is("archived_at", null),
        institutionDb.from("students").select("id", { count: "exact", head: true }).eq("student_status", "ACTIVE").is("archived_at", null),
        institutionDb.from("students").select("id", { count: "exact", head: true }).eq("student_status", "PENDING_ACTIVATION").is("archived_at", null),
        institutionDb.from("students").select("id", { count: "exact", head: true }).not("user_id", "is", null).is("archived_at", null),
    ]);
    for (const result of [total, active, pending, linked]) {
        if (result.error) throw new Error(`Unable to load student summary: ${result.error.message}`);
    }
    return {
        total: total.count ?? 0,
        active: active.count ?? 0,
        pendingActivation: pending.count ?? 0,
        portalAccountsLinked: linked.count ?? 0,
    };
}

export async function getStudentById(
    id: string
) {

    const {
        data,
        error,
    } = await institutionDb
        .from("students")
        .select(
            `
            id,
            institution_id,
            user_id,
            student_number,
            registration_number,
            source_index_number,
            source_exam_year,
            first_name,
            middle_name,
            last_name,
            gender,
            date_of_birth,
            nationality,
            national_id,
            passport_number,
            phone,
            email,
            physical_address,
            postal_address,
            emergency_contact_name,
            emergency_contact_phone,
            admission_year,
            entry_type,
            cohort_id,
            programme_id,
            programme_version_id,
            curriculum_id,
            entry_academic_year_id,
            source_type,
            source_reference,
            student_status,
            profile_photo_url,
            notes,
            created_at,
            updated_at,
            programmes(programme_code, programme_name),
            programme_versions(version_code, version_name),
            student_cohorts(cohort_code, cohort_name, entry_year),
            academic_years!students_entry_academic_year_id_fkey(year_code, year_name)
            `
        )
        .eq("id", id)
        .maybeSingle();

    if (error) {
        throw new Error(
            `Unable to load student: ${error.message}`
        );
    }

    if (!data) {
        throw new Error(
            "Student not found."
        );
    }

    return data;
}

export async function getMyStudentRecord(
    req: Request
) {

    const identity =
        getActorIdentity(req);

    const {
        data,
        error,
    } = await institutionDb
        .from("students")
        .select(
            `
            id,
            institution_id,
            user_id,
            student_number,
            registration_number,
            source_index_number,
            source_exam_year,
            first_name,
            middle_name,
            last_name,
            gender,
            date_of_birth,
            nationality,
            national_id,
            passport_number,
            phone,
            email,
            physical_address,
            postal_address,
            emergency_contact_name,
            emergency_contact_phone,
            admission_year,
            entry_type,
            cohort_id,
            programme_id,
            programme_version_id,
            curriculum_id,
            entry_academic_year_id,
            source_type,
            source_reference,
            student_status,
            profile_photo_url,
            notes,
            created_at,
            updated_at,
            programmes(programme_code, programme_name),
            programme_versions(version_code, version_name),
            student_cohorts(cohort_code, cohort_name, entry_year),
            academic_years!students_entry_academic_year_id_fkey(year_code, year_name)
            `
        )
        .or(
            `user_id.eq.${identity}`
        )
        .maybeSingle();

    if (error) {
        throw new Error(
            `Unable to load current student record: ${error.message}`
        );
    }

    if (!data) {
        throw new Error(
            "No student record is linked to this account."
        );
    }

    return data;
}

export async function createStudent(
    req: Request,
    input: CreateStudentInput
) {

    const payload =
        normalizeCreateInput(input);

    const duplicate =
        await institutionDb
            .from("students")
            .select("id")
            .eq(
                "student_number",
                payload.student_number
            )
            .maybeSingle();

    if (duplicate.error) {
        throw new Error(
            `Unable to validate student number: ${duplicate.error.message}`
        );
    }

    if (duplicate.data) {
        throw new Error(
            "A student with this student number already exists."
        );
    }

    const {
        data,
        error,
    } =
        await institutionDb
            .from("students")
            .insert(payload)
            .select()
            .single();

    if (error || !data) {
        throw new Error(
            error?.message ||
            "Unable to create student."
        );
    }

    await createStudentAudit(
        req,
        "STUDENT_CREATE",
        data.id,
        null,
        data
    );

    return data;
}

export async function updateStudent(
    req: Request,
    id: string,
    input: UpdateStudentInput
) {

    const current =
        await getStudentById(id);

    const updates:
        Record<string, unknown> = {};

    if (
        input.institutionId !== undefined
    ) {
        updates.institution_id =
            input.institutionId.trim();
    }

    if (
        input.userId !== undefined
    ) {
        updates.user_id =
            cleanNullable(input.userId);
    }

    if (
        input.studentNumber !== undefined
    ) {
        updates.student_number =
            input.studentNumber.trim();
    }

    if (
        input.firstName !== undefined
    ) {
        updates.first_name =
            input.firstName.trim();
    }

    if (
        input.middleName !== undefined
    ) {
        updates.middle_name =
            cleanNullable(input.middleName);
    }

    if (
        input.lastName !== undefined
    ) {
        updates.last_name =
            input.lastName.trim();
    }

    if (
        input.gender !== undefined
    ) {
        updates.gender =
            cleanNullable(input.gender);
    }

    if (
        input.dateOfBirth !== undefined
    ) {
        updates.date_of_birth =
            cleanNullable(input.dateOfBirth);
    }

    if (
        input.nationality !== undefined
    ) {
        updates.nationality =
            cleanNullable(input.nationality);
    }

    if (
        input.nationalId !== undefined
    ) {
        updates.national_id =
            cleanNullable(input.nationalId);
    }

    if (
        input.passportNumber !== undefined
    ) {
        updates.passport_number =
            cleanNullable(input.passportNumber);
    }

    if (
        input.phone !== undefined
    ) {
        updates.phone =
            cleanNullable(input.phone);
    }

    if (
        input.email !== undefined
    ) {
        updates.email =
            cleanNullable(input.email);
    }

    if (
        input.physicalAddress !== undefined
    ) {
        updates.physical_address =
            cleanNullable(input.physicalAddress);
    }

    if (
        input.postalAddress !== undefined
    ) {
        updates.postal_address =
            cleanNullable(input.postalAddress);
    }

    if (
        input.emergencyContactName !== undefined
    ) {
        updates.emergency_contact_name =
            cleanNullable(
                input.emergencyContactName
            );
    }

    if (
        input.emergencyContactPhone !== undefined
    ) {
        updates.emergency_contact_phone =
            cleanNullable(
                input.emergencyContactPhone
            );
    }

    if (
        input.admissionYear !== undefined
    ) {
        updates.admission_year =
            input.admissionYear;
    }

    if (
        input.entryType !== undefined
    ) {
        updates.entry_type =
            cleanNullable(
                input.entryType
            );
    }

    if (
        input.studentStatus !== undefined
    ) {
        updates.student_status =
            input.studentStatus;
    }

    if (
        input.profilePhotoUrl !== undefined
    ) {
        updates.profile_photo_url =
            cleanNullable(
                input.profilePhotoUrl
            );
    }

    if (
        input.notes !== undefined
    ) {
        updates.notes =
            cleanNullable(input.notes);
    }

    if (
        Object.keys(updates).length === 0
    ) {
        return current;
    }

    const {
        data,
        error,
    } =
        await institutionDb
            .from("students")
            .update(updates)
            .eq("id", id)
            .select()
            .single();

    if (error || !data) {
        throw new Error(
            error?.message ||
            "Unable to update student."
        );
    }

    await createStudentAudit(
        req,
        "STUDENT_UPDATE",
        id,
        current,
        data
    );

    return data;
}
