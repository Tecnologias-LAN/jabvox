<script setup>
// Previa real de una plantilla de WhatsApp, estilo burbuja de chat: header con
// media (imagen/video/documento del EJEMPLO que Meta guarda en la plantilla
// aprobada), cuerpo con {{n}} sustituidos por valores de ejemplo, footer y botones.
// Solo visual — no envía nada.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  // Plantilla aprobada tal como viene de inboxes/getWhatsAppTemplates (con components).
  template: { type: Object, default: null },
  // Valores de ejemplo por variable: { "1": "Juan", "2": "Bogotá" } para pintar el body.
  sampleValues: { type: Object, default: () => ({}) },
});

const { t } = useI18n();

const components = computed(() =>
  Array.isArray(props.template?.components) ? props.template.components : []
);

const componentOfType = type =>
  components.value.find(c => (c.type || '').toUpperCase() === type);

const headerComponent = computed(() => componentOfType('HEADER'));
const bodyComponent = computed(() => componentOfType('BODY'));
const footerComponent = computed(() => componentOfType('FOOTER'));
const buttonsComponent = computed(() => componentOfType('BUTTONS'));

const headerFormat = computed(() =>
  (headerComponent.value?.format || 'TEXT').toUpperCase()
);
const isMediaHeader = computed(() =>
  ['IMAGE', 'VIDEO', 'DOCUMENT'].includes(headerFormat.value)
);

// URL de ejemplo del media que Meta guarda en la plantilla aprobada. Meta la expone
// en example.header_handle[0] (o header_url en algunos payloads).
const headerMediaUrl = computed(() => {
  const ex = headerComponent.value?.example || {};
  const handle = ex.header_handle || ex.header_url || ex.header_handle_url;
  if (Array.isArray(handle)) return handle[0] || '';
  return handle || '';
});

// Texto del header cuando es de tipo TEXT (puede traer {{1}}).
const headerText = computed(() =>
  headerFormat.value === 'TEXT' ? headerComponent.value?.text || '' : ''
);

// Sustituye {{n}} por el valor de ejemplo (o deja el placeholder si no hay valor).
const fill = text =>
  String(text || '').replace(/\{\{\s*(\d+)\s*\}\}/g, (_, n) => {
    const v = props.sampleValues?.[String(n)];
    return v === undefined || v === null || v === '' ? `{{${n}}}` : String(v);
  });

const renderedHeaderText = computed(() => fill(headerText.value));
const renderedBody = computed(() => fill(bodyComponent.value?.text || ''));
const footerText = computed(() => footerComponent.value?.text || '');

const buttons = computed(() =>
  Array.isArray(buttonsComponent.value?.buttons)
    ? buttonsComponent.value.buttons
    : []
);

const mediaLabel = computed(() =>
  t(`JABVOX_BULK_WA.PREVIEW.MEDIA_${headerFormat.value}`)
);
</script>

<template>
  <div class="flex justify-center">
    <!-- Burbuja estilo WhatsApp -->
    <div
      class="w-full max-w-sm rounded-xl rounded-tl-sm bg-[#d9fdd3] dark:bg-n-teal-4 shadow-sm overflow-hidden"
    >
      <!-- Header media (imagen / video / documento del ejemplo de Meta) -->
      <template v-if="isMediaHeader">
        <img
          v-if="headerFormat === 'IMAGE' && headerMediaUrl"
          :src="headerMediaUrl"
          :alt="mediaLabel"
          class="w-full max-h-48 object-cover"
        />
        <video
          v-else-if="headerFormat === 'VIDEO' && headerMediaUrl"
          :src="headerMediaUrl"
          controls
          class="w-full max-h-48 bg-black"
        />
        <!-- Documento o media sin URL de ejemplo: placeholder -->
        <div
          v-else
          class="flex items-center gap-2 bg-n-alpha-2 px-3 py-4 text-n-slate-11"
        >
          <span
            :class="
              headerFormat === 'VIDEO'
                ? 'i-lucide-video'
                : headerFormat === 'DOCUMENT'
                  ? 'i-lucide-file-text'
                  : 'i-lucide-image'
            "
            class="size-6 shrink-0"
            aria-hidden="true"
          />
          <span class="text-xs">{{ mediaLabel }}</span>
        </div>
      </template>

      <div class="px-3 py-2 space-y-1.5">
        <!-- Header de texto -->
        <p
          v-if="renderedHeaderText"
          class="text-sm font-semibold text-n-slate-12 whitespace-pre-wrap"
        >
          {{ renderedHeaderText }}
        </p>

        <!-- Cuerpo -->
        <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
          {{ renderedBody || t('JABVOX_BULK_WA.PREVIEW.EMPTY_BODY') }}
        </p>

        <!-- Footer -->
        <p v-if="footerText" class="text-[11px] text-n-slate-10">
          {{ footerText }}
        </p>
      </div>

      <!-- Botones -->
      <div v-if="buttons.length" class="border-t border-n-teal-6/40">
        <div
          v-for="(btn, idx) in buttons"
          :key="`btn-${idx}`"
          class="flex items-center justify-center gap-1.5 border-t border-n-teal-6/30 first:border-t-0 px-3 py-2 text-sm text-n-blue-11"
        >
          <span
            :class="
              (btn.type || '').toUpperCase() === 'URL'
                ? 'i-lucide-external-link'
                : (btn.type || '').toUpperCase() === 'PHONE_NUMBER'
                  ? 'i-lucide-phone'
                  : 'i-lucide-reply'
            "
            class="size-3.5"
            aria-hidden="true"
          />
          {{ btn.text }}
        </div>
      </div>
    </div>
  </div>
</template>
