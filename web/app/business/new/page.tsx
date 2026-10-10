"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { LanguageToggle, Logo } from "@/components/AppShell";
import { CompanySetup } from "@/components/CompanySetup";
import { useAuth, useI18n } from "@/components/providers";
import { Loading } from "@/components/ui";

/** Create another business from any account (owner, manager, CA, or staff elsewhere). */
export default function NewBusinessPage() {
  const { status, signIn } = useAuth();
  const { t } = useI18n();
  const router = useRouter();

  useEffect(() => {
    if (status === "anonymous") router.replace("/login");
  }, [status, router]);

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gradient-to-b from-mint-50 to-slate-50 p-4">
      <div className="mb-6 flex w-full max-w-2xl items-center justify-between">
        <Logo />
        <LanguageToggle />
      </div>
      <div className="w-full max-w-2xl rounded-2xl bg-white p-6 shadow-sm ring-1 ring-slate-200">
        {status === "authenticated" ? (
          <CompanySetup
            another
            onCancel={() => (window.history.length > 1 ? router.back() : router.replace("/"))}
            onDone={async (tokens) => {
              await signIn(tokens);
              router.replace("/");
            }}
          />
        ) : (
          <Loading label={t("loading")} />
        )}
      </div>
    </div>
  );
}
