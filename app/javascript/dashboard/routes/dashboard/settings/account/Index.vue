<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAccount } from 'dashboard/composables/useAccount';
import { formatBytes } from 'shared/helpers/FileHelper';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import AccountId from './components/AccountId.vue';
import BuildInfo from './components/BuildInfo.vue';
import AccountDelete from './components/AccountDelete.vue';
import AudioTranscription from './components/AudioTranscription.vue';
import SectionLayout from './components/SectionLayout.vue';

export default {
  components: {
    BaseSettingsHeader,
    NextButton,
    AccountId,
    BuildInfo,
    AccountDelete,
    AudioTranscription,
    SectionLayout,
    WithLabel,
    NextInput,
  },
  setup() {
    const { updateUISettings, uiSettings } = useUISettings();
    const { enabledLanguages } = useConfig();
    const { accountId } = useAccount();
    const v$ = useVuelidate();

    return { updateUISettings, uiSettings, v$, enabledLanguages, accountId };
  },
  data() {
    return {
      id: '',
      name: '',
      locale: 'en',
      domain: '',
      supportEmail: '',
      features: {},
    };
  },
  validations: {
    name: {
      required,
    },
    locale: {
      required,
    },
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      uiFlags: 'accounts/getUIFlags',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      isOnJabvoxCloud: 'globalConfig/isOnJabvoxCloud',
    }),
    showAudioTranscriptionConfig() {
      // La transcripción de audio depende del módulo de IA de la cuenta, que ahora es
      // el Chat IA (Hermes); antes colgaba del flag de Captain.
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.JABVOX_AI_CHAT
      );
    },
    languagesSortedByCode() {
      const enabledLanguages = [...this.enabledLanguages];
      return enabledLanguages.sort((l1, l2) =>
        l1.iso_639_1_code.localeCompare(l2.iso_639_1_code)
      );
    },
    isUpdating() {
      return this.uiFlags.isUpdating;
    },
    featureInboundEmailEnabled() {
      return !!this.features?.inbound_emails;
    },
    featureCustomReplyDomainEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_domain
      );
    },
    featureCustomReplyEmailEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_email
      );
    },
    currentAccount() {
      return this.getAccount(this.accountId) || {};
    },
    jabvoxBilling() {
      return this.currentAccount.jabvox_billing || {};
    },
    storageUsage() {
      return this.jabvoxBilling.storage || {};
    },
    billableLimits() {
      return this.jabvoxBilling.limits || {};
    },
    visibleLimits() {
      const labels = {
        agents: 'Agentes',
        inboxes: 'Bandejas',
        forms: 'Formularios',
        advanced_flows: 'Flujos',
        automation_rules: 'Automatizaciones',
        analytics_dashboards: 'Dashboards',
        ai_documents: 'Docs IA',
        email_templates: 'Plantillas',
      };

      return Object.entries(labels).map(([key, label]) => ({
        key,
        label,
        usageLabel: this.limitUsageLabel(this.billableLimits[key] || {}),
        ...(this.billableLimits[key] || {}),
      }));
    },
    storageRows() {
      const labels = {
        images: 'Imágenes',
        videos: 'Videos',
        audios: 'Audios',
        documents: 'Docs',
      };
      const byType = this.storageUsage.by_type || {};
      return Object.entries(labels).map(([key, label]) => ({
        key,
        label,
        gb: byType[key]?.gb || 0,
        gbLabel: this.formatSize(byType[key]?.bytes || 0),
      }));
    },
    storageDescription() {
      const quota = this.storageUsage.quota_bytes;
      const quotaLabel = quota == null ? 'ilimitado' : this.formatSize(quota);
      return `${this.formatSize(this.storageUsage.used_bytes || 0)} de ${quotaLabel}`;
    },
    storagePercent() {
      return Math.min(Number(this.storageUsage.percent_used || 0), 100);
    },
    storagePercentLabel() {
      return `${this.storageUsage.percent_used ?? 0}%`;
    },
    // Bytes en la papelera (siguen ocupando hasta eliminarse definitivamente).
    trashBytes() {
      return Number(this.storageUsage.trash_bytes || 0);
    },
    trashLabel() {
      return this.formatSize(this.trashBytes);
    },
    extraPriceLabel() {
      const cents = this.jabvoxBilling.extra_price_cents || 0;
      return this.formatCurrency(cents);
    },
    totalPriceLabel() {
      const cents = this.jabvoxBilling.total_price_cents || 0;
      return this.formatCurrency(cents);
    },
    planPriceLabel() {
      const cents = this.jabvoxBilling.base_price_cents || 0;
      return this.formatCurrency(cents);
    },
    planPriceDescription() {
      return `${this.planPriceLabel} plan + ${this.extraPriceLabel} ampliaciones`;
    },
    monthlyTotalLabel() {
      return 'Total mensual';
    },
    planUsageTitle() {
      return 'Uso del plan';
    },
    planUsageDescription() {
      return 'Consumo actual, cuota contratada y ampliaciones activas.';
    },
    monthlyAddOnsLabel() {
      return 'Ampliaciones mensuales';
    },
  },
  watch: {
    'currentAccount.id'(id) {
      if (id) {
        this.initializeAccount();
      }
    },
  },
  mounted() {
    // Account already in the store (navigated in): seed immediately.
    if (this.currentAccount.id) {
      this.initializeAccount();
    }
  },
  methods: {
    async initializeAccount() {
      try {
        const { name, locale, id, domain, support_email, features } =
          this.getAccount(this.accountId);

        const effectiveLocale = this.uiSettings?.locale || locale;
        if (effectiveLocale) {
          this.$root.$i18n.locale = effectiveLocale;
        }
        this.name = name;
        this.locale = locale;
        this.id = id;
        this.domain = domain;
        this.supportEmail = support_email;
        this.features = features;
      } catch (error) {
        // Ignore error
      }
    },

    async updateAccount() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.ERROR'));
        return;
      }
      try {
        await this.$store.dispatch('accounts/update', {
          locale: this.locale,
          name: this.name,
          domain: this.domain,
          support_email: this.supportEmail,
        });
        // If user locale is set, update the locale with user locale
        const updatedLocale = this.uiSettings?.locale || this.locale;
        if (updatedLocale) {
          this.$root.$i18n.locale = updatedLocale;
        }
        this.getAccount(this.id).locale = this.locale;
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.SUCCESS'));
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.ERROR'));
      }
    },
    // Tamaño legible (B/KB/MB/GB automático), igual que el Drive (formatBytes).
    formatSize(bytes) {
      return formatBytes(Number(bytes) || 0, 1);
    },
    limitUsageLabel(limit) {
      const used = limit.used || 0;
      const total = limit.limit || '∞';
      const extra = limit.extra ? ` +${limit.extra}` : '';
      return `${used} / ${total}${extra}`;
    },
    formatCurrency(cents) {
      const currency = this.jabvoxBilling.currency || 'COP';
      return new Intl.NumberFormat('es-CO', {
        style: 'currency',
        currency,
        maximumFractionDigits: 0,
      }).format(cents / 100);
    },
  },
};
</script>

