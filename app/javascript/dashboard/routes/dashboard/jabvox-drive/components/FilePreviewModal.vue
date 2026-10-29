<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import driveAPI from 'dashboard/api/jabvox/drive';
import {
  previewKind,
  iconForFile,
  humanSize,
  resolveCategory,
  isOverflow,
  isPending,
  isQuarantined,
} from '../helper';

const props = defineProps({
  file: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close', 'download']);

const { t } = useI18n();

// Tope para preview que requiere descargar el contenido completo al navegador
// (texto/JSON/CSV/Word/Excel). Por encima de esto NO se previsualiza: se ofrece
// descarga, para no colgar el navegador ni demorar la apertura.
const MAX_PREVIEW_BYTES = 15 * 1024 * 1024; // 15 MB

// Tipos que se sirven directo por <src> (el navegador los renderiza nativo y
// soporta rangos/streaming, sin traer todo el blob a memoria JS).
const NATIVE_KINDS = ['image', 'pdf', 'audio', 'video'];

const url = computed(() =>
  props.file ? driveAPI.downloadUrl(props.file.id) : ''
);
const kind = computed(() => (props.file ? previewKind(props.file) : 'none'));

// Estados en los que el archivo NO se puede abrir (pero existe, no se perdió).
const overflow = computed(() => (props.file ? isOverflow(props.file) : false));
const pending = computed(() => (props.file ? isPending(props.file) : false));
const quarantined = computed(() =>
  props.file ? isQuarantined(props.file) : false
);
const blocked = computed(
  () => overflow.value || pending.value || quarantined.value
);

// Mensaje "imagen/audio/video/documento no se puede ver por falta de espacio",
// según la categoría del archivo retenido en overflow.
const overflowMessage = computed(() => {
  const cat = resolveCategory(props.file).toUpperCase();
  const key = `JABVOX_DRIVE.FILE.OVERFLOW_${cat}`;
  const translated = t(key);
  // Si no hay traducción específica para la categoría, usa la genérica.
  return translated === key
    ? t('JABVOX_DRIVE.FILE.OVERFLOW_GENERIC')
    : translated;
});

// Estado del preview que requiere fetch (texto/csv/docx/xlsx).
const loading = ref(false);
const errored = ref(false);
const tooLarge = ref(false);
const textContent = ref('');
const htmlContent = ref('');
const docxHeaderImages = ref([]); // membretes/logos de encabezado del Word
// Excel: varias hojas. sheets = [{name, rows}]; activeSheet = índice.
const sheets = ref([]); // [{ name, rows: [[...]] }]
const activeSheet = ref(0);
// Token para descartar resultados de un archivo anterior si el usuario cambia rápido.
let loadToken = 0;

const activeRows = computed(() => sheets.value[activeSheet.value]?.rows || []);

const needsFetch = computed(
  () => !NATIVE_KINDS.includes(kind.value) && kind.value !== 'none'
);

const resetState = () => {
  loading.value = false;
  errored.value = false;
  tooLarge.value = false;
  textContent.value = '';
  htmlContent.value = '';
  docxHeaderImages.value = [];
  sheets.value = [];
  activeSheet.value = 0;
};

// Descarga el contenido por el stream privado del Drive (?stream=1): nunca sale a
// terceros. Devuelve el Blob o lanza.
const fetchBlob = async () => {
  const resp = await fetch(`${url.value}?stream=1`, {
    credentials: 'same-origin',
  });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return resp.blob();
};

// Parser delimitado minimalista: respeta comillas dobles y celdas con saltos.
const parseDelimited = (text, delimiter) => {
  const rows = [];
  let row = [];
  let cell = '';
  let inQuotes = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        cell += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === delimiter) {
      row.push(cell);
      cell = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i += 1;
      row.push(cell);
      rows.push(row);
      row = [];
      cell = '';
    } else {
      cell += ch;
    }
  }
  if (cell !== '' || row.length) {
    row.push(cell);
    rows.push(row);
  }
  // Limita a 1000 filas para no colgar el DOM con hojas enormes.
  return rows.slice(0, 1000);
};

