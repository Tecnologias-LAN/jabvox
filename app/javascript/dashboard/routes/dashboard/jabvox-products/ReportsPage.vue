<script setup>
import SalesReportsTab from './tabs/SalesReportsTab.vue';
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden bg-white dark:bg-slate-900">
    <div
      class="flex items-center gap-3 px-4 sm:px-6 lg:px-8 py-5 sm:py-6 border-b border-slate-200 dark:border-slate-700 shrink-0 bg-gradient-to-r from-white to-slate-50 dark:from-slate-900 dark:to-slate-800/50"
    >
      <i
        class="i-lucide-bar-chart-2 text-slate-600 dark:text-slate-300 text-2xl"
      />
      <div>
        <h1
          class="text-xl sm:text-2xl font-bold text-slate-900 dark:text-slate-50"
        >
          {{ $t('JABVOX_PRODUCTS.REPORTS.TITLE') }}
        </h1>
      </div>
    </div>

    <div class="flex-1 overflow-y-auto py-6 sm:py-8">
      <div class="mx-auto max-w-4xl px-4 sm:px-6">
        <SalesReportsTab />
      </div>
    </div>
  </div>
</template>
