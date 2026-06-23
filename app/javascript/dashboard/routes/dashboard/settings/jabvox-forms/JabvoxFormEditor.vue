<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Textarea from 'dashboard/components-next/textarea/Textarea.vue';
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

// Options shaped for the design-system Select ({ value, label }).
const emailTemplateOptions = computed(() => [
  { value: '', label: t('JABVOX_FORMS.ACTION_EMAIL_TEMPLATE_NONE') },
  ...emailTemplates.value.map(tpl => ({
    value: String(tpl.id),
    label: tpl.name,
  })),
]);

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

// ── draft persistence ─────────────────────────────────────────────────────────
const draftKey = () =>
  props.form?.id ? `jabvox_draft_${props.form.id}` : 'jabvox_draft_new';

const saveDraft = () => {
  try {
    localStorage.setItem(draftKey(), JSON.stringify(draft));
  } catch (_e) {
    // storage unavailable
  }
};

const clearDraft = () => {
  try {
    localStorage.removeItem(draftKey());
  } catch (_e) {
    // storage unavailable
  }
};

const loadDraft = () => {
  try {
    const raw = localStorage.getItem(draftKey());
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
};

watch(draft, saveDraft, { deep: true });

watch(
  () => props.form,
  form => {
    const saved = loadDraft();
    if (saved) {
      Object.assign(draft, saved);
      return;
    }
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
// On mobile the config panel collapses into a drawer toggled by `showPanel`.
const showPanel = ref(false);
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
    clearDraft();
    emit('saved');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_FORMS.SAVE_ERROR'));
  } finally {
    uiFlags.value.isSaving = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden bg-n-background">
    <!-- ── Top bar ── -->
    <div
      class="flex flex-wrap items-center gap-2 sm:gap-3 px-3 sm:px-5 py-2.5 bg-n-solid-1 border-b border-n-weak shrink-0"
    >
      <Button
        icon="i-lucide-arrow-left"
        :label="$t('JABVOX_FORMS.BACK')"
        variant="ghost"
        color="slate"
        size="sm"
        @click="
          clearDraft();
          emit('close');
        "
      />
      <div class="hidden sm:block w-px h-5 bg-n-weak" />
      <div class="w-32 sm:w-44">
        <Input
          v-model="draft.name_jabvox"
          size="sm"
          :placeholder="$t('JABVOX_FORMS.FORM_NAME_PLACEHOLDER')"
        />
      </div>
      <div class="w-24 sm:w-28">
        <Input
          v-model="draft.slug_jabvox"
          size="sm"
          custom-input-class="font-mono"
          :placeholder="$t('JABVOX_FORMS.SLUG_PLACEHOLDER')"
        />
      </div>
      <label
        class="flex items-center gap-1.5 text-sm text-n-slate-11 cursor-pointer shrink-0"
      >
        <Switch v-model="draft.active_jabvox" />
        <span class="hidden sm:inline">{{ $t('JABVOX_FORMS.ACTIVE') }}</span>
      </label>
      <div class="flex-1" />
      <!-- Mobile: toggle config panel -->
      <Button
        icon="i-lucide-settings-2"
        variant="outline"
        color="slate"
        size="sm"
        class="lg:hidden"
        @click="showPanel = !showPanel"
      />
      <Button
        :label="$t('JABVOX_FORMS.CANCEL')"
        variant="outline"
        color="slate"
        size="sm"
        @click="emit('close')"
      />
      <Button
        :label="
          uiFlags.isSaving ? $t('JABVOX_FORMS.SAVING') : $t('JABVOX_FORMS.SAVE')
        "
        size="sm"
        :is-loading="uiFlags.isSaving"
        @click="onSave"
      />
    </div>

    <!-- ── Body ── -->
    <div class="flex flex-col lg:flex-row flex-1 min-h-0">
      <!-- ── Left: live form preview ── -->
      <div
        class="flex-1 overflow-auto p-4 sm:p-8 min-w-0 transition-colors duration-300"
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
                  ? 'border-n-brand bg-n-alpha-2 scale-[1.01]'
                  : 'border-n-weak bg-n-alpha-1',
                dragIdx === idx ? 'opacity-30 scale-95' : '',
              ]"
              @dragstart="onDragStart(idx)"
              @dragover="e => onDragOver(e, idx)"
              @drop="onDrop(idx)"
              @dragend="onDragEnd"
            >
              <!-- Drag handle -->
              <div
                class="absolute left-2.5 top-1/2 -translate-y-1/2 cursor-grab text-n-slate-9 group-hover:text-n-slate-11 transition-colors select-none"
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
                    class="flex-1 text-sm font-semibold text-n-slate-12 bg-transparent border-b border-transparent hover:border-n-weak focus:border-n-brand focus:outline-none py-0.5 transition-colors"
                  />
                  <span
                    v-if="field.required"
                    class="text-n-ruby-11 text-sm font-bold shrink-0"
                  >
                    {{ $t('JABVOX_FORMS.REQUIRED_MARK') }}
                  </span>

                  <!-- Hover controls -->
                  <div
                    class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
                  >
                    <select
                      v-model="field.type"
                      class="text-xs rounded-md border border-n-weak bg-n-solid-1 px-1.5 py-0.5 text-n-slate-11 focus:outline-none cursor-pointer"
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
                      class="flex items-center gap-0.5 text-xs text-n-slate-11 cursor-pointer whitespace-nowrap"
                    >
                      <input
                        v-model="field.required"
                        type="checkbox"
                        class="rounded accent-n-brand"
                      />
                      {{ $t('JABVOX_FORMS.REQUIRED_SHORT') }}
                    </label>
                    <button
                      class="p-0.5 text-n-slate-10 hover:text-n-ruby-11 transition-colors"
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
                      class="flex-1 text-xs border border-n-weak rounded px-2 py-1 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
                    />
                    <button
                      class="text-n-slate-10 hover:text-n-ruby-11 transition-colors"
                      @click="removeOption(field, oi)"
                    >
                      <span class="i-lucide-x size-3" />
                    </button>
                  </div>
                  <button
                    class="text-xs text-n-brand hover:opacity-80 flex items-center gap-1"
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
              class="w-full border-2 border-dashed border-n-weak rounded-xl py-3 text-sm text-n-slate-10 hover:border-n-brand hover:text-n-brand hover:bg-n-alpha-1 flex items-center justify-center gap-2 transition-all"
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

      <!-- ── Right: config panel (drawer on mobile) ── -->
      <div
        class="shrink-0 border-t lg:border-t-0 lg:border-l border-n-weak bg-n-solid-1 flex-col w-full lg:w-80"
        :class="showPanel ? 'flex' : 'hidden lg:flex'"
      >
        <!-- Tabs -->
        <div class="flex border-b border-n-weak shrink-0">
          <button
            v-for="tab in TABS"
            :key="tab.key"
            class="flex-1 flex items-center justify-center gap-1 py-2.5 text-xs font-medium border-b-2 transition-colors"
            :class="[
              activeTab === tab.key
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-11 hover:text-n-slate-12',
            ]"
            @click="activeTab = tab.key"
          >
            <span :class="tab.icon" class="size-3.5" />
            {{ $t(tab.label) }}
          </button>
        </div>

        <!-- Tab content -->
        <div class="flex-1 overflow-y-auto p-4 flex flex-col gap-4">
          <!-- ── Diseño ── -->
          <template v-if="activeTab === 'design'">
            <!-- Background color -->
            <div class="flex flex-col gap-1.5">
              <label class="text-xs font-medium text-n-slate-12">
                {{ $t('JABVOX_FORMS.DESIGN_BG_COLOR') }}
              </label>
              <div class="flex items-center gap-2">
                <input
                  v-model="draft.header_jabvox.bg_color"
                  type="color"
                  class="w-9 h-9 rounded-lg cursor-pointer border border-n-weak p-0.5 bg-n-solid-1 shrink-0"
                />
                <div class="flex-1">
                  <Input
                    v-model="draft.header_jabvox.bg_color"
                    size="sm"
                    custom-input-class="font-mono"
                  />
                </div>
              </div>
            </div>

            <!-- Button color -->
            <div class="flex flex-col gap-1.5">
              <label class="text-xs font-medium text-n-slate-12">
                {{ $t('JABVOX_FORMS.DESIGN_BUTTON_COLOR') }}
              </label>
              <div class="flex items-center gap-2">
                <input
                  v-model="draft.header_jabvox.button_color"
                  type="color"
                  class="w-9 h-9 rounded-lg cursor-pointer border border-n-weak p-0.5 bg-n-solid-1 shrink-0"
                />
                <div class="flex-1">
                  <Input
                    v-model="draft.header_jabvox.button_color"
                    size="sm"
                    custom-input-class="font-mono"
                  />
                </div>
              </div>
            </div>

            <Input
              v-model="draft.submit_button_text_jabvox"
              :label="$t('JABVOX_FORMS.SUBMIT_BUTTON_TEXT')"
              :placeholder="$t('JABVOX_FORMS.SUBMIT_BUTTON_PLACEHOLDER')"
            />

            <Input
              v-model="draft.slug_jabvox"
              :label="$t('JABVOX_FORMS.SLUG')"
              :placeholder="$t('JABVOX_FORMS.SLUG_PLACEHOLDER')"
              custom-input-class="font-mono"
            />

            <!-- Success section -->
            <div class="border-t border-n-weak pt-3 flex flex-col gap-3">
              <p
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ $t('JABVOX_FORMS.SUCCESS_SECTION') }}
              </p>

              <Textarea
                v-model="draft.submit_actions_jabvox.success.message"
                :label="$t('JABVOX_FORMS.SUCCESS_MESSAGE_LABEL')"
                :placeholder="$t('JABVOX_FORMS.SUCCESS_MESSAGE_PLACEHOLDER')"
                :max-length="300"
              />

              <Input
                v-model="draft.submit_actions_jabvox.success.button_label"
                :label="$t('JABVOX_FORMS.SUCCESS_BTN_LABEL')"
                :placeholder="$t('JABVOX_FORMS.SUCCESS_BTN_LABEL_PLACEHOLDER')"
              />

              <Input
                v-model="draft.submit_actions_jabvox.success.button_url"
                type="url"
                :label="$t('JABVOX_FORMS.SUCCESS_BTN_URL')"
                :placeholder="$t('JABVOX_FORMS.SUCCESS_BTN_URL_PLACEHOLDER')"
              />
            </div>
          </template>

          <!-- ── Pie de página ── -->
          <template v-else-if="activeTab === 'footer'">
            <p class="text-xs text-n-slate-10">
              {{ $t('JABVOX_FORMS.FOOTER_HINT') }}
            </p>
            <Input
              v-for="social in ['whatsapp', 'facebook', 'instagram', 'website']"
              :key="social"
              v-model="draft.footer_jabvox[social]"
              :label="$t(`JABVOX_FORMS.FOOTER_${social.toUpperCase()}`)"
              :placeholder="
                $t(`JABVOX_FORMS.FOOTER_${social.toUpperCase()}_PLACEHOLDER`)
              "
            />
            <Input
              v-model="draft.footer_jabvox.copyright"
              :label="$t('JABVOX_FORMS.FOOTER_COPYRIGHT')"
              :placeholder="$t('JABVOX_FORMS.FOOTER_COPYRIGHT_PLACEHOLDER')"
            />
          </template>

          <!-- ── Acciones ── -->
          <template v-else-if="activeTab === 'actions'">
            <!-- Email -->
            <div
              class="rounded-xl border border-n-weak p-3 flex flex-col gap-3"
            >
              <label class="flex items-center justify-between gap-2">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ $t('JABVOX_FORMS.ACTION_EMAIL') }}
                </span>
                <Switch v-model="draft.submit_actions_jabvox.email.enabled" />
              </label>
              <div
                v-if="draft.submit_actions_jabvox.email.enabled"
                class="flex flex-col gap-2"
              >
                <p
                  class="text-xs text-n-slate-11 bg-n-alpha-1 rounded-lg px-3 py-2"
                >
                  <span
                    class="i-lucide-info size-3 inline-block mr-1 align-middle"
                  />
                  {{ $t('JABVOX_FORMS.ACTION_EMAIL_NOTE') }}
                </p>
                <div class="flex flex-col gap-1.5">
                  <label class="text-xs font-medium text-n-slate-12">
                    {{ $t('JABVOX_FORMS.ACTION_EMAIL_TEMPLATE') }}
                    <span class="text-n-ruby-11">{{
                      $t('JABVOX_FORMS.REQUIRED_MARK')
                    }}</span>
                  </label>
                  <Select
                    v-model="draft.submit_actions_jabvox.email.template_id"
                    :options="emailTemplateOptions"
                  />
                  <p class="text-xs text-n-slate-10">
                    {{ $t('JABVOX_FORMS.ACTION_EMAIL_TEMPLATE_HELP') }}
                  </p>
                </div>
              </div>
            </div>

            <!-- Webhook -->
            <div
              class="rounded-xl border border-n-weak p-3 flex flex-col gap-3"
            >
              <label class="flex items-center justify-between gap-2">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ $t('JABVOX_FORMS.ACTION_WEBHOOK') }}
                </span>
                <Switch v-model="draft.submit_actions_jabvox.webhook.enabled" />
              </label>
              <div
                v-if="draft.submit_actions_jabvox.webhook.enabled"
                class="flex flex-col gap-2"
              >
                <Input
                  v-model="draft.submit_actions_jabvox.webhook.url"
                  type="url"
                  :label="$t('JABVOX_FORMS.ACTION_WEBHOOK_URL')"
                  :placeholder="
                    $t('JABVOX_FORMS.ACTION_WEBHOOK_URL_PLACEHOLDER')
                  "
                />
                <Input
                  v-model="draft.submit_actions_jabvox.webhook.secret"
                  type="password"
                  :label="$t('JABVOX_FORMS.ACTION_WEBHOOK_SECRET')"
                  :placeholder="
                    $t('JABVOX_FORMS.ACTION_WEBHOOK_SECRET_PLACEHOLDER')
                  "
                  :message="$t('JABVOX_FORMS.ACTION_WEBHOOK_SECRET_HELP')"
                />
              </div>
            </div>

            <!-- Privacy policy -->
            <div
              class="rounded-xl border border-n-weak p-3 flex flex-col gap-3"
            >
              <label class="flex items-center justify-between gap-2">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ $t('JABVOX_FORMS.PRIVACY_ENABLED') }}
                </span>
                <Switch v-model="draft.submit_actions_jabvox.privacy.enabled" />
              </label>
              <template v-if="draft.submit_actions_jabvox.privacy.enabled">
                <Input
                  v-model="draft.submit_actions_jabvox.privacy.title"
                  :label="$t('JABVOX_FORMS.PRIVACY_TITLE')"
                  :placeholder="$t('JABVOX_FORMS.PRIVACY_TITLE_DEFAULT')"
                />
                <Textarea
                  v-model="draft.submit_actions_jabvox.privacy.body"
                  :label="$t('JABVOX_FORMS.PRIVACY_BODY')"
                  :max-length="1000"
                />
                <Input
                  v-model="draft.submit_actions_jabvox.privacy.link_text"
                  :label="$t('JABVOX_FORMS.PRIVACY_LINK_TEXT')"
                  :placeholder="$t('JABVOX_FORMS.PRIVACY_LINK_TEXT_DEFAULT')"
                />
                <Input
                  v-model="draft.submit_actions_jabvox.privacy.link_url"
                  type="url"
                  :label="$t('JABVOX_FORMS.PRIVACY_LINK_URL')"
                  :placeholder="$t('JABVOX_FORMS.HEADER_IMAGE_PLACEHOLDER')"
                />
                <Input
                  v-model="draft.submit_actions_jabvox.privacy.accept_text"
                  :label="$t('JABVOX_FORMS.PRIVACY_ACCEPT_TEXT')"
                  :placeholder="$t('JABVOX_FORMS.PRIVACY_ACCEPT_TEXT_DEFAULT')"
                />
              </template>
            </div>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
