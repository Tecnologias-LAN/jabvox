<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';

// Selector de plantilla de WhatsApp y de qué llena cada una de sus variables.
//
// Una automatización dispara cuando la tarjeta o la tarea lleva tiempo quieta, es decir
// fuera de la ventana de 24h de WhatsApp. Ahí el texto libre no sale: solo una plantilla
// aprobada. Por eso aquí se elige plantilla, y no se escribe el mensaje.
const props = defineProps({
  inboxId: { type: [Number, String], default: null },
  templateName: { type: String, default: '' },
  templateLanguage: { type: String, default: '' },
  // { "1": { source: 'contact', field: 'name' }, ... }
  params: { type: Object, default: () => ({}) },
  // Las automatizaciones de tareas pueden usar datos de la tarea; las de kanban no.
  allowTask: { type: Boolean, default: false },
  customAttributeKeys: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'update:templateName',
  'update:templateLanguage',
  'update:params',
]);

const { t } = useI18n();
const store = useStore();

const templates = computed(() =>
  props.inboxId
    ? store.getters['inboxes/getFilteredWhatsAppTemplates'](props.inboxId) || []
    : []
);

const selected = computed(
  () => templates.value.find(tpl => tpl.name === props.templateName) || null
);

// Las variables de una plantilla son los {{...}} de su cuerpo. Se leen del texto porque es lo
// único que Meta devuelve de forma fiable en todas las versiones del API. Acepta tanto
// POSICIONALES ({{1}}, {{2}}) como NOMBRADAS ({{nomcliente}}, {{fechadepago}}): Meta usa
// nombradas cuando la plantilla es parameter_format NAMED, y antes el regex solo-dígitos las
// descartaba, así que no se mostraba el mapeo y la plantilla no se podía configurar.
const variables = computed(() => {
  const body = (selected.value?.components || []).find(c => c.type === 'BODY');
  const text = body?.text || '';
  const found = [...text.matchAll(/\{\{\s*([^}]+?)\s*\}\}/g)].map(m =>
    m[1].trim()
  );
  // Posicionales en orden numérico; nombradas en el orden de aparición.
  return [...new Set(found)].sort((a, b) => {
    const na = Number(a);
    const nb = Number(b);
    if (Number.isFinite(na) && Number.isFinite(nb)) return na - nb;
    return 0;
  });
});

// Idioma de la plantilla elegida. Se muestra para que quede claro en qué idioma saldrá:
// Meta trata "es" y "es_ES" como plantillas distintas y es un error fácil de cometer.
const languageLabel = computed(
  () => props.templateLanguage || selected.value?.language || ''
);

const bodyPreview = computed(() => {
  const body = (selected.value?.components || []).find(c => c.type === 'BODY');
  return body?.text || '';
});

const sourceOptions = computed(() => {
  const options = [
    {
      value: 'contact:name',
      label: t('JABVOX_AUTOMATIONS.PARAMS.CONTACT_NAME'),
    },
    {
      value: 'contact:phone_number',
      label: t('JABVOX_AUTOMATIONS.PARAMS.CONTACT_PHONE'),
    },
    {
      value: 'contact:email',
      label: t('JABVOX_AUTOMATIONS.PARAMS.CONTACT_EMAIL'),
    },
  ];
  if (props.allowTask) {
    options.push(
      {
        value: 'task:title_jabvox',
        label: t('JABVOX_AUTOMATIONS.PARAMS.TASK_TITLE'),
      },
      {
        value: 'task:due_date',
        label: t('JABVOX_AUTOMATIONS.PARAMS.TASK_DUE_DATE'),
      },
      {
        value: 'task:assignee_name',
        label: t('JABVOX_AUTOMATIONS.PARAMS.TASK_ASSIGNEE'),
      },
      {
        value: 'task:stage_name',
        label: t('JABVOX_AUTOMATIONS.PARAMS.TASK_STAGE'),
      }
    );
  }
  props.customAttributeKeys.forEach(key => {
    options.push({
      value: `custom:${key}`,
      label: `${t('JABVOX_AUTOMATIONS.PARAMS.CUSTOM')}: ${key}`,
    });
  });
  options.push({
    value: 'fixed:',
    label: t('JABVOX_AUTOMATIONS.PARAMS.FIXED'),
  });
  return options;
});

