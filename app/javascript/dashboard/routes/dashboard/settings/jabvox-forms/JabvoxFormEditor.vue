<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import EmailBodyEditor from '../jabvox-email/EmailBodyEditor.vue';

const props = defineProps({
  form: { type: Object, default: null },
});
const emit = defineEmits(['saved', 'close']);

const store = useStore();
const { t } = useI18n();
const uiFlags = ref({ isSaving: false });

const emailTemplates = computed(
  () => store.getters['jabvoxEmail/getTemplates'] || []
);
onMounted(() => store.dispatch('jabvoxEmail/fetchTemplates'));

const FIELD_TYPES = [
  { value: 'text', label: 'JABVOX_FORMS.FIELD_TYPE_TEXT' },
  { value: 'email', label: 'JABVOX_FORMS.FIELD_TYPE_EMAIL' },
  { value: 'phone', label: 'JABVOX_FORMS.FIELD_TYPE_PHONE' },
  { value: 'textarea', label: 'JABVOX_FORMS.FIELD_TYPE_TEXTAREA' },
  { value: 'select', label: 'JABVOX_FORMS.FIELD_TYPE_SELECT' },
  { value: 'cedula', label: 'JABVOX_FORMS.FIELD_TYPE_CEDULA' },
  { value: 'pais', label: 'JABVOX_FORMS.FIELD_TYPE_PAIS' },
];

const PRIVACY_DEFAULTS = {
  enabled: false,
  title: 'Tratamiento de datos personales',
  body: 'Autorizo a JABVOX a recolectar y tratar mis datos personales con la finalidad de contactarme, presentar soluciones comerciales y hacer seguimiento a mi solicitud.\n\nMis datos no serán compartidos con terceros no autorizados y serán tratados conforme a la normativa aplicable de protección de datos.',
  link_text: 'Consulta la política completa aquí',
  link_url:
    'https://www.minambiente.gov.co/politica-de-proteccion-de-datos-personales/',
  accept_text: 'Entendido',
};

const SOCIAL_LABELS = {
  whatsapp: 'WhatsApp',
  facebook: 'Facebook',
  instagram: 'Instagram',
  website: 'Sitio web',
};

const SOCIAL_ICONS = {
  whatsapp: 'i-lucide-message-circle',
  facebook: 'i-lucide-share-2',
  instagram: 'i-lucide-camera',
  website: 'i-lucide-globe',
};

