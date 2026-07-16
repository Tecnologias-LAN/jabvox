<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dialerCampaignsAPI } from 'dashboard/api/jabvox/dialer';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const dialogRef = ref(null);
const campaign = ref(null);
const from = ref('');
const to = ref('');
const groupBy = ref('day');
const fromHour = ref(0);
const toHour = ref(23);
const rows = ref([]);
const calls = ref([]);
const leads = ref([]);
const redialing = ref(null);
const totals = ref({
  total: 0,
  answered: 0,
  no_answer: 0,
  no_agent: 0,
  agents: 0,
});
const loading = ref(false);
const drillDay = ref(null);

const emptyTotals = () => ({
  total: 0,
  answered: 0,
  no_answer: 0,
  no_agent: 0,
  agents: 0,
});

const isSingleDay = computed(
  () => from.value && to.value && from.value === to.value
);

const hourOptions = computed(() =>
  Array.from({ length: 24 }, (_, h) => ({
    value: h,
    label: `${String(h).padStart(2, '0')}:00`,
  }))
);

const totalCards = computed(() => [
  { key: 'total', label: 'JABVOX_DIALER.REPORT.TOTAL', cls: 'text-n-slate-12' },
  {
    key: 'answered',
    label: 'JABVOX_DIALER.REPORT.ANSWERED',
    cls: 'text-n-teal-11',
  },
  {
    key: 'no_answer',
    label: 'JABVOX_DIALER.REPORT.NO_ANSWER',
    cls: 'text-n-amber-11',
  },
  {
    key: 'no_agent',
    label: 'JABVOX_DIALER.REPORT.NO_AGENT',
    cls: 'text-n-ruby-11',
  },
  {
    key: 'agents',
    label: 'JABVOX_DIALER.REPORT.AGENTS',
    cls: 'text-n-slate-11',
  },
]);

const fetchReport = async (gb = null, day = null) => {
  if (!campaign.value) return;
  loading.value = true;
  try {
    const params = {
      from: day || from.value,
      to: day || to.value,
      group_by: gb || groupBy.value,
    };
    if (isSingleDay.value || day) {
      params.from_hour = fromHour.value;
      params.to_hour = toHour.value;
    }
    const { data } = await dialerCampaignsAPI.getReport(
      campaign.value.id,
      params
    );
    rows.value = data.rows || [];
    totals.value = data.totals || emptyTotals();
    calls.value = data.calls || [];
    leads.value = data.leads || [];
  } catch {
    rows.value = [];
    calls.value = [];
    leads.value = [];
  } finally {
    loading.value = false;
  }
};

const open = c => {
  campaign.value = c;
  const today = new Date().toISOString().slice(0, 10);
  const weekAgo = new Date(Date.now() - 6 * 86400000)
    .toISOString()
    .slice(0, 10);
  from.value = weekAgo;
  to.value = today;
  groupBy.value = 'day';
  drillDay.value = null;
  rows.value = [];
  calls.value = [];
  leads.value = [];
  totals.value = emptyTotals();
  nextTick(() => dialogRef.value?.open());
  fetchReport();
};

const drillIntoDay = day => {
  const dayStr =
    typeof day === 'string'
      ? day.slice(0, 10)
      : new Date(day).toISOString().slice(0, 10);
  drillDay.value = dayStr;
  fetchReport('hour', dayStr);
};

const backToDaily = () => {
  drillDay.value = null;
  fetchReport('day');
};

watch([from, to], () => {
  if (from.value && to.value) {
    drillDay.value = null;
    fetchReport(isSingleDay.value ? 'hour' : 'day');
  }
});

const formatPeriod = period => {
  if (!period) return '—';
  const d = new Date(period);
  if (drillDay.value) return `${String(d.getUTCHours()).padStart(2, '0')}:00`;
  return d.toISOString().slice(0, 10);
};

// The backend already sends called_at in the campaign timezone (ISO). Show it as
// "YYYY-MM-DD HH:mm" without re-shifting the zone.
const formatCallTime = iso => {
  if (!iso) return '—';
  const [date, time] = iso.split('T');
  return `${date} ${(time || '').slice(0, 5)}`;
};