// Vue intenta interpretar `{{1}}` dentro del template como interpolación y falla al
// parsear. La etiqueta se arma en JS, donde las llaves son texto corriente.
const labelForVariable = position => `{{${position}}}`;

const valueFor = position => {
  const spec = props.params?.[position];
  if (!spec) return '';
  return spec.source === 'fixed'
    ? 'fixed:'
    : `${spec.source}:${spec.field || ''}`;
};

const onSourceChange = (position, raw) => {
  const [source, field] = String(raw).split(':');
  const next = { ...(props.params || {}) };
  if (!source) delete next[position];
  else if (source === 'fixed')
    next[position] = { source: 'fixed', value: next[position]?.value || '' };
  else next[position] = { source, field };
  emit('update:params', next);
};

const onFixedValue = (position, value) => {
  emit('update:params', {
    ...(props.params || {}),
    [position]: { source: 'fixed', value },
  });
};

const onTemplateChange = name => {
  const tpl = templates.value.find(item => item.name === name);
  emit('update:templateName', name);
  emit('update:templateLanguage', tpl?.language || 'es');
  // Las variables de la plantilla anterior no valen para la nueva.
  emit('update:params', {});
};

const labelClass = 'block text-sm font-medium text-n-slate-12 mb-1';
const fieldClass =
  'w-full rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand';
</script>

<template>
  <div class="flex flex-col gap-3">
    <div>
      <label :class="labelClass">
        {{ t('JABVOX_AUTOMATIONS.PARAMS.TEMPLATE_LABEL') }}
      </label>
      <select
        :value="templateName"
        :class="fieldClass"
        :disabled="!inboxId"
        @change="onTemplateChange($event.target.value)"
      >
        <option value="">
          {{
            inboxId
              ? t('JABVOX_AUTOMATIONS.PARAMS.TEMPLATE_PLACEHOLDER')
              : t('JABVOX_AUTOMATIONS.PARAMS.PICK_INBOX_FIRST')
          }}
        </option>
        <option
          v-for="tpl in templates"
          :key="tpl.id || tpl.name"
          :value="tpl.name"
        >
          {{ tpl.name }} ({{ tpl.language }})
        </option>
      </select>
      <p
        v-if="inboxId && !templates.length"
        class="mt-1 text-xs text-n-slate-10"
      >
        {{ t('JABVOX_AUTOMATIONS.PARAMS.NO_TEMPLATES') }}
      </p>
      <p
        v-else-if="templateName && languageLabel"
        class="mt-1 text-xs text-n-slate-10"
      >
        {{
          t('JABVOX_AUTOMATIONS.PARAMS.LANGUAGE', { language: languageLabel })
        }}
      </p>
    </div>

    <div
      v-if="bodyPreview"
      class="rounded-lg bg-n-alpha-1 p-2.5 text-xs text-n-slate-11"
    >
      {{ bodyPreview }}
    </div>

    <div v-if="variables.length" class="flex flex-col gap-2">
      <span :class="labelClass">
        {{ t('JABVOX_AUTOMATIONS.PARAMS.VARIABLES_LABEL') }}
      </span>
      <div
        v-for="position in variables"
        :key="position"
        class="flex items-center gap-2"
      >
        <span
          class="max-w-[9rem] shrink-0 truncate text-xs font-medium text-n-slate-11"
          :title="labelForVariable(position)"
        >
          {{ labelForVariable(position) }}
        </span>
        <select
          :value="valueFor(position)"
          :class="fieldClass"
          @change="onSourceChange(position, $event.target.value)"
        >
          <option value="">
            {{ t('JABVOX_AUTOMATIONS.PARAMS.PICK_SOURCE') }}
          </option>
          <option
            v-for="opt in sourceOptions"
            :key="opt.value"
            :value="opt.value"
          >
            {{ opt.label }}
          </option>
        </select>
        <input
          v-if="params?.[position]?.source === 'fixed'"
          :value="params[position].value"
          type="text"
          :class="fieldClass"
          :placeholder="t('JABVOX_AUTOMATIONS.PARAMS.FIXED_PLACEHOLDER')"
          @input="onFixedValue(position, $event.target.value)"
        />
      </div>
    </div>
  </div>
</template>
