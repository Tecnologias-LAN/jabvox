<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  availableAgents: { type: Array, default: () => [] },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);
const { t } = useI18n();

const dialogRef = ref(null);
const userId = ref('');
const extension = ref('');

const agentOptions = computed(() =>
  props.availableAgents.map(a => ({
    value: a.id,
    label: `${a.name} (${a.email})`,
  }))
);
const isValid = computed(
  () => !!userId.value && extension.value.trim().length > 0
);

const open = () => {
  userId.value = '';
  extension.value = '';
  nextTick(() => dialogRef.value?.open());
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (!isValid.value) return;
  emit('submit', { userId: userId.value, extension: extension.value.trim() });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('JABVOX_VOIP.EXTENSIONS.ADD_TITLE')"
    :description="t('JABVOX_VOIP.EXTENSIONS.SUBTITLE')"
    :confirm-button-label="t('JABVOX_VOIP.EXTENSIONS.ADD')"
    :cancel-button-label="t('JABVOX_VOIP.COMMON.CANCEL')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    width="lg"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <div class="flex flex-col gap-1.5">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_VOIP.EXTENSIONS.USER') }}
        </label>
        <Select
          v-model="userId"
          :options="agentOptions"
          :placeholder="t('JABVOX_VOIP.EXTENSIONS.SELECT_USER')"
        />
      </div>
      <Input
        v-model="extension"
        :label="t('JABVOX_VOIP.EXTENSIONS.EXTENSION')"
        :placeholder="t('JABVOX_VOIP.EXTENSIONS.PLACEHOLDER')"
        custom-input-class="font-mono"
        @keydown.enter="handleConfirm"
      />
    </div>
  </Dialog>
</template>
