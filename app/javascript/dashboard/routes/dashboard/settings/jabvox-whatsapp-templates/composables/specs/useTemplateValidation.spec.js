import { ref } from 'vue';
import { describe, it, expect } from 'vitest';
import {
  useTemplateValidation,
  detectVariables,
  hasEdgeVariable,
  hasConsecutiveVariables,
  hasMixedVariableTypes,
  isNonSequentialPositional,
} from '../useTemplateValidation';

const baseForm = (overrides = {}) => ({
  body: '',
  footer: '',
  header_type: 'NONE',
  header_content: '',
  buttons: [],
  ...overrides,
});

describe('useTemplateValidation', () => {
  describe('pure helpers', () => {
    it('detectVariables finds unique positional and NAMED tokens in order', () => {
      expect(detectVariables('Hola {{1}}, tu pedido {{1}} {{2}}')).toEqual([
        '1',
        '2',
      ]);
      expect(detectVariables('Hola {{nombre}}')).toEqual(['nombre']);
    });

    it('hasEdgeVariable detects a variable at the start or end', () => {
      expect(hasEdgeVariable('{{1}} bienvenido')).toBe(true);
      expect(hasEdgeVariable('Hola {{1}}')).toBe(true);
      expect(hasEdgeVariable('Hola {{1}}, bienvenido')).toBe(false);
      expect(hasEdgeVariable('')).toBe(false);
    });

    it('hasConsecutiveVariables detects two variables with no real text between them', () => {
      expect(hasConsecutiveVariables('Hola {{1}}{{2}} bienvenido')).toBe(true);
      expect(hasConsecutiveVariables('Hola {{1}} {{2}} bienvenido')).toBe(true);
      expect(hasConsecutiveVariables('Hola {{1}} y {{2}} bienvenido')).toBe(
        false
      );
    });

    it('hasMixedVariableTypes flags positional+NAMED mixed together (audit bug)', () => {
      expect(hasMixedVariableTypes(['1', 'nombre'])).toBe(true);
      expect(hasMixedVariableTypes(['1', '2'])).toBe(false);
      expect(hasMixedVariableTypes(['nombre', 'apellido'])).toBe(false);
    });

    it('isNonSequentialPositional flags gaps in positional numbering', () => {
      expect(isNonSequentialPositional(['1', '3'])).toBe(true);
      expect(isNonSequentialPositional(['1', '2', '3'])).toBe(false);
      expect(isNonSequentialPositional(['nombre'])).toBe(false);
    });
  });

  describe('reactive validation', () => {
    it('is valid for an empty form', () => {
      const form = ref(baseForm());
      const { isValid, errors } = useTemplateValidation(form);
      expect(isValid.value).toBe(true);
      expect(errors.value).toEqual([]);
    });

    it('flags a body over 1024 characters', () => {
      const form = ref(baseForm({ body: 'a'.repeat(1025) }));
      const { isValid, errors } = useTemplateValidation(form);
      expect(isValid.value).toBe(false);
      expect(errors.value.some(e => e.includes('1024'))).toBe(true);
    });

    it('flags a footer over 60 characters', () => {
      const form = ref(baseForm({ footer: 'x'.repeat(61) }));
      const { isValid } = useTemplateValidation(form);
      expect(isValid.value).toBe(false);
    });

    it('flags a variable at the edge of the body reactively', async () => {
      const form = ref(baseForm({ body: 'Hola {{1}}' }));
      const { isValid, bodyHasEdgeVar } = useTemplateValidation(form);
      expect(bodyHasEdgeVar.value).toBe(true);
      expect(isValid.value).toBe(false);

      form.value = { ...form.value, body: 'Hola {{1}}, bienvenido' };
      expect(bodyHasEdgeVar.value).toBe(false);
      expect(isValid.value).toBe(true);
    });

    it('flags consecutive variables', () => {
      const form = ref(baseForm({ body: 'Hola {{1}}{{2}}, bienvenido' }));
      const { isValid, bodyHasConsecutiveVars } = useTemplateValidation(form);
      expect(bodyHasConsecutiveVars.value).toBe(true);
      expect(isValid.value).toBe(false);
    });

    it('flags mixed positional + NAMED variables', () => {
      const form = ref(
        baseForm({ body: 'Hola {{1}}, tu pedido {{numero_pedido}} llegó' })
      );
      const { isValid, bodyHasMixedVarTypes } = useTemplateValidation(form);
      expect(bodyHasMixedVarTypes.value).toBe(true);
      expect(isValid.value).toBe(false);
    });

    it('flags non-sequential positional variables', () => {
      const form = ref(
        baseForm({ body: 'Hola {{1}}, tu código es {{3}}, gracias' })
      );
      const { isValid, bodyHasNonSequentialVars } = useTemplateValidation(form);
      expect(bodyHasNonSequentialVars.value).toBe(true);
      expect(isValid.value).toBe(false);
    });

    it('flags invalid NAMED variable formats', () => {
      const form = ref(
        baseForm({ body: 'Hola {{Nombre Empresa}}, bienvenido' })
      );
      const { isValid, invalidVars } = useTemplateValidation(form);
      expect(invalidVars.value).toContain('Nombre Empresa');
      expect(isValid.value).toBe(false);
    });

    it('accepts a well-formed sequential positional body', () => {
      const form = ref(
        baseForm({ body: 'Hola {{1}}, tu pedido {{2}} está listo' })
      );
      const { isValid } = useTemplateValidation(form);
      expect(isValid.value).toBe(true);
    });

    it('accepts a well-formed NAMED body', () => {
      const form = ref(
        baseForm({
          body: 'Hola {{nombre}}, tu pedido {{numero_pedido}} está listo',
        })
      );
      const { isValid } = useTemplateValidation(form);
      expect(isValid.value).toBe(true);
    });
  });

  describe('button validation', () => {
    const button = (type, overrides = {}) => ({
      type,
      text: 'Texto',
      url: '',
      phone_number: '',
      ...overrides,
    });

    it('rejects more than 10 combined buttons', () => {
      const buttons = Array.from({ length: 11 }, (_, i) =>
        button('QUICK_REPLY', { text: `Opción ${i}` })
      );
      const form = ref(baseForm({ body: 'Hola, elige', buttons }));
      const { isValid, buttonErrors } = useTemplateValidation(form);
      expect(isValid.value).toBe(false);
      expect(buttonErrors.value.some(e => e.includes('Máximo 10'))).toBe(true);
    });

    it('rejects COPY_CODE combined with another type', () => {
      const buttons = [
        button('COPY_CODE', { text: 'PROMO10' }),
        button('QUICK_REPLY', { text: 'Ver más' }),
      ];
      const form = ref(baseForm({ body: 'Hola', buttons }));
      const { isValid, buttonErrors } = useTemplateValidation(form);
      expect(isValid.value).toBe(false);
      expect(
        buttonErrors.value.some(e => e.includes('COPY_CODE no puede'))
      ).toBe(true);
    });

    it('rejects PHONE_NUMBER and VOICE_CALL together', () => {
      const buttons = [
        button('PHONE_NUMBER', {
          text: 'Llamar',
          phone_number: '+573001112233',
        }),
        button('VOICE_CALL', {
          text: 'Llamar ya',
          phone_number: '+573001112233',
        }),
      ];
      const form = ref(baseForm({ body: 'Hola', buttons }));
      const { isValid, buttonErrors } = useTemplateValidation(form);
      expect(isValid.value).toBe(false);
      expect(
        buttonErrors.value.some(e => e.includes('mutuamente excluyentes'))
      ).toBe(true);
    });

    it('rejects more than 2 URL buttons', () => {
      const buttons = [
        button('URL', { text: 'Uno', url: 'https://a.com' }),
        button('URL', { text: 'Dos', url: 'https://b.com' }),
        button('URL', { text: 'Tres', url: 'https://c.com' }),
      ];
      const form = ref(baseForm({ body: 'Hola', buttons }));
      const { isValid, buttonErrors } = useTemplateValidation(form);
      expect(isValid.value).toBe(false);
      expect(buttonErrors.value.some(e => e.includes('tipo URL'))).toBe(true);
    });

    it('rejects interleaved button types (not grouped)', () => {
      const buttons = [
        button('QUICK_REPLY', { text: 'A' }),
        button('URL', { text: 'B', url: 'https://a.com' }),
        button('QUICK_REPLY', { text: 'C' }),
      ];
      const form = ref(baseForm({ body: 'Hola', buttons }));
      const { isValid, buttonErrors } = useTemplateValidation(form);
      expect(isValid.value).toBe(false);
      expect(buttonErrors.value.some(e => e.includes('agrupados'))).toBe(true);
    });

    it('accepts grouped buttons of different types', () => {
      const buttons = [
        button('QUICK_REPLY', { text: 'A' }),
        button('QUICK_REPLY', { text: 'B' }),
        button('URL', { text: 'C', url: 'https://a.com' }),
      ];
      const form = ref(baseForm({ body: 'Hola', buttons }));
      const { isValid } = useTemplateValidation(form);
      expect(isValid.value).toBe(true);
    });

    it('accepts a single COPY_CODE button', () => {
      const buttons = [button('COPY_CODE', { text: 'PROMO10' })];
      const form = ref(baseForm({ body: 'Usa este código', buttons }));
      const { isValid } = useTemplateValidation(form);
      expect(isValid.value).toBe(true);
    });

    it('flags a button text over 25 characters', () => {
      const buttons = [button('QUICK_REPLY', { text: 'x'.repeat(26) })];
      const form = ref(baseForm({ body: 'Hola', buttons }));
      const { isValid, buttonErrors } = useTemplateValidation(form);
      expect(isValid.value).toBe(false);
      expect(buttonErrors.value.some(e => e.includes('25 caracteres'))).toBe(
        true
      );
    });
  });

  describe('counters', () => {
    it('exposes character counters for header/body/footer', () => {
      const form = ref(
        baseForm({
          body: 'Hola',
          footer: 'Pie',
          header_type: 'TEXT',
          header_content: 'Encabezado',
        })
      );
      const { counters } = useTemplateValidation(form);
      expect(counters.value.body).toEqual({ value: 4, max: 1024 });
      expect(counters.value.footer).toEqual({ value: 3, max: 60 });
      expect(counters.value.header).toEqual({ value: 10, max: 60 });
    });

    it('counterClass warns near the limit and errors over it', () => {
      const form = ref(baseForm());
      const { counterClass } = useTemplateValidation(form);
      expect(counterClass(10, 100)).toBe('text-n-slate-10');
      expect(counterClass(95, 100)).toBe('text-n-amber-11');
      expect(counterClass(101, 100)).toBe('text-n-ruby-11');
    });
  });
});
