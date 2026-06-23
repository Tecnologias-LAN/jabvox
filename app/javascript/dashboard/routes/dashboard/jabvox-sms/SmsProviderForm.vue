<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  provider: { type: Object, default: null },
});
const emit = defineEmits(['save', 'cancel']);

const uiFlags = useMapGetter('jabvoxSms/getUIFlags');
const { markDirty, markClean } = useUnsavedChanges();

const isEdit = computed(() => !!props.provider);

const form = ref({
  name: '',
  base_url: '',
  api_user: '',
  api_password: '',
  active: true,
});

const isValid = computed(
  () =>
    form.value.name.trim() &&
    form.value.base_url.trim() &&
    form.value.api_user.trim()
);

watch(form, () => markDirty(), { deep: true });

onMounted(async () => {
  if (props.provider) {
    form.value = {
      name: props.provider.name || '',
      base_url: props.provider.base_url || '',
      api_user: props.provider.api_user || '',
      api_password: '',
      active: props.provider.active ?? true,
    };
  }
  await nextTick();
  markClean();
});

const onSave = async () => {
  if (!isValid.value) return;
  emit('save', { ...form.value });
  await nextTick();
  markClean();
};

const onCancel = async () => {
  emit('cancel');
  await nextTick();
  markClean();
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <Input
      v-model="form.name"
      :label="$t('JABVOX_SMS.PROVIDERS.FORM.NAME')"
      :placeholder="$t('JABVOX_SMS.PROVIDERS.FORM.NAME_PLACEHOLDER')"
      autofocus
    />
    <Input
      v-model="form.base_url"
      :label="$t('JABVOX_SMS.PROVIDERS.FORM.BASE_URL')"
      :placeholder="$t('JABVOX_SMS.PROVIDERS.FORM.BASE_URL_PLACEHOLDER')"
      custom-input-class="font-mono"
    />
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <Input
        v-model="form.api_user"
        :label="$t('JABVOX_SMS.PROVIDERS.FORM.API_USER')"
        :placeholder="$t('JABVOX_SMS.PROVIDERS.FORM.API_USER_PLACEHOLDER')"
      />
      <Input
        v-model="form.api_password"
        type="password"
        :label="$t('JABVOX_SMS.PROVIDERS.FORM.API_PASSWORD')"
        :placeholder="$t('JABVOX_SMS.PROVIDERS.FORM.API_PASSWORD_PLACEHOLDER')"
        :message="isEdit ? $t('JABVOX_SMS.PROVIDERS.FORM.PASSWORD_HINT') : ''"
      />
    </div>

    <div
      class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
    >
      <div class="flex flex-col">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('JABVOX_SMS.PROVIDERS.FORM.ACTIVE') }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ $t('JABVOX_SMS.PROVIDERS.ACTIVE_HINT') }}
        </span>
      </div>
      <Switch v-model="form.active" />
    </div>

    <div class="flex justify-end gap-2 pt-1">
      <Button
        variant="outline"
        color="slate"
        :label="$t('JABVOX_SMS.COMMON.CANCEL')"
        @click="onCancel"
      />
      <Button
        :label="$t('JABVOX_SMS.SAVE')"
        :is-loading="uiFlags.isSaving"
        :disabled="uiFlags.isSaving || !isValid"
        @click="onSave"
      />
    </div>
  </div>
</template>
