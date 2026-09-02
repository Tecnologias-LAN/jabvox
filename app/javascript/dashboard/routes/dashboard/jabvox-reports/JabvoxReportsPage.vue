<script setup>
import { ref, computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ProductsReportTab from './tabs/ProductsReportTab.vue';
import AgentsReportTab from './tabs/AgentsReportTab.vue';
import DialerReportTab from './tabs/DialerReportTab.vue';
import AgentStatusTab from './tabs/AgentStatusTab.vue';
import HermesActivityTab from './tabs/HermesActivityTab.vue';

const { t } = useI18n();

const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
// The products report only exists while the products module is active
// (mirrors the API, which rejects reports#products when the flag is off).
const productsEnabled = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.JABVOX_PRODUCTS
  )
);
// La actividad de Hermes solo se muestra si el módulo de Chat IA está activo.
const aiChatEnabled = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.JABVOX_AI_CHAT)
);

const tabs = computed(() => [
  ...(productsEnabled.value
    ? [
        {
          key: 'products',
          label: () => t('JABVOX_REPORTS.TABS.PRODUCTS'),
          icon: 'i-lucide-package',
        },
      ]
    : []),
  {
    key: 'agents',
    label: () => t('JABVOX_REPORTS.TABS.AGENTS'),
    icon: 'i-lucide-users',
  },
  {
    key: 'dialer',
    label: () => t('JABVOX_REPORTS.TABS.DIALER'),
    icon: 'i-lucide-phone-call',
  },
  {
    key: 'agent_status',
    label: () => t('JABVOX_REPORTS.TABS.AGENT_STATUS'),
    icon: 'i-lucide-activity',
  },
  ...(aiChatEnabled.value
    ? [
        {
          key: 'hermes_activity',
          label: () => t('JABVOX_REPORTS.TABS.HERMES_ACTIVITY'),
          icon: 'i-lucide-bot',
        },
      ]
    : []),
]);

const route = useRoute();
// Initial tab can come from the URL (?tab=agents), e.g. when returning from a
// drill-down opened inside the agents report.
const activeTab = ref(route.query.tab || null);
// First visible tab is the default; also covers products being disabled.
const currentTab = computed(() => {
  const keys = tabs.value.map(tab => tab.key);
  return keys.includes(activeTab.value) ? activeTab.value : keys[0];
});
</script>

<template>
  <div
    class="flex flex-col flex-1 h-full w-full min-h-0 overflow-hidden bg-n-background"
  >
    <!-- Header -->
    <div class="shrink-0 border-b border-n-weak bg-n-solid-1">
      <div class="mx-auto w-full max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class="py-5 flex items-start gap-3">
          <span
            class="i-lucide-chart-bar size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_REPORTS.TITLE') }}
            </h1>
            <p class="mt-0.5 text-sm text-n-slate-11">
              {{ t('JABVOX_REPORTS.COMMON.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <!-- Tabs -->
        <div class="flex gap-1 overflow-x-auto">
          <button
            v-for="tab in tabs"
            :key="tab.key"
            class="flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px whitespace-nowrap"
            :class="
              currentTab === tab.key
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-10 hover:text-n-slate-12 hover:border-n-weak'
            "
            @click="activeTab = tab.key"
          >
            <span class="size-4" :class="[tab.icon]" />
            {{ tab.label() }}
          </button>
        </div>
      </div>
    </div>

    <!-- Tab content -->
    <div class="flex-1 overflow-y-auto min-h-0">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6">
        <ProductsReportTab v-if="currentTab === 'products'" />
        <AgentsReportTab v-else-if="currentTab === 'agents'" />
        <DialerReportTab v-else-if="currentTab === 'dialer'" />
        <AgentStatusTab v-else-if="currentTab === 'agent_status'" />
        <HermesActivityTab v-else-if="currentTab === 'hermes_activity'" />
      </div>
    </div>
  </div>
</template>
