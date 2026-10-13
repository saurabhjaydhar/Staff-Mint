export type ErrorCode =
  | 'VALIDATION_ERROR'
  | 'UNAUTHORIZED'
  | 'TOKEN_EXPIRED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'RATE_LIMITED'
  | 'PLAN_LIMIT'
  | 'FEATURE_NOT_IN_PLAN'
  | 'DEVICE_NOT_BOUND'
  | 'OUTSIDE_GEOFENCE'
  | 'FACE_NOT_CLEAR'
  | 'OTP_INVALID'
  | 'CONSENT_REQUIRED'
  | 'COMPANY_SETUP_REQUIRED'
  | 'PROVIDER_ERROR'
  | 'INTERNAL';

const STATUS: Record<ErrorCode, number> = {
  VALIDATION_ERROR: 400,
  UNAUTHORIZED: 401,
  TOKEN_EXPIRED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  RATE_LIMITED: 429,
  PLAN_LIMIT: 402,
  FEATURE_NOT_IN_PLAN: 402,
  DEVICE_NOT_BOUND: 403,
  OUTSIDE_GEOFENCE: 422,
  FACE_NOT_CLEAR: 422,
  OTP_INVALID: 400,
  CONSENT_REQUIRED: 400,
  COMPANY_SETUP_REQUIRED: 409,
  PROVIDER_ERROR: 502,
  INTERNAL: 500,
};

export class AppError extends Error {
  readonly status: number;
  constructor(
    readonly code: ErrorCode,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.status = STATUS[code];
  }
}

export const notFound = (what: string) => new AppError('NOT_FOUND', `${what} not found`);
export const forbidden = (msg = 'You do not have access to this') => new AppError('FORBIDDEN', msg);
export const badRequest = (msg: string, details?: unknown) => new AppError('VALIDATION_ERROR', msg, details);
export const conflict = (msg: string, details?: unknown) => new AppError('CONFLICT', msg, details);
