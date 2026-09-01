<script setup>
// Totals table for a drill-down: the grand total plus a breakdown (by status,
// management type, product, call status). Always reflects the active filters.
defineProps({
  total: { type: Number, default: 0 },
  rows: { type: Array, default: () => [] },
  label: { type: String, default: '' },
  loading: { type: Boolean, default: false },
});

const numberFmt = new Intl.NumberFormat('es-CO');
const moneyFmt = new Intl.NumberFormat('es-CO', {
  style: 'currency',
  currency: 'COP',
  maximumFractionDigits: 0,
});
const fmtNum = v => numberFmt.format(v || 0);
const fmtMoney = v => moneyFmt.format(Number(v || 0));
const hasSum = rows => rows.some(r => r.sum != null);
</script>

<template>
  <div
    class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
  >
    <!-- Grand total header -->
    <div
      class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak bg-n-alpha-1"
    >
      <span class="text-sm font-medium text-n-slate-11">
        {{ $t('JABVOX_REPORTS.ANALYTICS.TOTAL') }}
      </span>
      <span class="text-lg font-semibold tabular-nums text-n-slate-12">
        <span
          v-if="loading"
          class="inline-block h-5 w-12 animate-pulse rounded bg-n-alpha-2"
        />
        <template v-else>{{ fmtNum(total) }}</template>
      </span>
    </div>

    <!-- Breakdown rows -->
    <table v-if="rows.length" class="min-w-full text-sm">
      <thead>
        <tr
          class="text-left text-xs font-medium uppercase tracking-wide text-n-slate-10 border-b border-n-weak"
        >
          <th class="py-2.5 px-4">{{ label }}</th>
          <th class="py-2.5 px-4 text-right">
            {{ $t('JABVOX_REPORTS.ANALYTICS.QUANTITY') }}
          </th>
          <th v-if="hasSum(rows)" class="py-2.5 px-4 text-right">
            {{ $t('JABVOX_REPORTS.ANALYTICS.AMOUNT') }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak">
        <tr
          v-for="row in rows"
          :key="row.key"
          class="hover:bg-n-alpha-1 transition-colors"
        >
          <td class="py-2.5 px-4 text-n-slate-12">{{ row.label }}</td>
          <td
            class="py-2.5 px-4 text-right tabular-nums font-semibold text-n-slate-12"
          >
            {{ fmtNum(row.count) }}
          </td>
          <td
            v-if="hasSum(rows)"
            class="py-2.5 px-4 text-right tabular-nums text-n-slate-11"
          >
            {{ row.sum != null ? fmtMoney(row.sum) : '—' }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
