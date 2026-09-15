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
// Tras terminar el envío, delivered/read siguen llegando de Meta de forma
// asíncrona (el cliente lee minutos/horas después). Mientras el diálogo esté
// abierto seguimos refrescando, más lento, para reflejar leídos en tiempo real
// hasta este tope desde la apertura.
const POST_SEND_POLL_MS = 10000;
const POST_SEND_POLL_LIMIT_MS = 10 * 60 * 1000;
const RUNNING = ['queued', 'running', 'pending'];
// Delivered/read indicators (WhatsApp-style ticks), kept as constants so the
// template stays free of bare literals.
const CHECK = '✓';
const DOUBLE_CHECK = '✓✓';
const DASH = '—';

const open = ref(false);
const loading = ref(false);
const batch = ref(null);
const recipients = ref([]);
const statusFilter = ref('');
const search = ref('');
let pollTimer = null;
let openedAt = 0;

// "Reenviar a esta audiencia": estados a los que reenviar. Se combinan (multi) y
// se mandan como cadena separada por coma (p. ej. "failed,pending"); vacío = toda
// la audiencia.
const REUSE_STATUSES = ['failed', 'sent', 'delivered', 'read', 'pending'];
const reuseOpen = ref(false);
const reuseStatuses = ref(new Set());
const reusing = ref(false);

const toggleReuseStatus = s => {
  if (reuseStatuses.value.has(s)) reuseStatuses.value.delete(s);
  else reuseStatuses.value.add(s);
  reuseStatuses.value = new Set(reuseStatuses.value);
};

const isRunning = computed(() =>
  batch.value ? RUNNING.includes(batch.value.status_jabvox) : false
);

const totals = computed(() => ({
  sent: batch.value?.sent_count || 0,
  failed: batch.value?.failed_count || 0,
  total: batch.value?.total_rows_jabvox || 0,
  delivered: batch.value?.delivery_summary?.delivered || 0,
  read: batch.value?.delivery_summary?.read || 0,
  replied: batch.value?.delivery_summary?.replied || 0,
}));

// Tiempo de respuesta en segundos -> texto corto (ej. "2 min", "1 h 5 min").
const formatReplyTime = seconds => {
  if (seconds === null || seconds === undefined) return '';
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const restMinutes = minutes % 60;
  return restMinutes ? `${hours} h ${restMinutes} min` : `${hours} h`;
};

const stopPolling = () => {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
};

// Re-arma el intervalo del poll según el estado actual: rápido mientras el envío
// corre, lento tras terminar (para captar entregado/leído tardíos de Meta) y
// detenido al superar el tope. `runner` es el callback que refresca (load).
const restartPolling = runner => {
  stopPolling();
  if (isRunning.value) {
    pollTimer = setInterval(runner, POLL_MS);
  } else if (Date.now() - openedAt < POST_SEND_POLL_LIMIT_MS) {
    pollTimer = setInterval(runner, POST_SEND_POLL_MS);
  }
};

const load = async () => {
  if (!batch.value) return;
  const wasRunning = isRunning.value;
  try {
    const { data } = await bulkWhatsappAPI.getBatch(batch.value.id, {
      status: statusFilter.value || undefined,
      q: search.value.trim() || undefined,
    });
    batch.value = { ...batch.value, ...data };
    recipients.value = data.recipients || [];
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_BULK_WA.HISTORY.ERROR'));
    return;
  }
  // Al terminar el envío (running→terminal) o al superar el tope, re-evaluamos el
  // ritmo del poll (rápido → lento → detenido) para seguir captando leídos.
  if (
    wasRunning !== isRunning.value ||
    Date.now() - openedAt >= POST_SEND_POLL_LIMIT_MS
  ) {
    restartPolling(load);
  }
};

const startPolling = () => restartPolling(load);

const openDialog = async batchRow => {
  open.value = true;
  batch.value = batchRow;
  recipients.value = [];
  statusFilter.value = '';
  search.value = '';
  openedAt = Date.now();
  loading.value = true;
  await load();
  loading.value = false;
  startPolling();
};

const close = () => {
  open.value = false;
  stopPolling();
  batch.value = null;
  reuseOpen.value = false;
  reuseStatuses.value = new Set();
};

// Filtro/búsqueda: recargan del servidor (respeta paginación futura y CSV).
const applyFilter = async value => {
  statusFilter.value = value;
  await load();
};
const submitSearch = () => load();

