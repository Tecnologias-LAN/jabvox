<script setup>
/* eslint-disable no-underscore-dangle */
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SideDrawer from './SideDrawer.vue';

defineProps({
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);
const { t } = useI18n();

const open = ref(false);
const editingId = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  color_jabvox: '#64748b',
  is_active_jabvox: true,
  note_mode: 'optional',
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
]);

const visibleQuestions = computed(() =>
  form.value.questions.filter(q => !q._destroy)
);

const openNew = () => {
  editingId.value = null;
  form.value = emptyForm();
  open.value = true;
};

const openEdit = state => {
  editingId.value = state.id;
  form.value = {
    name_jabvox: state.name_jabvox,
    color_jabvox: state.color_jabvox || '#64748b',
    is_active_jabvox: state.is_active_jabvox ?? true,
    note_mode: state.note_mode || 'optional',
    questions: (state.questions || []).map(q => ({
      id: q.id,
      label: q.label,
      question_type: q.question_type,
      required: q.required,
      options: [...(q.options || [])],
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
  });
};

const removeQuestion = q => {
  if (q.id) {
    q._destroy = true;
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
        <Input
          v-model="form.name_jabvox"
          :label="t('JABVOX_MANAGEMENT_STATES.FORM.NAME')"
          :placeholder="t('JABVOX_MANAGEMENT_STATES.FORM.NAME_PLACEHOLDER')"
          autofocus
        />
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
            v-if="q.question_type === 'list'"
            :value="optionsText(q)"
            rows="3"
            :placeholder="
              t('JABVOX_MANAGEMENT_STATES.QUESTIONS.OPTIONS_PLACEHOLDER')
            "
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y"
            @input="setOptions(q, $event.target.value)"
          />
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
