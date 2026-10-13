const SUPPORTED_LOCALES = ['en', 'es'];

export const normalizeSupportedLocale = locale => {
  const language = String(locale || '')
    .toLowerCase()
    .split(/[-_]/)[0];

  return SUPPORTED_LOCALES.includes(language) ? language : 'es';
};
