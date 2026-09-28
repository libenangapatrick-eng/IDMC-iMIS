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
                student_status,
                profile_photo_url,
                notes,
                created_at,
                updated_at
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
            student_status,
            profile_photo_url,
            notes,
            created_at,
            updated_at
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
            applicant_id,
            source_application_id,
            admission_offer_id,
            programme_id,
            programme_version_id,
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
            student_status,
            profile_photo_url,
            admission_date,
            enrollment_date,
            expected_completion_date,
            activated_at,
            notes,
            created_at,
            updated_at
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

    const [applicantResult, profileResult, programmeResult, applicationResult, photoResult] =
        await Promise.all([
            institutionDb
                .from("applicants")
                .select("applicant_number, first_name, middle_name, last_name, gender, date_of_birth, nationality, national_id_number, passport_number, email, phone, address_line_1, address_line_2, city, district, region, country")
                .eq("id", data.applicant_id)
                .maybeSingle(),
            institutionDb
                .from("student_profiles")
                .select("preferred_name, first_name, middle_name, last_name, date_of_birth, gender, nationality, national_id_number, passport_number, phone, alternate_phone, email, profile_photo_url, disability_status, blood_group, marital_status")
                .eq("student_id", data.id)
                .maybeSingle(),
            institutionDb
                .from("programmes")
                .select("programme_code, programme_name, programme_type, award_level, duration_years, mode_of_study, status")
                .eq("id", data.programme_id)
                .maybeSingle(),
            institutionDb
                .from("applications")
                .select("application_number, academic_year_id, application_type, status, selection_status")
                .eq("id", data.source_application_id)
                .maybeSingle(),
            institutionDb
                .from("application_documents")
                .select("file_url")
                .eq("application_id", data.source_application_id)
                .eq("document_type", "PROFILE_PHOTO")
                .order("uploaded_at", { ascending: false })
                .limit(1)
                .maybeSingle(),
        ]);

    for (const result of [applicantResult, profileResult, programmeResult, applicationResult, photoResult]) {
        if (result.error) {
            throw new Error(`Unable to assemble student profile: ${result.error.message}`);
        }
    }

    const applicant = applicantResult.data as Record<string, any> | null;
    const profile = profileResult.data as Record<string, any> | null;
    const programme = programmeResult.data as Record<string, any> | null;
    const application = applicationResult.data as Record<string, any> | null;
    const admissionPhoto = photoResult.data as Record<string, any> | null;
    const firstName = data.first_name || profile?.first_name || applicant?.first_name || null;
    const middleName = data.middle_name || profile?.middle_name || applicant?.middle_name || null;
    const lastName = data.last_name || profile?.last_name || applicant?.last_name || null;

    return {
        ...data,
        first_name: firstName,
        middle_name: middleName,
        last_name: lastName,
        full_name: [firstName, middleName, lastName].filter(Boolean).join(" ") || data.student_number,
        gender: data.gender || profile?.gender || applicant?.gender || null,
        date_of_birth: data.date_of_birth || profile?.date_of_birth || applicant?.date_of_birth || null,
        nationality: data.nationality || profile?.nationality || applicant?.nationality || null,
        national_id: data.national_id || profile?.national_id_number || applicant?.national_id_number || null,
        passport_number: data.passport_number || profile?.passport_number || applicant?.passport_number || null,
        phone: data.phone || profile?.phone || applicant?.phone || null,
        email: data.email || profile?.email || applicant?.email || null,
        physical_address: data.physical_address || [applicant?.address_line_1, applicant?.address_line_2, applicant?.city, applicant?.district, applicant?.region, applicant?.country].filter(Boolean).join(", ") || null,
        profile_photo_url: data.profile_photo_url || profile?.profile_photo_url || admissionPhoto?.file_url || null,
        status: data.student_status,
        applicant_number: applicant?.applicant_number || null,
        application_number: application?.application_number || null,
        application_status: application?.status || null,
        academic_year_id: application?.academic_year_id || null,
        programme_code: programme?.programme_code || null,
        programme_name: programme?.programme_name || null,
        programme_type: programme?.programme_type || null,
        award_level: programme?.award_level || null,
        duration_years: programme?.duration_years || null,
        mode_of_study: programme?.mode_of_study || null,
    };
}

