<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import SectionCard from '../components/SectionCard.vue';
import ConfirmDialog from '../components/ConfirmDialog.vue';

const store = useStore();
const { t } = useI18n();

const config = useMapGetter('jabvoxProducts/getIntegrationConfig');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const INTEGRATIONS = [
  { value: 'alegra', label: 'Alegra' },
  { value: 'zoho_books', label: 'Zoho Books' },
  { value: 'xero', label: 'Xero' },
  { value: 'quickbooks', label: 'QuickBooks' },
  { value: 'odoo', label: 'Odoo' },
];

const isEditing = ref(false);
const showToken = ref(false);
const deleteDialog = ref(null);
const form = ref({
  integration_type_jabvox: 'alegra',
  integration_email_jabvox: '',
  integration_token_jabvox: '',
});

const isConnected = computed(() => config.value?.connected === true);
const integrationLabel = computed(
  () =>
    INTEGRATIONS.find(i => i.value === config.value?.integration_type_jabvox)
      ?.label ?? ''
);
// Show the editor when actively editing, or when there is no connection yet.
const showEditor = computed(() => isEditing.value || !isConnected.value);

onMounted(() => store.dispatch('jabvoxProducts/fetchIntegrationConfig'));

watch(
  config,
  val => {
    if (val) {
      form.value.integration_type_jabvox =
        val.integration_type_jabvox || 'alegra';
      form.value.integration_email_jabvox = val.integration_email_jabvox || '';
      form.value.integration_token_jabvox = '';
    }
  },
  { immediate: true }
);

const cancelEdit = () => {
  isEditing.value = false;
  if (config.value) {
    form.value.integration_type_jabvox =
      config.value.integration_type_jabvox || 'alegra';
    form.value.integration_email_jabvox =
      config.value.integration_email_jabvox || '';
    form.value.integration_token_jabvox = '';
  }
};

const onSave = async () => {
  try {
    await store.dispatch('jabvoxProducts/saveIntegrationConfig', form.value);
    isEditing.value = false;
    useAlert(t('JABVOX_PRODUCTS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const askDisconnect = () => {
  deleteDialog.value?.open({
    title: t('JABVOX_PRODUCTS.INTEGRATION.DISCONNECT'),
    description: t('JABVOX_PRODUCTS.INTEGRATION.DISCONNECT_CONFIRM'),
    data: true,
  });
};
const doDisconnect = async () => {
  try {
    await store.dispatch('jabvoxProducts/disconnectIntegration');
    isEditing.value = false;
    form.value = {
      integration_type_jabvox: 'alegra',
      integration_email_jabvox: '',
      integration_token_jabvox: '',
    };
    useAlert(t('JABVOX_PRODUCTS.INTEGRATION.DISCONNECT_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};
</script>

<template>
  <div class="w-full max-w-2xl">
    <SectionCard
      :title="t('JABVOX_PRODUCTS.TABS.INTEGRATION')"
      :description="t('JABVOX_PRODUCTS.INTEGRATION.SECTION_DESC')"
      icon="i-lucide-plug"
    >
      <template #actions>
        <Label
          :label="
            isConnected
              ? t('JABVOX_PRODUCTS.INTEGRATION.CONNECTED_LABEL')
              : t('JABVOX_PRODUCTS.INTEGRATION.NOT_CONNECTED_LABEL')
          "
          :color="isConnected ? 'teal' : 'slate'"
        >
          <template #icon>
            <span
              :class="
                isConnected ? 'i-lucide-circle-check' : 'i-lucide-circle-x'
              "
              class="size-3"
            />
          </template>
        </Label>
      </template>

      <!-- Connected summary -->
      <div v-if="isConnected && !isEditing" class="flex flex-col gap-4">
        <div
          class="flex flex-col gap-2 rounded-xl border border-n-weak bg-n-alpha-1 p-4"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="text-xs text-n-slate-10">
              {{ t('JABVOX_PRODUCTS.INTEGRATION.SYSTEM') }}
            </span>
            <span class="text-sm font-medium text-n-slate-12">{{
              integrationLabel
            }}</span>
          </div>
          <div
            v-if="config?.integration_email_jabvox"
            class="flex items-center justify-between gap-2"
          >
            <span class="text-xs text-n-slate-10">
              {{ t('JABVOX_PRODUCTS.INTEGRATION.EMAIL') }}
            </span>
            <span class="text-sm font-mono text-n-slate-11 truncate">
              {{ config.integration_email_jabvox }}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <Button
            :label="t('JABVOX_PRODUCTS.EDIT')"
            icon="i-lucide-pencil"
            variant="outline"
            color="slate"
            size="sm"
            @click="isEditing = true"
          />
          <Button
            :label="t('JABVOX_PRODUCTS.INTEGRATION.DISCONNECT')"
            icon="i-lucide-unplug"
            variant="ghost"
            color="ruby"
            size="sm"
            :is-loading="uiFlags.isSavingConfig"
            @click="askDisconnect"
          />
        </div>
      </div>

      <!-- Editor / connect form -->
      <div v-if="showEditor" class="flex flex-col gap-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_PRODUCTS.INTEGRATION.SYSTEM') }}
          </label>
          <Select
            v-model="form.integration_type_jabvox"
            :options="INTEGRATIONS"
          />
        </div>
        <Input
          v-model="form.integration_email_jabvox"
          type="email"
          :label="t('JABVOX_PRODUCTS.INTEGRATION.EMAIL')"
        />
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_PRODUCTS.INTEGRATION.TOKEN') }}
          </label>
          <div class="relative">
            <Input
              v-model="form.integration_token_jabvox"
              :type="showToken ? 'text' : 'password'"
              custom-input-class="!pr-10 font-mono"
              :placeholder="isConnected ? '••••••••' : ''"
            />
            <button
              type="button"
              class="absolute right-2 top-1/2 -translate-y-1/2 text-n-slate-10 hover:text-n-slate-12"
              @click="showToken = !showToken"
            >
              <span
                :class="showToken ? 'i-lucide-eye-off' : 'i-lucide-eye'"
                class="size-4"
              />
            </button>
          </div>
        </div>
        <div class="flex items-center gap-2 pt-1">
          <Button
            :label="
              isConnected
                ? t('JABVOX_PRODUCTS.SAVE')
                : t('JABVOX_PRODUCTS.INTEGRATION.CONNECT')
            "
            :is-loading="uiFlags.isSavingConfig"
            @click="onSave"
          />
          <Button
            v-if="isConnected"
            :label="t('JABVOX_PRODUCTS.CANCEL')"
            variant="outline"
            color="slate"
            @click="cancelEdit"
          />
        </div>
      </div>
    </SectionCard>

    <ConfirmDialog ref="deleteDialog" @confirm="doDisconnect" />
  </div>
</template>
