<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SaveBar from './components/SaveBar.vue';

const store = useStore();
const { t } = useI18n();
const { isDirty, markDirty, markClean } = useUnsavedChanges();

const config = useMapGetter('jabvoxSaldo/getConfig');
const status = useMapGetter('jabvoxSaldo/getStatus');
const uiFlags = useMapGetter('jabvoxSaldo/getUIFlags');

const showApiKey = ref(false);
const showApiSecret = ref(false);

const form = ref({
  name_jabvox: '',
  proxy_url_jabvox: '',
  api_key_jabvox: '',
  api_secret_jabvox: '',
  is_active_jabvox: true,
});

watch(form, () => markDirty(), { deep: true });

const hasApiKey = computed(() => !!config.value?.has_api_key);
const isValid = computed(() => form.value.proxy_url_jabvox.trim().length > 0);

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
  await nextTick();
  markClean();
};

onMounted(loadData);

const onSave = async () => {
  if (!isValid.value) return;
  try {
    const payload = { ...form.value };
    if (!payload.api_key_jabvox) delete payload.api_key_jabvox;
    if (!payload.api_secret_jabvox) delete payload.api_secret_jabvox;
    await store.dispatch('jabvoxSaldo/updateConfig', payload);
    form.value.api_key_jabvox = '';
    form.value.api_secret_jabvox = '';
    await nextTick();
    markClean();
    useAlert(t('JABVOX_SALDO.SAVE_SUCCESS'));
    await loadData();
  } catch {
    useAlert(t('JABVOX_SALDO.ERROR'));
  }
};

const onDiscard = async () => {
  fillForm(config.value);
  await nextTick();
  markClean();
};

const onRefreshStatus = () => store.dispatch('jabvoxSaldo/fetchStatus');

const formatBalance = value => {
  const n = Number(value || 0);
  return `$${n.toLocaleString('es-CO', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })} COP`;
};

