<script setup>
import { ref, computed, watch, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const emit = defineEmits(['close']);
const store = useStore();
const { t } = useI18n();

const formConfig = computed(() => store.getters['jabvoxForms/getFormConfig']);
const uiFlags = computed(() => store.getters['jabvoxForms/getUIFlags']);

const customDomain = ref('');
const serverOrigin = window.location.origin;

watch(
  formConfig,
  val => {
    customDomain.value = val?.base_url_jabvox || '';
  },
  { immediate: true }
);

const domainHostname = computed(() => {
  if (!customDomain.value) return '';
  try {
    return new URL(customDomain.value).hostname;
  } catch (_e) {
    return customDomain.value.replace(/^https?:\/\//, '').split('/')[0];
  }
});

const serverHost = window.location.hostname;
const dnsRecordTtl = '3600';
const serverFormPath = '/f/…';

const copyServerHost = () => {
  navigator.clipboard.writeText(serverHost);
};

const onSave = async () => {
  try {
    await store.dispatch('jabvoxForms/updateFormConfig', {
      base_url_jabvox: customDomain.value.trim(),
    });
    useAlert(t('JABVOX_FORMS.CONFIG_SAVED'));
    emit('close');
  } catch (_e) {
    useAlert(t('JABVOX_FORMS.CONFIG_ERROR'));
  }
};

// ── SSL ───────────────────────────────────────────────────────────────────────
const sslStatus = computed(() => formConfig.value?.ssl_status || 'none');
const sslError = computed(() => formConfig.value?.ssl_error || '');
const sslExpiresAt = computed(() => {
  const d = formConfig.value?.ssl_expires_at;
  return d ? new Date(d).toLocaleDateString() : null;
});
const sslProvisionedAt = computed(() => {
  const d = formConfig.value?.ssl_provisioned_at;
  return d ? new Date(d).toLocaleDateString() : null;
});

const sslStatusLabel = computed(() => {
  const map = {
    none: t('JABVOX_FORMS.SSL_STATUS_NONE'),
    provisioning: t('JABVOX_FORMS.SSL_STATUS_PROVISIONING'),
    active: t('JABVOX_FORMS.SSL_STATUS_ACTIVE'),
    failed: t('JABVOX_FORMS.SSL_STATUS_FAILED'),
  };
  return map[sslStatus.value] || sslStatus.value;
});

const sslStatusClass = computed(() => {
  const map = {
    none: 'bg-slate-100 text-slate-500 dark:bg-slate-700 dark:text-slate-400',
    provisioning:
      'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
    active:
      'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
    failed: 'bg-red-100 text-red-600 dark:bg-red-900/30 dark:text-red-400',
  };
  return map[sslStatus.value] || map.none;
});

const canRequestSsl = computed(
  () =>
    domainHostname.value &&
    sslStatus.value !== 'provisioning' &&
    !uiFlags.value.isProvisioningSsl
);

let pollTimer = null;

const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

const startPolling = () => {
  stopPolling();
  pollTimer = setInterval(async () => {
    await store.dispatch('jabvoxForms/refreshFormConfig');
    const status = store.getters['jabvoxForms/getFormConfig']?.ssl_status;
    if (status !== 'provisioning') {
      stopPolling();
      if (status === 'active') useAlert(t('JABVOX_FORMS.SSL_SUCCESS'));
    }
  }, 5000);
};

const onProvisionSsl = async () => {
  try {
    await store.dispatch('jabvoxForms/provisionSsl');
    startPolling();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_FORMS.CONFIG_ERROR'));
  }
};

watch(
  sslStatus,
  status => {
    if (status === 'provisioning') startPolling();
    else stopPolling();
  },
  { immediate: true }
);

onUnmounted(stopPolling);
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    @click.self="emit('close')"
  >
    <div
      class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 w-full max-w-lg p-6 space-y-5 shadow-xl max-h-[90vh] overflow-y-auto"
    >
      <div class="flex items-center justify-between">
        <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          {{ $t('JABVOX_FORMS.CONFIG_TITLE') }}
        </h2>
        <button
          class="p-1 rounded hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-400"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>

      <!-- Custom domain input -->
      <div class="space-y-1">
        <label
          class="block text-xs font-medium text-slate-600 dark:text-slate-300"
        >
          {{ $t('JABVOX_FORMS.CUSTOM_DOMAIN_LABEL') }}
        </label>
        <input
          v-model="customDomain"
          type="url"
          :placeholder="$t('JABVOX_FORMS.CUSTOM_DOMAIN_PLACEHOLDER')"
          class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
        />
        <p class="text-xs text-slate-400 dark:text-slate-500">
          {{ $t('JABVOX_FORMS.CUSTOM_DOMAIN_HELP') }}
        </p>
      </div>

      <!-- DNS instructions (shown when a domain is entered) -->
      <div
        v-if="domainHostname"
        class="rounded-xl border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/20 p-4 space-y-3"
      >
        <p
          class="text-xs font-semibold text-blue-700 dark:text-blue-300 flex items-center gap-1.5"
        >
          <span class="i-lucide-info size-3.5" />
          {{ $t('JABVOX_FORMS.DNS_INSTRUCTIONS_TITLE') }}
        </p>
        <p class="text-xs text-blue-600 dark:text-blue-400">
          {{ $t('JABVOX_FORMS.DNS_INSTRUCTIONS_BODY') }}
        </p>

        <div
          class="rounded-lg bg-white dark:bg-slate-800 border border-blue-100 dark:border-blue-800 overflow-hidden text-xs font-mono"
        >
          <div
            class="grid grid-cols-2 bg-blue-100 dark:bg-blue-900/40 px-3 py-1.5 text-blue-700 dark:text-blue-300 font-semibold"
          >
            <span>{{ $t('JABVOX_FORMS.DNS_COL_FIELD') }}</span>
            <span>{{ $t('JABVOX_FORMS.DNS_COL_VALUE') }}</span>
          </div>
          <div
            class="grid grid-cols-2 px-3 py-2 text-slate-700 dark:text-slate-200"
          >
            <span class="text-slate-500">{{
              $t('JABVOX_FORMS.DNS_ROW_TYPE')
            }}</span>
            <span class="font-semibold">{{
              $t('JABVOX_FORMS.DNS_ROW_TYPE_VAL')
            }}</span>
          </div>
          <div
            class="grid grid-cols-2 border-t border-blue-100 dark:border-blue-800 px-3 py-2 text-slate-700 dark:text-slate-200"
          >
            <span class="text-slate-500">{{
              $t('JABVOX_FORMS.DNS_ROW_NAME')
            }}</span>
            <span>{{ $t('JABVOX_FORMS.DNS_ROW_NAME_VAL') }}</span>
          </div>
          <div
            class="grid grid-cols-2 border-t border-blue-100 dark:border-blue-800 px-3 py-2 text-slate-700 dark:text-slate-200 items-center"
          >
            <span class="text-slate-500">{{
              $t('JABVOX_FORMS.DNS_ROW_POINTS_TO')
            }}</span>
            <div class="flex items-center gap-1.5">
              <span>{{ serverHost }}</span>
              <button
                class="text-slate-400 hover:text-woot-500 transition-colors"
                @click="copyServerHost"
              >
                <span class="i-lucide-copy size-3" />
              </button>
            </div>
          </div>
          <div
            class="grid grid-cols-2 border-t border-blue-100 dark:border-blue-800 px-3 py-2 text-slate-700 dark:text-slate-200"
          >
            <span class="text-slate-500">{{
              $t('JABVOX_FORMS.DNS_ROW_TTL')
            }}</span>
            <span>{{ dnsRecordTtl }}</span>
          </div>
        </div>

        <p class="text-[11px] text-blue-500 dark:text-blue-400">
          {{ $t('JABVOX_FORMS.DNS_NOTE') }}
        </p>
      </div>

      <!-- SSL Certificate section -->
      <div
        class="rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-3"
      >
        <div class="flex items-center justify-between">
          <p
            class="text-xs font-semibold text-slate-700 dark:text-slate-200 flex items-center gap-1.5"
          >
            <span class="i-lucide-lock size-3.5" />
            {{ $t('JABVOX_FORMS.SSL_SECTION_TITLE') }}
          </p>
          <span
            class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium"
            :class="sslStatusClass"
          >
            <span
              v-if="sslStatus === 'provisioning'"
              class="i-lucide-loader-circle size-3 animate-spin"
            />
            <span
              v-else-if="sslStatus === 'active'"
              class="i-lucide-shield-check size-3"
            />
            <span
              v-else-if="sslStatus === 'failed'"
              class="i-lucide-shield-x size-3"
            />
            {{ sslStatusLabel }}
          </span>
        </div>

        <!-- Active cert info -->
        <div
          v-if="sslStatus === 'active'"
          class="text-[11px] text-slate-500 dark:text-slate-400 space-y-0.5"
        >
          <p v-if="sslProvisionedAt">
            {{ $t('JABVOX_FORMS.SSL_PROVISIONED') }}: {{ sslProvisionedAt }}
          </p>
          <p v-if="sslExpiresAt">
            {{ $t('JABVOX_FORMS.SSL_EXPIRES') }}: {{ sslExpiresAt }}
          </p>
        </div>

        <!-- Error message -->
        <div
          v-if="sslStatus === 'failed' && sslError"
          class="rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 px-3 py-2 text-[11px] text-red-600 dark:text-red-400"
        >
          <p class="font-semibold mb-0.5">
            {{ $t('JABVOX_FORMS.SSL_ERROR_TITLE') }}
          </p>
          <p>{{ sslError }}</p>
        </div>

        <!-- Provisioning hint -->
        <p
          v-if="sslStatus === 'provisioning'"
          class="text-[11px] text-amber-600 dark:text-amber-400"
        >
          {{ $t('JABVOX_FORMS.SSL_POLLING_HINT') }}
        </p>

        <!-- Nginx config hint (shown when active and nginx not configured) -->
        <p
          v-if="sslStatus === 'active'"
          class="text-[11px] text-slate-400 dark:text-slate-500"
        >
          {{ $t('JABVOX_FORMS.SSL_NGINX_HINT') }}
        </p>

        <!-- CTA button -->
        <button
          :disabled="!canRequestSsl"
          class="w-full flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          :class="
            sslStatus === 'active'
              ? 'border border-slate-300 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700'
              : 'bg-woot-500 hover:bg-woot-600 text-white'
          "
          :title="!domainHostname ? $t('JABVOX_FORMS.SSL_REQUIRES_DOMAIN') : ''"
          @click="onProvisionSsl"
        >
          <span
            v-if="sslStatus === 'provisioning'"
            class="i-lucide-loader-circle size-4 animate-spin"
          />
          <span v-else class="i-lucide-shield-plus size-4" />
          {{
            sslStatus === 'active'
              ? $t('JABVOX_FORMS.SSL_RENEW_BTN')
              : sslStatus === 'failed'
                ? $t('JABVOX_FORMS.SSL_RETRY_BTN')
                : $t('JABVOX_FORMS.SSL_REQUEST_BTN')
          }}
        </button>
      </div>

      <!-- Always-available server URL -->
      <div
        class="rounded-lg border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-700/30 px-3 py-2.5 space-y-0.5"
      >
        <p class="text-[11px] font-medium text-slate-500 dark:text-slate-400">
          {{ $t('JABVOX_FORMS.SERVER_URL_LABEL') }}
        </p>
        <p
          class="text-xs font-mono text-slate-600 dark:text-slate-300 truncate"
        >
          {{ serverOrigin }}{{ serverFormPath }}
        </p>
      </div>

      <div class="flex gap-2 justify-end pt-1">
        <button
          class="px-4 py-2 text-sm text-slate-600 dark:text-slate-300 border border-slate-300 dark:border-slate-600 rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
          @click="emit('close')"
        >
          {{ $t('JABVOX_FORMS.CANCEL') }}
        </button>
        <button
          :disabled="uiFlags.isSavingConfig"
          class="px-4 py-2 text-sm text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors disabled:opacity-50"
          @click="onSave"
        >
          {{
            uiFlags.isSavingConfig
              ? $t('JABVOX_FORMS.SAVING')
              : $t('JABVOX_FORMS.SAVE')
          }}
        </button>
      </div>
    </div>
  </div>
</template>