const renderText = async () => {
  const blob = await fetchBlob();
  let text = await blob.text();
  const name = (props.file?.filename || '').toLowerCase();
  const ct = (props.file?.content_type || '').toLowerCase();
  if (name.endsWith('.json') || ct.includes('json')) {
    try {
      text = JSON.stringify(JSON.parse(text), null, 2);
    } catch {
      /* no es JSON válido: se muestra tal cual */
    }
  }
  textContent.value = text;
};

const renderCsv = async () => {
  const blob = await fetchBlob();
  const text = await blob.text();
  const name = (props.file?.filename || '').toLowerCase();
  const delimiter = name.endsWith('.tsv') ? '\t' : ',';
  sheets.value = [{ name: 'CSV', rows: parseDelimited(text, delimiter) }];
};

// MIME de una imagen por su extensión (para los media del docx).
const imageMimeForName = name => {
  const ext = (name.split('.').pop() || '').toLowerCase();
  if (ext === 'png') return 'image/png';
  if (ext === 'jpg' || ext === 'jpeg') return 'image/jpeg';
  if (ext === 'gif') return 'image/gif';
  if (ext === 'bmp') return 'image/bmp';
  if (ext === 'webp') return 'image/webp';
  if (ext === 'svg') return 'image/svg+xml';
  if (ext === 'emf' || ext === 'wmf') return 'image/x-emf';
  return 'application/octet-stream';
};

// Extrae los nombres de media referenciados en un conjunto de archivos .rels.
const mediaTargetsFrom = async (zip, relNames) => {
  const lists = await Promise.all(
    relNames.map(async rel => {
      const txt = await zip.file(rel).async('string');
      return (txt.match(/Target="media\/[^"]+"/g) || []).map(m =>
        m.replace(/Target="|"/g, '').replace('media/', '')
      );
    })
  );
  return new Set(lists.flat());
};

