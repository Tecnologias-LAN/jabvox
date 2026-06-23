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
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-6xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div class="flex items-start gap-3">
        <span
          class="i-lucide-package size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ $t('JABVOX_PRODUCTS.TITLE') }}
          </h1>
          <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
            {{ $t('JABVOX_PRODUCTS.SUBTITLE') }}
          </p>
        </div>
      </div>

      <!-- Tabs -->
      <div
        class="flex items-center gap-1 p-1 rounded-xl bg-n-alpha-1 border border-n-weak w-full overflow-x-auto"
      >
        <button
          v-for="tab in TABS"
          :key="tab.key"
          class="flex items-center justify-center gap-2 px-3.5 py-2 text-sm font-medium rounded-lg whitespace-nowrap transition-colors shrink-0 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            activeTab === tab.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          <span :class="tab.icon" class="size-4 shrink-0" />
          {{ $t(tab.label) }}
        </button>
      </div>

      <!-- Tab content -->
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
