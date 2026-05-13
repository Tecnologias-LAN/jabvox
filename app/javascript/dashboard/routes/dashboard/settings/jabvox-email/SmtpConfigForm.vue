<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

const store = useStore();
const { t } = useI18n();

const config = computed(() => store.getters['jabvoxEmail/getSmtpConfig']);
const uiFlags = computed(() => store.getters['jabvoxEmail/getUIFlags']);

const form = ref({
  from_name: '',
  from_email: '',
  address: '',
  port: 587,
  username: '',
  password: '',
  authentication: 'login',
  enable_starttls_auto: true,
  enable_ssl_tls: false,
});

const showPassword = ref(false);

const refreshIntervalMs = 15000;
let refreshTimer = null;

const statusLabel = computed(() => {
  if (uiFlags.value.isTesting) return t('JABVOX_EMAIL.SMTP.STATUS.TESTING');
  if (uiFlags.value.isFetchingSmtp)
    return t('JABVOX_EMAIL.SMTP.STATUS.CHECKING');
  if (config.value?.verified) return t('JABVOX_EMAIL.SMTP.STATUS.CONNECTED');
  return t('JABVOX_EMAIL.SMTP.STATUS.DISCONNECTED');
});

const statusClasses = computed(() => {
  if (uiFlags.value.isTesting) {
    return 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300';
  }
  if (config.value?.verified) {
    return 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400';
  }
  return 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300';
});

watch(
  config,
  val => {
    if (val?.id) {
      form.value = {
        from_name: val.from_name || '',
        from_email: val.from_email || '',
        address: val.address || '',
        port: val.port || 587,
        username: val.username || '',
        password: '',
        authentication: val.authentication || 'login',
        enable_starttls_auto: val.enable_starttls_auto ?? true,
        enable_ssl_tls: val.enable_ssl_tls ?? false,
      };
    }
  },
  { immediate: true }
);

const onSave = async () => {
  try {
    const payload = { ...form.value };
    if (payload.password) {
      payload.password = payload.password.replace(/\s+/g, '');
    }
    if (!payload.password) delete payload.password;
    await store.dispatch('jabvoxEmail/saveSmtpConfig', payload);
    useAlert(t('JABVOX_EMAIL.SMTP.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_EMAIL.SMTP.SAVE_ERROR'));
  }
};