// Re-queue a lead so the campaign dials it again ("volver a marcar").
const redial = async contactId => {
  if (!campaign.value || !contactId) return;
  redialing.value = contactId;
  try {
    await dialerCampaignsAPI.redialLead(campaign.value.id, {
      contact_id: contactId,
    });
    useAlert(t('JABVOX_DIALER.REPORT.REDIAL_OK'));
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  } finally {
    redialing.value = null;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      campaign
        ? `${t('JABVOX_DIALER.REPORT.TITLE')} — ${campaign.name_jabvox}`
        : t('JABVOX_DIALER.REPORT.TITLE')
    "
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="3xl"
    overflow-y-auto
  >
    <div class="flex flex-col gap-5">
      <!-- Filters -->
      <div v-if="!drillDay" class="flex flex-wrap items-end gap-3">
        <div class="flex flex-col gap-1.5">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('JABVOX_DIALER.REPORT.FROM') }}
          </label>
          <input
            v-model="from"
            type="date"
            class="rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('JABVOX_DIALER.REPORT.TO') }}
          </label>
          <input
            v-model="to"
            type="date"
            class="rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>
        <template v-if="isSingleDay">
          <div class="flex flex-col gap-1.5 w-28">
            <label class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_DIALER.REPORT.FROM_HOUR') }}
            </label>
            <Select v-model="fromHour" :options="hourOptions" />
          </div>
          <div class="flex flex-col gap-1.5 w-28">
            <label class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_DIALER.REPORT.TO_HOUR') }}
            </label>
            <Select v-model="toHour" :options="hourOptions" />
          </div>
        </template>
      </div>

      <!-- Drill indicator -->
      <div v-else class="flex items-center gap-2">
        <Button
          icon="i-lucide-arrow-left"
          :label="drillDay"
          variant="outline"
          color="slate"
          size="sm"
          @click="backToDaily"
        />
      </div>

      <!-- Totals -->
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
        <div
          v-for="card in totalCards"
          :key="card.key"
          class="rounded-xl border border-n-weak bg-n-alpha-1 p-3 text-center"
        >
          <div class="text-xl font-bold tabular-nums" :class="card.cls">
            {{ totals[card.key] ?? 0 }}
          </div>
          <div class="text-xs text-n-slate-10 mt-0.5">{{ t(card.label) }}</div>
        </div>
      </div>

      <!-- Loading / empty / table -->
      <div
        v-if="loading"
        class="flex items-center justify-center gap-2 py-10 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
      </div>
      <div
        v-else-if="!rows.length"
        class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_DIALER.REPORT.EMPTY') }}
      </div>
      <div
        v-else
        class="rounded-2xl border border-n-weak overflow-hidden overflow-x-auto"
      >
        <table class="min-w-full text-sm">
          <thead
            class="bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
          >
            <tr>
              <th class="text-left px-4 py-2.5">
                {{ t('JABVOX_DIALER.REPORT.PERIOD') }}
              </th>
              <th class="text-right px-4 py-2.5">
                {{ t('JABVOX_DIALER.REPORT.TOTAL') }}
              </th>
              <th class="text-right px-4 py-2.5 text-n-teal-11">
                {{ t('JABVOX_DIALER.REPORT.ANSWERED') }}
              </th>
              <th class="text-right px-4 py-2.5 text-n-amber-11">
                {{ t('JABVOX_DIALER.REPORT.NO_ANSWER') }}
              </th>
              <th class="text-right px-4 py-2.5 text-n-ruby-11">
                {{ t('JABVOX_DIALER.REPORT.NO_AGENT') }}
              </th>
              <th class="text-right px-4 py-2.5">
                {{ t('JABVOX_DIALER.REPORT.AGENTS') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="row in rows"
              :key="row.period"
              class="hover:bg-n-alpha-1 transition-colors"
              :class="{ 'cursor-pointer': !drillDay }"
              @click="!drillDay && drillIntoDay(row.period)"
            >
              <td class="px-4 py-2.5 font-mono text-xs text-n-slate-12">
                <span class="inline-flex items-center gap-1">
                  {{ formatPeriod(row.period) }}
                  <span
                    v-if="!drillDay"
                    class="i-lucide-chevron-right size-3 text-n-slate-9"
                  />
                </span>
              </td>
              <td class="px-4 py-2.5 text-right font-medium tabular-nums">
                {{ row.total }}
              </td>
              <td class="px-4 py-2.5 text-right text-n-teal-11 tabular-nums">
                {{ row.answered }}
              </td>
              <td class="px-4 py-2.5 text-right text-n-amber-11 tabular-nums">
                {{ row.no_answer }}
              </td>
              <td class="px-4 py-2.5 text-right text-n-ruby-11 tabular-nums">
                {{ row.no_agent }}
              </td>
              <td class="px-4 py-2.5 text-right text-n-slate-11 tabular-nums">
                {{ row.agents }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Per-call detail: who was dialed, by whom, when and the outcome -->
      <div v-if="leads.length" class="mt-6">
        <h3 class="text-sm font-semibold text-n-slate-12 mb-2">
          {{ t('JABVOX_DIALER.REPORT.LEADS_TITLE') }}
        </h3>
        <div
          class="rounded-xl border border-n-weak overflow-x-auto overflow-y-auto max-h-80"
        >
          <table class="w-full text-sm">
            <thead class="sticky top-0 z-10">
              <tr
                class="bg-n-alpha-1 text-[11px] font-semibold uppercase text-n-slate-10 text-left"
              >
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.CALL_LEAD') }}
                </th>
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.CALL_PHONE') }}
                </th>
                <th class="px-4 py-2.5 text-center">
                  {{ t('JABVOX_DIALER.REPORT.LEAD_ATTEMPTS') }}
                </th>
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.LEAD_LAST_STATUS') }}
                </th>
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.CALL_AGENT') }}
                </th>
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.CALL_WHEN') }}
                </th>
                <th class="px-4 py-2.5" />
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="(l, i) in leads"
                :key="i"
                class="hover:bg-n-alpha-1 transition-colors"
              >
                <td class="px-4 py-2.5 text-n-slate-12 truncate max-w-[200px]">
                  {{ l.lead_name || '—' }}
                </td>
                <td class="px-4 py-2.5 font-mono text-xs text-n-slate-11">
                  {{ l.phone || '—' }}
                </td>
                <td
                  class="px-4 py-2.5 text-center text-n-slate-12 font-semibold"
                >
                  {{ l.attempts }}
                </td>
                <td class="px-4 py-2.5">
                  <span
                    class="inline-flex items-center px-2 py-0.5 rounded-md text-[11px] font-medium"
                    :class="
                      l.last_status === 'answered' || l.last_answered
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : 'bg-n-amber-3 text-n-amber-11'
                    "
                  >
                    {{
                      l.last_status === 'answered' || l.last_answered
                        ? t('JABVOX_DIALER.REPORT.ANSWERED')
                        : t('JABVOX_DIALER.REPORT.NO_ANSWER')
                    }}
                  </span>
                </td>
                <td class="px-4 py-2.5 text-n-slate-11">
                  {{ l.last_agent || '—' }}
                </td>
                <td class="px-4 py-2.5 font-mono text-xs text-n-slate-11">
                  {{ formatCallTime(l.last_called_at) }}
                </td>
                <td class="px-4 py-2.5 text-right">
                  <button
                    v-if="l.contact_id"
                    class="inline-flex items-center gap-1 px-2 py-1 text-[11px] rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors disabled:opacity-50"
                    :disabled="redialing === l.contact_id"
                    @click="redial(l.contact_id)"
                  >
                    <span class="i-lucide-rotate-ccw size-3" />
                    {{ t('JABVOX_DIALER.REPORT.REDIAL') }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div v-if="calls.length" class="mt-6">
        <h3 class="text-sm font-semibold text-n-slate-12 mb-2">
          {{ t('JABVOX_DIALER.REPORT.CALLS_TITLE') }}
        </h3>
        <div
          class="rounded-xl border border-n-weak overflow-x-auto overflow-y-auto max-h-80"
        >
          <table class="w-full text-sm">
            <thead class="sticky top-0 z-10">
              <tr
                class="bg-n-alpha-1 text-[11px] font-semibold uppercase text-n-slate-10 text-left"
              >
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.CALL_LEAD') }}
                </th>
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.CALL_PHONE') }}
                </th>
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.CALL_AGENT') }}
                </th>
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.CALL_WHEN') }}
                </th>
                <th class="px-4 py-2.5">
                  {{ t('JABVOX_DIALER.REPORT.CALL_STATUS') }}
                </th>
                <th class="px-4 py-2.5" />
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="(c, i) in calls"
                :key="i"
                class="hover:bg-n-alpha-1 transition-colors"
              >
                <td class="px-4 py-2.5 text-n-slate-12 truncate max-w-[200px]">
                  {{ c.lead_name || '—' }}
                </td>
                <td class="px-4 py-2.5 font-mono text-xs text-n-slate-11">
                  {{ c.phone || '—' }}
                </td>
                <td class="px-4 py-2.5 text-n-slate-11">
                  {{ c.agent_name || '—' }}
                </td>
                <td class="px-4 py-2.5 font-mono text-xs text-n-slate-11">
                  {{ formatCallTime(c.called_at) }}
                </td>
                <td class="px-4 py-2.5">
                  <span
                    class="inline-flex items-center px-2 py-0.5 rounded-md text-[11px] font-medium"
                    :class="
                      c.answered
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : 'bg-n-amber-3 text-n-amber-11'
                    "
                  >
                    {{
                      c.answered
                        ? t('JABVOX_DIALER.REPORT.ANSWERED')
                        : t('JABVOX_DIALER.REPORT.NO_ANSWER')
                    }}
                  </span>
                </td>
                <td class="px-4 py-2.5 text-right">
                  <button
                    v-if="c.contact_id"
                    class="inline-flex items-center gap-1 px-2 py-1 text-[11px] rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors disabled:opacity-50"
                    :disabled="redialing === c.contact_id"
                    @click="redial(c.contact_id)"
                  >
                    <span class="i-lucide-rotate-ccw size-3" />
                    {{ t('JABVOX_DIALER.REPORT.REDIAL') }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </Dialog>
</template>
