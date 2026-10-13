import type { DictKey } from "./i18n";
import type { Role } from "./types";

export interface NavItem {
  href: string;
  label: DictKey;
  roles: Role[];
  icon: string;
}

// Owner sees everything. Manager (branch-scoped) gets day-to-day pages.
// CA sees only Reports + Payroll (read-only) + Export. Employees use the mobile app.
export const NAV_ITEMS: NavItem[] = [
  { href: "/clients", label: "nav_clients", roles: ["ca"], icon: "◫" },
  { href: "/", label: "nav_dashboard", roles: ["owner", "manager"], icon: "▦" },
  { href: "/import", label: "nav_import", roles: ["owner"], icon: "⇪" },
  { href: "/staff", label: "nav_staff", roles: ["owner", "manager"], icon: "☺" },
  { href: "/attendance", label: "nav_attendance", roles: ["owner", "manager"], icon: "✓" },
  { href: "/roster", label: "nav_roster", roles: ["owner", "manager"], icon: "▥" },
  { href: "/payroll", label: "nav_payroll", roles: ["owner", "ca"], icon: "₹" },
  { href: "/leaves", label: "nav_leaves", roles: ["owner", "manager"], icon: "☂" },
  { href: "/advances", label: "nav_advances", roles: ["owner"], icon: "⇄" },
  { href: "/reports", label: "nav_reports", roles: ["owner", "ca"], icon: "⎙" },
  { href: "/settings", label: "nav_settings", roles: ["owner"], icon: "⚙" },
  { href: "/billing", label: "nav_billing", roles: ["owner"], icon: "▤" },
  { href: "/audit", label: "nav_audit", roles: ["owner"], icon: "☰" },
];

export function navFor(role: Role): NavItem[] {
  return NAV_ITEMS.filter((n) => n.roles.includes(role));
}

/** Whether a role may open a path (exact page match on the first segment). */
export function canAccess(role: Role, pathname: string): boolean {
  const seg = "/" + (pathname.split("/").filter(Boolean)[0] || "");
  const item = NAV_ITEMS.find((n) => n.href === seg);
  if (!item) return true; // unknown pages are not gated here
  return item.roles.includes(role);
}

/** Landing page for a role. */
export function homeFor(role: Role): string {
  return navFor(role)[0]?.href ?? "/";
}

export function canExport(role: Role): boolean {
  return role === "owner" || role === "ca";
}

/** CA is read-only everywhere. */
export function isReadOnly(role: Role): boolean {
  return role === "ca";
}