// Token-based balance tone: low (ruby), medium (amber), healthy (brand).
const balanceTone = computed(() => {
  const n = Number(status.value?.balance || 0);
  if (n <= 10000) return 'text-n-ruby-11';
  if (n < 50000) return 'text-n-amber-11';
  return 'text-n-brand';
});
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-4xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div class="flex items-start gap-3">
        <span
          class="i-lucide-wallet size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('JABVOX_SALDO.TITLE') }}
          </h1>
          <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
            {{ t('JABVOX_SALDO.SUBTITLE') }}
          </p>
        </div>
      </div>

      <!-- Balance / status card (hero) -->
      <div
        class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm p-5 sm:p-6"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1 min-w-0">
            <span
              class="text-xs font-medium uppercase tracking-wide text-n-slate-10"
            >
              {{ t('JABVOX_SALDO.STATUS.BALANCE_LABEL') }}
            </span>
            <!-- Balance -->
            <div v-if="uiFlags.isCheckingStatus" class="py-1">
              <Spinner :size="22" />
            </div>
            <p
              v-else-if="status"
              class="text-3xl font-bold tabular-nums"
              :class="balanceTone"
            >
              {{ formatBalance(status.balance) }}
            </p>
            <p v-else class="text-sm text-n-slate-10 py-1">
              {{ t('JABVOX_SALDO.STATUS.NOT_CONFIGURED') }}
            </p>
            <p
              v-if="status && status.message"
              class="text-xs text-n-slate-11 truncate"
            >
              {{ status.message }}
            </p>
          </div>

          <div class="flex flex-col items-end gap-2 shrink-0">
            <Label
              v-if="status"
              :label="
                status.connected
                  ? t('JABVOX_SALDO.STATUS.CONNECTED')
                  : t('JABVOX_SALDO.STATUS.DISCONNECTED')
              "
              :color="status.connected ? 'teal' : 'ruby'"
            >
              <template #icon>
                <span
                  :class="
                    status.connected
                      ? 'i-lucide-circle-check'
                      : 'i-lucide-circle-x'
                  "
                  class="size-3"
                />
              </template>
            </Label>
            <Button
              :label="t('JABVOX_SALDO.STATUS.REFRESH')"
              icon="i-lucide-refresh-cw"
              variant="outline"
              color="slate"
              size="sm"
              :is-loading="uiFlags.isCheckingStatus"
              @click="onRefreshStatus"
            />
          </div>
        </div>
      </div>

      <!-- Config form -->
      <form class="flex flex-col gap-6" @submit.prevent>
        <div
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
        >
          <div class="border-b border-n-weak px-5 py-4 sm:px-6">
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('JABVOX_SALDO.FORM.TITLE') }}
            </h2>
          </div>
          <div class="px-5 py-5 sm:px-6 flex flex-col gap-8">
            <!-- General -->
            <section class="flex flex-col gap-4">
              <h3
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ t('JABVOX_SALDO.FORM.SECTION_GENERAL') }}
              </h3>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <Input
                  v-model="form.name_jabvox"
                  :label="t('JABVOX_SALDO.FORM.NAME')"
                  :placeholder="t('JABVOX_SALDO.FORM.NAME_PLACEHOLDER')"
                />
                <Input
                  v-model="form.proxy_url_jabvox"
                  :label="`${t('JABVOX_SALDO.FORM.PROXY_URL')} ${t('JABVOX_SALDO.FORM.REQUIRED')}`"
                  :placeholder="t('JABVOX_SALDO.FORM.PROXY_URL_PLACEHOLDER')"
                  custom-input-class="font-mono"
                />
              </div>
              <div
                class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
              >
                <div class="flex flex-col">
                  <span class="text-sm font-medium text-n-slate-12">
                    {{ t('JABVOX_SALDO.FORM.ACTIVE') }}
                  </span>
                  <span class="text-xs text-n-slate-11">
                    {{ t('JABVOX_SALDO.FORM.ACTIVE_HINT') }}
                  </span>
                </div>
                <Switch v-model="form.is_active_jabvox" />
              </div>
            </section>

            <!-- Credentials -->
            <section class="flex flex-col gap-4">
              <h3
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ t('JABVOX_SALDO.FORM.SECTION_CREDENTIALS') }}
              </h3>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <!-- API key -->
                <div class="flex flex-col gap-1.5">
                  <label class="text-sm font-medium text-n-slate-12">
                    {{ t('JABVOX_SALDO.FORM.API_KEY') }}
                  </label>
                  <div class="relative">
                    <Input
                      v-model="form.api_key_jabvox"
                      :type="showApiKey ? 'text' : 'password'"
                      autocomplete="new-password"
                      custom-input-class="!pr-10 font-mono"
                      :placeholder="
                        hasApiKey
                          ? '••••••••••••'
                          : t('JABVOX_SALDO.FORM.API_KEY_PLACEHOLDER')
                      "
                    />
                    <button
                      type="button"
                      class="absolute right-2 top-1/2 -translate-y-1/2 text-n-slate-10 hover:text-n-slate-12"
                      @click="showApiKey = !showApiKey"
                    >
                      <span
                        :class="
                          showApiKey ? 'i-lucide-eye-off' : 'i-lucide-eye'
                        "
                        class="size-4"
                      />
                    </button>
                  </div>
                  <p
                    v-if="hasApiKey && !form.api_key_jabvox"
                    class="text-xs text-n-slate-10"
                  >
                    {{ t('JABVOX_SALDO.FORM.API_SECRET_HINT') }}
                  </p>
                </div>

                <!-- API secret -->
                <div class="flex flex-col gap-1.5">
                  <label class="text-sm font-medium text-n-slate-12">
                    {{ t('JABVOX_SALDO.FORM.API_SECRET') }}
                  </label>
                  <div class="relative">
                    <Input
                      v-model="form.api_secret_jabvox"
                      :type="showApiSecret ? 'text' : 'password'"
                      autocomplete="new-password"
                      custom-input-class="!pr-10 font-mono"
                      placeholder="••••••••••••"
                    />
                    <button
                      type="button"
                      class="absolute right-2 top-1/2 -translate-y-1/2 text-n-slate-10 hover:text-n-slate-12"
                      @click="showApiSecret = !showApiSecret"
                    >
                      <span
                        :class="
                          showApiSecret ? 'i-lucide-eye-off' : 'i-lucide-eye'
                        "
                        class="size-4"
                      />
                    </button>
                  </div>
                  <p class="text-xs text-n-slate-10">
                    {{ t('JABVOX_SALDO.FORM.API_SECRET_HINT') }}
                  </p>
                </div>
              </div>
            </section>
          </div>
        </div>

        <SaveBar
          :visible="isDirty"
          :is-saving="uiFlags.isSaving"
          :disabled="!isValid"
          @save="onSave"
          @discard="onDiscard"
        />
      </form>
    </div>
  </div>
</template>
