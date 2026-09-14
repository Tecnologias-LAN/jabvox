import { splitE164 } from '../phoneParts';

describe('splitE164', () => {
  it('separa el prefijo del número local', () => {
    expect(splitE164('+573001234567')).toEqual({
      dialCode: '+57',
      countryCode: 'CO',
      national: '3001234567',
    });
  });

  it('elige el prefijo MÁS LARGO, igual que el backend', () => {
    // +1684 es Samoa Americana. libphonenumber-js lo parte como +1, lo que
    // descuadraría las piezas respecto a lo que guardó el backend.
    expect(splitE164('+16847331234')).toMatchObject({
      dialCode: '+1684',
      national: '7331234',
    });
  });

  it('funciona con prefijos de un solo dígito', () => {
    expect(splitE164('+15417543010')).toMatchObject({
      dialCode: '+1',
      national: '5417543010',
    });
  });

  it('funciona con prefijos de tres dígitos', () => {
    expect(splitE164('+93700123456')).toMatchObject({
      dialCode: '+93',
      countryCode: 'AF',
      national: '700123456',
    });
  });

  it('devuelve null cuando no es un E.164', () => {
    expect(splitE164('3001234567')).toBeNull();
    expect(splitE164('no-es-numero')).toBeNull();
    expect(splitE164('')).toBeNull();
    expect(splitE164(null)).toBeNull();
    expect(splitE164(undefined)).toBeNull();
  });

  it('devuelve null si tras el prefijo no queda un número local plausible', () => {
    expect(splitE164('+5730')).toBeNull();
  });

  it('devuelve null para un prefijo que no existe en el catálogo', () => {
    // El componente lo trata como caso de respaldo y muestra el número entero,
    // en vez de dejar el campo vacío y borrar el teléfono al guardar.
    expect(splitE164('+999123456789')).toBeNull();
  });

  it('el número local nunca conserva el prefijo', () => {
    const parts = splitE164('+573001234567');

    expect(parts.national.startsWith('57')).toBe(false);
    expect(parts.national).toBe('3001234567');
  });

  it('recomponer las piezas devuelve el número original', () => {
    const original = '+573001234567';
    const { dialCode, national } = splitE164(original);

    expect(`${dialCode}${national}`).toBe(original);
  });
});
