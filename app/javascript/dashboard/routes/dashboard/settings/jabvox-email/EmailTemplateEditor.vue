<script setup>
import { ref, watch, computed } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import EmailBodyEditor from './EmailBodyEditor.vue';

const props = defineProps({
  template: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const store = useStore();
const uiFlags = computed(() => store.getters['jabvoxEmail/getUIFlags']);
const isEdit = computed(() => !!props.template);
const { t } = useI18n();

const form = ref({
  name: '',
  subject: '',
  body: '',
  active: true,
});

watch(
  () => props.template,
  val => {
    if (val) {
      form.value = {
        name: val.name,
        subject: val.subject || '',
        body: val.body || '',
        active: val.active ?? true,
      };
    } else {
      form.value = { name: '', subject: '', body: '', active: true };
    }
  },
  { immediate: true }
);

const VARIABLES = [
  '{{contact_name}}',
  '{{contact_email}}',
  '{{contact_phone}}',
  '{{stage_name}}',
  '{{funnel_name}}',
];

const subjectRef = ref(null);

const insertVariable = v => {
  const el = subjectRef.value;
  if (el && document.activeElement === el) {
    const start = el.selectionStart;
    const end = el.selectionEnd;
    form.value.subject =
      form.value.subject.slice(0, start) + v + form.value.subject.slice(end);
    setTimeout(() => {
      el.selectionStart = start + v.length;
      el.selectionEnd = start + v.length;
    }, 0);
  } else {
    form.value.body += v;
  }
};

const onVariableDragStart = (event, value) => {
  event.dataTransfer?.setData('text/plain', value);
  event.dataTransfer?.setData('text/jabvox-variable', value);
  event.dataTransfer.dropEffect = 'copy';
};

const onDropSubject = event => {
  const value =
    event.dataTransfer?.getData('text/jabvox-variable') ||
    event.dataTransfer?.getData('text/plain');
  if (!value) return;
  const el = subjectRef.value;
  if (!el) return;
  const start = el.selectionStart ?? form.value.subject.length;
  const end = el.selectionEnd ?? form.value.subject.length;
  form.value.subject =
    form.value.subject.slice(0, start) + value + form.value.subject.slice(end);
  setTimeout(() => {
    el.focus();
    const pos = start + value.length;
    el.selectionStart = pos;
    el.selectionEnd = pos;
  }, 0);
};

const isValid = computed(
  () =>
    form.value.name.trim() &&
    form.value.subject.trim() &&
    form.value.body.trim()
);

const onSave = async () => {
  if (!isValid.value) return;
  try {
    if (isEdit.value) {
      await store.dispatch('jabvoxEmail/updateTemplate', {
        id: props.template.id,
        ...form.value,
      });
    } else {
      await store.dispatch('jabvoxEmail/createTemplate', form.value);
    }
    useAlert(
      isEdit.value
        ? t('JABVOX_EMAIL.TEMPLATES.UPDATE_SUCCESS')
        : t('JABVOX_EMAIL.TEMPLATES.CREATE_SUCCESS')
    );
    emit('close');
  } catch (e) {
    const d = e?.response?.data;
    useAlert(d?.error || d?.message || t('JABVOX_EMAIL.TEMPLATES.SAVE_ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-4 h-full">
    <!-- Header -->
    <div class="flex items-center gap-3">
      <button
        class="text-sm text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200 flex items-center gap-1"
        @click="emit('close')"
      >
        {{ $t('JABVOX_EMAIL.TEMPLATES.BACK') }}
      </button>
      <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
        {{
          isEdit
            ? $t('JABVOX_EMAIL.TEMPLATES.EDIT_TITLE')
            : $t('JABVOX_EMAIL.TEMPLATES.NEW_TITLE')
        }}
      </h2>
    </div>

    <!-- Meta fields -->
    <div
      class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-3"
    >
      <div class="grid grid-cols-2 gap-4">
        <div class="space-y-1">
          <label
            class="block text-xs font-medium text-slate-600 dark:text-slate-300"
          >
            {{ $t('JABVOX_EMAIL.TEMPLATES.FORM.NAME') }}
          </label>
          <input
            v-model="form.name"
            type="text"
            :placeholder="$t('JABVOX_EMAIL.TEMPLATES.FORM.NAME_PLACEHOLDER')"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
        <div class="flex items-end pb-1">
          <label class="flex items-center gap-2 cursor-pointer">
            <input v-model="form.active" type="checkbox" class="rounded" />
            <span class="text-sm text-slate-700 dark:text-slate-300">
              {{ $t('JABVOX_EMAIL.TEMPLATES.FORM.ACTIVE') }}
            </span>
          </label>
        </div>
      </div>

      <div class="space-y-1">
        <label
          class="block text-xs font-medium text-slate-600 dark:text-slate-300"
        >
          {{ $t('JABVOX_EMAIL.TEMPLATES.FORM.SUBJECT') }}
        </label>
        <input
          ref="subjectRef"
          v-model="form.subject"
          type="text"
          :placeholder="$t('JABVOX_EMAIL.TEMPLATES.FORM.SUBJECT_PLACEHOLDER')"
          class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
          @dragover.prevent
          @drop.prevent="onDropSubject"
        />
      </div>

      <div class="flex items-center gap-2 flex-wrap">
        <span class="text-xs text-slate-400">
          {{ $t('JABVOX_EMAIL.TEMPLATES.FORM.VARIABLES_LABEL') }}
        </span>
        <button
          v-for="v in VARIABLES"
          :key="v"
          class="text-xs px-2 py-0.5 rounded bg-woot-50 dark:bg-woot-900/20 text-woot-600 dark:text-woot-400 border border-woot-200 dark:border-woot-800 hover:bg-woot-100 transition-colors font-mono"
          draggable="true"
          @click="insertVariable(v)"
          @dragstart="event => onVariableDragStart(event, v)"
        >
          {{ v }}
        </button>
      </div>
    </div>

    <!-- WYSIWYG Editor -->
    <EmailBodyEditor v-model="form.body" />

    <!-- Actions -->
    <div class="flex gap-3 pt-2">
      <button
        :disabled="uiFlags.isSaving || !isValid"
        class="px-5 py-2 bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium rounded-lg transition-colors disabled:opacity-50"
        @click="onSave"
      >
        {{
          uiFlags.isSaving
            ? $t('JABVOX_EMAIL.TEMPLATES.SAVING')
            : $t('JABVOX_EMAIL.TEMPLATES.SAVE')
        }}
      </button>
      <button
        class="px-5 py-2 border border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-300 text-sm font-medium rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
        @click="emit('close')"
      >
        {{ $t('JABVOX_EMAIL.TEMPLATES.CANCEL') }}
      </button>
    </div>
  </div>
</template>