// Descarga el CSV vía axios (lleva el token) y fuerza la descarga en el
// navegador. window.open no enviaba el header y caía en el login de Devise.
const exportCsv = async () => {
  if (!batch.value) return;
  try {
    const { data: blob } = await bulkWhatsappAPI.downloadBatchCsv(
      batch.value.id,
      { status: statusFilter.value || undefined }
    );
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `envio_${batch.value.id}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_BULK_WA.HISTORY.ERROR'));
  }
};

// Reenviar a esta audiencia: clona los leads de los estados elegidos (o toda la
// audiencia si no se eligió ninguno) y emite `reused` con los lead_ids listos
// para precargar el envío.
const reuse = async () => {
  if (!batch.value || reusing.value) return;
  reusing.value = true;
  try {
    const status = [...reuseStatuses.value].join(',') || undefined;
    const { data } = await bulkWhatsappAPI.reuseBatch(batch.value.id, {
      status,
    });
    useAlert(t('JABVOX_BULK_WA.REPORT.REUSE'));
    close();
    emit('reused', data); // el padre abre el wizard con esta audiencia precargada
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_BULK_WA.HISTORY.ERROR'));
  } finally {
    reusing.value = false;
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
              <span class="ml-2 text-n-teal-11">
                {{
                  t('JABVOX_BULK_WA.REPORT.TOTALS_DELIVERY', {
                    delivered: totals.delivered,
                    read: totals.read,
                  })
                }}
              </span>
              <span class="ml-2 text-n-blue-11">
                {{
                  t('JABVOX_BULK_WA.REPORT.TOTALS_REPLIED', {
                    replied: totals.replied,
                  })
                }}
              </span>
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
                { v: 'delivered', l: 'FILTER_DELIVERED' },
                { v: 'read', l: 'FILTER_READ' },
                { v: 'replied', l: 'FILTER_REPLIED' },
                { v: 'not_replied', l: 'FILTER_NOT_REPLIED' },
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
          <!-- Reenviar a esta audiencia -->
          <Button
            :label="t('JABVOX_BULK_WA.REPORT.REUSE')"
            icon="i-lucide-repeat"
            size="sm"
            :is-loading="reusing"
            @click="reuseOpen = !reuseOpen"
          />
        </div>

        <!-- Panel de reenvío: inline (no popover flotante) para que siempre sea visible
             y con scroll propio; así el botón de confirmar nunca queda cortado. -->
        <div
          v-if="reuseOpen"
          class="shrink-0 mx-4 mt-2 rounded-xl border border-n-weak bg-n-alpha-1 p-3 sm:p-4 max-h-[45vh] overflow-y-auto"
        >
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_BULK_WA.REPORT.REUSE_STATUS_TITLE') }}
          </p>
          <p class="text-xs text-n-slate-10 mt-0.5">
            {{ t('JABVOX_BULK_WA.REPORT.REUSE_STATUS_HINT') }}
          </p>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-2 mt-3">
            <label
              v-for="s in REUSE_STATUSES"
              :key="s"
              class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer rounded-lg border border-n-weak px-3 py-2"
              :class="
                reuseStatuses.has(s) ? 'bg-n-brand/10 border-n-brand' : ''
              "
            >
              <input
                type="checkbox"
                class="rounded accent-n-brand shrink-0"
                :checked="reuseStatuses.has(s)"
                @change="toggleReuseStatus(s)"
              />
              <span>{{
                t(`JABVOX_BULK_WA.REPORT.REUSE_STATUS_${s.toUpperCase()}`)
              }}</span>
            </label>
          </div>
          <div class="flex flex-wrap justify-end gap-2 pt-3">
            <Button
              :label="t('JABVOX_BULK_WA.REPORT.REUSE_CANCEL')"
              variant="ghost"
              color="slate"
              size="sm"
              @click="reuseOpen = false"
            />
            <Button
              :label="t('JABVOX_BULK_WA.REPORT.REUSE_CONFIRM')"
              icon="i-lucide-repeat"
              size="sm"
              :is-loading="reusing"
              @click="reuse"
            />
          </div>
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
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.DELIVERED') }}
                </th>
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.READ') }}
                </th>
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.REPLIED') }}
                </th>
                <th class="py-2 px-3">
                  {{ t('JABVOX_BULK_WA.REPORT.COLS.REPLY_TIME') }}
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
                <td class="py-2 px-3 text-n-slate-11">
                  <span
                    :title="r.delivered_at || ''"
                    :class="r.delivered ? 'text-n-teal-11' : 'text-n-slate-9'"
                  >
                    {{ r.delivered ? CHECK : DASH }}
                  </span>
                </td>
                <td class="py-2 px-3 text-n-slate-11">
                  <span
                    :title="r.read_at || ''"
                    :class="r.read ? 'text-n-teal-11' : 'text-n-slate-9'"
                  >
                    {{ r.read ? DOUBLE_CHECK : DASH }}
                  </span>
                </td>
                <td class="py-2 px-3 text-n-slate-11">
                  <span
                    :title="r.replied_at || ''"
                    :class="r.replied ? 'text-n-blue-11' : 'text-n-slate-9'"
                  >
                    {{
                      r.replied
                        ? t('JABVOX_BULK_WA.REPORT.REPLIED_YES')
                        : t('JABVOX_BULK_WA.REPORT.REPLIED_NO')
                    }}
                  </span>
                </td>
                <td class="py-2 px-3 text-n-slate-11">
                  {{ formatReplyTime(r.reply_time_seconds) }}
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
