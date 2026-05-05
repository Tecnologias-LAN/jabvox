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
  <div class="flex flex-col h-full overflow-hidden bg-white dark:bg-slate-900">
    <div
      class="flex items-center gap-3 px-6 py-4 border-b border-slate-200 dark:border-slate-700 shrink-0"
    >
      <i class="i-lucide-package text-slate-600 dark:text-slate-300 text-xl" />
      <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_PRODUCTS.TITLE') }}
      </h1>
    </div>

    <div
      class="flex border-b border-slate-200 dark:border-slate-700 shrink-0 overflow-x-auto"
    >
      <button
        v-for="tab in TABS"
        :key="tab.key"
        class="flex items-center gap-2 px-5 py-3 text-sm font-medium border-b-2 whitespace-nowrap transition-colors"
        :class="[
          activeTab === tab.key
            ? 'border-woot-600 text-woot-600'
            : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300',
        ]"
        @click="activeTab = tab.key"
      >
        <i :class="tab.icon" />
        {{ $t(tab.label) }}
      </button>
    </div>

    <div class="flex-1 overflow-y-auto px-6 py-5">
      <ProductsTab v-if="activeTab === 'products'" />
      <DiscountsTab v-else-if="activeTab === 'discounts'" />
      <StatusesTab v-else-if="activeTab === 'statuses'" />
      <IntegrationTab v-else-if="activeTab === 'integration'" />
      <ConfigTab v-else-if="activeTab === 'config'" />
      <PdfTab v-else-if="activeTab === 'pdf'" />
      <SalesReportAccessTab v-else-if="activeTab === 'sales_reports'" />
    </div>
  </div>
</template>
