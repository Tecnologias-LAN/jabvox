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
const { t } = useI18n();

const dialogRef = ref(null);
const mode = ref('create');
const editingId = ref(null);
const form = ref({ name: '', color: '#64748b', is_active: true });

const title = computed(() =>
  mode.value === 'edit'
    ? t('JABVOX_DIALER.DIALER_STATES.EDIT_TITLE')
    : t('JABVOX_DIALER.DIALER_STATES.NEW')
);
const isValid = computed(() => form.value.name.trim().length > 0);

const openCreate = () => {
  mode.value = 'create';
  editingId.value = null;
  form.value = { name: '', color: '#64748b', is_active: true };
  nextTick(() => dialogRef.value?.open());
};

const openEdit = state => {
  mode.value = 'edit';
  editingId.value = state.id;
  form.value = {
    name: state.name,
    color: state.color,
    is_active: state.is_active,
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
      name: form.value.name.trim(),
      color: form.value.color,
      is_active: form.value.is_active,
    },
  });
};

defineExpose({ openCreate, openEdit, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('JABVOX_DIALER.DIALER_STATES.NEW_SUBTITLE')"
    :confirm-button-label="t('JABVOX_DIALER.COMMON.SAVE')"
    :cancel-button-label="t('JABVOX_DIALER.COMMON.CANCEL')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    width="sm"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('JABVOX_DIALER.DIALER_STATES.FORM.NAME')"
        :placeholder="t('JABVOX_DIALER.DIALER_STATES.FORM.NAME_PLACEHOLDER')"
        autofocus
      />

      <div class="flex flex-col gap-1.5">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_DIALER.DIALER_STATES.FORM.COLOR') }}
        </label>
        <div class="flex items-center gap-2">
          <input
            v-model="form.color"
            type="color"
            class="w-10 h-9 rounded-lg cursor-pointer border border-n-weak p-0.5 bg-n-solid-1 shrink-0"
          />
          <div class="flex-1">
            <Input
              v-model="form.color"
              size="sm"
              custom-input-class="font-mono"
            />
          </div>
        </div>
      </div>

      <div
        class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
      >
        <span class="text-sm text-n-slate-12">
          {{ t('JABVOX_DIALER.DIALER_STATES.FORM.ACTIVE') }}
        </span>
        <Switch v-model="form.is_active" />
      </div>
    </div>
  </Dialog>
</template>
