import Link from "next/link";

export default function NotFound() {
  return (
    <div className="grid min-h-dvh place-items-center px-4 text-center">
      <div>
        <p className="text-lg font-semibold">Page not found</p>
        <Link href="/" className="mt-3 inline-block text-sm font-medium text-mint-700 underline">
          Go to Home
        </Link>
      </div>
    </div>
  );
}
