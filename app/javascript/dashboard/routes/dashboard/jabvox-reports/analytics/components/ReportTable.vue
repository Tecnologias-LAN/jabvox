<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

// Generic drill-down table, configured entirely by a metric's `columns`
// definition (see reportMetrics.js). Each column's `type` selects the cell
// renderer, so a new metric never needs a new table component.
defineProps({
  columns: { type: Array, required: true },
  rows: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
  orderDir: { type: String, default: 'desc' },
});
const emit = defineEmits(['sort', 'retry']);

const { t } = useI18n();
const DASH = '—';

const expanded = ref(new Set());
const toggleExpand = id => {
  const next = new Set(expanded.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  expanded.value = next;
};

const dateFmt = new Intl.DateTimeFormat('es-CO', {
  dateStyle: 'medium',
  timeStyle: 'short',
});
const formatDate = v => (v ? dateFmt.format(new Date(v)) : DASH);

const moneyFmt = new Intl.NumberFormat('es-CO', {
  style: 'currency',
  currency: 'COP',
  maximumFractionDigits: 0,
});
const formatMoney = v => (v == null ? DASH : moneyFmt.format(Number(v)));

const formatDuration = secs => {
  if (secs == null) return DASH;
  const s = Number(secs);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
};

const statusLabel = s => {
  const map = {
    sent: t('JABVOX_REPORTS.ANALYTICS.STATUS.SENT'),
    delivered: t('JABVOX_REPORTS.ANALYTICS.STATUS.DELIVERED'),
    read: t('JABVOX_REPORTS.ANALYTICS.STATUS.READ'),
    failed: t('JABVOX_REPORTS.ANALYTICS.STATUS.FAILED'),
  };
  return map[s] || s || DASH;
};

const statusClass = s => {
  if (s === 'failed') return 'bg-n-ruby-3 text-n-ruby-11';
  if (s === 'read') return 'bg-n-teal-3 text-n-teal-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};

const directionLabel = d => {
  if (d === 'inbound') return t('JABVOX_REPORTS.ANALYTICS.DIRECTION.INBOUND');
  if (d === 'outbound') return t('JABVOX_REPORTS.ANALYTICS.DIRECTION.OUTBOUND');
  return DASH;
};
</script>

<template>
  <div class="overflow-x-auto rounded-xl border border-n-weak">
    <table class="w-full min-w-[720px] border-collapse text-sm">
      <thead>
        <tr class="border-b border-n-weak bg-n-solid-2 text-left">
          <th
            v-for="col in columns"
            :key="col.key"
            scope="col"
            class="px-3 py-2.5 font-medium text-n-slate-11 whitespace-nowrap"
            :aria-sort="
              col.sortable
                ? orderDir === 'asc'
                  ? 'ascending'
                  : 'descending'
                : undefined
            "
          >
            <button
              v-if="col.sortable"
              type="button"
              class="flex items-center gap-1 hover:text-n-slate-12"
              @click="emit('sort', col.key)"
            >
              {{ col.label }}
              <span
                class="size-3"
                :class="
                  orderDir === 'asc'
                    ? 'i-lucide-arrow-up'
                    : 'i-lucide-arrow-down'
                "
              />
            </button>
            <span v-else>{{ col.label }}</span>
          </th>
        </tr>
      </thead>

      <tbody>
        <!-- Loading skeleton (not a full-page spinner) -->
        <template v-if="loading && !rows.length">
          <tr v-for="n in 8" :key="`sk-${n}`" class="border-b border-n-weak">
            <td v-for="col in columns" :key="col.key" class="px-3 py-3">
              <div class="h-4 w-full animate-pulse rounded bg-n-alpha-2" />
            </td>
          </tr>
        </template>

        <!-- Error -->
        <tr v-else-if="error">
          <td :colspan="columns.length" class="px-3 py-10 text-center">
            <p class="text-sm text-n-ruby-11">
              {{ t('JABVOX_REPORTS.ANALYTICS.RECORDS_ERROR') }}
            </p>
            <button
              type="button"
              class="mt-2 rounded-lg border border-n-weak px-3 py-1.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
              @click="emit('retry')"
            >
              {{ t('JABVOX_REPORTS.ANALYTICS.RETRY') }}
            </button>
          </td>
        </tr>

        <!-- Empty -->
        <tr v-else-if="!rows.length">
          <td
            :colspan="columns.length"
            class="px-3 py-12 text-center text-sm text-n-slate-10"
          >
            {{ t('JABVOX_REPORTS.ANALYTICS.EMPTY') }}
          </td>
        </tr>

        <!-- Rows -->
        <template v-else>
          <tr
            v-for="row in rows"
            :key="row.id"
            class="border-b border-n-weak last:border-0 hover:bg-n-alpha-1"
          >
            <td
              v-for="col in columns"
              :key="col.key"
              class="px-3 py-2.5 align-top text-n-slate-12"
            >
              <!-- lead visual -->
              <template v-if="col.type === 'lead'">
                <div v-if="row.lead" class="flex items-center gap-2">
                  <Avatar
                    :name="
                      row.lead.name || t('JABVOX_REPORTS.ANALYTICS.NO_LEAD')
                    "
                    :src="row.lead.avatar_url"
                    :size="28"
                    rounded-full
                  />
                  <div class="min-w-0">
                    <div class="truncate font-medium text-n-slate-12">
                      {{
                        row.lead.name || t('JABVOX_REPORTS.ANALYTICS.NO_LEAD')
                      }}
                    </div>
                    <div
                      class="flex items-center gap-1 text-xs text-n-slate-10"
                    >
                      <span
                        v-if="row.lead.channel"
                        class="i-lucide-radio size-3"
                      />
                      {{ row.lead.phone || DASH }}
                    </div>
                  </div>
                </div>
                <span v-else class="text-n-slate-9">{{ DASH }}</span>
              </template>

              <!-- datetime -->
              <span
                v-else-if="col.type === 'datetime'"
                class="whitespace-nowrap"
              >
                {{ formatDate(row[col.key]) }}
              </span>

              <!-- expandable text -->
              <template v-else-if="col.type === 'text-expand'">
                <button
                  v-if="row[col.full] && row[col.full] !== row[col.key]"
                  type="button"
                  class="text-left"
                  @click="toggleExpand(`${row.id}-${col.key}`)"
                >
                  <span>{{
                    expanded.has(`${row.id}-${col.key}`)
                      ? row[col.full]
                      : row[col.key]
                  }}</span>
                </button>
                <span v-else>{{ row[col.key] || DASH }}</span>
              </template>

              <!-- status -->
              <span
                v-else-if="col.type === 'status'"
                class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
                :class="statusClass(row[col.key])"
              >
                {{ statusLabel(row[col.key]) }}
              </span>

              <!-- badge -->
              <span
                v-else-if="col.type === 'badge'"
                class="inline-flex rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
              >
                {{ row[col.key] || DASH }}
              </span>

              <!-- money -->
              <span v-else-if="col.type === 'money'" class="tabular-nums">
                {{ formatMoney(row[col.key]) }}
              </span>

              <!-- duration -->
              <span v-else-if="col.type === 'duration'" class="tabular-nums">
                {{ formatDuration(row[col.key]) }}
              </span>

              <!-- direction -->
              <span v-else-if="col.type === 'direction'">
                {{ directionLabel(row[col.key]) }}
              </span>

              <!-- link: open the conversation in a new tab -->
              <a
                v-else-if="col.type === 'link'"
                :href="row[col.key] || undefined"
                :class="
                  row[col.key]
                    ? 'text-n-brand hover:underline'
                    : 'pointer-events-none text-n-slate-9'
                "
                target="_blank"
                rel="noopener noreferrer"
              >
                <span class="i-lucide-external-link size-4" />
              </a>

              <!-- default text -->
              <span v-else>{{ row[col.key] || DASH }}</span>
            </td>
          </tr>
        </template>
      </tbody>
    </table>
  </div>
</template>
