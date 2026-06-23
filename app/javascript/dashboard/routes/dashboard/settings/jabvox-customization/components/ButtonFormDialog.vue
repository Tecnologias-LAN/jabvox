<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const BUTTON_COLORS = [
  '#6b7280',
  '#3b82f6',
  '#10b981',
  '#f59e0b',
  '#ef4444',
  '#8b5cf6',
  '#ec4899',
  '#06b6d4',
  '#84cc16',
  '#f97316',
];

const { t } = useI18n();

const dialogRef = ref(null);
const mode = ref('create');
const editingId = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  url_jabvox: '',
  color_jabvox: '#6b7280',
  active_jabvox: true,
});
const form = ref(emptyForm());

const title = computed(() =>
  mode.value === 'edit'
    ? t('JABVOX_CUSTOMIZATION.BUTTONS.EDIT_TITLE')
    : t('JABVOX_CUSTOMIZATION.BUTTONS.NEW')
);

const isValid = computed(
  () =>
    form.value.name_jabvox.trim().length > 0 &&
    form.value.url_jabvox.trim().length > 0
);

const openCreate = () => {
  mode.value = 'create';
  editingId.value = null;
  form.value = emptyForm();
  nextTick(() => dialogRef.value?.open());
};

const openEdit = btn => {
  mode.value = 'edit';
  editingId.value = btn.id;
  form.value = {
    name_jabvox: btn.name_jabvox,
    url_jabvox: btn.url_jabvox,
    color_jabvox: btn.color_jabvox,
    active_jabvox: btn.active_jabvox,
  };
  nextTick(() => dialogRef.value?.open());
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (!isValid.value) return;
  emit('submit', {
    mode: mode.value,
    id: editingId.value,
    values: {
      name_jabvox: form.value.name_jabvox.trim(),
      url_jabvox: form.value.url_jabvox.trim(),
      color_jabvox: form.value.color_jabvox,
      active_jabvox: form.value.active_jabvox,
    },
  });
};

defineExpose({ openCreate, openEdit, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('JABVOX_CUSTOMIZATION.BUTTONS.FORM_DESCRIPTION')"
    :confirm-button-label="t('JABVOX_CUSTOMIZATION.BUTTONS.SAVE')"
    :cancel-button-label="t('JABVOX_CUSTOMIZATION.BUTTONS.CANCEL')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    width="lg"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name_jabvox"
        :label="t('JABVOX_CUSTOMIZATION.BUTTONS.NAME_LABEL')"
        :placeholder="t('JABVOX_CUSTOMIZATION.BUTTONS.NAME_PLACEHOLDER')"
        autofocus
      />
      <Input
        v-model="form.url_jabvox"
        :label="t('JABVOX_CUSTOMIZATION.BUTTONS.URL_LABEL')"
        :placeholder="t('JABVOX_CUSTOMIZATION.BUTTONS.URL_PLACEHOLDER')"
        :message="t('JABVOX_CUSTOMIZATION.BUTTONS.URL_HINT')"
      />

      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_CUSTOMIZATION.BUTTONS.COLOR_LABEL') }}
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="color in BUTTON_COLORS"
            :key="color"
            type="button"
            class="size-7 rounded-full border-2 transition-transform hover:scale-110"
            :style="{
              backgroundColor: color,
              borderColor: form.color_jabvox === color ? color : 'transparent',
            }"
            :class="form.color_jabvox === color ? 'scale-110 shadow-md' : ''"
            @click="form.color_jabvox = color"
          />
        </div>
      </div>

      <div
        class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
      >
        <div class="flex flex-col">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_CUSTOMIZATION.BUTTONS.ACTIVE_LABEL') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('JABVOX_CUSTOMIZATION.BUTTONS.ACTIVE_HINT') }}
          </span>
        </div>
        <Switch v-model="form.active_jabvox" />
      </div>
    </div>
  </Dialog>
</template>
