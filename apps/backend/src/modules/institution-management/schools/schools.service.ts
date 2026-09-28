import {
    institutionDb
} from "../shared/institution-db.js";

import type {
    SchoolCreateInput,
    SchoolUpdateInput
} from "../shared/types.js";

export async function listSchools(params: {
    page: number;
    limit: number;
    search?: string;
    status?: string;
    institutionId?: string;
    campusId?: string;
}) {
    const {
        page,
        limit,
        search,
        status,
        institutionId,
        campusId
    } = params;

    const from =
        (page - 1) * limit;

    const to =
        from + limit - 1;

    let query = institutionDb
        .from("schools")
        .select("*", {
            count: "exact"
        })
        .order("school_name", {
            ascending: true
        })
        .range(from, to);

    if (institutionId) {
        query = query.eq(
            "institution_id",
            institutionId
        );
    }

    if (campusId) {
        query = query.eq(
            "campus_id",
            campusId
        );
    }

    if (search) {
        const safeSearch = search
            .replace(/,/g, "")
            .replace(/%/g, "");

        query = query.or(
            [
                `school_code.ilike.%${safeSearch}%`,
                `school_name.ilike.%${safeSearch}%`,
                `dean_title.ilike.%${safeSearch}%`
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

export async function getSchool(
    id: string
) {
    const {
        data,
        error
    } = await institutionDb
        .from("schools")
        .select("*")
        .eq("id", id)
        .maybeSingle();

    if (error) {
        throw error;
    }

    return data;
}

export async function schoolInstitutionExists(
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

export async function campusBelongsToInstitution(
    campusId: string,
    institutionId: string
) {
    const {
        data,
        error
    } = await institutionDb
        .from("campuses")
        .select("id")
        .eq("id", campusId)
        .eq("institution_id", institutionId)
        .maybeSingle();

    if (error) {
        throw error;
    }

    return Boolean(data);
}

export async function createSchool(
    input: SchoolCreateInput
) {
    const {
        data,
        error
    } = await institutionDb
        .from("schools")
        .insert({
            institution_id:
                input.institution_id,
            campus_id:
                input.campus_id ?? null,
            school_code:
                input.school_code.trim(),
            school_name:
                input.school_name.trim(),
            dean_title:
                input.dean_title ?? "Dean",
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

export async function updateSchool(
    id: string,
    input: SchoolUpdateInput
) {
    const {
        data,
        error
    } = await institutionDb
        .from("schools")
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


