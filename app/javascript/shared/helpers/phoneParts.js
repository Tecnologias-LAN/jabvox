import countries from 'shared/constants/countries.js';

/**
 * Separa un teléfono E.164 en país + número local, con el MISMO criterio que el
 * backend (Jabvox::PhoneParts): siempre gana el prefijo más largo que encaje.
 *
 * Existe porque `libphonenumber-js` no basta por sí solo en dos casos reales:
 *
 *  1. Un número que no reconoce como válido (por ejemplo un prefijo que no está
 *     en su base) devuelve null. Si el formulario se queda sin valor, al guardar
 *     BORRA el teléfono del contacto.
 *  2. Devuelve el código de llamada, no el del país elegido: "+16847331234"
 *     (Samoa Americana) sale como "+1" + "6847331234", mientras el backend lo
 *     guarda como "+1684" + "7331234". Las dos mitades acabarían descuadradas.
 *
 * Se usa como respaldo: primero se intenta con libphonenumber-js, y esto cubre
 * lo que aquella no resuelve.
 */

// Prefijos ordenados de más largo a más corto, para que "+1684" gane a "+1".
const dialCodesByLength = countries
  .map(country => country.dial_code)
  .filter(Boolean)
  .sort((a, b) => b.length - a.length);

// Mínimo de dígitos que debe quedar tras el prefijo para considerarlo un número
// local plausible. Evita partir "+5730" como país + "0".
const MIN_LOCAL_DIGITS = 4;

/**
 * @param {string} e164 teléfono en formato "+<dígitos>"
 * @returns {{dialCode: string, countryCode: string, national: string}|null}
 */
export const splitE164 = e164 => {
  const value = String(e164 ?? '').trim();
  if (!/^\+[1-9]\d{1,14}$/.test(value)) return null;

  const dialCode = dialCodesByLength.find(
    code =>
      value.startsWith(code) && value.length - code.length >= MIN_LOCAL_DIGITS
  );
  if (!dialCode) return null;

  const country = countries.find(c => c.dial_code === dialCode);
  return {
    dialCode,
    countryCode: country?.id ?? '',
    national: value.slice(dialCode.length),
  };
};
