<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import bulkWhatsappAPI from 'dashboard/api/jabvox/bulkWhatsapp';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Reportes agregados de envíos masivos: totales (enviados con éxito, entregados,
// leídos, fallidos) y serie por envío / día / semana, filtrable por rango de
// fechas. Cruza delivered/read con message_status_events en el backend.
const { t } = useI18n();

const loading = ref(false);
const totals = ref(null);
const series = ref([]);
const groupBy = ref('batch');
const from = ref('');
const to = ref('');

const GROUP_OPTIONS = ['batch', 'day', 'week'];

const rangeParams = () => {
  const params = { groupBy: groupBy.value };
  if (from.value)
    params.from = Math.floor(new Date(from.value).getTime() / 1000);
  if (to.value) {
    // incluye todo el día final
    params.to = Math.floor(new Date(`${to.value}T23:59:59`).getTime() / 1000);
  }
  return params;
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await bulkWhatsappAPI.getAnalytics(rangeParams());
    totals.value = data.totals;
    series.value = data.series || [];
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_BULK_WA.ANALYTICS.ERROR'));
  } finally {
    loading.value = false;
  }
};

const fmtInt = v => (v == null ? '0' : Number(v).toLocaleString());
const fmtPct = v => (v == null ? '—' : `${v}%`);

const TIP = key => t(`JABVOX_BULK_WA.ANALYTICS.HINTS.${key}`);

const cards = computed(() => {
  const s = totals.value;
  if (!s) return [];
  return [
    {
      key: 'recipients',
      label: t('JABVOX_BULK_WA.ANALYTICS.TOTAL'),
      value: fmtInt(s.recipients),
      tip: TIP('TOTAL'),
    },
    {
      key: 'sent',
      label: t('JABVOX_BULK_WA.ANALYTICS.SENT'),
      value: fmtInt(s.sent),
      tip: TIP('SENT'),
    },
    {
      key: 'delivered',
      label: t('JABVOX_BULK_WA.ANALYTICS.DELIVERED'),
      value: fmtInt(s.delivered),
      tip: TIP('DELIVERED'),
    },
    {
      key: 'read',
      label: t('JABVOX_BULK_WA.ANALYTICS.READ'),
      value: fmtInt(s.read),
      tip: TIP('READ'),
    },
    {
      key: 'failed',
      label: t('JABVOX_BULK_WA.ANALYTICS.FAILED'),
      value: fmtInt(s.failed),
      tip: TIP('FAILED'),
      danger: (s.failed || 0) > 0,
    },
    {
      key: 'pending',
      label: t('JABVOX_BULK_WA.ANALYTICS.PENDING'),
      value: fmtInt(s.pending),
      tip: TIP('PENDING'),
    },
    {
      key: 'delivery_rate',
      label: t('JABVOX_BULK_WA.ANALYTICS.DELIVERY_RATE'),
      value: fmtPct(s.delivery_rate),
      tip: TIP('DELIVERY_RATE'),
      positive: true,
    },
    {
      key: 'read_rate',
      label: t('JABVOX_BULK_WA.ANALYTICS.READ_RATE'),
      value: fmtPct(s.read_rate),
      tip: TIP('READ_RATE'),
      positive: true,
    },
  ];
});

const onGroupChange = value => {
  groupBy.value = value;
  load();
};

onMounted(load);
</script>

<template>
  <div class="mx-auto w-full max-w-4xl flex flex-col gap-5">
    <!-- Filtros: agrupación + rango -->
    <div class="flex flex-wrap items-end gap-3">
      <div class="flex items-center gap-1">
        <Button
          v-for="opt in GROUP_OPTIONS"
          :key="opt"
          :label="t(`JABVOX_BULK_WA.ANALYTICS.GROUP.${opt.toUpperCase()}`)"
          size="xs"
          :variant="groupBy === opt ? 'solid' : 'outline'"
          color="slate"
          @click="onGroupChange(opt)"
        />
      </div>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('JABVOX_BULK_WA.ANALYTICS.FROM') }}
        <input
          v-model="from"
          type="date"
          class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-1 text-n-slate-12"
          @change="load"
        />
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('JABVOX_BULK_WA.ANALYTICS.TO') }}
        <input
          v-model="to"
          type="date"
          class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-1 text-n-slate-12"
          @change="load"
        />
      </label>
    </div>

    <div v-if="loading" class="flex items-center justify-center py-16">
      <Spinner :size="24" />
    </div>

    <template v-else>
      <!-- Totales -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div
          v-for="card in cards"
          :key="card.key"
          v-tooltip="card.tip"
          :aria-label="`${card.label}: ${card.value}`"
          tabindex="0"
          class="rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 shadow-sm transition-colors hover:border-n-slate-6 focus:outline-none focus:ring-2 focus:ring-n-brand"
        >
          <div class="flex items-center gap-1 text-xs text-n-slate-11">
            <span>{{ card.label }}</span>
            <span class="i-lucide-info w-3 h-3 text-n-slate-9" />
          </div>
          <div
            class="text-2xl font-semibold mt-1"
            :class="[
              card.positive ? 'text-n-teal-11' : '',
              card.danger ? 'text-n-ruby-11' : 'text-n-slate-12',
            ]"
          >
            {{ card.value }}
          </div>
        </div>
      </div>

      <!-- Serie por envío / día / semana -->
      <div class="overflow-x-auto rounded-lg border border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11 sticky top-0 z-[1]">
            <tr>
              <th class="text-left px-3 py-2 font-medium">
                {{ t('JABVOX_BULK_WA.ANALYTICS.COLS.GROUP') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('JABVOX_BULK_WA.ANALYTICS.COLS.TOTAL') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('JABVOX_BULK_WA.ANALYTICS.COLS.SENT') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('JABVOX_BULK_WA.ANALYTICS.COLS.DELIVERED') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('JABVOX_BULK_WA.ANALYTICS.COLS.READ') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('JABVOX_BULK_WA.ANALYTICS.COLS.FAILED') }}
              </th>
              <th class="text-right px-3 py-2 font-medium">
                {{ t('JABVOX_BULK_WA.ANALYTICS.COLS.READ_RATE') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in series"
              :key="row.key"
              class="border-t border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            >
              <td class="px-3 py-2 whitespace-nowrap">{{ row.label }}</td>
              <td class="px-3 py-2 text-right tabular-nums">
                {{ fmtInt(row.total) }}
              </td>
              <td class="px-3 py-2 text-right tabular-nums">
                {{ fmtInt(row.sent) }}
              </td>
              <td class="px-3 py-2 text-right tabular-nums">
                {{ fmtInt(row.delivered) }}
              </td>
              <td class="px-3 py-2 text-right tabular-nums">
                {{ fmtInt(row.read) }}
              </td>
              <td
                class="px-3 py-2 text-right tabular-nums"
                :class="row.failed > 0 ? 'text-n-ruby-11' : ''"
              >
                {{ fmtInt(row.failed) }}
              </td>
              <td class="px-3 py-2 text-right tabular-nums text-n-teal-11">
                {{ fmtPct(row.read_rate) }}
              </td>
            </tr>
            <tr v-if="!series.length">
              <td colspan="7" class="px-3 py-8 text-center text-n-slate-10">
                {{ t('JABVOX_BULK_WA.ANALYTICS.EMPTY') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
