import {
  formatWhatsappText,
  escapeHtml,
  textLength,
  toggleMarker,
} from '../whatsappFormatting';

describe('whatsappFormatting', () => {
  describe('#formatWhatsappText', () => {
    it('aplica negrita con UN asterisco', () => {
      expect(formatWhatsappText('hola *mundo*')).toBe(
        'hola <strong>mundo</strong>'
      );
    });

    // El error más común: WhatsApp no es Markdown. Con ** el cliente consume el
    // par interno y deja los asteriscos de fuera a la vista.
    it('con dos asteriscos deja los sobrantes visibles, como el cliente real', () => {
      expect(formatWhatsappText('**mundo**')).toBe('*<strong>mundo</strong>*');
    });

    it('aplica cursiva, tachado y monoespaciado', () => {
      expect(formatWhatsappText('_a_')).toBe('<em>a</em>');
      expect(formatWhatsappText('~a~')).toBe('<del>a</del>');
      expect(formatWhatsappText('```a```')).toBe('<code>a</code>');
    });

    it('anida formatos', () => {
      expect(formatWhatsappText('*_a_*')).toBe('<strong><em>a</em></strong>');
    });

    it('no formatea si el delimitador está pegado a un espacio', () => {
      expect(formatWhatsappText('* hola *')).toBe('* hola *');
    });

    it('no formatea a través de saltos de línea', () => {
      expect(formatWhatsappText('*hola\nmundo*')).toBe('*hola\nmundo*');
    });

    it('deja intacto un asterisco suelto', () => {
      expect(formatWhatsappText('2 * 3 = 6')).toBe('2 * 3 = 6');
    });

    it('formatea una variable', () => {
      expect(formatWhatsappText('*{{1}}*')).toBe('<strong>{{1}}</strong>');
    });

    // Sin esto, un <script> escrito en el cuerpo se ejecutaría en el panel.
    it('escapa el HTML antes de formatear', () => {
      expect(formatWhatsappText('<script>alert(1)</script>')).toBe(
        '&lt;script&gt;alert(1)&lt;/script&gt;'
      );
      expect(formatWhatsappText('*<img src=x onerror=alert(1)>*')).toBe(
        '<strong>&lt;img src=x onerror=alert(1)&gt;</strong>'
      );
    });

    it('devuelve cadena vacía para nulo o vacío', () => {
      expect(formatWhatsappText('')).toBe('');
      expect(formatWhatsappText(null)).toBe('');
      expect(formatWhatsappText(undefined)).toBe('');
    });
  });

  describe('#escapeHtml', () => {
    it('escapa los cinco caracteres peligrosos', () => {
      expect(escapeHtml('<>&"\'')).toBe('&lt;&gt;&amp;&quot;&#39;');
    });
  });

  describe('#textLength', () => {
    it('cuenta texto normal', () => {
      expect(textLength('hola')).toBe(4);
    });

    // '😊'.length es 2 en JavaScript: con límites de 25 en un botón, contar así
    // bloquea textos que sí caben.
    it('cuenta un emoji como UN carácter', () => {
      expect(textLength('😊')).toBe(1);
      expect(textLength('Comprar 🛒🔥')).toBe(10);
    });

    it('cuenta un emoji compuesto como UNO solo', () => {
      // '👨‍👩‍👧'.length es 8.
      expect(textLength('👨‍👩‍👧')).toBe(1);
    });

    it('devuelve 0 para vacío o nulo', () => {
      expect(textLength('')).toBe(0);
      expect(textLength(null)).toBe(0);
    });
  });

  describe('#toggleMarker', () => {
    it('envuelve la selección', () => {
      expect(toggleMarker('hola mundo', 5, 10, '*')).toEqual({
        value: 'hola *mundo*',
        start: 6,
        end: 11,
      });
    });

    it('desenvuelve si la selección ya está envuelta por fuera', () => {
      expect(toggleMarker('hola *mundo*', 6, 11, '*')).toEqual({
        value: 'hola mundo',
        start: 5,
        end: 10,
      });
    });

    it('desenvuelve si los marcadores están dentro de la selección', () => {
      expect(toggleMarker('hola *mundo*', 5, 12, '*')).toEqual({
        value: 'hola mundo',
        start: 5,
        end: 10,
      });
    });

    it('sin selección inserta los marcadores y deja el cursor en medio', () => {
      expect(toggleMarker('hola ', 5, 5, '*')).toEqual({
        value: 'hola **',
        start: 6,
        end: 6,
      });
    });

    it('acepta la selección al revés', () => {
      expect(toggleMarker('hola mundo', 10, 5, '*').value).toBe('hola *mundo*');
    });
  });
});
