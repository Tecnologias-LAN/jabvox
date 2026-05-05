<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

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

onMounted(async () => {
  await store.dispatch('jabvoxProducts/fetchIntegrationConfig');
});

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

const startEdit = () => {
  isEditing.value = true;
};

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

const onDisconnect = async () => {
  if (!window.confirm(t('JABVOX_PRODUCTS.INTEGRATION.DISCONNECT_CONFIRM')))
    return;
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
  <div class="max-w-lg space-y-6">
    <div>
      <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_PRODUCTS.INTEGRATION.TITLE') }}
      </h2>
      <p class="text-sm text-slate-500 mt-1">
        {{ $t('JABVOX_PRODUCTS.INTEGRATION.DESCRIPTION') }}
      </p>
    </div>

    <div
      v-if="uiFlags.isFetchingConfig"
      class="text-sm text-slate-400 animate-pulse py-6"
    >
      {{ $t('JABVOX_PRODUCTS.LOADING') }}
    </div>

    <template v-else>
      <!-- Connected state (read-only view) -->
      <div
        v-if="isConnected && !isEditing"
        class="rounded-xl border border-green-200 bg-green-50 dark:bg-green-900/20 dark:border-green-800 p-5 space-y-4"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="flex items-center gap-2">
            <span
              class="inline-flex items-center gap-1.5 text-xs font-medium text-green-700 dark:text-green-400 bg-green-100 dark:bg-green-900/40 px-2.5 py-1 rounded-full"
            >
              <span
                class="w-1.5 h-1.5 rounded-full bg-green-500 inline-block"
              />
              {{ $t('JABVOX_PRODUCTS.INTEGRATION.CONNECTED_LABEL') }}
            </span>
          </div>
          <div class="flex items-center gap-2">
            <button
              class="text-xs text-slate-600 dark:text-slate-300 hover:text-woot-600 border border-slate-200 dark:border-slate-600 rounded-lg px-3 py-1.5 transition-colors"
              @click="startEdit"
            >
              {{ $t('JABVOX_PRODUCTS.INTEGRATION.EDIT_CONNECTION') }}
            </button>
            <button
              class="text-xs text-red-600 hover:text-red-700 border border-red-200 hover:border-red-300 rounded-lg px-3 py-1.5 transition-colors disabled:opacity-50"
              :disabled="uiFlags.isSavingConfig"
              @click="onDisconnect"
            >
              {{ $t('JABVOX_PRODUCTS.INTEGRATION.DISCONNECT') }}
            </button>
          </div>
        </div>
        <div class="space-y-1">
          <p class="text-sm font-medium text-slate-800 dark:text-slate-100">
            {{ integrationLabel }}
          </p>
          <p class="text-sm text-slate-500 dark:text-slate-400">
            {{ config.integration_email_jabvox }}
          </p>
        </div>
      </div>

      <!-- Not connected state -->
      <div
        v-else-if="!isConnected && !isEditing"
        class="rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/50 p-5 space-y-4"
      >
        <div class="flex items-center gap-2">
          <span
            class="inline-flex items-center gap-1.5 text-xs font-medium text-slate-500 bg-slate-100 dark:bg-slate-700 px-2.5 py-1 rounded-full"
          >
            <span class="w-1.5 h-1.5 rounded-full bg-slate-400 inline-block" />
            {{ $t('JABVOX_PRODUCTS.INTEGRATION.NOT_CONNECTED_LABEL') }}
          </span>
        </div>
        <p class="text-sm text-slate-500">
          {{ $t('JABVOX_PRODUCTS.INTEGRATION.DESCRIPTION') }}
        </p>
        <Button
          :label="$t('JABVOX_PRODUCTS.INTEGRATION.CONNECT')"
          @click="startEdit"
        />
      </div>

      <!-- Edit / Connect form -->
      <div v-if="isEditing || (!isConnected && isEditing)" class="space-y-4">
        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
          >
            {{ $t('JABVOX_PRODUCTS.INTEGRATION.SYSTEM') }}
          </label>
          <select
            v-model="form.integration_type_jabvox"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          >
            <option
              v-for="opt in INTEGRATIONS"
              :key="opt.value"
              :value="opt.value"
            >
              {{ opt.label }}
            </option>
          </select>
        </div>

        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
          >
            {{ $t('JABVOX_PRODUCTS.INTEGRATION.EMAIL') }}
          </label>
          <input
            v-model="form.integration_email_jabvox"
            type="email"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>

        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
          >
            {{ $t('JABVOX_PRODUCTS.INTEGRATION.TOKEN') }}
          </label>
          <input
            v-model="form.integration_token_jabvox"
            type="password"
            :placeholder="isConnected ? '••••••••' : ''"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
          <p v-if="isConnected" class="mt-1 text-xs text-slate-400">
            {{ $t('JABVOX_PRODUCTS.INTEGRATION.TOKEN_HINT') }}
          </p>
        </div>

        <div class="flex items-center gap-3 pt-2">
          <Button
            :label="$t('JABVOX_PRODUCTS.SAVE')"
            :is-loading="uiFlags.isSavingConfig"
            @click="onSave"
          />
          <button
            v-if="isConnected"
            class="text-sm text-slate-500 hover:text-slate-700 dark:text-slate-400"
            @click="cancelEdit"
          >
            {{ $t('JABVOX_PRODUCTS.INTEGRATION.CANCEL') }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
