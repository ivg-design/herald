import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const config = [
  { ignores: [".next/**", ".next-verify/**", "node_modules/**", "out/**", "next-env.d.ts", ".screenshots/**", "scratch-check.mts"] },
  ...nextVitals,
  ...nextTs,
];

export default config;
