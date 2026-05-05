<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ProductsReportTab from './tabs/ProductsReportTab.vue';
import AgentsReportTab from './tabs/AgentsReportTab.vue';
import DialerReportTab from './tabs/DialerReportTab.vue';
import AgentStatusTab from './tabs/AgentStatusTab.vue';

const { t } = useI18n();
const activeTab = ref('products');

const tabs = [
  {
    key: 'products',
    label: () => t('JABVOX_REPORTS.TABS.PRODUCTS'),
    icon: 'i-lucide-package',
  },
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
];
</script>

<template>
  <div
    class="flex flex-col flex-1 h-full w-full min-h-0 overflow-hidden bg-n-surface-1"
  >
    <!-- Header -->
    <div class="shrink-0 border-b border-n-weak bg-n-surface-2">
      <div class="px-6 py-5 flex items-center gap-3">
        <span class="i-lucide-chart-bar w-6 h-6 text-woot-500" />
        <h1 class="text-lg font-semibold text-n-slate-12">
          {{ t('JABVOX_REPORTS.TITLE') }}
        </h1>
      </div>
      <!-- Tabs -->
      <div class="flex px-6 gap-1 overflow-x-auto">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px whitespace-nowrap"
          :class="
            activeTab === tab.key
              ? 'border-woot-500 text-woot-600'
              : 'border-transparent text-n-slate-10 hover:text-n-slate-12 hover:border-n-weak'
          "
          @click="activeTab = tab.key"
        >
          <span class="w-4 h-4" :class="[tab.icon]" />
          {{ tab.label() }}
        </button>
      </div>
    </div>

    <!-- Tab content -->
    <div class="flex-1 overflow-y-auto min-h-0">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 py-6">
        <ProductsReportTab v-if="activeTab === 'products'" />
        <AgentsReportTab v-else-if="activeTab === 'agents'" />
        <DialerReportTab v-else-if="activeTab === 'dialer'" />
        <AgentStatusTab v-else-if="activeTab === 'agent_status'" />
      </div>
    </div>
  </div>
</template>
