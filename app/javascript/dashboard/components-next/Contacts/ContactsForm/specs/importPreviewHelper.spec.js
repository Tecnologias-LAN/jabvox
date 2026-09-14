import {
  buildPreviewRows,
  importableCount,
  rowsWithPrefix,
  rowsAlreadyExisting,
} from '../importPreviewHelper';

describe('importPreviewHelper', () => {
  describe('buildPreviewRows', () => {
    it('extrae nombre, correo y teléfono de las columnas mapeadas', () => {
      const headers = ['name', 'email', 'phone_number'];
      const rows = [['Ana', 'ana@example.com', '3001234567']];

      expect(buildPreviewRows(headers, rows)).toEqual([
        { name: 'Ana', email: 'ana@example.com', phone_number: '3001234567' },
      ]);
    });

    it('envía el teléfono TAL CUAL: el prefijo lo aplica el backend según el país', () => {
      const rows = buildPreviewRows(
        ['name', 'phone_number'],
        [['Ana', '3001234567']]
      );

      expect(rows[0].phone_number).toBe('3001234567');
    });

    it('compone el nombre a partir de nombre y apellido cuando no hay columna name', () => {
      const headers = ['first_name', 'last_name', 'phone_number'];
      const rows = [['Ana', 'Pérez', '3001234567']];

      expect(buildPreviewRows(headers, rows)[0].name).toBe('Ana Pérez');
    });

    it('no rompe cuando falta una columna: devuelve cadena vacía', () => {
      const rows = buildPreviewRows(['name'], [['Ana']]);

      expect(rows[0]).toEqual({ name: 'Ana', email: '', phone_number: '' });
    });

    it('mantiene una entrada por fila del archivo', () => {
      const rows = buildPreviewRows(
        ['name', 'phone_number'],
        [
          ['Ana', '3001234567'],
          ['Luis', '3007654321'],
        ]
      );

      expect(rows).toHaveLength(2);
    });
  });

  describe('importableCount', () => {
    const counts = { nuevas: 10, duplicadas_bd: 4, duplicadas_archivo: 2 };

    it('con política skip solo cuenta las nuevas', () => {
      expect(importableCount(counts, 'skip')).toBe(10);
    });

    it('con política update suma también las que ya existen', () => {
      expect(importableCount(counts, 'update')).toBe(14);
    });

    it('nunca cuenta las repetidas dentro del archivo', () => {
      expect(importableCount(counts, 'update')).not.toBe(16);
    });

    it('devuelve 0 cuando no hay vista previa todavía', () => {
      expect(importableCount({}, 'skip')).toBe(0);
      expect(importableCount(undefined, 'skip')).toBe(0);
    });
  });

  describe('rowsWithPrefix', () => {
    const preview = {
      rows: [
        { index: 0, notice: 'prefijo_en_archivo', phone: '+573001234567' },
        { index: 1, notice: null, phone: '+573007654321' },
      ],
    };

    it('devuelve solo las filas que ya traían el prefijo en el archivo', () => {
      expect(rowsWithPrefix(preview)).toHaveLength(1);
      expect(rowsWithPrefix(preview)[0].index).toBe(0);
    });

    it('devuelve vacío sin vista previa', () => {
      expect(rowsWithPrefix(null)).toEqual([]);
    });
  });

  describe('rowsAlreadyExisting', () => {
    const preview = {
      rows: [
        { index: 0, status: 'duplicada_bd', existing_contact_id: 7 },
        { index: 1, status: 'nueva' },
        { index: 2, status: 'duplicada_archivo' },
      ],
    };

    it('devuelve solo los leads que ya existen en la cuenta', () => {
      const rows = rowsAlreadyExisting(preview);

      expect(rows).toHaveLength(1);
      expect(rows[0].existing_contact_id).toBe(7);
    });

    it('devuelve vacío sin vista previa', () => {
      expect(rowsAlreadyExisting(null)).toEqual([]);
    });
  });
});