export async function getMyStudentPortalData(req: Request) {
    const student = await getMyStudentRecord(req) as Record<string, any>;
    const sid = String(student.id);

    const query = async (table: string, orderField = "created_at", required = false) => {
        const result = await institutionDb
            .from(table)
            .select("*")
            .eq("student_id", sid)
            .order(orderField, { ascending: false })
            .limit(200);
        if (result.error) {
            if (required) throw new Error(`Unable to load ${table}: ${result.error.message}`);
            console.warn(`Optional student portal source ${table} is unavailable: ${result.error.message}`);
            return [];
        }
        return result.data ?? [];
    };

    const [registrations, courses, attendance, courseResults, semesterResults, cgpaRecords, account, invoices, payments, documents, announcements] =
        await Promise.all([
            query("student_registrations", "created_at", true),
            query("course_registrations", "created_at", true),
            query("attendance_records"),
            query("course_results"),
            query("student_semester_results"),
            query("student_cgpa_records", "calculated_at"),
            institutionDb.from("student_financial_accounts").select("*").eq("student_id", sid).maybeSingle(),
            query("invoices", "invoice_date"),
            query("payments", "payment_date"),
            institutionDb.from("documents").select("*").in("entity_type", ["student", "students"]).eq("entity_id", sid).order("created_at", { ascending: false }).limit(200),
            institutionDb.from("announcements").select("*").in("status", ["PUBLISHED"]).order("publish_at", { ascending: false }).limit(100),
        ]);

    for (const result of [account, documents, announcements]) {
        if (result.error) console.warn(`Optional student portal data is unavailable: ${result.error.message}`);
    }

    const offeringIds = [...new Set((courses as Record<string, any>[]).map(row => row.course_offering_id).filter(Boolean))];
    let offerings: any[] = [];
    let timetableEntries: any[] = [];
    if (offeringIds.length) {
        const offeringResult = await institutionDb.from("course_offerings").select("*").in("id", offeringIds);
        const timetableResult = await institutionDb.from("timetable_entries").select("*").in("course_offering_id", offeringIds).order("created_at", { ascending: false });
        if (offeringResult.error || timetableResult.error) {
            throw new Error(`Unable to load course timetable: ${offeringResult.error?.message || timetableResult.error?.message}`);
        }
        offerings = offeringResult.data ?? [];
        timetableEntries = timetableResult.data ?? [];
    }

    const courseIds = [...new Set([...courses, ...offerings].map((row: any) => row.course_id).filter(Boolean))];
    let courseMaster: any[] = [];
    if (courseIds.length) {
        const result = await institutionDb.from("courses").select("id, course_code, course_name, course_short_name, credit_units").in("id", courseIds);
        if (result.error) throw new Error(`Unable to load course names: ${result.error.message}`);
        courseMaster = result.data ?? [];
    }

    const slotIds = [...new Set(timetableEntries.map(row => row.timetable_slot_id).filter(Boolean))];
    let timetableSlots: any[] = [];
    if (slotIds.length) {
        const result = await institutionDb.from("timetable_slots").select("*").in("id", slotIds);
        if (result.error) throw new Error(`Unable to load timetable slots: ${result.error.message}`);
        timetableSlots = result.data ?? [];
    }

    const offeringMap = new Map(offerings.map(row => [row.id, row]));
    const courseMap = new Map(courseMaster.map(row => [row.id, row]));
    const enrichedCourses = (courses as Record<string, any>[]).map(row => {
        const offering = offeringMap.get(row.course_offering_id) as Record<string, any> | undefined;
        const master = courseMap.get(row.course_id || offering?.course_id) as Record<string, any> | undefined;
        return {
            ...row,
            offering_code: offering?.offering_code || null,
            course_code: master?.course_code || null,
            course_name: master?.course_name || null,
            course_short_name: master?.course_short_name || null,
        };
    });

    const enrichedTimetable = timetableEntries.map(row => {
        const offering = offeringMap.get(row.course_offering_id) as Record<string, any> | undefined;
        const master = courseMap.get(offering?.course_id) as Record<string, any> | undefined;
        return { ...row, offering_code: offering?.offering_code || null, course_code: master?.course_code || null, course_name: master?.course_name || null };
    });

    return {
        student,
        registrations,
        course_registrations: enrichedCourses,
        course_offerings: offerings,
        courses: courseMaster,
        attendance_records: attendance,
        course_results: courseResults,
        semester_results: semesterResults,
        cgpa_records: cgpaRecords,
        timetable_entries: enrichedTimetable,
        timetable_slots: timetableSlots,
        financial_account: account.error ? null : account.data ?? null,
        invoices,
        payments,
        documents: documents.error ? [] : documents.data ?? [],
        announcements: announcements.error ? [] : announcements.data ?? [],
    };
}

export async function updateMyProfilePhoto(req: Request, value: unknown) {
    const student = await getMyStudentRecord(req) as Record<string, any>;
    const photo = String(value ?? "").trim();
    if (!/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=\s]+$/.test(photo)) {
        throw new Error("Profile photo must be a JPEG, PNG or WebP image.");
    }
    if (Buffer.byteLength(photo, "utf8") > 2 * 1024 * 1024) {
        throw new Error("Profile photo must be smaller than 2 MB.");
    }

    const studentUpdate = await institutionDb.from("students").update({ profile_photo_url: photo }).eq("id", student.id);
    if (studentUpdate.error) throw new Error(`Unable to save profile photo: ${studentUpdate.error.message}`);

    const profileUpdate = await institutionDb.from("student_profiles").upsert(
        { student_id: student.id, profile_photo_url: photo },
        { onConflict: "student_id" }
    );
    if (profileUpdate.error) throw new Error(`Unable to save student profile photo: ${profileUpdate.error.message}`);

    return { profile_photo_url: photo };
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
