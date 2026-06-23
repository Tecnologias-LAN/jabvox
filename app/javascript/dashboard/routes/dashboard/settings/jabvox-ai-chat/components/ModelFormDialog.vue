<script setup>
import { ref, computed, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);
const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const editing = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  provider_jabvox: '',
  model_jabvox: '',
  api_key_jabvox: '',
  base_url_jabvox: '',
  is_default_jabvox: false,
});
const form = ref(emptyForm());
const showApiKey = ref(false);

const title = computed(() =>
  editing.value
    ? t('JABVOX_AI_CHAT.MODELS.EDIT')
    : t('JABVOX_AI_CHAT.MODELS.ADD')
);
const isValid = computed(
  () =>
    form.value.name_jabvox.trim().length > 0 &&
    form.value.model_jabvox.trim().length > 0
);

const openCreate = () => {
  editing.value = null;
  form.value = emptyForm();
  showApiKey.value = false;
  nextTick(() => dialogRef.value?.open());
};

const openEdit = model => {
  editing.value = model;
  form.value = {
    name_jabvox: model.name_jabvox,
    provider_jabvox: model.provider_jabvox || '',
    model_jabvox: model.model_jabvox,
    api_key_jabvox: '',
    base_url_jabvox: model.base_url_jabvox || '',
    is_default_jabvox: model.is_default_jabvox,
  };
  showApiKey.value = false;
  nextTick(() => dialogRef.value?.open());
};

const close = () => dialogRef.value?.close();

const handleConfirm = async () => {
  if (!isValid.value) return;
  const payload = { ...form.value };
  if (!payload.api_key_jabvox) delete payload.api_key_jabvox;
  if (!payload.provider_jabvox) delete payload.provider_jabvox;
  try {
    if (editing.value) {
      await store.dispatch('jabvoxAiChat/updateModel', {
        id: editing.value.id,
        ...payload,
      });
    } else {
      await store.dispatch('jabvoxAiChat/createModel', payload);
    }
    close();
    emit('saved');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  }
};

defineExpose({ openCreate, openEdit, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :confirm-button-label="t('JABVOX_AI_CHAT.MODELS.SAVE')"
    :cancel-button-label="t('JABVOX_AI_CHAT.MODELS.CANCEL')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    width="lg"
    overflow-y-auto
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Input
          v-model="form.name_jabvox"
          :label="t('JABVOX_AI_CHAT.MODELS.NAME')"
          :placeholder="t('JABVOX_AI_CHAT.MODELS.NAME_PLACEHOLDER')"
          autofocus
        />
        <Input
          v-model="form.provider_jabvox"
          :label="t('JABVOX_AI_CHAT.MODELS.PROVIDER')"
          :placeholder="t('JABVOX_AI_CHAT.MODELS.PROVIDER_PLACEHOLDER')"
          :message="t('JABVOX_AI_CHAT.MODELS.PROVIDER_HINT')"
        />
      </div>

      <Input
        v-model="form.model_jabvox"
        :label="t('JABVOX_AI_CHAT.MODELS.MODEL_API')"
        :placeholder="t('JABVOX_AI_CHAT.MODELS.MODEL_PLACEHOLDER')"
        custom-input-class="font-mono"
      />

      <!-- API key with reveal toggle -->
      <div class="flex flex-col gap-1.5">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_AI_CHAT.MODELS.API_KEY') }}
        </label>
        <div class="relative">
          <Input
            v-model="form.api_key_jabvox"
            :type="showApiKey ? 'text' : 'password'"
            custom-input-class="!pr-10 font-mono"
            :placeholder="t('JABVOX_AI_CHAT.MODELS.API_KEY_PLACEHOLDER')"
          />
          <button
            type="button"
            class="absolute right-2 top-1/2 -translate-y-1/2 text-n-slate-10 hover:text-n-slate-12"
            @click="showApiKey = !showApiKey"
          >
            <span
              :class="showApiKey ? 'i-lucide-eye-off' : 'i-lucide-eye'"
              class="size-4"
            />
          </button>
        </div>
      </div>

      <Input
        v-model="form.base_url_jabvox"
        :label="t('JABVOX_AI_CHAT.MODELS.BASE_URL')"
        :placeholder="t('JABVOX_AI_CHAT.MODELS.BASE_URL_PLACEHOLDER')"
        :message="t('JABVOX_AI_CHAT.MODELS.BASE_URL_HINT')"
        custom-input-class="font-mono"
      />

      <div
        class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_AI_CHAT.MODELS.IS_DEFAULT') }}
        </span>
        <Switch v-model="form.is_default_jabvox" />
      </div>
    </div>
  </Dialog>
</template>
