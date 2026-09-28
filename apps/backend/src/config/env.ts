import "dotenv/config";
import { z } from "zod";

const optionalText = z.preprocess(
  (input) => typeof input === "string" && input.trim() === "" ? undefined : input,
  z.string().min(1).optional()
);

const optionalUrl = z.preprocess(
  (input) => typeof input === "string" && input.trim() === "" ? undefined : input,
  z.string().url().optional()
);

const envSchema = z.object({
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),

  PORT: z.coerce.number().default(4000),

  SUPABASE_URL: z
    .string()
    .url(),

  SUPABASE_SERVICE_ROLE_KEY: z
    .string()
    .min(1),

  JWT_SECRET: z
    .string()
    .min(16),

  JWT_EXPIRES_IN: z
    .string()
    .default("8h"),

  CORS_ORIGIN: z
    .string()
    .default("http://127.0.0.1:5500"),

  SMTP_HOST: z
    .string()
    .min(1),

  SMTP_PORT: z.coerce
    .number()
    .default(465),

  SMTP_SECURE: z
    .string()
    .default("true")
    .transform((value) => value === "true"),

  SMTP_USER: z
    .string()
    .email(),

  SMTP_PASSWORD: z
    .string()
    .min(1),

  SMTP_FROM_NAME: z
    .string()
    .default("IDMC Integrated Management Information System"),

  SMTP_FROM_EMAIL: z
    .string()
    .email(),

  FRONTEND_URL: z
    .string()
    .url()
    .default("http://127.0.0.1:5500/apps/frontend"),

  PAYMENT_PROVIDER_CALLBACK_SECRET: z
    .string()
    .min(24)
    .optional(),

  NATIONAL_RESULTS_PROVIDER_URL: optionalUrl,
  NATIONAL_RESULTS_PROVIDER_API_KEY: optionalText,
});

export const env = envSchema.parse(process.env);
