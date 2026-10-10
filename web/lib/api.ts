// Small typed client for the StaffMint API v1 (see docs/API.md).
// - Unwraps `{ data }` envelopes, parses `{ error: { code, message, details } }` into ApiError.
// - Attaches the bearer token; on 401 TOKEN_EXPIRED it refreshes once via /auth/refresh
//   (refresh-token rotation, single-flight for concurrent requests) and retries the request.

import { localStorageTokenStore, type TokenStore } from "./tokens";
import type { Lang, Tokens } from "./types";

export const DEFAULT_API_BASE_URL = "http://localhost:4000/api/v1";

export type ApiErrorCode =
  | "VALIDATION_ERROR"
  | "UNAUTHORIZED"
  | "TOKEN_EXPIRED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "RATE_LIMITED"
  | "PLAN_LIMIT"
  | "FEATURE_NOT_IN_PLAN"
  | "DEVICE_NOT_BOUND"
  | "OUTSIDE_GEOFENCE"
  | "OTP_INVALID"
  | "COMPANY_SETUP_REQUIRED"
  | "INTERNAL"
  | "NETWORK_ERROR"
  | (string & {});

export class ApiError extends Error {
  readonly status: number;
  readonly code: ApiErrorCode;
  readonly details?: unknown;

  constructor(status: number, code: ApiErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export function isApiError(e: unknown): e is ApiError {
  return e instanceof ApiError;
}

/** Human readable message for any thrown value. */
export function errorMessage(e: unknown): string {
  if (e instanceof ApiError) return e.message || e.code;
  if (e instanceof Error) return e.message;
  return String(e);
}

/** Parse an error response body into an ApiError. Never throws. */
export async function parseErrorResponse(res: Response): Promise<ApiError> {
  let body: unknown = null;
  try {
    const text = await res.text();
    body = text ? JSON.parse(text) : null;
  } catch {
    body = null;
  }
  const err = (body as { error?: { code?: string; message?: string; details?: unknown } } | null)?.error;
  if (err && typeof err === "object") {
    return new ApiError(
      res.status,
      err.code || defaultCodeForStatus(res.status),
      err.message || res.statusText || "Request failed",
      err.details,
    );
  }
  return new ApiError(res.status, defaultCodeForStatus(res.status), res.statusText || `Request failed (${res.status})`);
}

function defaultCodeForStatus(status: number): ApiErrorCode {
  switch (status) {
    case 400:
      return "VALIDATION_ERROR";
    case 401:
      return "UNAUTHORIZED";
    case 402:
      return "PLAN_LIMIT";
    case 403:
      return "FORBIDDEN";
    case 404:
      return "NOT_FOUND";
    case 409:
      return "CONFLICT";
    case 429:
      return "RATE_LIMITED";
    default:
      return "INTERNAL";
  }
}

/** Extract filename from a Content-Disposition header. */
export function filenameFromDisposition(header: string | null): string | null {
  if (!header) return null;
  const star = /filename\*\s*=\s*(?:UTF-8'')?([^;]+)/i.exec(header);
  if (star) {
    try {
      return decodeURIComponent(star[1].trim().replace(/^"|"$/g, ""));
    } catch {
      /* fall through */
    }
  }
  const plain = /filename\s*=\s*"?([^";]+)"?/i.exec(header);
  return plain ? plain[1].trim() : null;
}

export type Query = Record<string, string | number | boolean | null | undefined>;

export interface RequestOptions {
  query?: Query;
  /** JSON body (object) or FormData (multipart). */
  body?: unknown;
  /** Skip auth header + refresh logic (public endpoints). */
  auth?: boolean;
  signal?: AbortSignal;
}

export interface ApiClientOptions {
  baseUrl?: string;
  fetch?: typeof fetch;
  tokens?: TokenStore;
  getLanguage?: () => Lang | undefined;
  /** Called when the session is unrecoverable (refresh failed / unauthorized). */
  onAuthFailure?: (err: ApiError) => void;
}

export interface Envelope<T> {
  data: T;
  meta?: Record<string, unknown>;
}

export class ApiClient {
  readonly baseUrl: string;
  readonly tokens: TokenStore;
  private readonly fetchImpl: typeof fetch;
  private readonly getLanguage?: () => Lang | undefined;
  onAuthFailure?: (err: ApiError) => void;
  private refreshing: Promise<Tokens> | null = null;

  constructor(opts: ApiClientOptions = {}) {
    this.baseUrl = (opts.baseUrl || DEFAULT_API_BASE_URL).replace(/\/+$/, "");
    this.fetchImpl = opts.fetch || ((...args: Parameters<typeof fetch>) => fetch(...args));
    this.tokens = opts.tokens || localStorageTokenStore;
    this.getLanguage = opts.getLanguage;
    this.onAuthFailure = opts.onAuthFailure;
  }

  url(path: string, query?: Query): string {
    const p = path.startsWith("/") ? path : `/${path}`;
    let u = `${this.baseUrl}${p}`;
    if (query) {
      const qs = new URLSearchParams();
      for (const [k, v] of Object.entries(query)) {
        if (v === undefined || v === null || v === "") continue;
        qs.set(k, String(v));
      }
      const s = qs.toString();
      if (s) u += `${u.includes("?") ? "&" : "?"}${s}`;
    }
    return u;
  }

  private buildInit(method: string, opts: RequestOptions, accessToken: string | null): RequestInit {
    const headers: Record<string, string> = { Accept: "application/json" };
    const lang = this.getLanguage?.();
    if (lang) headers["Accept-Language"] = lang;
    if (accessToken && opts.auth !== false) headers.Authorization = `Bearer ${accessToken}`;
    let body: BodyInit | undefined;
    if (opts.body instanceof FormData) {
      body = opts.body; // browser sets multipart boundary
    } else if (opts.body !== undefined) {
      headers["Content-Type"] = "application/json";
      body = JSON.stringify(opts.body);
    }
    return { method, headers, body, signal: opts.signal };
  }

