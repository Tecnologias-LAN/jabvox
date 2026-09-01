<script setup>
// Full-page wrapper for a metric drill-down. Shares the reports look and the
// same permission guard, but lives at its own shareable URL
// (/jabvox/reports/:metricKey), so opening a metric is a real navigation.
import AnalyticsDrilldown from './analytics/AnalyticsDrilldown.vue';
</script>

<template>
  <div
    class="flex flex-col flex-1 h-full w-full min-h-0 overflow-hidden bg-n-background"
  >
    <div class="flex-1 overflow-y-auto min-h-0">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6">
        <AnalyticsDrilldown />
      </div>
    </div>
  </div>
</template>
