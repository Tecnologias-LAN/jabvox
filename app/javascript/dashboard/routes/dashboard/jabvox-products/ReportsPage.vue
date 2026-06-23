<script setup>
import { useI18n } from 'vue-i18n';
import SalesReportsTab from './tabs/SalesReportsTab.vue';

const { t } = useI18n();
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-6xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div class="flex items-start gap-3">
        <span
          class="i-lucide-bar-chart-3 size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('JABVOX_PRODUCTS.REPORTS.TITLE') }}
          </h1>
        </div>
      </div>

      <SalesReportsTab />
    </div>
  </div>
</template>