  /** Low-level: performs the request with auth + one refresh retry. Returns the OK Response. */
  async send(method: string, path: string, opts: RequestOptions = {}): Promise<Response> {
    const doFetch = async (token: string | null) => {
      try {
        return await this.fetchImpl(this.url(path, opts.query), this.buildInit(method, opts, token));
      } catch (e) {
        if ((e as Error)?.name === "AbortError") throw e;
        throw new ApiError(0, "NETWORK_ERROR", "Could not reach the StaffMint server. Check your connection.");
      }
    };

    const useAuth = opts.auth !== false;
    let res = await doFetch(useAuth ? this.tokens.get()?.accessToken ?? null : null);
    if (res.ok) return res;

    let err = await parseErrorResponse(res);
    if (useAuth && res.status === 401 && err.code === "TOKEN_EXPIRED" && this.tokens.get()?.refreshToken) {
      const fresh = await this.refresh(); // throws (and signals auth failure) if refresh fails
      res = await doFetch(fresh.accessToken);
      if (res.ok) return res;
      err = await parseErrorResponse(res);
    }
    if (useAuth && res.status === 401) {
      this.tokens.clear();
      this.onAuthFailure?.(err);
    }
    throw err;
  }

  /** Refresh tokens (single-flight). Rotation: the old refresh token becomes invalid. */
  refresh(): Promise<Tokens> {
    if (this.refreshing) return this.refreshing;
    const current = this.tokens.get();
    const run = async (): Promise<Tokens> => {
      if (!current?.refreshToken) {
        const e = new ApiError(401, "UNAUTHORIZED", "Session expired. Please log in again.");
        this.tokens.clear();
        this.onAuthFailure?.(e);
        throw e;
      }
      let res: Response;
      try {
        res = await this.fetchImpl(this.url("/auth/refresh"), {
          method: "POST",
          headers: { "Content-Type": "application/json", Accept: "application/json" },
          body: JSON.stringify({ refreshToken: current.refreshToken }),
        });
      } catch {
        throw new ApiError(0, "NETWORK_ERROR", "Could not reach the StaffMint server. Check your connection.");
      }
      if (!res.ok) {
        const e = await parseErrorResponse(res);
        this.tokens.clear();
        this.onAuthFailure?.(e);
        throw e;
      }
      const body = (await res.json()) as Envelope<Tokens & { accountChange?: unknown }>;
      const tokens = { accessToken: body.data.accessToken, refreshToken: body.data.refreshToken };
      this.tokens.set(tokens);
      // The refresh moved this browser to another business (access ended / role changed): the app reloads and says why.
      if (body.data.accountChange && typeof window !== "undefined") {
        window.dispatchEvent(new CustomEvent("staffmint:account-changed", { detail: body.data.accountChange }));
      }
      return tokens;
    };
    this.refreshing = run().finally(() => {
      this.refreshing = null;
    });
    return this.refreshing;
  }

  /** JSON request returning the full envelope `{data, meta}`. */
  async requestEnvelope<T>(method: string, path: string, opts: RequestOptions = {}): Promise<Envelope<T>> {
    const res = await this.send(method, path, opts);
    if (res.status === 204) return { data: undefined as T };
    const text = await res.text();
    if (!text) return { data: undefined as T };
    try {
      return JSON.parse(text) as Envelope<T>;
    } catch {
      throw new ApiError(res.status, "INTERNAL", "Unexpected response from server");
    }
  }

  /** JSON request returning the unwrapped `data`. */
  async request<T>(method: string, path: string, opts: RequestOptions = {}): Promise<T> {
    return (await this.requestEnvelope<T>(method, path, opts)).data;
  }

  get<T>(path: string, query?: Query, opts: Omit<RequestOptions, "query"> = {}) {
    return this.request<T>("GET", path, { ...opts, query });
  }
  post<T>(path: string, body?: unknown, opts: RequestOptions = {}) {
    return this.request<T>("POST", path, { ...opts, body: body ?? {} });
  }
  patch<T>(path: string, body: unknown, opts: RequestOptions = {}) {
    return this.request<T>("PATCH", path, { ...opts, body });
  }
  put<T>(path: string, body: unknown, opts: RequestOptions = {}) {
    return this.request<T>("PUT", path, { ...opts, body });
  }
  delete<T>(path: string, opts: RequestOptions = {}) {
    return this.request<T>("DELETE", path, opts);
  }

  /** Download a file (reports, export) with auth. */
  async download(path: string, query?: Query, fallbackName = "download"): Promise<{ blob: Blob; filename: string }> {
    const res = await this.send("GET", path, { query });
    const blob = await res.blob();
    const filename = filenameFromDisposition(res.headers.get("Content-Disposition")) || fallbackName;
    return { blob, filename };
  }
}

const envBase = process.env.NEXT_PUBLIC_API_BASE_URL;

/** Language getter wired up by the i18n provider. */
let currentLang: Lang | undefined;
export function setApiLanguage(lang: Lang) {
  currentLang = lang;
}

/** App-wide client instance. */
export const api = new ApiClient({
  baseUrl: envBase || DEFAULT_API_BASE_URL,
  getLanguage: () => currentLang,
  onAuthFailure: () => {
    if (typeof window !== "undefined") window.dispatchEvent(new Event("staffmint:auth-failure"));
  },
});
