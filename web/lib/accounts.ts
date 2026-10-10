import type { DictKey } from "./i18n";
import type { Membership, Role } from "./types";

export const ROLE_KEY: Record<Role, DictKey> = { owner: "role_owner", manager: "role_manager", ca: "role_ca", employee: "role_employee" };

/** Badge colour per role, so "Owner" and "Staff" read differently at a glance. */
export const ROLE_TONE: Record<Role, "mint" | "violet" | "amber" | "sky"> = { owner: "mint", manager: "sky", ca: "violet", employee: "amber" };

/** The web dashboard is for owners, managers and accountants; staff accounts open in the mobile app. */
export function webCanOpen(m: Pick<Membership, "role">): boolean {
  return m.role !== "employee";
}

/** Accounts other than the open one that this browser can switch to. */
export function switchTargets(list: Membership[] | undefined, activeId: string | null | undefined): Membership[] {
  return (list ?? []).filter((m) => m.id !== activeId && webCanOpen(m));
}

/** "Add another business" once they own one, else "Start my own business". */
export function newBusinessLabel(list: Membership[] | undefined): DictKey {
  return (list ?? []).some((m) => m.role === "owner") ? "acc_new" : "acc_new_first";
}

const ICONS: Record<string, string> = { pharmacy: "✚", clinic: "✚", salon: "✂", restaurant: "☕", shop: "🛍", office: "▣", factory: "⚙" };
export function businessIcon(type: string | null | undefined): string {
  return ICONS[type ?? ""] ?? "🏪";
}
