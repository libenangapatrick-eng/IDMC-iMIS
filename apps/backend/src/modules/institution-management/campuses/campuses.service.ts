import {
    institutionDb
} from "../shared/institution-db.js";

import type {
    CampusCreateInput,
    CampusUpdateInput
} from "../shared/types.js";

export async function listCampuses(params: {
    page: number;
    limit: number;
    search?: string;
    status?: string;
    institutionId?: string;
}) {
    const {
        page,
        limit,
        search,
        status,
        institutionId
    } = params;

    const from =
        (page - 1) * limit;

    const to =
        from + limit - 1;

    let query = institutionDb
        .from("campuses")
        .select("*", {
            count: "exact"
        })
        .order("campus_name", {
            ascending: true
        })
        .range(from, to);

    if (institutionId) {
        query = query.eq(
            "institution_id",
            institutionId
        );
    }

    if (search) {
        const safeSearch = search
            .replace(/,/g, "")
            .replace(/%/g, "");

        query = query.or(
            [
                `campus_code.ilike.%${safeSearch}%`,
                `campus_name.ilike.%${safeSearch}%`,
                `campus_type.ilike.%${safeSearch}%`,
                `city.ilike.%${safeSearch}%`,
                `region.ilike.%${safeSearch}%`
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

export async function getCampus(
    id: string
) {
    const {
        data,
        error
    } = await institutionDb
        .from("campuses")
        .select("*")
        .eq("id", id)
        .maybeSingle();

    if (error) {
        throw error;
    }

    return data;
}

export async function institutionExists(
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

export async function createCampus(
    input: CampusCreateInput
) {
    const {
        data,
        error
    } = await institutionDb
        .from("campuses")
        .insert({
            institution_id: input.institution_id,
            campus_code: input.campus_code.trim(),
            campus_name: input.campus_name.trim(),
            campus_type: input.campus_type ?? null,
            physical_address:
                input.physical_address ?? null,
            city: input.city ?? null,
            region: input.region ?? null,
            phone: input.phone ?? null,
            email: input.email ?? null,
            status: input.status ?? "ACTIVE"
        })
        .select("*")
        .single();

    if (error) {
        throw error;
    }

    return data;
}

export async function updateCampus(
    id: string,
    input: CampusUpdateInput
) {
    const {
        data,
        error
    } = await institutionDb
        .from("campuses")
        .update({
            ...input,
            updated_at: new Date().toISOString()
        })
        .eq("id", id)
        .select("*")
        .single();

    if (error) {
        throw error;
    }

    return data;
}


