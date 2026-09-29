import { backendMessage } from '../jabvox/backendMessage';

describe('backendMessage', () => {
  const err = data => ({ response: { data } });

  it('devuelve el mensaje del backend', () => {
    expect(backendMessage(err({ message: 'Inbox no puede estar vacío' }))).toBe(
      'Inbox no puede estar vacío'
    );
  });

  // El fallo real: vue-i18n lanzaba "Not allowed nest placeholder" al recibir llaves,
  // y la excepción rompía el guardado entero en vez de mostrar el aviso.
  it('quita las llaves que vue-i18n interpretaría como placeholder', () => {
    const msg = backendMessage(
      err({ message: 'Validation failed: {"campo"=>"valor"} inválido' })
    );
    expect(msg).not.toMatch(/[{}]/);
    expect(msg).toContain('Validation failed');
  });

  it('cae a `error` y luego a `errors` cuando no hay `message`', () => {
    expect(backendMessage(err({ error: 'sin permiso' }))).toBe('sin permiso');
    expect(backendMessage(err({ errors: ['uno', 'dos'] }))).toBe('uno, dos');
  });

  it('devuelve null si no hay nada utilizable, para usar el texto traducido', () => {
    expect(backendMessage(err({}))).toBeNull();
    expect(backendMessage(undefined)).toBeNull();
    expect(backendMessage(new Error('fallo de red'))).toBeNull();
  });

  it('no rompe si `errors` no es un array', () => {
    expect(backendMessage(err({ errors: 'texto suelto' }))).toBeNull();
  });
});
