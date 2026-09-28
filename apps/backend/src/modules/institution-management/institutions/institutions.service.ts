import {
    institutionDb
} from "../shared/institution-db.js";

import type {
    InstitutionCreateInput,
    InstitutionUpdateInput
} from "../shared/types.js";

import {
    PRIMARY_INSTITUTION_CODE,
    PRIMARY_INSTITUTION_NAME
} from "../shared/single-institution.js";

export async function listInstitutions(params: {
    page: number;
    limit: number;
    search?: string;
    status?: string;
}) {
    const {
        page,
        limit,
        search,
        status
    } = params;

    const from =
        (page - 1) * limit;

    const to =
        from + limit - 1;

    let query = institutionDb
        .from("institutions")
        .select("*", {
            count: "exact"
        })
        .order("institution_name", {
            ascending: true
        })
        .eq("institution_code", PRIMARY_INSTITUTION_CODE)
        .range(from, to);

    if (search) {
        const safeSearch = search
            .replace(/,/g, "")
            .replace(/%/g, "");

        query = query.or(
            [
                `institution_code.ilike.%${safeSearch}%`,
                `institution_name.ilike.%${safeSearch}%`,
                `short_name.ilike.%${safeSearch}%`,
                `registration_number.ilike.%${safeSearch}%`,
                `accreditation_number.ilike.%${safeSearch}%`,
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

export async function getInstitution(
    id: string
) {
    const {
        data,
        error
    } = await institutionDb
        .from("institutions")
        .select("*")
        .eq("id", id)
        .eq("institution_code", PRIMARY_INSTITUTION_CODE)
        .maybeSingle();

    if (error) {
        throw error;
    }

    return data;
}

export async function getPrimaryInstitutionStructure() {
    const { data: institution, error: institutionError } =
        await institutionDb
            .from("institutions")
            .select("*")
            .eq("institution_code", PRIMARY_INSTITUTION_CODE)
            .maybeSingle();

    if (institutionError) throw institutionError;
    if (!institution) return null;

    const [campuses, schools, departments] = await Promise.all([
        institutionDb
            .from("campuses")
            .select("*")
            .eq("institution_id", institution.id)
            .order("campus_name"),
        institutionDb
            .from("schools")
            .select("*")
            .eq("institution_id", institution.id)
            .order("school_name"),
        institutionDb
            .from("departments")
            .select("*")
            .eq("institution_id", institution.id)
            .order("department_name")
    ]);

    const error = campuses.error || schools.error || departments.error;
    if (error) throw error;

    return {
        institution,
        campuses: campuses.data ?? [],
        schools: schools.data ?? [],
        departments: departments.data ?? []
    };
}

export async function createInstitution(
    input: InstitutionCreateInput
) {
    const payload = {
        institution_code: input.institution_code.trim(),
        institution_name: input.institution_name.trim(),
        short_name: input.short_name ?? null,
        registration_number: input.registration_number ?? null,
        accreditation_number: input.accreditation_number ?? null,
        institution_type: input.institution_type ?? null,
        ownership_type: input.ownership_type ?? null,
        email: input.email ?? null,
        phone: input.phone ?? null,
        website: input.website ?? null,
        physical_address: input.physical_address ?? null,
        postal_address: input.postal_address ?? null,
        city: input.city ?? null,
        region: input.region ?? null,
        country: input.country ?? "Tanzania",
        logo_url: input.logo_url ?? null,
        status: input.status ?? "ACTIVE"
    };

    const {
        data,
        error
    } = await institutionDb
        .from("institutions")
        .insert(payload)
        .select("*")
        .single();

    if (error) {
        throw error;
    }

    return data;
}

export async function updateInstitution(
    id: string,
    input: InstitutionUpdateInput
) {
    const {
        data,
        error
    } = await institutionDb
        .from("institutions")
        .update({
            ...input,
            institution_code: PRIMARY_INSTITUTION_CODE,
            institution_name: PRIMARY_INSTITUTION_NAME,
            short_name: "IDMS",
            status: "ACTIVE",
            updated_at: new Date().toISOString()
        })
        .eq("id", id)
        .eq("institution_code", PRIMARY_INSTITUTION_CODE)
        .select("*")
        .single();

    if (error) {
        throw error;
    }

    return data;
}


