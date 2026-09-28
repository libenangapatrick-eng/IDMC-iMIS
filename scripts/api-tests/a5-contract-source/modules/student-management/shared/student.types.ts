export type StudentStatus =
    | "ACTIVE"
    | "INACTIVE"
    | "SUSPENDED"
    | "GRADUATED"
    | "WITHDRAWN"
    | "DEFERRED";

export interface CreateStudentInput {
    institutionId: string;
    userId?: string | null;

    studentNumber: string;

    firstName: string;
    middleName?: string | null;
    lastName: string;

    gender?: string | null;

    dateOfBirth?: string | null;

    nationality?: string | null;

    nationalId?: string | null;

    passportNumber?: string | null;

    phone?: string | null;

    email?: string | null;

    physicalAddress?: string | null;

    postalAddress?: string | null;

    emergencyContactName?: string | null;

    emergencyContactPhone?: string | null;

    admissionYear?: number | null;

    entryType?: string | null;

    studentStatus?: StudentStatus;

    profilePhotoUrl?: string | null;

    notes?: string | null;
}

export interface UpdateStudentInput {
    institutionId?: string;

    userId?: string | null;

    studentNumber?: string;

    firstName?: string;
    middleName?: string | null;
    lastName?: string;

    gender?: string | null;

    dateOfBirth?: string | null;

    nationality?: string | null;

    nationalId?: string | null;

    passportNumber?: string | null;

    phone?: string | null;

    email?: string | null;

    physicalAddress?: string | null;

    postalAddress?: string | null;

    emergencyContactName?: string | null;

    emergencyContactPhone?: string | null;

    admissionYear?: number | null;

    entryType?: string | null;

    studentStatus?: StudentStatus;

    profilePhotoUrl?: string | null;

    notes?: string | null;
}
