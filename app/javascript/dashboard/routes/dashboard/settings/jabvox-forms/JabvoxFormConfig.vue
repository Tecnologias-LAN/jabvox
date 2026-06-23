<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const emit = defineEmits(['close']);
const store = useStore();
const { t } = useI18n();

const formConfig = computed(() => store.getters['jabvoxForms/getFormConfig']);
const uiFlags = computed(() => store.getters['jabvoxForms/getUIFlags']);

const dialogRef = ref(null);
const customDomain = ref('');
const serverOrigin = window.location.origin;
const serverHost = window.location.hostname;
const dnsRecordTtl = '3600';
const serverFormPath = '/f/…';

watch(
  formConfig,
  val => {
    customDomain.value = val?.base_url_jabvox || '';
  },
  { immediate: true }
);

onMounted(() => dialogRef.value?.open());

const domainHostname = computed(() => {
  if (!customDomain.value) return '';
  try {
    return new URL(customDomain.value).hostname;
  } catch (_e) {
    return customDomain.value.replace(/^https?:\/\//, '').split('/')[0];
  }
});

const copyServerHost = () => {
  navigator.clipboard.writeText(serverHost);
  useAlert(t('JABVOX_FORMS.URL_COPIED'));
};

const onConfirm = async () => {
  try {
    await store.dispatch('jabvoxForms/updateFormConfig', {
      base_url_jabvox: customDomain.value.trim(),
    });
    useAlert(t('JABVOX_FORMS.CONFIG_SAVED'));
    dialogRef.value?.close();
  } catch (_e) {
    useAlert(t('JABVOX_FORMS.CONFIG_ERROR'));
  }
};

// ── SSL (read-only, managed from Super Admin) ─────────────────────────────────
const sslStatus = computed(() => formConfig.value?.ssl_status || 'none');
const sslExpiresAt = computed(() => {
  const d = formConfig.value?.ssl_expires_at;
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
    none: 'bg-n-alpha-2 text-n-slate-11',
    provisioning: 'bg-n-amber-3 text-n-amber-11',
    active: 'bg-n-teal-3 text-n-teal-11',
    failed: 'bg-n-ruby-3 text-n-ruby-11',
  };
  return map[sslStatus.value] || map.none;
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('JABVOX_FORMS.CONFIG_TITLE')"
    :confirm-button-label="t('JABVOX_FORMS.SAVE')"
    :cancel-button-label="t('JABVOX_FORMS.CANCEL')"
    :is-loading="uiFlags.isSavingConfig"
    width="lg"
    overflow-y-auto
    @confirm="onConfirm"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-5">
      <!-- Custom domain input -->
      <Input
        v-model="customDomain"
        type="url"
        :label="t('JABVOX_FORMS.CUSTOM_DOMAIN_LABEL')"
        :placeholder="t('JABVOX_FORMS.CUSTOM_DOMAIN_PLACEHOLDER')"
        :message="t('JABVOX_FORMS.CUSTOM_DOMAIN_HELP')"
      />

      <!-- DNS instructions (shown when a domain is entered) -->
      <div
        v-if="domainHostname"
        class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 flex flex-col gap-3"
      >
        <p
          class="text-xs font-semibold text-n-slate-12 flex items-center gap-1.5"
        >
          <span class="i-lucide-info size-3.5" />
          {{ t('JABVOX_FORMS.DNS_INSTRUCTIONS_TITLE') }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{ t('JABVOX_FORMS.DNS_INSTRUCTIONS_BODY') }}
        </p>

        <div
          class="rounded-lg bg-n-solid-1 border border-n-weak overflow-hidden text-xs font-mono"
        >
          <div
            class="grid grid-cols-2 bg-n-alpha-2 px-3 py-1.5 text-n-slate-12 font-semibold"
          >
            <span>{{ t('JABVOX_FORMS.DNS_COL_FIELD') }}</span>
            <span>{{ t('JABVOX_FORMS.DNS_COL_VALUE') }}</span>
          </div>
          <div class="grid grid-cols-2 px-3 py-2 text-n-slate-12">
            <span class="text-n-slate-10">{{
              t('JABVOX_FORMS.DNS_ROW_TYPE')
            }}</span>
            <span class="font-semibold">{{
              t('JABVOX_FORMS.DNS_ROW_TYPE_VAL')
            }}</span>
          </div>
          <div
            class="grid grid-cols-2 border-t border-n-weak px-3 py-2 text-n-slate-12"
          >
            <span class="text-n-slate-10">{{
              t('JABVOX_FORMS.DNS_ROW_NAME')
            }}</span>
            <span>{{ t('JABVOX_FORMS.DNS_ROW_NAME_VAL') }}</span>
          </div>
          <div
            class="grid grid-cols-2 border-t border-n-weak px-3 py-2 text-n-slate-12 items-center"
          >
            <span class="text-n-slate-10">{{
              t('JABVOX_FORMS.DNS_ROW_POINTS_TO')
            }}</span>
            <div class="flex items-center gap-1.5">
              <span>{{ serverHost }}</span>
              <button
                class="text-n-slate-10 hover:text-n-brand transition-colors"
                @click="copyServerHost"
              >
                <span class="i-lucide-copy size-3" />
              </button>
            </div>
          </div>
          <div
            class="grid grid-cols-2 border-t border-n-weak px-3 py-2 text-n-slate-12"
          >
            <span class="text-n-slate-10">{{
              t('JABVOX_FORMS.DNS_ROW_TTL')
            }}</span>
            <span>{{ dnsRecordTtl }}</span>
          </div>
        </div>

        <p class="text-[11px] text-n-slate-10">
          {{ t('JABVOX_FORMS.DNS_NOTE') }}
        </p>
      </div>

      <!-- SSL Certificate status (read-only) -->
      <div
        class="rounded-xl border border-n-weak p-4 flex items-center justify-between gap-3"
      >
        <p
          class="text-xs font-semibold text-n-slate-12 flex items-center gap-1.5"
        >
          <span class="i-lucide-lock size-3.5" />
          {{ t('JABVOX_FORMS.SSL_SECTION_TITLE') }}
        </p>
        <div class="flex flex-col items-end gap-0.5">
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
            {{ sslStatusLabel }}
          </span>
          <span
            v-if="sslStatus === 'active' && sslExpiresAt"
            class="text-[10px] text-n-slate-10"
          >
            {{ t('JABVOX_FORMS.SSL_EXPIRES') }}: {{ sslExpiresAt }}
          </span>
        </div>
      </div>

      <!-- Always-available server URL -->
      <div
        class="rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2.5 flex flex-col gap-0.5"
      >
        <p class="text-[11px] font-medium text-n-slate-10">
          {{ t('JABVOX_FORMS.SERVER_URL_LABEL') }}
        </p>
        <p class="text-xs font-mono text-n-slate-11 truncate">
          {{ serverOrigin }}{{ serverFormPath }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
