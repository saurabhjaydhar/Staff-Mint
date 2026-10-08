import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-3 p-6 text-center">
      <span className="grid h-12 w-12 place-items-center rounded-xl bg-mint-500 text-2xl font-bold text-white">₹</span>
      <h1 className="text-xl font-semibold">Page not found</h1>
      <Link href="/" className="text-sm font-medium text-mint-700 underline">
        Back to StaffMint
      </Link>
    </div>
  );
}
