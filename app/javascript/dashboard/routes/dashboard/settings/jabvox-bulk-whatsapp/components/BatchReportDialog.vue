<script setup>
import { ref, computed, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import bulkWhatsappAPI from 'dashboard/api/jabvox/bulkWhatsapp';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Per-execution report: opens a batch, lists its recipients with status filter,
// search, CSV export and "resend to this audience". While the batch is still
// running it polls every few seconds so counts/rows update live.
const emit = defineEmits(['reused']);

const { t } = useI18n();

const POLL_MS = 4000;
const RUNNING = ['queued', 'running', 'pending'];

const open = ref(false);
const loading = ref(false);
const batch = ref(null);
const recipients = ref([]);
const statusFilter = ref('');
const search = ref('');
let pollTimer = null;

const isRunning = computed(() =>
  batch.value ? RUNNING.includes(batch.value.status_jabvox) : false
);

const totals = computed(() => ({
  sent: batch.value?.sent_count || 0,
  failed: batch.value?.failed_count || 0,
  total: batch.value?.total_rows_jabvox || 0,
}));

const load = async () => {
  if (!batch.value) return;
  try {
    const { data } = await bulkWhatsappAPI.getBatch(batch.value.id, {
      status: statusFilter.value || undefined,
      q: search.value.trim() || undefined,
    });
    batch.value = { ...batch.value, ...data };
    recipients.value = data.recipients || [];
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_BULK_WA.HISTORY.ERROR'));
  }
};

const stopPolling = () => {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
};

const startPolling = () => {
  stopPolling();
  if (isRunning.value) pollTimer = setInterval(load, POLL_MS);
};

const openDialog = async batchRow => {
  open.value = true;
  batch.value = batchRow;
  recipients.value = [];
  statusFilter.value = '';
  search.value = '';
  loading.value = true;
  await load();
  loading.value = false;
  startPolling();
};

const close = () => {
  open.value = false;
  stopPolling();
  batch.value = null;
};

// Filtro/búsqueda: recargan del servidor (respeta paginación futura y CSV).
const applyFilter = async value => {
  statusFilter.value = value;
  await load();
};
const submitSearch = () => load();

const exportCsv = () => {
  if (!batch.value) return;
  window.open(bulkWhatsappAPI.batchCsvUrl(batch.value.id), '_blank');
};

const reuse = async () => {
  if (!batch.value) return;
  try {
    const { data } = await bulkWhatsappAPI.reuseBatch(batch.value.id);
    useAlert(t('JABVOX_BULK_WA.REPORT.REUSE'));
    close();
    emit('reused', data); // el padre abre el wizard en Paso 3 con este batch
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_BULK_WA.HISTORY.ERROR'));
  }
};

const statusLabel = s =>
  t(`JABVOX_BULK_WA.STATUS.${(s || 'pending').toUpperCase()}`);

const statusClass = s =>
  ({
    sent: 'text-n-teal-11',
    failed: 'text-n-ruby-11',
    pending: 'text-n-slate-10',
  })[s] || 'text-n-slate-10';

onUnmounted(stopPolling);

defineExpose({ openDialog });
</script>

<template>
  <teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
      @click.self="close"
    >
      <div
        class="flex flex-col w-full max-w-4xl max-h-[88vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-lg overflow-hidden"
      >
        <!-- Header -->
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <div class="min-w-0">
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ t('JABVOX_BULK_WA.REPORT.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{
                t('JABVOX_BULK_WA.REPORT.TOTALS', {
                  sent: totals.sent,
                  failed: totals.failed,
                  total: totals.total,
                })
              }}
              <span v-if="isRunning" class="ml-2 text-n-amber-11">
                {{ t('JABVOX_BULK_WA.REPORT.LIVE') }}
              </span>
            </p>
          </div>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            @click="close"
          />
        </div>

        <!-- Toolbar -->
        <div class="px-5 pt-4 flex flex-wrap items-center gap-2">
          <div class="flex items-center gap-1">
            <Button
              v-for="opt in [
                { v: '', l: 'FILTER_ALL' },
                { v: 'sent', l: 'FILTER_SENT' },
                { v: 'failed', l: 'FILTER_FAILED' },
                { v: 'pending', l: 'FILTER_PENDING' },
              ]"
              :key="opt.l"
              :label="t(`JABVOX_BULK_WA.REPORT.${opt.l}`)"
              size="xs"
              :variant="statusFilter === opt.v ? 'solid' : 'outline'"
              color="slate"
              @click="applyFilter(opt.v)"
            />
          </div>
          <div class="relative flex-1 min-w-[180px]">
            <Input
              v-model="search"
              :placeholder="t('JABVOX_BULK_WA.REPORT.SEARCH_PLACEHOLDER')"
              @keyup.enter="submitSearch"
            />
          </div>
          <Button
            :label="t('JABVOX_BULK_WA.REPORT.EXPORT_CSV')"
            icon="i-lucide-download"
            variant="outline"
            color="slate"
            size="sm"
            @click="exportCsv"
          />
          <Button
            :label="t('JABVOX_BULK_WA.REPORT.REUSE')"
            icon="i-lucide-repeat"
            size="sm"
            @click="reuse"
          />
        </div>

        <!-- Body -->
        <div class="flex-1 overflow-y-auto px-5 py-4">
          <div v-if="loading" class="flex items-center justify-center py-16">
            <Spinner :size="24" />
          </div>
          <div
            v-else-if="!recipients.length"
            class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_BULK_WA.REPORT.EMPTY') }}
          </div>
          <table v-else class="min-w-full text-sm">
            <thead>
              <tr
                class="text-left text-xs font-medium uppercase tracking-wide text-n-slate-10 border-b border-n-weak"
              >
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.NAME') }}
                </th>
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.PHONE') }}
                </th>
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.TEMPLATE') }}
                </th>
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.STATUS') }}
                </th>
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.ERROR_CODE') }}
                </th>
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.ERROR_MESSAGE') }}
                </th>
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.SENT_AT') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr v-for="r in recipients" :key="r.id">
                <td class="py-2 px-3 text-n-slate-12">{{ r.name }}</td>
                <td class="py-2 px-3 text-n-slate-11">{{ r.phone_number }}</td>
                <td class="py-2 px-3 text-n-slate-11">{{ r.template_name }}</td>
                <td
                  class="py-2 px-3 font-medium"
                  :class="statusClass(r.status)"
                >
                  {{ statusLabel(r.status) }}
                </td>
                <td class="py-2 px-3 text-n-slate-11">{{ r.error_code }}</td>
                <td class="py-2 px-3 text-n-slate-11 max-w-xs truncate">
                  {{ r.error_message }}
                </td>
                <td class="py-2 px-3 text-n-slate-11">{{ r.sent_at }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </teleport>
</template>
