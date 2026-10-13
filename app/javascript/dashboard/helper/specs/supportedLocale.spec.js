import { normalizeSupportedLocale } from '../supportedLocale';

describe('normalizeSupportedLocale', () => {
  it.each([
    ['en', 'en'],
    ['es', 'es'],
    ['en-US', 'en'],
    ['es_MX', 'es'],
    ['fr', 'es'],
    [null, 'es'],
  ])('normalizes %s to %s', (locale, expected) => {
    expect(normalizeSupportedLocale(locale)).toBe(expected);
  });
});
