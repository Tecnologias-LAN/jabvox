// Utilidades de presentación del módulo Jabvox Drive.
import { formatBytes } from 'shared/helpers/FileHelper';

// Categorías de archivo usadas por el filtro de tipo y los iconos.
export const FILE_TYPES = ['image', 'audio', 'video', 'document'];

// Deriva una categoría a partir de content_type (o del campo `category` del backend).
export const resolveCategory = file => {
  if (file?.category && FILE_TYPES.includes(file.category)) {
    return file.category;
  }
  const ct = (file?.content_type || '').toLowerCase();
  if (ct.startsWith('image/')) return 'image';
  if (ct.startsWith('audio/')) return 'audio';
  if (ct.startsWith('video/')) return 'video';
  if (
    ct.includes('pdf') ||
    ct.includes('word') ||
    ct.includes('document') ||
    ct.includes('sheet') ||
    ct.includes('excel') ||
    ct.includes('presentation') ||
    ct.includes('text') ||
    ct.includes('csv')
  ) {
    return 'document';
  }
  return 'other';
};

// Icono lucide por categoría.
export const iconForCategory = category => {
  switch (category) {
    case 'image':
      return 'i-lucide-image';
    case 'audio':
      return 'i-lucide-music';
    case 'video':
      return 'i-lucide-video';
    case 'document':
      return 'i-lucide-file-text';
    default:
      return 'i-lucide-file';
  }
};

export const iconForFile = file => iconForCategory(resolveCategory(file));

// Formato humano de tamaño reutilizando el helper del repo.
export const humanSize = bytes => formatBytes(bytes || 0, 1);

// Un archivo retenido en excedentes (overflow) por cuota llena: existe y NO se
// perdió, pero no se puede ver/descargar hasta que se libere o amplíe el espacio.
// El backend lo marca con status 'restricted' + bucket 'overflow'.
export const isOverflow = file =>
  file?.status === 'restricted' || file?.bucket === 'overflow';

// Subida/ingesta aún en curso (no confirmada): tampoco se puede abrir todavía.
export const isPending = file => file?.status === 'pending';

// En cuarentena (retenido por análisis/integridad): tampoco se abre.
export const isQuarantined = file => file?.status === 'quarantined';

// ¿El archivo se puede abrir/previsualizar? Solo si está disponible.
export const isOpenable = file =>
  !isOverflow(file) && !isPending(file) && !isQuarantined(file);

// Bytes -> GB con 2 decimales (para la cuota).
export const bytesToGb = bytes => (bytes || 0) / 1024 ** 3;

// Extensión en minúsculas (sin punto) a partir del nombre del archivo.
export const fileExtension = file => {
  const name = (file?.filename || '').toLowerCase();
  const idx = name.lastIndexOf('.');
  return idx >= 0 ? name.slice(idx + 1) : '';
};

// Extensiones de texto que el navegador no marca como text/* pero son legibles.
const TEXT_EXTENSIONS = new Set([
  'txt',
  'json',
  'log',
  'md',
  'markdown',
  'xml',
  'yml',
  'yaml',
  'ini',
  'conf',
  'env',
  'js',
  'ts',
  'css',
  'html',
  'htm',
  'sql',
  'sh',
  'rb',
  'py',
  'java',
  'c',
  'cpp',
  'go',
  'rs',
  'php',
  'vue',
]);

export const isTextLike = file => {
  const ct = (file?.content_type || '').toLowerCase();
  if (ct.startsWith('text/')) return true;
  if (ct.includes('json') || ct.includes('xml') || ct.includes('javascript')) {
    return true;
  }
  return TEXT_EXTENSIONS.has(fileExtension(file));
};

// Ejecutables / scripts: el Drive es SOLO almacenamiento. Nunca se previsualizan
// (se descargan como attachment). Debe coincidir con EXECUTABLE_EXTENSIONS del
// DownloadsController, que fuerza la descarga server-side pase lo que pase.
export const EXECUTABLE_EXTENSIONS = new Set([
  'exe',
  'bat',
  'cmd',
  'com',
  'msi',
  'msp',
  'scr',
  'pif',
  'ps1',
  'psm1',
  'vbs',
  'vbe',
  'jse',
  'wsf',
  'wsh',
  'hta',
  'jar',
  'app',
  'dmg',
  'pkg',
  'deb',
  'rpm',
  'sh',
  'bash',
  'zsh',
  'csh',
  'run',
  'bin',
  'elf',
  'out',
  'dll',
  'so',
  'dylib',
  'apk',
  'ipa',
  'gadget',
  'reg',
  'lnk',
  'inf',
]);

export const isExecutable = file =>
  EXECUTABLE_EXTENSIONS.has(fileExtension(file));

// Preview inline soportado en el modal.
//   image | audio | video | pdf  -> render nativo del navegador (<img>/<audio>/…)
//   text                         -> texto plano / JSON formateado (fetch + <pre>)
//   csv                          -> tabla (fetch + parse)
//   docx                         -> Word a HTML (mammoth)
//   xlsx                         -> Excel a tabla (SheetJS)
//   none                         -> no previsualizable (solo descarga)
export const previewKind = file => {
  // Ejecutables: jamás se previsualizan (solo descarga). Guarda primero.
  if (isExecutable(file)) return 'none';

  const category = resolveCategory(file);
  if (category === 'image') return 'image';
  if (category === 'audio') return 'audio';
  if (category === 'video') return 'video';

  const ct = (file?.content_type || '').toLowerCase();
  const ext = fileExtension(file);

  if (ct.includes('pdf') || ext === 'pdf') return 'pdf';

  // Excel moderno (.xlsx). El formato viejo .xls (binario) no se soporta.
  if (
    ext === 'xlsx' ||
    ct.includes('spreadsheetml') ||
    ct === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ) {
    return 'xlsx';
  }

  // Word moderno (.docx). El formato viejo .doc (binario) no se soporta.
  if (
    ext === 'docx' ||
    ct.includes('wordprocessingml') ||
    ct ===
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ) {
    return 'docx';
  }

  // CSV / TSV como tabla.
  if (ext === 'csv' || ext === 'tsv' || ct.includes('csv')) return 'csv';

  // JSON y texto plano (incluye código, logs, markdown, etc.).
  if (isTextLike(file)) return 'text';

  return 'none';
};
