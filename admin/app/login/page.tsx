"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState, type FormEvent } from "react";
import { Logo } from "@/components/AdminShell";
import { useAuth } from "@/components/providers";
import { Alert, Button, Field, Input } from "@/components/ui";
import { request, errorText } from "@/lib/api";
import type { Admin } from "@/lib/types";

/** Sign in: email + password, then the 6-digit code sent to that email. */
function LoginForm() {
  const { session, signIn } = useAuth();
  const router = useRouter();
  const next = useSearchParams().get("next");
  const dest = next && next.startsWith("/") && !next.startsWith("//") ? next : "/";
  const [step, setStep] = useState<"password" | "code">("password");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [ticket, setTicket] = useState("");
  const [sentTo, setSentTo] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (session) router.replace(dest);
  }, [session, router, dest]);

  async function submitPassword(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const r = await request<{ ticket: string; sentTo: string; devCode?: string }>("POST", "/admin-auth/login", { email, password }, { auth: false });
      setTicket(r.ticket);
      setSentTo(r.sentTo);
      setCode(r.devCode ?? "");
      setStep("code");
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  async function submitCode(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const r = await request<{ accessToken: string; expiresInSec: number; admin: Admin }>("POST", "/admin-auth/verify", { ticket, code }, { auth: false });
      signIn(r.accessToken, r.expiresInSec, r.admin);
      router.replace(dest);
    } catch (err) {
      setError(errorText(err));
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-gradient-to-b from-mint-50 to-slate-50 px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-8 flex justify-center">
          <Logo />
        </div>
        <div className="rounded-3xl bg-white p-6 shadow-sm ring-1 ring-slate-200">
          {step === "password" ? (
            <form onSubmit={submitPassword} className="space-y-4">
              <div>
                <h1 className="text-xl font-semibold">Sign in</h1>
                <p className="mt-1 text-sm text-slate-500">For the StaffMint team only.</p>
              </div>
              {error && <Alert>{error}</Alert>}
              <Field label="Email">{(id) => <Input id={id} type="email" autoComplete="username" inputMode="email" required value={email} onChange={(e) => setEmail(e.target.value)} />}</Field>
              <Field label="Password">
                {(id) => <Input id={id} type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} />}
              </Field>
              <Button type="submit" size="lg" loading={busy} className="w-full">
                Continue
              </Button>
            </form>
          ) : (
            <form onSubmit={submitCode} className="space-y-4">
              <div>
                <h1 className="text-xl font-semibold">Enter the code</h1>
                <p className="mt-1 text-sm text-slate-500">We emailed a 6-digit code to {sentTo}. It works for 10 minutes.</p>
              </div>
              {error && <Alert>{error}</Alert>}
              <Field label="Code">
                {(id) => (
                  <Input
                    id={id}
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    pattern="\d{6}"
                    maxLength={6}
                    required
                    autoFocus
                    value={code}
                    onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
                    className="text-center text-2xl tracking-[0.5em]"
                  />
                )}
              </Field>
              <Button type="submit" size="lg" loading={busy} disabled={code.length !== 6} className="w-full">
                Sign in
              </Button>
              <button
                type="button"
                className="w-full text-sm text-slate-500 underline"
                onClick={() => {
                  setStep("password");
                  setCode("");
                  setError(null);
                }}
              >
                Use a different account
              </button>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}
