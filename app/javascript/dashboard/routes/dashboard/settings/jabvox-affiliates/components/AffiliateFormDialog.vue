<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);
const { t } = useI18n();

const dialogRef = ref(null);
const name = ref('');
// When set, the dialog switches to "credentials" mode after creation.
const created = ref(null);

const isValid = computed(() => name.value.trim().length > 0);
const createdCode = computed(() => created.value?.account_code ?? '');
const createdToken = computed(() => created.value?.auth_token ?? '');

const open = () => {
  name.value = '';
  created.value = null;
  nextTick(() => dialogRef.value?.open());
};

// Called by the parent after a successful create to reveal the credentials.
const showCredentials = affiliate => {
  created.value = affiliate;
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (created.value) {
    close();
    return;
  }
  if (!isValid.value) return;
  emit('submit', name.value.trim());
};

const copy = async text => {
  await navigator.clipboard.writeText(text);
  useAlert(t('JABVOX_AFFILIATES.COPIED'));
};

defineExpose({ open, showCredentials, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      created
        ? t('JABVOX_AFFILIATES.FORM.CREDENTIALS_TITLE')
        : t('JABVOX_AFFILIATES.FORM.TITLE')
    "
    :description="created ? '' : t('JABVOX_AFFILIATES.FORM.SUBTITLE')"
    :confirm-button-label="
      created
        ? t('JABVOX_AFFILIATES.FORM.DONE')
        : t('JABVOX_AFFILIATES.FORM.SUBMIT')
    "
    :cancel-button-label="t('JABVOX_AFFILIATES.FORM.CANCEL')"
    :show-cancel-button="!created"
    :disable-confirm-button="!created && !isValid"
    :is-loading="isSaving"
    width="lg"
    @confirm="handleConfirm"
  >
    <!-- Step 1: name -->
    <Input
      v-if="!created"
      v-model="name"
      :label="t('JABVOX_AFFILIATES.FORM.NAME_LABEL')"
      :placeholder="t('JABVOX_AFFILIATES.FORM.NAME_PLACEHOLDER')"
      autofocus
      @keydown.enter="handleConfirm"
    />

    <!-- Step 2: generated credentials -->
    <div v-else class="flex flex-col gap-4">
      <div
        class="flex items-start gap-2 rounded-xl border border-n-amber-6 bg-n-amber-2 px-3 py-2.5"
      >
        <span
          class="i-lucide-triangle-alert size-4 text-n-amber-11 shrink-0 mt-0.5"
        />
        <p class="text-xs text-n-amber-12 leading-relaxed">
          {{ t('JABVOX_AFFILIATES.FORM.CREDENTIALS_WARNING') }}
        </p>
      </div>

      <div class="flex flex-col gap-1.5">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_AFFILIATES.FORM.ACCOUNT_CODE') }}
        </label>
        <div class="flex items-center gap-2">
          <code
            class="flex-1 min-w-0 truncate rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-mono text-n-slate-12"
          >
            {{ createdCode }}
          </code>
          <Button
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-copy"
            @click="copy(createdCode)"
          />
        </div>
      </div>

      <div class="flex flex-col gap-1.5">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_AFFILIATES.FORM.TOKEN') }}
        </label>
        <div class="flex items-center gap-2">
          <code
            class="flex-1 min-w-0 truncate rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-mono text-n-slate-12"
          >
            {{ createdToken }}
          </code>
          <Button
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-copy"
            @click="copy(createdToken)"
          />
        </div>
      </div>
    </div>
  </Dialog>
</template>
