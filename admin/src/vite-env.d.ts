/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL?: string;
  readonly VITE_TURNSTILE_SITE_KEY?: string;
  readonly VITE_APP_URL?: string;
  readonly VITE_ENV_LABEL?: string;
  /** "1" runs the panel on the in-memory admin API (src/mock), with no backend. */
  readonly VITE_MOCK?: string;
}