const defaultField = () => ({
  id: `field_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
  type: 'text',
  label: '',
  required: false,
  options: [],
});

const draft = reactive({
  name_jabvox: '',
  slug_jabvox: '',
  submit_button_text_jabvox: 'Enviar',
  active_jabvox: true,
  header_jabvox: {
    html: '',
    body_html: '',
    bg_color: '#f1f5f9',
    button_color: '#6c63ff',
  },
  footer_jabvox: {
    whatsapp: '',
    facebook: '',
    instagram: '',
    website: '',
    copyright: '',
  },
  fields_jabvox: [],
  submit_actions_jabvox: {
    email: { enabled: false, template_id: '' },
    webhook: { enabled: false, url: '', secret: '' },
    success: { message: '', button_label: '', button_url: '' },
    privacy: { ...PRIVACY_DEFAULTS },
  },
});

watch(
  () => props.form,
  form => {
    if (!form) return;
    draft.name_jabvox = form.name_jabvox || '';
    draft.slug_jabvox = form.slug_jabvox || '';
    draft.submit_button_text_jabvox =
      form.submit_button_text_jabvox || 'Enviar';
    draft.active_jabvox = form.active_jabvox ?? true;
    draft.header_jabvox = {
      html: '',
      body_html: '',
      bg_color: '#f1f5f9',
      button_color: '#6c63ff',
      ...(form.header_jabvox || {}),
    };
    draft.footer_jabvox = {
      whatsapp: '',
      facebook: '',
      instagram: '',
      website: '',
      copyright: '',
      ...(form.footer_jabvox || {}),
    };
    draft.fields_jabvox = (form.fields_jabvox || []).map(f => ({
      ...f,
      options: f.options || [],
    }));
    const sa = form.submit_actions_jabvox || {};
    draft.submit_actions_jabvox = {
      email: { enabled: false, template_id: '', ...(sa.email || {}) },
      webhook: { enabled: false, url: '', secret: '', ...(sa.webhook || {}) },
      success: {
        message: '',
        button_label: '',
        button_url: '',
        ...(sa.success || {}),
      },
      privacy: { ...PRIVACY_DEFAULTS, ...(sa.privacy || {}) },
    };
  },
  { immediate: true }
);

// ── fields ────────────────────────────────────────────────────────────────────
const addField = () => draft.fields_jabvox.push(defaultField());
const removeField = idx => draft.fields_jabvox.splice(idx, 1);
const addOption = field => {
  field.options = [...(field.options || []), ''];
};
const removeOption = (field, idx) => {
  field.options = field.options.filter((_, i) => i !== idx);
};

// ── drag & drop ───────────────────────────────────────────────────────────────
const dragIdx = ref(null);
const dragOverIdx = ref(null);

const onDragStart = idx => {
  dragIdx.value = idx;
};
const onDragOver = (e, idx) => {
  e.preventDefault();
  dragOverIdx.value = idx;
};
const onDrop = idx => {
  if (dragIdx.value === null || dragIdx.value === idx) return;
  const arr = [...draft.fields_jabvox];
  const [moved] = arr.splice(dragIdx.value, 1);
  arr.splice(idx, 0, moved);
  draft.fields_jabvox = arr;
  dragIdx.value = null;
  dragOverIdx.value = null;
};
const onDragEnd = () => {
  dragIdx.value = null;
  dragOverIdx.value = null;
};

// ── footer ────────────────────────────────────────────────────────────────────
const hasFooter = computed(() =>
  Object.values(draft.footer_jabvox).some(v => v?.trim())
);
const footerSocials = computed(() =>
  ['whatsapp', 'facebook', 'instagram', 'website'].filter(k =>
    draft.footer_jabvox[k]?.trim()
  )
);

// ── right panel tabs ──────────────────────────────────────────────────────────
const activeTab = ref('design');
const TABS = [
  { key: 'design', icon: 'i-lucide-palette', label: 'JABVOX_FORMS.TAB_DESIGN' },
  {
    key: 'footer',
    icon: 'i-lucide-footprints',
    label: 'JABVOX_FORMS.TAB_FOOTER',
  },
  { key: 'actions', icon: 'i-lucide-zap', label: 'JABVOX_FORMS.TAB_ACTIONS' },
];

// ── save ──────────────────────────────────────────────────────────────────────
const onSave = async () => {
  if (!draft.name_jabvox.trim()) {
    useAlert(t('JABVOX_FORMS.NAME_REQUIRED'));
    return;
  }
  uiFlags.value.isSaving = true;
  try {
    const payload = {
      name_jabvox: draft.name_jabvox.trim(),
      slug_jabvox: draft.slug_jabvox.trim() || undefined,
      submit_button_text_jabvox:
        draft.submit_button_text_jabvox.trim() || 'Enviar',
      active_jabvox: draft.active_jabvox,
      header_jabvox: { ...draft.header_jabvox },
      footer_jabvox: { ...draft.footer_jabvox },
      fields_jabvox: draft.fields_jabvox.map(f => ({ ...f })),
      submit_actions_jabvox: {
        email: {
          enabled: draft.submit_actions_jabvox.email.enabled,
          template_id:
            draft.submit_actions_jabvox.email.template_id || undefined,
        },
        webhook: { ...draft.submit_actions_jabvox.webhook },
        success: { ...draft.submit_actions_jabvox.success },
        privacy: { ...draft.submit_actions_jabvox.privacy },
      },
    };
    if (!draft.submit_actions_jabvox.webhook.secret) {
      delete payload.submit_actions_jabvox.webhook.secret;
    }
    if (props.form?.id) {
      await store.dispatch('jabvoxForms/updateForm', {
        id: props.form.id,
        ...payload,
      });
      useAlert(t('JABVOX_FORMS.UPDATE_SUCCESS'));
    } else {
      await store.dispatch('jabvoxForms/createForm', payload);
      useAlert(t('JABVOX_FORMS.CREATE_SUCCESS'));
    }
    emit('saved');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_FORMS.SAVE_ERROR'));
  } finally {
    uiFlags.value.isSaving = false;
  }
};
</script>

<template>
  <div
    class="flex flex-col h-full overflow-hidden bg-slate-50 dark:bg-slate-900"
  >
    <!-- ── Top bar ── -->
    <div
      class="flex items-center gap-3 px-5 py-2.5 bg-white dark:bg-slate-800 border-b border-slate-200 dark:border-slate-700 shrink-0"
    >
      <button
        class="flex items-center gap-1 text-sm text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200 transition-colors shrink-0"
        @click="emit('close')"
      >
        <span class="i-lucide-arrow-left size-4" />
        {{ $t('JABVOX_FORMS.BACK') }}
      </button>
      <div class="w-px h-5 bg-slate-200 dark:bg-slate-600" />
      <input
        v-model="draft.name_jabvox"
        type="text"
        maxlength="80"
        :placeholder="$t('JABVOX_FORMS.FORM_NAME_PLACEHOLDER')"
        class="w-44 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-1.5 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
      />
      <input
        v-model="draft.slug_jabvox"
        type="text"
        pattern="[-a-z0-9]+"
        :placeholder="$t('JABVOX_FORMS.SLUG_PLACEHOLDER')"
        class="w-28 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-1.5 font-mono text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
      />
      <label
        class="flex items-center gap-1.5 text-sm text-slate-600 dark:text-slate-300 cursor-pointer shrink-0"
      >
        <input v-model="draft.active_jabvox" type="checkbox" class="rounded" />
        {{ $t('JABVOX_FORMS.ACTIVE') }}
      </label>
      <div class="flex-1" />
      <button
        class="px-4 py-1.5 text-sm text-slate-600 dark:text-slate-300 border border-slate-300 dark:border-slate-600 rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
        @click="emit('close')"
      >
        {{ $t('JABVOX_FORMS.CANCEL') }}
      </button>
      <button
        :disabled="uiFlags.isSaving"
        class="px-4 py-1.5 text-sm text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors disabled:opacity-50"
        @click="onSave"
      >
        {{
          uiFlags.isSaving ? $t('JABVOX_FORMS.SAVING') : $t('JABVOX_FORMS.SAVE')
        }}
      </button>
    </div>

    <!-- ── Body ── -->
    <div class="flex flex-1 min-h-0">
      <!-- ── Left: live form preview ── -->
      <div
        class="flex-1 overflow-auto p-8 min-w-0 transition-colors duration-300"
        :style="{ background: draft.header_jabvox.bg_color || '#f1f5f9' }"
      >
        <div
          class="mx-auto max-w-[560px] bg-white dark:bg-slate-800 rounded-2xl shadow-2xl overflow-hidden ring-1 ring-black/5"
        >
          <!-- Rich header (WYSIWYG editor) -->
          <EmailBodyEditor v-model="draft.header_jabvox.html" />

          <!-- Fields -->
          <div class="px-7 pt-5 pb-2 space-y-3">
            <div
              v-for="(field, idx) in draft.fields_jabvox"
              :key="field.id"
              draggable="true"
              class="group relative rounded-xl border transition-all duration-150"
              :class="[
                dragOverIdx === idx && dragIdx !== idx
                  ? 'border-woot-400 bg-woot-50 dark:bg-woot-900/20 scale-[1.01]'
                  : 'border-slate-200 dark:border-slate-600 bg-slate-50 dark:bg-slate-700/30',
                dragIdx === idx ? 'opacity-30 scale-95' : '',
              ]"
              @dragstart="onDragStart(idx)"
              @dragover="e => onDragOver(e, idx)"
              @drop="onDrop(idx)"
              @dragend="onDragEnd"
            >
              <!-- Drag handle -->
              <div
                class="absolute left-2.5 top-1/2 -translate-y-1/2 cursor-grab text-slate-300 group-hover:text-slate-400 transition-colors select-none"
              >
                <span class="i-lucide-grip-vertical size-4" />
              </div>

              <div class="pl-8 pr-3 py-3 space-y-2">
                <!-- Label row + inline controls -->
                <div class="flex items-center gap-2">
                  <input
                    v-model="field.label"
                    type="text"
                    maxlength="60"
                    :placeholder="$t('JABVOX_FORMS.FIELD_LABEL_PLACEHOLDER')"
                    class="flex-1 text-sm font-semibold text-slate-700 dark:text-slate-100 bg-transparent border-b border-transparent hover:border-slate-300 dark:hover:border-slate-500 focus:border-woot-500 focus:outline-none py-0.5 transition-colors"
                  />
                  <span
                    v-if="field.required"
                    class="text-red-500 text-sm font-bold shrink-0"
                  >
                    *
                  </span>

                  <!-- Hover controls -->
                  <div
                    class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
                  >
                    <select
                      v-model="field.type"
                      class="text-xs rounded-md border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 px-1.5 py-0.5 text-slate-600 dark:text-slate-300 focus:outline-none cursor-pointer"
                    >
                      <option
                        v-for="ft in FIELD_TYPES"
                        :key="ft.value"
                        :value="ft.value"
                      >
                        {{ $t(ft.label) }}
                      </option>
                    </select>
                    <label
                      class="flex items-center gap-0.5 text-xs text-slate-500 cursor-pointer whitespace-nowrap"
                    >
                      <input
                        v-model="field.required"
                        type="checkbox"
                        class="rounded"
                      />
                      {{ $t('JABVOX_FORMS.REQUIRED_SHORT') }}
                    </label>
                    <button
                      class="p-0.5 text-slate-400 hover:text-red-500 transition-colors"
                      @click="removeField(idx)"
                    >
                      <span class="i-lucide-trash-2 size-3.5" />
                    </button>
                  </div>
                </div>

                <!-- Input preview -->
                <textarea
                  v-if="field.type === 'textarea'"
                  disabled
                  rows="2"
                  :placeholder="field.label || '...'"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 px-3 py-2 text-sm text-slate-400 bg-white dark:bg-slate-800 resize-none cursor-not-allowed"
                />
                <select
                  v-else-if="field.type === 'select'"
                  disabled
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 px-3 py-2 text-sm text-slate-400 bg-white dark:bg-slate-800 cursor-not-allowed"
                >
                  <option
                    v-for="(opt, oi) in field.options.length
                      ? field.options
                      : ['Opción 1']"
                    :key="oi"
                  >
                    {{ opt || `Opción ${oi + 1}` }}
                  </option>
                </select>
                <select
                  v-else-if="field.type === 'pais'"
                  disabled
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 px-3 py-2 text-sm text-slate-400 bg-white dark:bg-slate-800 cursor-not-allowed"
                >
                  <option>{{ $t('JABVOX_FORMS.SELECT_COUNTRY') }}</option>
                </select>
                <input
                  v-else
                  disabled
                  :type="
                    field.type === 'email'
                      ? 'email'
                      : field.type === 'phone'
                        ? 'tel'
                        : 'text'
                  "
                  :inputmode="field.type === 'cedula' ? 'numeric' : undefined"
                  :placeholder="field.label || '...'"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 px-3 py-2 text-sm text-slate-400 bg-white dark:bg-slate-800 cursor-not-allowed"
                />

                <!-- Select options -->
                <div
                  v-if="field.type === 'select'"
                  class="pl-1 pt-0.5 space-y-1"
                >
                  <div
                    v-for="(opt, oi) in field.options"
                    :key="oi"
                    class="flex items-center gap-1.5"
                  >
                    <input
                      v-model="field.options[oi]"
                      type="text"
                      maxlength="40"
                      :placeholder="`Opción ${oi + 1}`"
                      class="flex-1 text-xs border border-slate-200 dark:border-slate-600 rounded px-2 py-1 bg-white dark:bg-slate-700 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-1 focus:ring-woot-500"
                    />
                    <button
                      class="text-slate-400 hover:text-red-500 transition-colors"
                      @click="removeOption(field, oi)"
                    >
                      <span class="i-lucide-x size-3" />
                    </button>
                  </div>
                  <button
                    class="text-xs text-woot-500 hover:text-woot-600 flex items-center gap-1"
                    @click="addOption(field)"
                  >
                    <span class="i-lucide-plus size-3" />
                    {{ $t('JABVOX_FORMS.ADD_OPTION') }}
                  </button>
                </div>
              </div>
            </div>

            <!-- Add field -->
            <button
              class="w-full border-2 border-dashed border-slate-300 dark:border-slate-600 rounded-xl py-3 text-sm text-slate-400 hover:border-woot-400 hover:text-woot-500 hover:bg-woot-50 dark:hover:bg-woot-900/10 flex items-center justify-center gap-2 transition-all"
              @click="addField"
            >
              <span class="i-lucide-plus size-4" />
              {{ $t('JABVOX_FORMS.ADD_FIELD') }}
            </button>

            <!-- Privacy checkbox preview -->
            <div
              v-if="draft.submit_actions_jabvox.privacy.enabled"
              class="rounded-xl border border-slate-200 dark:border-slate-600 bg-slate-50 dark:bg-slate-700/30 px-4 py-3"
            >
              <div class="flex items-start gap-2">
                <input
                  type="checkbox"
                  disabled
                  class="mt-0.5 rounded shrink-0"
                />
                <span
                  class="text-xs text-slate-500 dark:text-slate-400 leading-snug"
                >
                  {{ $t('JABVOX_FORMS.PRIVACY_ACCEPT_LABEL') }}
                  <span class="text-woot-500 underline cursor-pointer">{{
                    $t('JABVOX_FORMS.PRIVACY_POLICY_LINK')
                  }}</span>
                </span>
              </div>
            </div>

            <!-- Submit button -->
            <button
              disabled
              class="w-full py-2.5 rounded-xl text-white text-sm font-semibold cursor-not-allowed opacity-90 mt-1"
              :style="{
                background: draft.header_jabvox.button_color || '#6c63ff',
              }"
            >
              {{
                draft.submit_button_text_jabvox ||
                $t('JABVOX_FORMS.SUBMIT_BUTTON_PLACEHOLDER')
              }}
            </button>
          </div>

          <!-- After-fields editor -->
          <div class="border-t border-slate-100 dark:border-slate-700 pt-2">
            <p
              class="text-[10px] text-slate-400 text-center py-1.5 select-none"
            >
              {{ $t('JABVOX_FORMS.BODY_HTML_LABEL') }}
            </p>
            <EmailBodyEditor v-model="draft.header_jabvox.body_html" />
          </div>

          <!-- Footer preview -->
          <div
            v-if="hasFooter"
            class="border-t border-slate-100 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/60 px-7 py-4 mt-3"
          >
            <div
              v-if="footerSocials.length"
              class="flex flex-wrap items-center justify-center gap-4 mb-2"
            >
              <span
                v-for="key in footerSocials"
                :key="key"
                class="flex items-center gap-1.5 text-xs text-slate-500 dark:text-slate-400"
              >
                <span :class="SOCIAL_ICONS[key]" class="size-3.5 shrink-0" />
                {{ SOCIAL_LABELS[key] }}
              </span>
            </div>
            <p
              v-if="draft.footer_jabvox.copyright"
              class="text-center text-[11px] text-slate-400 dark:text-slate-500"
            >
              {{ draft.footer_jabvox.copyright }}
            </p>
          </div>
        </div>
      </div>

      <!-- ── Right: config panel ── -->
      <div
        class="w-72 shrink-0 border-l border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 flex flex-col"
      >
        <!-- Tabs -->
        <div
          class="flex border-b border-slate-200 dark:border-slate-700 shrink-0"
        >
          <button
            v-for="tab in TABS"
            :key="tab.key"
            class="flex-1 flex items-center justify-center gap-1 py-2.5 text-xs font-medium border-b-2 transition-colors"
            :class="[
              activeTab === tab.key
                ? 'border-woot-600 text-woot-600'
                : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300',
            ]"
            @click="activeTab = tab.key"
          >
            <span :class="tab.icon" class="size-3.5" />
            {{ $t(tab.label) }}
          </button>
        </div>

        <!-- Tab content -->
        <div class="flex-1 overflow-y-auto p-4 space-y-4">
          <!-- ── Diseño ── -->
          <template v-if="activeTab === 'design'">
            <div class="space-y-5">
              <!-- Background color -->
              <div class="space-y-1.5">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                >
                  {{ $t('JABVOX_FORMS.DESIGN_BG_COLOR') }}
                </label>
                <div class="flex items-center gap-2">
                  <input
                    v-model="draft.header_jabvox.bg_color"
                    type="color"
                    class="w-9 h-9 rounded-lg cursor-pointer border border-slate-200 dark:border-slate-600 p-0.5 bg-white shrink-0"
                  />
                  <input
                    v-model="draft.header_jabvox.bg_color"
                    type="text"
                    maxlength="20"
                    class="flex-1 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-1.5 text-slate-800 dark:text-slate-100 font-mono focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
              </div>

              <!-- Button color -->
              <div class="space-y-1.5">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                >
                  {{ $t('JABVOX_FORMS.DESIGN_BUTTON_COLOR') }}
                </label>
                <div class="flex items-center gap-2">
                  <input
                    v-model="draft.header_jabvox.button_color"
                    type="color"
                    class="w-9 h-9 rounded-lg cursor-pointer border border-slate-200 dark:border-slate-600 p-0.5 bg-white shrink-0"
                  />
                  <input
                    v-model="draft.header_jabvox.button_color"
                    type="text"
                    maxlength="20"
                    class="flex-1 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-1.5 text-slate-800 dark:text-slate-100 font-mono focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
              </div>

              <!-- Submit button text -->
              <div class="space-y-1.5">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                >
                  {{ $t('JABVOX_FORMS.SUBMIT_BUTTON_TEXT') }}
                </label>
                <input
                  v-model="draft.submit_button_text_jabvox"
                  type="text"
                  maxlength="40"
                  :placeholder="$t('JABVOX_FORMS.SUBMIT_BUTTON_PLACEHOLDER')"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                />
              </div>

              <!-- Slug -->
              <div class="space-y-1.5">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                >
                  {{ $t('JABVOX_FORMS.SLUG') }}
                </label>
                <input
                  v-model="draft.slug_jabvox"
                  type="text"
                  pattern="[-a-z0-9]+"
                  :placeholder="$t('JABVOX_FORMS.SLUG_PLACEHOLDER')"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 font-mono text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                />
              </div>

              <!-- Divider -->
              <div class="border-t border-slate-200 dark:border-slate-700 pt-1">
                <p
                  class="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wide mb-3"
                >
                  {{ $t('JABVOX_FORMS.SUCCESS_SECTION') }}
                </p>

                <!-- Success message -->
                <div class="space-y-1.5 mb-3">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.SUCCESS_MESSAGE_LABEL') }}
                  </label>
                  <textarea
                    v-model="draft.submit_actions_jabvox.success.message"
                    rows="3"
                    maxlength="300"
                    :placeholder="
                      $t('JABVOX_FORMS.SUCCESS_MESSAGE_PLACEHOLDER')
                    "
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500 resize-none"
                  />
                </div>

                <!-- Success button label -->
                <div class="space-y-1.5 mb-3">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.SUCCESS_BTN_LABEL') }}
                  </label>
                  <input
                    v-model="draft.submit_actions_jabvox.success.button_label"
                    type="text"
                    maxlength="50"
                    :placeholder="
                      $t('JABVOX_FORMS.SUCCESS_BTN_LABEL_PLACEHOLDER')
                    "
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>

                <!-- Success button URL -->
                <div class="space-y-1.5">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.SUCCESS_BTN_URL') }}
                  </label>
                  <input
                    v-model="draft.submit_actions_jabvox.success.button_url"
                    type="url"
                    :placeholder="
                      $t('JABVOX_FORMS.SUCCESS_BTN_URL_PLACEHOLDER')
                    "
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
              </div>
            </div>
          </template>

          <!-- ── Pie de página ── -->
          <template v-else-if="activeTab === 'footer'">
            <p class="text-xs text-slate-400 dark:text-slate-500">
              {{ $t('JABVOX_FORMS.FOOTER_HINT') }}
            </p>
            <div
              v-for="social in ['whatsapp', 'facebook', 'instagram', 'website']"
              :key="social"
              class="space-y-1"
            >
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-300"
              >
                {{ $t(`JABVOX_FORMS.FOOTER_${social.toUpperCase()}`) }}
              </label>
              <input
                v-model="draft.footer_jabvox[social]"
                type="text"
                maxlength="200"
                :placeholder="
                  $t(`JABVOX_FORMS.FOOTER_${social.toUpperCase()}_PLACEHOLDER`)
                "
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              />
            </div>
            <div class="space-y-1">
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-300"
              >
                {{ $t('JABVOX_FORMS.FOOTER_COPYRIGHT') }}
              </label>
              <input
                v-model="draft.footer_jabvox.copyright"
                type="text"
                maxlength="100"
                :placeholder="$t('JABVOX_FORMS.FOOTER_COPYRIGHT_PLACEHOLDER')"
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              />
            </div>
          </template>

          <!-- ── Acciones ── -->
          <template v-else-if="activeTab === 'actions'">
            <!-- Email -->
            <div
              class="rounded-xl border border-slate-200 dark:border-slate-600 p-3 space-y-3"
            >
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  v-model="draft.submit_actions_jabvox.email.enabled"
                  type="checkbox"
                  class="rounded"
                />
                <span
                  class="text-sm font-medium text-slate-700 dark:text-slate-300"
                >
                  {{ $t('JABVOX_FORMS.ACTION_EMAIL') }}
                </span>
              </label>
              <div
                v-if="draft.submit_actions_jabvox.email.enabled"
                class="space-y-2"
              >
                <p
                  class="text-xs text-slate-500 dark:text-slate-400 bg-slate-100 dark:bg-slate-700 rounded-lg px-3 py-2"
                >
                  <span
                    class="i-lucide-info size-3 inline-block mr-1 align-middle"
                  />
                  {{ $t('JABVOX_FORMS.ACTION_EMAIL_NOTE') }}
                </p>
                <div class="space-y-1">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.ACTION_EMAIL_TEMPLATE') }}
                    <span class="text-red-500">*</span>
                  </label>
                  <select
                    v-model="draft.submit_actions_jabvox.email.template_id"
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  >
                    <option value="">
                      {{ $t('JABVOX_FORMS.ACTION_EMAIL_TEMPLATE_NONE') }}
                    </option>
                    <option
                      v-for="tpl in emailTemplates"
                      :key="tpl.id"
                      :value="String(tpl.id)"
                    >
                      {{ tpl.name }}
                    </option>
                  </select>
                  <p class="text-xs text-slate-400 dark:text-slate-500">
                    {{ $t('JABVOX_FORMS.ACTION_EMAIL_TEMPLATE_HELP') }}
                  </p>
                </div>
              </div>
            </div>

            <!-- Webhook -->
            <div
              class="rounded-xl border border-slate-200 dark:border-slate-600 p-3 space-y-3"
            >
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  v-model="draft.submit_actions_jabvox.webhook.enabled"
                  type="checkbox"
                  class="rounded"
                />
                <span
                  class="text-sm font-medium text-slate-700 dark:text-slate-300"
                >
                  {{ $t('JABVOX_FORMS.ACTION_WEBHOOK') }}
                </span>
              </label>
              <div
                v-if="draft.submit_actions_jabvox.webhook.enabled"
                class="space-y-2"
              >
                <div class="space-y-1">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.ACTION_WEBHOOK_URL') }}
                  </label>
                  <input
                    v-model="draft.submit_actions_jabvox.webhook.url"
                    type="url"
                    :placeholder="
                      $t('JABVOX_FORMS.ACTION_WEBHOOK_URL_PLACEHOLDER')
                    "
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
                <div class="space-y-1">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.ACTION_WEBHOOK_SECRET') }}
                  </label>
                  <input
                    v-model="draft.submit_actions_jabvox.webhook.secret"
                    type="password"
                    autocomplete="new-password"
                    :placeholder="
                      $t('JABVOX_FORMS.ACTION_WEBHOOK_SECRET_PLACEHOLDER')
                    "
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                  <p class="text-xs text-slate-400 dark:text-slate-500">
                    {{ $t('JABVOX_FORMS.ACTION_WEBHOOK_SECRET_HELP') }}
                  </p>
                </div>
              </div>
            </div>

            <!-- Privacy policy -->
            <div
              class="rounded-xl border border-slate-200 dark:border-slate-600 p-3 space-y-3"
            >
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  v-model="draft.submit_actions_jabvox.privacy.enabled"
                  type="checkbox"
                  class="rounded"
                />
                <span
                  class="text-sm font-medium text-slate-700 dark:text-slate-300"
                >
                  {{ $t('JABVOX_FORMS.PRIVACY_ENABLED') }}
                </span>
              </label>
              <template v-if="draft.submit_actions_jabvox.privacy.enabled">
                <div class="space-y-1">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.PRIVACY_TITLE') }}
                  </label>
                  <input
                    v-model="draft.submit_actions_jabvox.privacy.title"
                    type="text"
                    maxlength="100"
                    :placeholder="$t('JABVOX_FORMS.PRIVACY_TITLE_DEFAULT')"
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
                <div class="space-y-1">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.PRIVACY_BODY') }}
                  </label>
                  <textarea
                    v-model="draft.submit_actions_jabvox.privacy.body"
                    rows="4"
                    maxlength="1000"
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500 resize-none"
                  />
                </div>
                <div class="space-y-1">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.PRIVACY_LINK_TEXT') }}
                  </label>
                  <input
                    v-model="draft.submit_actions_jabvox.privacy.link_text"
                    type="text"
                    maxlength="80"
                    :placeholder="$t('JABVOX_FORMS.PRIVACY_LINK_TEXT_DEFAULT')"
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
                <div class="space-y-1">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.PRIVACY_LINK_URL') }}
                  </label>
                  <input
                    v-model="draft.submit_actions_jabvox.privacy.link_url"
                    type="url"
                    :placeholder="$t('JABVOX_FORMS.HEADER_IMAGE_PLACEHOLDER')"
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
                <div class="space-y-1">
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >
                    {{ $t('JABVOX_FORMS.PRIVACY_ACCEPT_TEXT') }}
                  </label>
                  <input
                    v-model="draft.submit_actions_jabvox.privacy.accept_text"
                    type="text"
                    maxlength="50"
                    :placeholder="
                      $t('JABVOX_FORMS.PRIVACY_ACCEPT_TEXT_DEFAULT')
                    "
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
              </template>
            </div>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
