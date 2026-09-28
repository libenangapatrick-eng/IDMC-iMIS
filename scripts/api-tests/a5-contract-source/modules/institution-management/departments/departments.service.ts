import {
    institutionDb
} from "../shared/institution-db.js";

import type {
    DepartmentCreateInput,
    DepartmentUpdateInput
} from "../shared/types.js";

export async function listDepartments(params: {
    page: number;
    limit: number;
    search?: string;
    status?: string;
    institutionId?: string;
    schoolId?: string;
}) {
    const {
        page,
        limit,
        search,
        status,
        institutionId,
        schoolId
    } = params;

    const from =
        (page - 1) * limit;

    const to =
        from + limit - 1;

    let query = institutionDb
        .from("departments")
        .select("*", {
            count: "exact"
        })
        .order("department_name", {
            ascending: true
        })
        .range(from, to);

    if (institutionId) {
        query = query.eq(
            "institution_id",
            institutionId
        );
    }

    if (schoolId) {
        query = query.eq(
            "school_id",
            schoolId
        );
    }

    if (search) {
        const safeSearch = search
            .replace(/,/g, "")
            .replace(/%/g, "");

        query = query.or(
            [
                `department_code.ilike.%${safeSearch}%`,
                `department_name.ilike.%${safeSearch}%`,
                `head_title.ilike.%${safeSearch}%`
            ].join(",")
        );
    }

    if (status) {
        query = query.eq(
            "status",
            status
        );
    }

    const {
        data,
        error,
        count
    } = await query;

    if (error) {
        throw error;
    }

    return {
        rows: data ?? [],
        total: count ?? 0
    };
}

export async function getDepartment(
    id: string
) {
    const {
        data,
        error
    } = await institutionDb
        .from("departments")
        .select("*")
        .eq("id", id)
        .maybeSingle();

    if (error) {
        throw error;
    }

    return data;
}

export async function departmentInstitutionExists(
    institutionId: string
) {
    const {
        data,
        error
    } = await institutionDb
        .from("institutions")
        .select("id")
        .eq("id", institutionId)
        .maybeSingle();

    if (error) {
        throw error;
    }

    return Boolean(data);
}

export async function schoolBelongsToInstitution(
    schoolId: string,
    institutionId: string
) {
    const {
        data,
        error
    } = await institutionDb
        .from("schools")
        .select("id")
        .eq("id", schoolId)
        .eq("institution_id", institutionId)
        .maybeSingle();

    if (error) {
        throw error;
    }

    return Boolean(data);
}

export async function createDepartment(
    input: DepartmentCreateInput
) {
    const {
        data,
        error
    } = await institutionDb
        .from("departments")
        .insert({
            institution_id:
                input.institution_id,
            school_id:
                input.school_id,
            department_code:
                input.department_code.trim(),
            department_name:
                input.department_name.trim(),
            head_title:
                input.head_title ??
                "Headof Department",
            email:
                input.email ?? null,
            phone:
                input.phone ?? null,
            status:
                input.status ?? "ACTIVE"
        })
        .select("*")
        .single();

    if (error) {
        throw error;
    }

    return data;
}

export async function updateDepartment(
    id: string,
    input: DepartmentUpdateInput
) {
    const {
        data,
        error
    } = await institutionDb
        .from("departments")
        .update({
            ...input,
            updated_at:
                new Date().toISOString()
        })
        .eq("id", id)
        .select("*")
        .single();

    if (error) {
        throw error;
    }

    return data;
}


