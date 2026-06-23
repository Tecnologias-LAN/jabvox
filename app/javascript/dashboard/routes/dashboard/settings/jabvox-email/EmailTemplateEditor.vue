<script setup>
import { ref, watch, computed } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
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
    <div class="flex items-center gap-2">
      <Button
        icon="i-lucide-arrow-left"
        :label="$t('JABVOX_EMAIL.TEMPLATES.BACK')"
        variant="ghost"
        color="slate"
        size="sm"
        @click="emit('close')"
      />
      <h2 class="text-base font-semibold text-n-slate-12">
        {{
          isEdit
            ? $t('JABVOX_EMAIL.TEMPLATES.EDIT_TITLE')
            : $t('JABVOX_EMAIL.TEMPLATES.NEW_TITLE')
        }}
      </h2>
    </div>

    <!-- Meta fields -->
    <div
      class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 flex flex-col gap-3"
    >
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 items-end">
        <Input
          v-model="form.name"
          :label="$t('JABVOX_EMAIL.TEMPLATES.FORM.NAME')"
          :placeholder="$t('JABVOX_EMAIL.TEMPLATES.FORM.NAME_PLACEHOLDER')"
        />
        <div
          class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-2.5"
        >
          <span class="text-sm text-n-slate-12">
            {{ $t('JABVOX_EMAIL.TEMPLATES.FORM.ACTIVE') }}
          </span>
          <Switch v-model="form.active" />
        </div>
      </div>

      <div class="flex flex-col gap-1.5">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('JABVOX_EMAIL.TEMPLATES.FORM.SUBJECT') }}
        </label>
        <input
          ref="subjectRef"
          v-model="form.subject"
          type="text"
          :placeholder="$t('JABVOX_EMAIL.TEMPLATES.FORM.SUBJECT_PLACEHOLDER')"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          @dragover.prevent
          @drop.prevent="onDropSubject"
        />
      </div>

      <div class="flex items-center gap-2 flex-wrap">
        <span class="text-xs text-n-slate-10">
          {{ $t('JABVOX_EMAIL.TEMPLATES.FORM.VARIABLES_LABEL') }}
        </span>
        <button
          v-for="v in VARIABLES"
          :key="v"
          class="text-xs px-2 py-0.5 rounded-md bg-n-alpha-2 text-n-brand border border-n-weak hover:bg-n-alpha-3 transition-colors font-mono"
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
    <div class="flex gap-2 pt-2">
      <Button
        :label="
          uiFlags.isSaving
            ? $t('JABVOX_EMAIL.TEMPLATES.SAVING')
            : $t('JABVOX_EMAIL.TEMPLATES.SAVE')
        "
        :is-loading="uiFlags.isSaving"
        :disabled="!isValid"
        @click="onSave"
      />
      <Button
        :label="$t('JABVOX_EMAIL.TEMPLATES.CANCEL')"
        variant="outline"
        color="slate"
        @click="emit('close')"
      />
    </div>
  </div>
</template>
