// Navigation: four tabs at the bottom on phones, everything in the sidebar on bigger screens.

export interface NavItem {
  href: string;
  label: string;
  icon: string;
  /** Shown in the phone's bottom tab bar (the rest live under More). */
  tab?: boolean;
}

export const NAV: NavItem[] = [
  { href: "/", label: "Home", icon: "⌂", tab: true },
  { href: "/businesses", label: "Businesses", icon: "▦", tab: true },
  { href: "/messages", label: "Messages", icon: "✉", tab: true },
  { href: "/plans", label: "Plans & prices", icon: "₹" },
  { href: "/settings", label: "Settings & flags", icon: "⚙" },
  { href: "/recovery", label: "Number recovery", icon: "↺" },
  { href: "/activity", label: "Activity log", icon: "≡" },
  { href: "/admins", label: "Admins", icon: "☺" },
  { href: "/account", label: "My account", icon: "◉" },
];

export const TABS: NavItem[] = [...NAV.filter((n) => n.tab), { href: "/more", label: "More", icon: "⋯", tab: true }];

/** Is this nav item the current screen? Home matches only "/"; others match their subtree. */
export function isActive(href: string, pathname: string): boolean {
  if (href === "/") return pathname === "/";
  if (href === "/more") return pathname === "/more" || NAV.some((n) => !n.tab && n.href !== "/" && (pathname === n.href || pathname.startsWith(`${n.href}/`)));
  return pathname === href || pathname.startsWith(`${href}/`);
}