<template>
  <div class="flex flex-col w-full max-w-2xl ltr:mr-auto rtl:ml-auto">
    <BaseSettingsHeader :title="$t('GENERAL_SETTINGS.TITLE')" />
    <div class="flex-grow flex-shrink min-w-0 mt-3">
      <SectionLayout
        :title="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.TITLE')"
        :description="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.NOTE')"
        class="!pt-0"
      >
        <form
          v-if="!uiFlags.isFetchingItem"
          class="grid gap-4"
          @submit.prevent="updateAccount"
        >
          <WithLabel
            name="account-name"
            :has-error="v$.name.$error"
            :label="$t('GENERAL_SETTINGS.FORM.NAME.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.NAME.ERROR')"
          >
            <NextInput
              v-model="name"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.NAME.PLACEHOLDER')"
              @blur="v$.name.$touch"
            />
          </WithLabel>
          <WithLabel
            name="site-language"
            :has-error="v$.locale.$error"
            :label="$t('GENERAL_SETTINGS.FORM.LANGUAGE.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.LANGUAGE.ERROR')"
          >
            <select v-model="locale" class="!mb-0 text-sm">
              <option
                v-for="lang in languagesSortedByCode"
                :key="lang.iso_639_1_code"
                :value="lang.iso_639_1_code"
              >
                {{ lang.name }}
              </option>
            </select>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyDomainEnabled"
            name="custom-domain"
            :label="$t('GENERAL_SETTINGS.FORM.DOMAIN.LABEL')"
          >
            <NextInput
              v-model="domain"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.DOMAIN.PLACEHOLDER')"
            />
            <template #help>
              {{
                featureInboundEmailEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.INBOUND_EMAIL_ENABLED')
              }}

              {{
                featureCustomReplyDomainEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.CUSTOM_EMAIL_DOMAIN_ENABLED')
              }}
            </template>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyEmailEnabled"
            name="support-email"
            :label="$t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.LABEL')"
          >
            <NextInput
              v-model="supportEmail"
              type="text"
              class="w-full"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.PLACEHOLDER')
              "
            />
          </WithLabel>
          <div>
            <NextButton blue :is-loading="isUpdating" type="submit">
              {{ $t('GENERAL_SETTINGS.SUBMIT') }}
            </NextButton>
          </div>
        </form>
      </SectionLayout>

      <woot-loading-state v-if="uiFlags.isFetchingItem" />
    </div>
    <SectionLayout
      v-if="!uiFlags.isFetchingItem && jabvoxBilling.storage"
      :title="planUsageTitle"
      :description="planUsageDescription"
    >
      <div class="grid gap-5">
        <div class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="mb-1 text-sm font-medium text-n-slate-12">
                {{ jabvoxBilling.plan?.name || 'Plan sin asignar' }}
              </p>
              <p class="mb-0 text-sm text-n-slate-11">
                {{ storageDescription }}
              </p>
            </div>
            <span class="text-sm font-medium text-n-slate-12">
              {{ storagePercentLabel }}
            </span>
          </div>
          <div class="mt-3 h-2 overflow-hidden rounded-full bg-n-slate-4">
            <div
              class="h-full rounded-full bg-n-brand"
              :style="{ width: `${storagePercent}%` }"
            />
          </div>
          <div class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div
              v-for="row in storageRows"
              :key="row.key"
              class="rounded-md border border-n-weak p-3"
            >
              <p class="mb-1 text-xs text-n-slate-11">{{ row.label }}</p>
              <p class="mb-0 text-sm font-medium text-n-slate-12">
                {{ row.gbLabel }}
              </p>
            </div>
          </div>
          <!-- Papelera: ocupa espacio hasta eliminarse definitivamente (o a los 7 días). -->
          <p
            v-if="trashBytes > 0"
            class="mt-3 flex items-center gap-1.5 text-xs text-n-slate-11"
          >
            <span class="i-lucide-trash-2 size-3.5 text-n-slate-10" />
            {{
              $t('GENERAL_SETTINGS.STORAGE_TRASH_NOTICE', { size: trashLabel })
            }}
          </p>
        </div>

        <div class="grid gap-2">
          <div
            v-for="limit in visibleLimits"
            :key="limit.key"
            class="grid grid-cols-[1fr_auto] items-center gap-3 rounded-md border border-n-weak px-3 py-2 text-sm"
          >
            <span class="text-n-slate-11">{{ limit.label }}</span>
            <span class="font-medium text-n-slate-12">
              {{ limit.usageLabel }}
            </span>
          </div>
          <div
            class="mt-2 flex items-center justify-between rounded-md border border-n-weak px-3 py-2 text-sm"
          >
            <span class="text-n-slate-11">{{ monthlyAddOnsLabel }}</span>
            <span class="font-medium text-n-slate-12">
              {{ extraPriceLabel }}
            </span>
          </div>
          <div
            class="flex items-center justify-between rounded-md border border-n-weak px-3 py-2 text-sm"
          >
            <span class="text-n-slate-11">{{ monthlyTotalLabel }}</span>
            <span class="text-right font-medium text-n-slate-12">
              {{ totalPriceLabel }}
              <span class="block text-xs font-normal text-n-slate-10">
                {{ planPriceDescription }}
              </span>
            </span>
          </div>
        </div>
      </div>
    </SectionLayout>
    <AudioTranscription v-if="showAudioTranscriptionConfig" />
    <AccountId />
    <div v-if="!uiFlags.isFetchingItem && isOnJabvoxCloud">
      <AccountDelete />
    </div>
    <BuildInfo />
  </div>
</template>
