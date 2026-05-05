<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const config = useMapGetter('jabvoxSaldo/getConfig');
const status = useMapGetter('jabvoxSaldo/getStatus');
const uiFlags = useMapGetter('jabvoxSaldo/getUIFlags');

const form = ref({
  name_jabvox: '',
  proxy_url_jabvox: '',
  api_key_jabvox: '',
  api_secret_jabvox: '',
  is_active_jabvox: true,
});

const hasApiKey = computed(() => !!config.value?.api_key_jabvox);

const fillForm = data => {
  form.value = {
    name_jabvox: data?.name_jabvox || '',
    proxy_url_jabvox: data?.proxy_url_jabvox || '',
    api_key_jabvox: '',
    api_secret_jabvox: '',
    is_active_jabvox: data?.is_active_jabvox ?? true,
  };
};

const loadData = async () => {
  await store.dispatch('jabvoxSaldo/fetchConfig');
  fillForm(config.value);
  await store.dispatch('jabvoxSaldo/fetchStatus');
};

onMounted(loadData);

const onSave = async () => {
  try {
    const payload = { ...form.value };
    if (!payload.api_key_jabvox) delete payload.api_key_jabvox;
    if (!payload.api_secret_jabvox) delete payload.api_secret_jabvox;
    await store.dispatch('jabvoxSaldo/updateConfig', payload);
    form.value.api_key_jabvox = '';
    form.value.api_secret_jabvox = '';
    useAlert(t('JABVOX_SALDO.SAVE_SUCCESS'));
    await loadData();
  } catch {
    useAlert(t('JABVOX_SALDO.ERROR'));
  }
};

const onRefreshStatus = () => store.dispatch('jabvoxSaldo/fetchStatus');

const formatBalance = value => {
  const n = Number(value || 0);
  return `$${n.toLocaleString('es-CO', { minimumFractionDigits: 0, maximumFractionDigits: 0 })} COP`;
};

const balanceColor = computed(() => {
  const n = Number(status.value?.balance || 0);
  if (n <= 10000) return { color: '#ef4444' };
  if (n < 50000) return { color: '#f97316' };
  return { color: '#2563eb' };
});
</script>

<template>
  <SettingsLayout>
    <BaseSettingsHeader
      :title="$t('JABVOX_SALDO.TITLE')"
      :description="$t('JABVOX_SALDO.DESCRIPTION')"
    />

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-6 space-y-5"
      >
        <h3 class="text-sm font-semibold text-slate-800 dark:text-slate-100">
          {{ $t('JABVOX_SALDO.FORM.TITLE') }}
        </h3>

        <div class="space-y-4">
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_SALDO.FORM.NAME') }}
            </label>
            <input
              v-model="form.name_jabvox"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100"
            />
          </div>

          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_SALDO.FORM.PROXY_URL') }}
              <span>{{ $t('JABVOX_SALDO.FORM.REQUIRED') }}</span>
            </label>
            <input
              v-model="form.proxy_url_jabvox"
              type="text"
              :placeholder="$t('JABVOX_SALDO.FORM.PROXY_URL_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100"
            />
          </div>

          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_SALDO.FORM.API_KEY') }}
              <span
                v-if="hasApiKey && !form.api_key_jabvox"
                class="ml-1 font-normal text-slate-400"
              >
                {{ $t('JABVOX_SALDO.FORM.API_SECRET_HINT') }}
              </span>
            </label>
            <input
              v-model="form.api_key_jabvox"
              type="password"
              :placeholder="
                hasApiKey ? '••••••••••••' : $t('JABVOX_SALDO.FORM.API_KEY')
              "
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100"
            />
          </div>

          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_SALDO.FORM.API_SECRET') }}
              <span class="ml-1 font-normal text-slate-400">
                {{ $t('JABVOX_SALDO.FORM.API_SECRET_HINT') }}
              </span>
            </label>
            <input
              v-model="form.api_secret_jabvox"
              type="password"
              placeholder="••••••••••••"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100"
            />
          </div>

          <div>
            <label
              class="inline-flex items-center gap-2 text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              <input
                v-model="form.is_active_jabvox"
                type="checkbox"
                class="rounded border-slate-300"
              />
              {{ $t('JABVOX_SALDO.FORM.ACTIVE') }}
            </label>
          </div>
        </div>

        <Button
          :label="
            uiFlags.isSaving
              ? $t('JABVOX_PRODUCTS.LOADING')
              : $t('JABVOX_SALDO.SAVE')
          "
          :disabled="uiFlags.isSaving || !form.proxy_url_jabvox"
          @click="onSave"
        />
      </div>

      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-6 space-y-4 self-start"
      >
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-semibold text-slate-800 dark:text-slate-100">
            {{ $t('JABVOX_SALDO.STATUS.TITLE') }}
          </h3>
          <Button
            variant="clear"
            size="small"
            :icon="
              uiFlags.isCheckingStatus
                ? 'i-lucide-loader-circle'
                : 'i-lucide-refresh-cw'
            "
            :class="{ 'animate-spin': uiFlags.isCheckingStatus }"
            :label="$t('JABVOX_SALDO.STATUS.REFRESH')"
            :disabled="uiFlags.isCheckingStatus"
            @click="onRefreshStatus"
          />
        </div>

        <div v-if="!status" class="text-sm text-slate-400">
          {{ $t('JABVOX_SALDO.STATUS.LOADING') }}
        </div>
        <div v-else class="space-y-2">
          <span
            class="inline-flex items-center gap-1.5 text-sm font-medium px-3 py-1 rounded-full"
            :class="
              status.connected
                ? 'bg-green-100 text-green-700'
                : 'bg-red-100 text-red-600'
            "
          >
            <span
              class="size-2 rounded-full"
              :class="status.connected ? 'bg-green-500' : 'bg-red-500'"
            />
            {{
              status.connected
                ? $t('JABVOX_SALDO.STATUS.CONNECTED')
                : $t('JABVOX_SALDO.STATUS.DISCONNECTED')
            }}
          </span>
          <p class="text-sm text-slate-500 dark:text-slate-400">
            {{ status.message }}
          </p>
          <p class="text-2xl font-bold" :style="balanceColor">
            {{ formatBalance(status.balance) }}
          </p>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
