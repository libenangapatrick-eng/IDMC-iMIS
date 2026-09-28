import { getSupabase } from "../../config/database.js";

import type {
    AcademicRecord,
    CreateAcademicRecordInput,
    UpdateAcademicRecordInput
} from "./shared/academics.types.js";

export class AcademicsService {

    async list(
        institutionId: string
    ): Promise<AcademicRecord[]> {

        const supabase = getSupabase();

        const { data, error } = await supabase
            .from("academic_records")
            .select("*")
            .eq("institution_id", institutionId)
            .order("created_at", { ascending: false });

        if (error) {
            throw new Error(
                `Failed to list academic records: ${error.message}`
            );
        }

        return (data || []) as AcademicRecord[];
    }

    async getById(
        institutionId: string,
        id: string
    ): Promise<AcademicRecord | null> {

        const supabase = getSupabase();

        const { data, error } = await supabase
            .from("academic_records")
            .select("*")
            .eq("institution_id", institutionId)
            .eq("id", id)
            .maybeSingle();

        if (error) {
            throw new Error(
                `Failed to get academic record: ${error.message}`
            );
        }

        return data as AcademicRecord | null;
    }

    async create(
        input: CreateAcademicRecordInput
    ): Promise<AcademicRecord> {

        const supabase = getSupabase();

        const payload = {
            institution_id: input.institutionId,
            student_id: input.studentId,

            academic_year:
                input.academicYear ?? null,

            semester:
                input.semester ?? null,

            programme_id:
                input.programmeId ?? null,

            course_code:
                input.courseCode ?? null,

            course_name:
                input.courseName ?? null,

            registration_status:
                input.registrationStatus ?? "ACTIVE",

            credits:
                input.credits ?? null,

            grade:
                input.grade ?? null,

            grade_point:
                input.gradePoint ?? null,

            notes:
                input.notes ?? null
        };

        const { data, error } = await supabase
            .from("academic_records")
            .insert(payload)
            .select("*")
            .single();

        if (error) {
            throw new Error(
                `Failed to create academic record: ${error.message}`
            );
        }

        return data as AcademicRecord;
    }

    async update(
        id: string,
        input: UpdateAcademicRecordInput
    ): Promise<AcademicRecord> {

        const supabase = getSupabase();

        const payload: Record<string, unknown> = {};

        if (input.institutionId !== undefined) {
            payload.institution_id =
                input.institutionId;
        }

        if (input.studentId !== undefined) {
            payload.student_id =
                input.studentId;
        }

        if (input.academicYear !== undefined) {
            payload.academic_year =
                input.academicYear;
        }

        if (input.semester !== undefined) {
            payload.semester =
                input.semester;
        }

        if (input.programmeId !== undefined) {
            payload.programme_id =
                input.programmeId;
        }

        if (input.courseCode !== undefined) {
            payload.course_code =
                input.courseCode;
        }

        if (input.courseName !== undefined) {
            payload.course_name =
                input.courseName;
        }

        if (input.registrationStatus !== undefined) {
            payload.registration_status =
                input.registrationStatus;
        }

        if (input.credits !== undefined) {
            payload.credits =
                input.credits;
        }

        if (input.grade !== undefined) {
            payload.grade =
                input.grade;
        }

        if (input.gradePoint !== undefined) {
            payload.grade_point =
                input.gradePoint;
        }

        if (input.notes !== undefined) {
            payload.notes =
                input.notes;
        }

        const { data, error } = await supabase
            .from("academic_records")
            .update(payload)
            .eq("id", id)
            .select("*")
            .single();

        if (error) {
            throw new Error(
                `Failed to update academic record: ${error.message}`
            );
        }

        return data as AcademicRecord;
    }

    async remove(
        institutionId: string,
        id: string
    ): Promise<void> {

        const supabase = getSupabase();

        const { error } = await supabase
            .from("academic_records")
            .delete()
            .eq("institution_id", institutionId)
            .eq("id", id);

        if (error) {
            throw new Error(
                `Failed to delete academic record: ${error.message}`
            );
        }
    }
}

export const academicsService =
    new AcademicsService();