const onTest = async () => {
  try {
    await store.dispatch('jabvoxEmail/testSmtpConfig');
    await store.dispatch('jabvoxEmail/fetchSmtpConfig');
    useAlert(t('JABVOX_EMAIL.SMTP.TEST_SUCCESS'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_EMAIL.SMTP.TEST_ERROR'));
  }
};

onMounted(() => {
  refreshTimer = setInterval(() => {
    store.dispatch('jabvoxEmail/fetchSmtpConfig');
  }, refreshIntervalMs);
});

onBeforeUnmount(() => {
  if (refreshTimer) clearInterval(refreshTimer);
});
</script>

<template>
  <form autocomplete="off" class="w-full flex justify-center" @submit.prevent>
    <div class="w-full max-w-3xl space-y-6">
      <div
        class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 p-6 space-y-5"
      >
        <div class="flex items-center justify-between gap-3">
          <h2
            class="text-base font-semibold text-slate-800 dark:text-slate-100"
          >
            {{ $t('JABVOX_EMAIL.SMTP.TITLE') }}
          </h2>
          <span
            class="inline-flex items-center gap-2 text-xs font-medium px-2.5 py-1 rounded-full"
            :class="statusClasses"
          >
            <span
              class="w-1.5 h-1.5 rounded-full"
              :class="
                uiFlags.isTesting
                  ? 'bg-amber-500 animate-pulse'
                  : config?.verified
                    ? 'bg-green-500'
                    : 'bg-red-500'
              "
            />
            {{ statusLabel }}
          </span>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_EMAIL.SMTP.FROM_NAME') }}
            </label>
            <input
              v-model="form.from_name"
              type="text"
              :placeholder="$t('JABVOX_EMAIL.SMTP.FROM_NAME_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_EMAIL.SMTP.FROM_EMAIL') }}
            </label>
            <input
              v-model="form.from_email"
              type="email"
              :placeholder="$t('JABVOX_EMAIL.SMTP.FROM_EMAIL_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
        </div>

        <div class="grid grid-cols-3 gap-4">
          <div class="col-span-2 space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_EMAIL.SMTP.ADDRESS') }}
            </label>
            <input
              v-model="form.address"
              type="text"
              :placeholder="$t('JABVOX_EMAIL.SMTP.ADDRESS_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_EMAIL.SMTP.PORT') }}
            </label>
            <input
              v-model.number="form.port"
              type="number"
              :placeholder="$t('JABVOX_EMAIL.SMTP.PORT_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_EMAIL.SMTP.USERNAME') }}
            </label>
            <input
              v-model="form.username"
              type="text"
              :placeholder="$t('JABVOX_EMAIL.SMTP.USERNAME_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_EMAIL.SMTP.PASSWORD') }}
            </label>
            <div class="relative">
              <input
                v-model="form.password"
                :type="showPassword ? 'text' : 'password'"
                :placeholder="
                  config?.has_password
                    ? '••••••••'
                    : $t('JABVOX_EMAIL.SMTP.PASSWORD_PLACEHOLDER')
                "
                autocomplete="new-password"
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 pr-10 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              />
              <button
                type="button"
                class="absolute right-2 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 dark:hover:text-slate-200"
                @click="showPassword = !showPassword"
              >
                <span
                  :class="showPassword ? 'i-lucide-eye-off' : 'i-lucide-eye'"
                  class="size-4"
                />
              </button>
            </div>
          </div>
        </div>

        <div class="space-y-1">
          <label
            class="block text-xs font-medium text-slate-600 dark:text-slate-300"
          >
            {{ $t('JABVOX_EMAIL.SMTP.AUTHENTICATION') }}
          </label>
          <select
            v-model="form.authentication"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
          >
            <option value="plain">
              {{ $t('JABVOX_EMAIL.SMTP.AUTH_PLAIN') }}
            </option>
            <option value="login">
              {{ $t('JABVOX_EMAIL.SMTP.AUTH_LOGIN') }}
            </option>
            <option value="cram_md5">
              {{ $t('JABVOX_EMAIL.SMTP.AUTH_CRAM_MD5') }}
            </option>
          </select>
          <p class="text-xs text-slate-500 dark:text-slate-400">
            {{ $t('JABVOX_EMAIL.SMTP.AUTH_HELP') }}
          </p>
        </div>

        <div class="flex gap-6">
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              v-model="form.enable_starttls_auto"
              type="checkbox"
              class="rounded"
            />
            <span class="text-sm text-slate-700 dark:text-slate-300">
              {{ $t('JABVOX_EMAIL.SMTP.STARTTLS') }}
            </span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              v-model="form.enable_ssl_tls"
              type="checkbox"
              class="rounded"
            />
            <span class="text-sm text-slate-700 dark:text-slate-300">
              {{ $t('JABVOX_EMAIL.SMTP.SSL_TLS') }}
            </span>
          </label>
        </div>

        <div class="flex gap-3 pt-2">
          <button
            :disabled="uiFlags.isSaving"
            class="px-4 py-2 bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium rounded-lg transition-colors disabled:opacity-50"
            @click="onSave"
          >
            {{
              uiFlags.isSaving
                ? $t('JABVOX_EMAIL.SMTP.SAVING')
                : $t('JABVOX_EMAIL.SMTP.SAVE')
            }}
          </button>
          <button
            v-if="config?.id"
            :disabled="uiFlags.isTesting"
            class="px-4 py-2 border border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-300 text-sm font-medium rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors disabled:opacity-50"
            @click="onTest"
          >
            {{
              uiFlags.isTesting
                ? $t('JABVOX_EMAIL.SMTP.TESTING')
                : $t('JABVOX_EMAIL.SMTP.TEST')
            }}
          </button>
        </div>
      </div>
    </div>
  </form>
</template>
