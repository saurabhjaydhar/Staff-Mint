// Free trial: every new owner tries all features for 14 days, then moves to Free.

import type { Trial } from "./types";

const DAY = 86_400_000;
const MONTHS_EN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Whole days left, counting today's part as one; 0 once ended. Counted here so an open tab stays right. */
export function trialDaysLeft(trial: Pick<Trial, "endsAt">, now = new Date()): number {
  const ms = new Date(trial.endsAt).getTime() - now.getTime();
  return ms <= 0 ? 0 : Math.ceil(ms / DAY);
}

export type TrialBannerState =
  | { kind: "none" }
  | { kind: "active"; days: number; soon: boolean; endsOn: string; planName: string }
  | { kind: "ended"; paused: string[] };

/** What the owner's banner shows. Ended banners stay hidden once dismissed for that trial. */
export function trialBanner(trial: Trial | null | undefined, opts: { isOwner: boolean; dismissedFor?: string | null }, now = new Date()): TrialBannerState {
  if (!trial || !opts.isOwner) return { kind: "none" };
  const days = trialDaysLeft(trial, now);
  if (days > 0) {
    const d = new Date(trial.endsAt);
    return { kind: "active", days, soon: days <= 3, endsOn: `${d.getDate()} ${MONTHS_EN[d.getMonth()]}`, planName: trial.planName };
  }
  if (opts.dismissedFor === trial.endsAt) return { kind: "none" };
  return { kind: "ended", paused: trial.paidFeatures.filter((f) => f !== "priority_support") };
}

export const trialDismissKey = (companyId: string) => `staffmint.trialEndedSeen.${companyId}`;
