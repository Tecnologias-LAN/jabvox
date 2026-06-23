<script setup>
import {
  ref,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
  nextTick,
} from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import SectionCard from './components/SectionCard.vue';
import SaveBar from './components/SaveBar.vue';

const store = useStore();
const { t } = useI18n();
const { isDirty, markDirty, markClean } = useUnsavedChanges();

const config = computed(() => store.getters['jabvoxEmail/getSmtpConfig']);
const uiFlags = computed(() => store.getters['jabvoxEmail/getUIFlags']);

const showPassword = ref(false);

const emptyForm = () => ({
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
const form = ref(emptyForm());

const authOptions = computed(() => [
  { value: 'plain', label: t('JABVOX_EMAIL.SMTP.AUTH_PLAIN') },
  { value: 'login', label: t('JABVOX_EMAIL.SMTP.AUTH_LOGIN') },
  { value: 'cram_md5', label: t('JABVOX_EMAIL.SMTP.AUTH_CRAM_MD5') },
]);

const refreshIntervalMs = 15000;
let refreshTimer = null;

const statusLabel = computed(() => {
  if (uiFlags.value.isTesting) return t('JABVOX_EMAIL.SMTP.STATUS.TESTING');
  if (uiFlags.value.isFetchingSmtp)
    return t('JABVOX_EMAIL.SMTP.STATUS.CHECKING');
  if (config.value?.verified) return t('JABVOX_EMAIL.SMTP.STATUS.CONNECTED');
  return t('JABVOX_EMAIL.SMTP.STATUS.DISCONNECTED');
});

const statusColor = computed(() => {
  if (uiFlags.value.isTesting) return 'amber';
  if (config.value?.verified) return 'teal';
  return 'ruby';
});

// Inline validation: surface a clear error when the from-email looks invalid.
const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const fromEmailError = computed(() => {
  const v = form.value.from_email.trim();
  if (!v) return '';
  return emailRe.test(v) ? '' : t('JABVOX_EMAIL.SMTP.FROM_EMAIL_INVALID');
});

const applyConfig = val => {
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
};

watch(
  config,
  async val => {
    if (val?.id) {
      applyConfig(val);
      await nextTick();
      markClean();
    }
  },
  { immediate: true }
);

watch(form, () => markDirty(), { deep: true });

const onSave = async () => {
  try {
    const payload = { ...form.value };
    if (payload.password) {
      payload.password = payload.password.replace(/\s+/g, '');
    }
    if (!payload.password) delete payload.password;
    await store.dispatch('jabvoxEmail/saveSmtpConfig', payload);
    await nextTick();
    markClean();
    useAlert(t('JABVOX_EMAIL.SMTP.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_EMAIL.SMTP.SAVE_ERROR'));
  }
};

const onDiscard = async () => {
  if (config.value?.id) applyConfig(config.value);
  else form.value = emptyForm();
  await nextTick();
  markClean();
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
  <form autocomplete="off" class="w-full flex flex-col gap-4" @submit.prevent>
    <SectionCard
      :title="t('JABVOX_EMAIL.SMTP.TITLE')"
      :description="t('JABVOX_EMAIL.SMTP.DESCRIPTION')"
      icon="i-lucide-server"
    >
      <template #actions>
        <Label :label="statusLabel" :color="statusColor">
          <template #icon>
            <span
              :class="[
                uiFlags.isTesting
                  ? 'i-lucide-loader-circle animate-spin'
                  : config?.verified
                    ? 'i-lucide-circle-check'
                    : 'i-lucide-circle-x',
              ]"
              class="size-3"
            />
          </template>
        </Label>
      </template>

      <div class="flex flex-col gap-8">
        <!-- Group: sender identity -->
        <section class="flex flex-col gap-4">
          <h3
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_EMAIL.SMTP.GROUP_SENDER') }}
          </h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model="form.from_name"
              :label="t('JABVOX_EMAIL.SMTP.FROM_NAME')"
              :placeholder="t('JABVOX_EMAIL.SMTP.FROM_NAME_PLACEHOLDER')"
            />
            <Input
              v-model="form.from_email"
              type="email"
              :label="t('JABVOX_EMAIL.SMTP.FROM_EMAIL')"
              :placeholder="t('JABVOX_EMAIL.SMTP.FROM_EMAIL_PLACEHOLDER')"
              :message="fromEmailError"
              :message-type="fromEmailError ? 'error' : 'info'"
            />
          </div>
        </section>

        <!-- Group: server -->
        <section class="flex flex-col gap-4">
          <h3
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_EMAIL.SMTP.GROUP_SERVER') }}
          </h3>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div class="sm:col-span-2">
              <Input
                v-model="form.address"
                :label="t('JABVOX_EMAIL.SMTP.ADDRESS')"
                :placeholder="t('JABVOX_EMAIL.SMTP.ADDRESS_PLACEHOLDER')"
              />
            </div>
            <Input
              v-model.number="form.port"
              type="number"
              :label="t('JABVOX_EMAIL.SMTP.PORT')"
              :placeholder="t('JABVOX_EMAIL.SMTP.PORT_PLACEHOLDER')"
            />
          </div>
          <!-- Authentication -->
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_EMAIL.SMTP.AUTHENTICATION') }}
            </label>
            <Select v-model="form.authentication" :options="authOptions" />
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_EMAIL.SMTP.AUTH_HELP') }}
            </p>
          </div>
        </section>

        <!-- Group: credentials -->
        <section class="flex flex-col gap-4">
          <h3
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_EMAIL.SMTP.GROUP_CREDENTIALS') }}
          </h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model="form.username"
              :label="t('JABVOX_EMAIL.SMTP.USERNAME')"
              :placeholder="t('JABVOX_EMAIL.SMTP.USERNAME_PLACEHOLDER')"
            />
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_EMAIL.SMTP.PASSWORD') }}
              </label>
              <div class="relative">
                <Input
                  v-model="form.password"
                  :type="showPassword ? 'text' : 'password'"
                  custom-input-class="!pr-10"
                  :placeholder="
                    config?.has_password
                      ? '••••••••'
                      : t('JABVOX_EMAIL.SMTP.PASSWORD_PLACEHOLDER')
                  "
                />
                <button
                  type="button"
                  class="absolute right-2 top-1/2 -translate-y-1/2 text-n-slate-10 hover:text-n-slate-12"
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
        </section>

        <!-- Group: security -->
        <section class="flex flex-col gap-4">
          <h3
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_EMAIL.SMTP.GROUP_SECURITY') }}
          </h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div
              class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
            >
              <span class="text-sm text-n-slate-12">
                {{ t('JABVOX_EMAIL.SMTP.STARTTLS') }}
              </span>
              <Switch v-model="form.enable_starttls_auto" />
            </div>
            <div
              class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
            >
              <span class="text-sm text-n-slate-12">
                {{ t('JABVOX_EMAIL.SMTP.SSL_TLS') }}
              </span>
              <Switch v-model="form.enable_ssl_tls" />
            </div>
          </div>
        </section>
      </div>

      <!-- Footer: test connection + first-time save -->
      <template #footer>
        <div class="flex flex-wrap items-center justify-between gap-3">
          <Button
            v-if="config?.id"
            :label="
              uiFlags.isTesting
                ? t('JABVOX_EMAIL.SMTP.TESTING')
                : t('JABVOX_EMAIL.SMTP.TEST')
            "
            icon="i-lucide-plug-zap"
            variant="outline"
            color="slate"
            size="sm"
            :is-loading="uiFlags.isTesting"
            @click="onTest"
          />
          <span v-else />
          <Button
            v-if="!config?.id"
            :label="
              uiFlags.isSaving
                ? t('JABVOX_EMAIL.SMTP.SAVING')
                : t('JABVOX_EMAIL.SMTP.SAVE')
            "
            :is-loading="uiFlags.isSaving"
            @click="onSave"
          />
        </div>
      </template>
    </SectionCard>

    <SaveBar
      :visible="!!config?.id && isDirty"
      :is-saving="uiFlags.isSaving"
      @save="onSave"
      @discard="onDiscard"
    />
  </form>
</template>