// Extrae las imágenes de encabezados/pies (membretes, logos) que mammoth NO
// convierte (solo procesa el cuerpo). Devuelve data URIs para mostrarlas arriba.
const extractHeaderImages = async arrayBuffer => {
  try {
    const JSZip = (await import('jszip')).default;
    const zip = await JSZip.loadAsync(arrayBuffer);
    const names = Object.keys(zip.files);

    // Media que YA usa el cuerpo (mammoth la incrusta): no duplicar.
    const bodyMedia = zip.file('word/_rels/document.xml.rels')
      ? await mediaTargetsFrom(zip, ['word/_rels/document.xml.rels'])
      : new Set();

    // Media referenciada por header*.xml / footer*.xml.
    const headerRels = names.filter(n =>
      /^word\/_rels\/(header|footer)\d*\.xml\.rels$/.test(n)
    );
    const headerMedia = await mediaTargetsFrom(zip, headerRels);

    // Solo las imágenes exclusivas de encabezado/pie.
    const wanted = names.filter(n => {
      if (!/^word\/media\//.test(n)) return false;
      const base = n.split('/').pop();
      return headerMedia.has(base) && !bodyMedia.has(base);
    });

    return Promise.all(
      wanted.map(async media => {
        const base = media.split('/').pop();
        const b64 = await zip.file(media).async('base64');
        return `data:${imageMimeForName(base)};base64,${b64}`;
      })
    );
  } catch {
    return [];
  }
};

const renderDocx = async () => {
  const blob = await fetchBlob();
  const arrayBuffer = await blob.arrayBuffer();
  const mammoth = await import('mammoth/mammoth.browser');
  // Cuerpo con formato: títulos, negritas, listas, tablas y las imágenes del
  // cuerpo incrustadas como data URI (base64), sin salir al servidor.
  const result = await mammoth.convertToHtml(
    { arrayBuffer },
    {
      convertImage: mammoth.images.imgElement(image =>
        image.read('base64').then(data => ({
          src: `data:${image.contentType};base64,${data}`,
        }))
      ),
      // mammoth exige comillas SIMPLES dentro de style-name (las dobles las ignora).
      styleMap: [
        "p[style-name='Title'] => h1.doc-title:fresh",
        "p[style-name='Subtitle'] => h2.doc-subtitle:fresh",
        "p[style-name='Heading 1'] => h1:fresh",
        "p[style-name='Heading 2'] => h2:fresh",
        "p[style-name='Heading 3'] => h3:fresh",
      ],
    }
  );
  // Las imágenes de encabezado/pie (membretes) van arriba, sobre el cuerpo.
  docxHeaderImages.value = await extractHeaderImages(arrayBuffer);
  htmlContent.value = result.value || '';
};

const renderXlsx = async () => {
  const blob = await fetchBlob();
  const arrayBuffer = await blob.arrayBuffer();
  const XLSX = await import('xlsx');
  const wb = XLSX.read(arrayBuffer, { type: 'array' });
  // Todas las hojas, navegables por pestañas.
  sheets.value = wb.SheetNames.map(name => ({
    name,
    rows: XLSX.utils
      .sheet_to_json(wb.Sheets[name], {
        header: 1,
        blankrows: false,
        defval: '',
      })
      .slice(0, 1000),
  }));
};

const loadPreview = async () => {
  resetState();
  // Archivo retenido (overflow/pending/quarantined): NO se descarga ni abre; se
  // muestra el aviso correspondiente. Nunca se pierde, solo no está disponible aún.
  if (!props.file || blocked.value || !needsFetch.value) return;

  // Cortafuegos de tamaño: archivos enormes no se previsualizan (se descargan).
  if ((props.file.byte_size || 0) > MAX_PREVIEW_BYTES) {
    tooLarge.value = true;
    return;
  }

  loadToken += 1;
  const token = loadToken;
  loading.value = true;
  try {
    if (kind.value === 'text') await renderText();
    else if (kind.value === 'csv') await renderCsv();
    else if (kind.value === 'docx') await renderDocx();
    else if (kind.value === 'xlsx') await renderXlsx();
  } catch {
    if (token === loadToken) errored.value = true;
  } finally {
    // Si el usuario ya cambió de archivo, no pisamos el estado nuevo.
    if (token === loadToken) loading.value = false;
  }
};

// Cerrar con Escape. Carga el preview cuando cambia el archivo.
const onKeydown = event => {
  if (event.key === 'Escape') emit('close');
};
watch(
  () => props.file,
  file => {
    if (file) {
      document.addEventListener('keydown', onKeydown);
      loadPreview();
    } else {
      document.removeEventListener('keydown', onKeydown);
      resetState();
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown));
</script>

<template>
  <div
    v-if="file"
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-4"
    role="dialog"
    aria-modal="true"
    :aria-label="file.filename"
    @click.self="emit('close')"
  >
    <div
      class="flex max-h-[90vh] w-full max-w-5xl flex-col overflow-hidden rounded-xl bg-n-solid-1 shadow-xl"
    >
      <header
        class="flex items-center justify-between gap-3 border-b border-n-weak px-4 py-3"
      >
        <div class="flex items-center gap-2 min-w-0">
          <span
            :class="iconForFile(file)"
            class="size-5 text-n-slate-11 shrink-0"
            aria-hidden="true"
          />
          <span class="truncate text-sm font-medium text-n-slate-12">
            {{ file.filename }}
          </span>
        </div>
        <div class="flex items-center gap-1.5 shrink-0">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-download"
            :aria-label="t('JABVOX_DRIVE.FILE.DOWNLOAD')"
            @click="emit('download', file)"
          />
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-x"
            :aria-label="t('JABVOX_DRIVE.FILE.CLOSE_PREVIEW')"
            @click="emit('close')"
          />
        </div>
      </header>

      <!-- Pestañas de hojas (solo Excel con más de una hoja) -->
      <div
        v-if="!blocked && kind === 'xlsx' && sheets.length > 1"
        class="flex shrink-0 gap-1 overflow-x-auto border-b border-n-weak bg-n-solid-2 px-3 py-1.5"
      >
        <button
          v-for="(s, i) in sheets"
          :key="i"
          type="button"
          class="shrink-0 rounded px-2.5 py-1 text-xs font-medium transition-colors"
          :class="
            i === activeSheet
              ? 'bg-n-brand text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="activeSheet = i"
        >
          {{ s.name }}
        </button>
      </div>

      <div
        class="flex min-h-[40vh] flex-1 flex-col overflow-auto bg-n-alpha-1 p-4"
      >
        <!-- Retenido: overflow (sin espacio), procesando o en cuarentena. El
             archivo EXISTE y no se perdió; solo no se puede ver todavía. -->
        <div
          v-if="blocked"
          class="m-auto flex max-w-sm flex-col items-center gap-3 py-10 text-center"
        >
          <span
            :class="
              pending
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-cloud-off'
            "
            class="size-12 text-n-slate-9"
            aria-hidden="true"
          />
          <p class="text-sm font-medium text-n-slate-12">
            <template v-if="overflow">{{ overflowMessage }}</template>
            <template v-else-if="pending">
              {{ t('JABVOX_DRIVE.FILE.PENDING_BADGE') }}
            </template>
            <template v-else>
              {{ t('JABVOX_DRIVE.FILE.QUARANTINED_BADGE') }}
            </template>
          </p>
          <p class="text-xs text-n-slate-10">
            <template v-if="overflow">
              {{ t('JABVOX_DRIVE.FILE.OVERFLOW_HINT') }}
            </template>
            <template v-else-if="pending">
              {{ t('JABVOX_DRIVE.FILE.PENDING_HINT') }}
            </template>
            <template v-else>
              {{ t('JABVOX_DRIVE.FILE.QUARANTINED_HINT') }}
            </template>
          </p>
        </div>

        <!-- Nativos del navegador -->
        <img
          v-else-if="kind === 'image'"
          :src="url"
          :alt="file.filename"
          class="m-auto max-h-[70vh] max-w-full rounded object-contain"
        />
        <iframe
          v-else-if="kind === 'pdf'"
          :src="url"
          :title="file.filename"
          class="h-[70vh] w-full rounded border-0 bg-white"
        />
        <audio
          v-else-if="kind === 'audio'"
          :src="url"
          controls
          class="m-auto w-full"
        />
        <video
          v-else-if="kind === 'video'"
          :src="url"
          controls
          class="m-auto max-h-[70vh] max-w-full rounded"
        />

        <!-- Estados del preview que requiere fetch -->
        <div
          v-else-if="loading"
          class="m-auto flex flex-col items-center gap-3 py-10 text-n-slate-11"
        >
          <span
            class="i-lucide-loader-circle size-8 animate-spin text-n-slate-9"
          />
          <span class="text-sm">{{
            t('JABVOX_DRIVE.FILE.LOADING_PREVIEW')
          }}</span>
        </div>

        <!-- Texto / JSON -->
        <pre
          v-else-if="kind === 'text' && !errored && !tooLarge"
          class="w-full whitespace-pre-wrap break-words rounded bg-n-solid-1 p-3 text-xs leading-relaxed text-n-slate-12"
          >{{ textContent }}</pre>

        <!-- Word (.docx) renderizado a HTML con formato e imágenes -->
        <div
          v-else-if="kind === 'docx' && !errored && !tooLarge"
          class="drive-docx mx-auto w-full max-w-3xl rounded bg-white p-6 text-sm leading-relaxed text-gray-900 shadow-sm"
        >
          <!-- Membretes/logos del encabezado (mammoth no los incluye en el cuerpo) -->
          <div
            v-if="docxHeaderImages.length"
            class="mb-4 flex flex-wrap items-center justify-center gap-3 border-b border-gray-200 pb-4"
          >
            <img
              v-for="(img, i) in docxHeaderImages"
              :key="i"
              :src="img"
              alt="Encabezado del documento"
              class="max-h-24 max-w-full object-contain"
            />
          </div>
          <!-- eslint-disable-next-line vue/no-v-html -->
          <div v-html="htmlContent" />
        </div>

        <!-- CSV / Excel como tabla (hoja activa) -->
        <div
          v-else-if="
            (kind === 'csv' || kind === 'xlsx') && !errored && !tooLarge
          "
          class="w-full overflow-auto"
        >
          <table class="min-w-full border-collapse text-xs">
            <tbody>
              <tr
                v-for="(r, ri) in activeRows"
                :key="ri"
                :class="ri === 0 ? 'bg-n-alpha-2 font-semibold' : ''"
              >
                <td
                  v-for="(cell, ci) in r"
                  :key="ci"
                  class="border border-n-weak px-2 py-1 align-top text-n-slate-12 whitespace-pre-wrap"
                >
                  {{ cell }}
                </td>
              </tr>
            </tbody>
          </table>
          <p
            v-if="activeRows.length >= 1000"
            class="mt-2 text-xs text-n-slate-10"
          >
            {{ t('JABVOX_DRIVE.FILE.TABLE_TRUNCATED') }}
          </p>
        </div>

        <!-- No previsualizable / demasiado grande / error: ofrecer descarga -->
        <div
          v-else
          class="m-auto flex flex-col items-center gap-3 py-10 text-center text-n-slate-11"
        >
          <span
            :class="iconForFile(file)"
            class="size-12 text-n-slate-9"
            aria-hidden="true"
          />
          <p v-if="tooLarge" class="max-w-xs text-sm">
            {{
              t('JABVOX_DRIVE.FILE.TOO_LARGE_PREVIEW', {
                size: humanSize(file.byte_size),
              })
            }}
          </p>
          <p v-else-if="errored" class="max-w-xs text-sm">
            {{ t('JABVOX_DRIVE.FILE.PREVIEW_ERROR') }}
          </p>
          <p v-else class="max-w-xs text-sm">
            {{ t('JABVOX_DRIVE.FILE.NO_PREVIEW') }}
          </p>
          <Button
            color="blue"
            size="sm"
            icon="i-lucide-download"
            :label="t('JABVOX_DRIVE.FILE.DOWNLOAD')"
            @click="emit('download', file)"
          />
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Tipografía del HTML generado por mammoth (Word -> HTML), estilo documento. */
.drive-docx :deep(.doc-title) {
  font-size: 1.5rem;
  font-weight: 700;
  margin-bottom: 0.5rem;
}
.drive-docx :deep(.doc-subtitle) {
  font-size: 1.1rem;
  color: #555;
  margin-bottom: 0.75rem;
}
.drive-docx :deep(p) {
  margin-bottom: 0.6rem;
}
.drive-docx :deep(h1),
.drive-docx :deep(h2),
.drive-docx :deep(h3) {
  font-weight: 700;
  margin: 0.9rem 0 0.5rem;
}
.drive-docx :deep(h1) {
  font-size: 1.4rem;
}
.drive-docx :deep(h2) {
  font-size: 1.2rem;
}
.drive-docx :deep(ul),
.drive-docx :deep(ol) {
  padding-left: 1.4rem;
  margin-bottom: 0.6rem;
}
.drive-docx :deep(li) {
  margin-bottom: 0.2rem;
}
.drive-docx :deep(table) {
  border-collapse: collapse;
  margin: 0.6rem 0;
  width: 100%;
}
.drive-docx :deep(td),
.drive-docx :deep(th) {
  border: 1px solid #d1d5db;
  padding: 0.3rem 0.5rem;
}
.drive-docx :deep(strong) {
  font-weight: 700;
}
.drive-docx :deep(em) {
  font-style: italic;
}
.drive-docx :deep(a) {
  color: #2563eb;
  text-decoration: underline;
}
.drive-docx :deep(img) {
  max-width: 100%;
  height: auto;
  margin: 0.5rem 0;
}
</style>
