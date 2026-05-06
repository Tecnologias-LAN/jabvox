<script setup>
import { ref } from 'vue';
import ProductsTab from './tabs/ProductsTab.vue';
import DiscountsTab from './tabs/DiscountsTab.vue';
import StatusesTab from './tabs/StatusesTab.vue';
import IntegrationTab from './tabs/IntegrationTab.vue';
import ConfigTab from './tabs/ConfigTab.vue';
import PdfTab from './tabs/PdfTab.vue';
import SalesReportAccessTab from './tabs/SalesReportAccessTab.vue';

const activeTab = ref('products');

const TABS = [
  {
    key: 'products',
    label: 'JABVOX_PRODUCTS.TABS.PRODUCTS',
    icon: 'i-lucide-package',
  },
  {
    key: 'discounts',
    label: 'JABVOX_PRODUCTS.TABS.DISCOUNTS',
    icon: 'i-lucide-tag',
  },
  {
    key: 'statuses',
    label: 'JABVOX_PRODUCTS.TABS.STATUSES',
    icon: 'i-lucide-list-checks',
  },
  {
    key: 'integration',
    label: 'JABVOX_PRODUCTS.TABS.INTEGRATION',
    icon: 'i-lucide-plug',
  },
  {
    key: 'config',
    label: 'JABVOX_PRODUCTS.TABS.CONFIG',
    icon: 'i-lucide-settings',
  },
  { key: 'pdf', label: 'JABVOX_PRODUCTS.TABS.PDF', icon: 'i-lucide-file-text' },
  {
    key: 'sales_reports',
    label: 'JABVOX_PRODUCTS.TABS.REPORT_ACCESS',
    icon: 'i-lucide-shield-check',
  },
];
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <div class="shrink-0 border-b border-n-weak bg-n-surface-1">
      <div class="max-w-3xl mx-auto px-6 sm:px-8 pt-6 pb-0">
        <h1 class="text-heading-1 text-n-slate-12">
          {{ $t('JABVOX_PRODUCTS.TITLE') }}
        </h1>
      </div>
      <div class="flex px-6 sm:px-8 gap-1 max-w-3xl mx-auto mt-4 overflow-x-auto">
        <button
          v-for="tab in TABS"
          :key="tab.key"
          class="flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px whitespace-nowrap"
          :class="[
            activeTab === tab.key
              ? 'border-woot-500 text-woot-600'
              : 'border-transparent text-n-slate-10 hover:text-n-slate-12 hover:border-n-weak',
          ]"
          @click="activeTab = tab.key"
        >
          <i :class="tab.icon" />
          {{ $t(tab.label) }}
        </button>
      </div>
    </div>

    <div class="flex-1 overflow-y-auto">
      <div class="max-w-3xl mx-auto px-6 sm:px-8 py-8">
        <ProductsTab v-if="activeTab === 'products'" />
        <DiscountsTab v-else-if="activeTab === 'discounts'" />
        <StatusesTab v-else-if="activeTab === 'statuses'" />
        <IntegrationTab v-else-if="activeTab === 'integration'" />
        <ConfigTab v-else-if="activeTab === 'config'" />
        <PdfTab v-else-if="activeTab === 'pdf'" />
        <SalesReportAccessTab v-else-if="activeTab === 'sales_reports'" />
      </div>
    </div>
  </div>
</template>
