export type AcademicStatus =
    | "ACTIVE"
    | "INACTIVE"
    | "COMPLETED"
    | "SUSPENDED"
    | "WITHDRAWN";

export interface CreateAcademicRecordInput {
    institutionId: string;
    studentId: string;

    academicYear?: string | null;
    semester?: string | null;

    programmeId?: string | null;
    courseCode?: string | null;
    courseName?: string | null;

    registrationStatus?: AcademicStatus;

    credits?: number | null;
    grade?: string | null;
    gradePoint?: number | null;

    notes?: string | null;
}

export interface UpdateAcademicRecordInput {
    institutionId?: string;
    studentId?: string;

    academicYear?: string | null;
    semester?: string | null;

    programmeId?: string | null;
    courseCode?: string | null;
    courseName?: string | null;

    registrationStatus?: AcademicStatus;

    credits?: number | null;
    grade?: string | null;
    gradePoint?: number | null;

    notes?: string | null;
}

export interface AcademicRecord {
    id: string;

    institution_id: string;
    student_id: string;

    academic_year: string | null;
    semester: string | null;

    programme_id: string | null;
    course_code: string | null;
    course_name: string | null;

    registration_status: AcademicStatus;

    credits: number | null;
    grade: string | null;
    grade_point: number | null;

    notes: string | null;

    created_at: string;
    updated_at: string;
}
