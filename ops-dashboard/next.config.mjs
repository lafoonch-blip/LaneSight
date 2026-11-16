/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // The service_role key is read only in server code (lib/supabase.ts). Guard against it ever being
  // bundled for the browser: Next only exposes vars prefixed NEXT_PUBLIC_, and we never prefix it.
  poweredByHeader: false,
};
export default nextConfig;
