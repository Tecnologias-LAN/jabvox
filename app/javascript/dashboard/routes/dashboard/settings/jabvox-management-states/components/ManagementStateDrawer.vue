<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { DESTROY_KEY } from 'dashboard/helper/jabvox/nestedAttributes';
import SideDrawer from './SideDrawer.vue';

const props = defineProps({
  isSaving: { type: Boolean, default: false },
  // Existing group names, offered as datalist suggestions (typing a new one is allowed).
  groupSuggestions: { type: Array, default: () => [] },
  // Lead/contact fields available to map an answer to (autofill at typification).
  // Each item: { value: 'contact.phone_number', label: 'Teléfono' }.
  leadFieldOptions: { type: Array, default: () => [] },
});

const emit = defineEmits(['submit']);
const { t } = useI18n();

const open = ref(false);
const editingId = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  state_group_jabvox: '',
  usage_info_jabvox: '',
  color_jabvox: '#64748b',
  is_active_jabvox: true,
  note_mode: 'optional',
  managed_jabvox: true,
  contact_jabvox: false,
  effective_contact_jabvox: false,
  advisory_jabvox: false,
  service_type_jabvox: 'No',
  positivity_level_jabvox: 0,
  questions: [],
});
const form = ref(emptyForm());

const title = computed(() =>
  editingId.value
    ? t('JABVOX_MANAGEMENT_STATES.EDIT')
    : t('JABVOX_MANAGEMENT_STATES.NEW')
);
const isValid = computed(() => form.value.name_jabvox.trim().length > 0);

const noteModeOptions = computed(() => [
  {
    value: 'optional',
    label: t('JABVOX_MANAGEMENT_STATES.FORM.NOTE_OPTIONAL'),
  },
  {
    value: 'required',
    label: t('JABVOX_MANAGEMENT_STATES.FORM.NOTE_REQUIRED'),
  },
  { value: 'hidden', label: t('JABVOX_MANAGEMENT_STATES.FORM.NOTE_HIDDEN') },
]);

// Stored as-is on service_type_jabvox (backend expects these exact strings).
const SERVICE_TYPES = [
  'No',
  'Asesoría 1:1',
  'Asesoría Express',
  'Asesoria Grupal',
  'Toma de pedido',
  'Recordatorio de fechas',
  'Rechazos',
  'Atencion NE WA',
  'Llamada digital',
];
const serviceTypeOptions = SERVICE_TYPES.map(value => ({
  value,
  label: value,
}));

