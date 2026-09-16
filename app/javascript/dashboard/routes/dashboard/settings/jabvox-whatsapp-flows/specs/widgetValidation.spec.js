import { describe, it, expect } from 'vitest';
import {
  validateWidget,
  validateScreen,
  validateFlow,
} from '../widgetValidation';

const campoTexto = (props = {}) => ({
  id: 'c1',
  type: 'TextInput',
  props: { name: 'nombre', label: 'Nombre', ...props },
});

const botonEnviar = () => ({
  id: 'cf',
  type: 'Footer',
  props: { label: 'Enviar', action: { name: 'complete' } },
});

const pantalla = (components, extra = {}) => ({
  id: 'inicio',
  title: 'Inicio',
  components,
  ...extra,
});

describe('validateWidget', () => {
  it('acepta un widget bien configurado', () => {
    expect(validateWidget(campoTexto())).toEqual([]);
  });

  it('exige los campos obligatorios', () => {
    const errores = validateWidget(campoTexto({ label: '' }));
    expect(errores).toHaveLength(1);
    expect(errores[0].field).toBe('label');
  });

  it('avisa cuando el texto supera el máximo de Meta', () => {
    const errores = validateWidget(campoTexto({ label: 'x'.repeat(21) }));
    expect(errores[0].message).toContain('Máximo 20 caracteres');
  });

  // El nombre es la clave de la respuesta y va en las referencias ${form.campo}.
  it('rechaza un nombre de campo que no es un identificador', () => {
    expect(validateWidget(campoTexto({ name: 'mi campo' }))[0].field).toBe(
      'name'
    );
    expect(validateWidget(campoTexto({ name: '1campo' }))[0].field).toBe(
      'name'
    );
    expect(validateWidget(campoTexto({ name: 'campo_1' }))).toEqual([]);
  });

  it('avisa si dos campos comparten el nombre, porque la respuesta se pisaría', () => {
    const errores = validateWidget(campoTexto(), {
      usedNames: ['nombre', 'nombre'],
    });
    expect(errores[0].message).toContain('Ya hay otro campo');
  });

  describe('listas de opciones', () => {
    const conOpciones = data_source => ({
      id: 'c2',
      type: 'RadioButtonsGroup',
      props: { name: 'opcion', label: 'Elige', data_source },
    });

    it('exige al menos una opción', () => {
      expect(validateWidget(conOpciones([]))[0].field).toBe('data_source');
    });

    it('rechaza más opciones de las que Meta admite', () => {
      const muchas = Array.from({ length: 21 }, (_, i) => ({
        id: `o${i}`,
        title: `Opción ${i}`,
      }));
      expect(validateWidget(conOpciones(muchas))[0].message).toContain(
        'Máximo 20'
      );
    });

    it('avisa de identificadores repetidos y de textos que faltan', () => {
      const errores = validateWidget(
        conOpciones([
          { id: 'a', title: 'A' },
          { id: 'a', title: '' },
        ])
      );
      expect(errores.map(e => e.message).join(' ')).toContain('repetido');
      expect(errores.map(e => e.message).join(' ')).toContain('falta el texto');
    });
  });

  describe('acciones', () => {
    const conAccion = action => ({
      id: 'c3',
      type: 'Footer',
      props: { label: 'Ir', action },
    });

    it('exige destino en una navegación', () => {
      const errores = validateWidget(conAccion({ name: 'navigate', next: '' }));
      expect(errores[0].message).toContain('a qué pantalla');
    });

    it('impide que una pantalla navegue hacia sí misma', () => {
      const errores = validateWidget(
        conAccion({ name: 'navigate', next: 'inicio' }),
        { screenId: 'inicio' }
      );
      expect(errores[0].message).toContain('sí misma');
    });

    it('exige una URL https en un enlace', () => {
      expect(
        validateWidget(conAccion({ name: 'open_url', url: 'ejemplo.com' }))[0]
          .message
      ).toContain('https://');
      expect(
        validateWidget(conAccion({ name: 'open_url', url: 'https://ok.com' }))
      ).toEqual([]);
    });
  });
});

describe('validateScreen', () => {
  it('acepta una pantalla completa', () => {
    const errores = validateScreen(pantalla([campoTexto(), botonEnviar()]), {
      isLast: true,
    });
    expect(errores).toEqual({});
  });

  it('exige un botón al final', () => {
    const errores = validateScreen(pantalla([campoTexto()]));
    expect(errores.screen.join(' ')).toContain('botón');
  });

  it('exige que la última pantalla tenga alguna pregunta', () => {
    const soloTexto = {
      id: 't',
      type: 'TextBody',
      props: { text: 'Gracias' },
    };
    const errores = validateScreen(pantalla([soloTexto, botonEnviar()]), {
      isLast: true,
    });
    expect(errores.screen.join(' ')).toContain('al menos una pregunta');
  });

  it('respeta el límite de un solo botón por pantalla', () => {
    const errores = validateScreen(
      pantalla([campoTexto(), botonEnviar(), { ...botonEnviar(), id: 'cf2' }])
    );
    expect(errores.screen.join(' ')).toContain('Solo se permite');
  });

  it('señala el widget concreto que tiene el error', () => {
    const errores = validateScreen(
      pantalla([campoTexto({ label: '' }), botonEnviar()])
    );
    expect(errores.c1).toBeDefined();
    expect(errores.c1[0].field).toBe('label');
  });
});

describe('validateFlow', () => {
  it('da por válido un formulario bien armado', () => {
    const resultado = validateFlow([pantalla([campoTexto(), botonEnviar()])]);
    expect(resultado.valid).toBe(true);
    expect(resultado.messages).toEqual([]);
  });

  it('exige al menos una pantalla', () => {
    expect(validateFlow([]).valid).toBe(false);
  });

  it('nombra la pantalla en cada mensaje, para saber dónde está el fallo', () => {
    const resultado = validateFlow([
      pantalla([campoTexto({ label: '' }), botonEnviar()], { title: 'Datos' }),
    ]);
    expect(resultado.valid).toBe(false);
    expect(resultado.messages[0]).toContain('Datos:');
  });
});
