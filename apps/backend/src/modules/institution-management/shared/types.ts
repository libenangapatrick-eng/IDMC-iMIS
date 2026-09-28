export type InstitutionStatus =
    | "ACTIVE"
    | "INACTIVE"
    | "DISABLED";

export interface ListQuery {
    page?: number;
    limit?: number;
    search?: string;
    status?: string;
}

export interface InstitutionCreateInput {
    institution_code: string;
    institution_name: string;
    short_name?: string | null;
    registration_number?: string | null;
    accreditation_number?: string | null;
    institution_type?: string | null;
    ownership_type?: string | null;
    email?: string | null;
    phone?: string | null;
    website?: string | null;
    physical_address?: string | null;
    postal_address?: string | null;
    city?: string | null;
    region?: string | null;
    country?: string | null;
    logo_url?: string | null;
    status?: string;
}

export type InstitutionUpdateInput =
    Partial<InstitutionCreateInput>;

export interface CampusCreateInput {
    institution_id: string;
    campus_code: string;
    campus_name: string;
    campus_type?: string | null;
    physical_address?: string | null;
    city?: string | null;
    region?: string | null;
    phone?: string | null;
    email?: string | null;
    status?: string;
}

export type CampusUpdateInput =
    Partial<CampusCreateInput>;

export interface SchoolCreateInput {
    institution_id: string;
    campus_id?: string | null;
    school_code: string;
    school_name: string;
    dean_title?: string | null;
    email?: string | null;
    phone?: string | null;
    status?: string;
}

export type SchoolUpdateInput =
    Partial<SchoolCreateInput>;

export interface DepartmentCreateInput {
    institution_id: string;
    school_id: string;
    department_code: string;
    department_name: string;
    head_title?: string | null;
    email?: string | null;
    phone?: string | null;
    status?: string;
}

export type DepartmentUpdateInput =
    Partial<DepartmentCreateInput>;


