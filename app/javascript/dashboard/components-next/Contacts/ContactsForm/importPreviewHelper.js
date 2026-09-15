/**
 * Ayudantes de la vista previa de importación de contactos.
 *
 * Se mantienen fuera del componente para poder probarlos: son la parte que
 * decide qué se le manda al backend y cuántos leads entrarían realmente.
 *
 * Regla del prefijo: el teléfono se envía TAL CUAL viene del archivo. Es el
 * backend quien le aplica el prefijo del país elegido, para que la vista previa
 * y la importación real produzcan exactamente el mismo número.
 */

/**
 * Reduce las filas del archivo a lo que define identidad (nombre, correo,
 * teléfono), que es lo único que necesita el endpoint de vista previa.
 *
 * @param {string[]} headers columnas ya mapeadas (name, email, phone_number…)
 * @param {Array<Array<string>>} rows filas de datos, sin la cabecera
 */
export const buildPreviewRows = (headers, rows) => {
  const idx = field => headers.indexOf(field);
  const nameIdx = idx('name');
  const firstIdx = idx('first_name');
  const lastIdx = idx('last_name');
  const emailIdx = idx('email');
  const phoneIdx = idx('phone_number');

  const at = (row, index) => (index >= 0 ? (row[index] ?? '') : '');

  return rows.map(row => {
    // Sin columna "name", se compone a partir de nombre y apellido.
    const composed = [at(row, firstIdx), at(row, lastIdx)]
      .filter(Boolean)
      .join(' ')
      .trim();

    return {
      name: nameIdx >= 0 ? at(row, nameIdx) : composed,
      email: at(row, emailIdx),
      phone_number: at(row, phoneIdx),
    };
  });
};

/**
 * Cuántas filas entrarían realmente según la política elegida para los leads
 * que ya existen: 'skip' solo monta las nuevas, 'update' también sobrescribe
 * las que ya estaban.
 */
export const importableCount = (counts = {}, duplicatePolicy = 'skip') => {
  const nuevas = counts.nuevas ?? 0;
  const existentes = counts.duplicadas_bd ?? 0;
  return duplicatePolicy === 'update' ? nuevas + existentes : nuevas;
};

/** Filas cuyo teléfono ya traía el prefijo internacional en el archivo. */
export const rowsWithPrefix = (preview = null) =>
  (preview?.rows ?? []).filter(row => row.notice === 'prefijo_en_archivo');

/** Filas que corresponden a un lead que ya existe en la cuenta. */
export const rowsAlreadyExisting = (preview = null) =>
  (preview?.rows ?? []).filter(row => row.status === 'duplicada_bd');