const questionTypeOptions = computed(() => [
  { value: 'text', label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.TYPE_TEXT') },
  {
    value: 'number',
    label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.TYPE_NUMBER'),
  },
  { value: 'date', label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.TYPE_DATE') },
  {
    value: 'boolean',
    label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.TYPE_BOOLEAN'),
  },
  { value: 'list', label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.TYPE_LIST') },
  {
    value: 'multiselect',
    label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.TYPE_MULTISELECT'),
  },
]);

// Types that carry a list of options (single- and multi-select).
const OPTION_TYPES = ['list', 'multiselect'];
const hasOptions = q => OPTION_TYPES.includes(q.question_type);

const visibilityOperatorOptions = computed(() => [
  {
    value: 'equals',
    label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.OP_EQUALS'),
  },
  {
    value: 'not_equals',
    label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.OP_NOT_EQUALS'),
  },
  {
    value: 'includes',
    label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.OP_INCLUDES'),
  },
  {
    value: 'answered',
    label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.OP_ANSWERED'),
  },
]);

const visibilityLogicOptions = computed(() => [
  { value: 'and', label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.LOGIC_AND') },
  { value: 'or', label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.LOGIC_OR') },
]);

// Options for the "autofill from lead" selector: a "none" entry + the fields
// provided by the parent (base contact fields + custom attributes + lead cols).
const leadFieldSelectOptions = computed(() => [
  { value: '', label: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.LEAD_FIELD_NONE') },
  ...props.leadFieldOptions,
]);

const visibleQuestions = computed(() =>
  form.value.questions.filter(q => !q[DESTROY_KEY])
);

// Deep-clone visibility into a plain editable object with a guaranteed shape.
const cloneVisibility = raw => {
  const rules = Array.isArray(raw?.rules) ? raw.rules : [];
  return {
    logic: raw?.logic === 'or' ? 'or' : 'and',
    rules: rules.map(r => ({
      question: r.question ?? '',
      operator: r.operator ?? 'equals',
      value: r.value ?? '',
    })),
  };
};

// Other questions (by label) that a rule can reference — excludes self and
// blank labels, since rules match on label.
const conditionSourceOptions = q =>
  visibleQuestions.value
    .filter(other => other !== q && (other.label || '').trim().length > 0)
    .map(other => ({ value: other.label, label: other.label }));

const addCondition = q => {
  if (!q.visibility) q.visibility = { logic: 'and', rules: [] };
  q.visibility.rules.push({ question: '', operator: 'equals', value: '' });
};

const removeCondition = (q, idx) => {
  q.visibility.rules.splice(idx, 1);
};

const openNew = () => {
  editingId.value = null;
  form.value = emptyForm();
  open.value = true;
};

const openEdit = state => {
  editingId.value = state.id;
  form.value = {
    name_jabvox: state.name_jabvox,
    state_group_jabvox: state.state_group_jabvox || '',
    usage_info_jabvox: state.usage_info_jabvox || '',
    color_jabvox: state.color_jabvox || '#64748b',
    is_active_jabvox: state.is_active_jabvox ?? true,
    note_mode: state.note_mode || 'optional',
    managed_jabvox: state.managed_jabvox !== false,
    contact_jabvox: state.contact_jabvox === true,
    effective_contact_jabvox: state.effective_contact_jabvox === true,
    advisory_jabvox: state.advisory_jabvox === true,
    service_type_jabvox: state.service_type_jabvox || 'No',
    positivity_level_jabvox: state.positivity_level_jabvox ?? 0,
    questions: (state.questions || []).map(q => ({
      id: q.id,
      label: q.label,
      question_type: q.question_type,
      required: q.required,
      options: [...(q.options || [])],
      visibility: cloneVisibility(q.visibility),
      lead_field: q.lead_field || '',
      lead_field_locked: q.lead_field_locked === true,
    })),
  };
  open.value = true;
};

const close = () => {
  open.value = false;
};

const addQuestion = () => {
  form.value.questions.push({
    label: '',
    question_type: 'text',
    required: false,
    options: [],
    visibility: { logic: 'and', rules: [] },
    lead_field: '',
    lead_field_locked: false,
  });
};

const removeQuestion = q => {
  if (q.id) {
    q[DESTROY_KEY] = true;
  } else {
    form.value.questions = form.value.questions.filter(x => x !== q);
  }
};

const optionsText = q => (q.options || []).join('\n');
const setOptions = (q, text) => {
  q.options = text
    .split('\n')
    .map(s => s.trim())
    .filter(Boolean);
};

const handleSubmit = () => {
  if (!isValid.value) return;
  emit('submit', {
    id: editingId.value,
    form: form.value,
  });
};

defineExpose({ openNew, openEdit, close });
</script>

<template>
  <SideDrawer v-model:open="open" :title="title">
    <div class="flex flex-col gap-8">
      <!-- Live preview -->
      <div
        class="flex items-center justify-between gap-3 rounded-2xl border border-n-weak bg-n-alpha-1 px-4 py-4"
      >
        <span class="text-xs font-medium text-n-slate-10">
          {{ t('JABVOX_MANAGEMENT_STATES.DRAWER.PREVIEW_TITLE') }}
        </span>
        <span
          class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-sm font-medium"
          :style="{
            backgroundColor: `${form.color_jabvox}1a`,
            color: form.color_jabvox,
          }"
        >
          <span
            class="size-2 rounded-full"
            :style="{ backgroundColor: form.color_jabvox }"
          />
          {{ form.name_jabvox || t('JABVOX_MANAGEMENT_STATES.FORM.NAME') }}
        </span>
      </div>

      <!-- General -->
      <section class="flex flex-col gap-4">
        <h3
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_MANAGEMENT_STATES.DRAWER.SECTION_GENERAL') }}
        </h3>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_MANAGEMENT_STATES.FORM.GROUP') }}
          </label>
          <input
            v-model="form.state_group_jabvox"
            type="text"
            list="jabvox-mgmt-group-suggestions"
            :placeholder="t('JABVOX_MANAGEMENT_STATES.FORM.GROUP_PLACEHOLDER')"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
          <datalist id="jabvox-mgmt-group-suggestions">
            <option v-for="g in groupSuggestions" :key="g" :value="g" />
          </datalist>
        </div>
        <Input
          v-model="form.name_jabvox"
          :label="t('JABVOX_MANAGEMENT_STATES.FORM.SUBSTATE')"
          :placeholder="t('JABVOX_MANAGEMENT_STATES.FORM.NAME_PLACEHOLDER')"
          autofocus
        />
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_MANAGEMENT_STATES.FORM.USAGE_INFO') }}
          </label>
          <textarea
            v-model="form.usage_info_jabvox"
            rows="3"
            :placeholder="
              t('JABVOX_MANAGEMENT_STATES.FORM.USAGE_INFO_PLACEHOLDER')
            "
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y"
          />
        </div>
      </section>

      <!-- Appearance -->
      <section class="flex flex-col gap-4">
        <h3
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_MANAGEMENT_STATES.DRAWER.SECTION_APPEARANCE') }}
        </h3>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_MANAGEMENT_STATES.FORM.COLOR') }}
          </label>
          <div class="flex items-center gap-2">
            <input
              v-model="form.color_jabvox"
              type="color"
              class="w-10 h-9 rounded-lg cursor-pointer border border-n-weak p-0.5 bg-n-solid-1 shrink-0"
              :aria-label="t('JABVOX_MANAGEMENT_STATES.FORM.COLOR')"
            />
            <div class="flex-1">
              <Input
                v-model="form.color_jabvox"
                size="sm"
                custom-input-class="font-mono"
              />
            </div>
          </div>
        </div>
      </section>

      <!-- Configuration -->
      <section class="flex flex-col gap-4">
        <h3
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_MANAGEMENT_STATES.DRAWER.SECTION_CONFIG') }}
        </h3>
        <div
          class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
        >
          <div class="flex flex-col">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_MANAGEMENT_STATES.FORM.ACTIVE') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('JABVOX_MANAGEMENT_STATES.DRAWER.ACTIVE_HINT') }}
            </span>
          </div>
          <Switch v-model="form.is_active_jabvox" />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_MANAGEMENT_STATES.FORM.NOTE_MODE') }}
          </label>
          <Select v-model="form.note_mode" :options="noteModeOptions" />
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <label
            v-for="flag in [
              ['managed_jabvox', 'MANAGED'],
              ['contact_jabvox', 'CONTACT'],
              ['effective_contact_jabvox', 'EFFECTIVE_CONTACT'],
              ['advisory_jabvox', 'ADVISORY'],
            ]"
            :key="flag[0]"
            class="flex items-center justify-between gap-2 rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2.5 cursor-pointer"
          >
            <span class="text-sm text-n-slate-12">
              {{ t(`JABVOX_MANAGEMENT_STATES.FORM.${flag[1]}`) }}
            </span>
            <Switch v-model="form[flag[0]]" />
          </label>
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_MANAGEMENT_STATES.FORM.SERVICE_TYPE') }}
          </label>
          <Select
            v-model="form.service_type_jabvox"
            :options="serviceTypeOptions"
          />
        </div>
        <Input
          v-model="form.positivity_level_jabvox"
          type="number"
          min="0"
          max="100"
          :label="t('JABVOX_MANAGEMENT_STATES.FORM.POSITIVITY_LEVEL')"
        />
      </section>

      <!-- Questions -->
      <section class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <h3
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.TITLE') }}
          </h3>
          <Button
            :label="t('JABVOX_MANAGEMENT_STATES.QUESTIONS.ADD')"
            icon="i-lucide-plus"
            variant="outline"
            color="slate"
            size="sm"
            @click="addQuestion"
          />
        </div>

        <div
          v-for="q in visibleQuestions"
          :key="q.id ?? q"
          class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-3"
        >
          <div class="flex items-start gap-2">
            <div class="flex-1">
              <Input
                v-model="q.label"
                size="sm"
                :placeholder="t('JABVOX_MANAGEMENT_STATES.QUESTIONS.LABEL')"
              />
            </div>
            <Button
              icon="i-lucide-trash-2"
              variant="ghost"
              color="ruby"
              size="sm"
              @click="removeQuestion(q)"
            />
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <Select v-model="q.question_type" :options="questionTypeOptions" />
            <label
              class="flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 cursor-pointer"
            >
              <Switch v-model="q.required" />
              <span class="text-sm text-n-slate-12">
                {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.REQUIRED') }}
              </span>
            </label>
          </div>
          <textarea
            v-if="hasOptions(q)"
            :value="optionsText(q)"
            rows="3"
            :placeholder="
              t('JABVOX_MANAGEMENT_STATES.QUESTIONS.OPTIONS_PLACEHOLDER')
            "
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y"
            @input="setOptions(q, $event.target.value)"
          />

          <!-- Autofill from a lead/contact field -->
          <div
            class="flex flex-col gap-2 rounded-lg border border-dashed border-n-weak bg-n-solid-1 p-2.5"
          >
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.LEAD_FIELD_TITLE') }}
            </span>
            <select
              v-model="q.lead_field"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-2 py-1.5 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            >
              <option
                v-for="opt in leadFieldSelectOptions"
                :key="opt.value"
                :value="opt.value"
              >
                {{ opt.label }}
              </option>
            </select>
            <label
              v-if="q.lead_field"
              class="flex items-center gap-2 cursor-pointer"
            >
              <Switch v-model="q.lead_field_locked" />
              <span class="text-xs text-n-slate-11">
                {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.LEAD_FIELD_LOCKED') }}
              </span>
            </label>
          </div>

          <!-- Conditional visibility: show this question only when… -->
          <div
            class="flex flex-col gap-2 rounded-lg border border-dashed border-n-weak bg-n-solid-1 p-2.5"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.VISIBILITY_TITLE') }}
              </span>
              <Button
                :label="t('JABVOX_MANAGEMENT_STATES.QUESTIONS.ADD_CONDITION')"
                icon="i-lucide-plus"
                variant="ghost"
                color="slate"
                size="xs"
                @click="addCondition(q)"
              />
            </div>

            <p
              v-if="!q.visibility || q.visibility.rules.length === 0"
              class="text-xs text-n-slate-10"
            >
              {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.VISIBILITY_ALWAYS') }}
            </p>

            <template v-else>
              <div
                v-if="q.visibility.rules.length > 1"
                class="flex items-center gap-2"
              >
                <span class="text-xs text-n-slate-10">
                  {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.MATCH') }}
                </span>
                <Select
                  v-model="q.visibility.logic"
                  :options="visibilityLogicOptions"
                  size="sm"
                />
              </div>

              <div
                v-for="(rule, idx) in q.visibility.rules"
                :key="idx"
                class="flex flex-col gap-1.5 sm:flex-row sm:items-center"
              >
                <select
                  v-model="rule.question"
                  class="flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm px-2 py-1.5 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                >
                  <option value="">
                    {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.PICK_QUESTION') }}
                  </option>
                  <option
                    v-for="opt in conditionSourceOptions(q)"
                    :key="opt.value"
                    :value="opt.value"
                  >
                    {{ opt.label }}
                  </option>
                </select>
                <select
                  v-model="rule.operator"
                  class="rounded-lg border border-n-weak bg-n-solid-1 text-sm px-2 py-1.5 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                >
                  <option
                    v-for="opt in visibilityOperatorOptions"
                    :key="opt.value"
                    :value="opt.value"
                  >
                    {{ opt.label }}
                  </option>
                </select>
                <input
                  v-if="rule.operator !== 'answered'"
                  v-model="rule.value"
                  type="text"
                  :placeholder="
                    t('JABVOX_MANAGEMENT_STATES.QUESTIONS.CONDITION_VALUE')
                  "
                  class="flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm px-2 py-1.5 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                />
                <Button
                  icon="i-lucide-x"
                  variant="ghost"
                  color="ruby"
                  size="xs"
                  @click="removeCondition(q, idx)"
                />
              </div>
            </template>
          </div>
        </div>
      </section>
    </div>

    <template #footer>
      <div class="flex items-center justify-end gap-2">
        <Button
          :label="t('JABVOX_MANAGEMENT_STATES.COMMON.CANCEL')"
          variant="outline"
          color="slate"
          @click="close"
        />
        <Button
          :label="t('JABVOX_MANAGEMENT_STATES.SAVE')"
          :is-loading="isSaving"
          :disabled="!isValid"
          @click="handleSubmit"
        />
      </div>
    </template>
  </SideDrawer>
</template>
