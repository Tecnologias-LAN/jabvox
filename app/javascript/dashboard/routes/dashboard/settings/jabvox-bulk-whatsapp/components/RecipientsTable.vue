<script setup>
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Shared recipients table for a bulk WhatsApp send (or, from Informes →
// Plantillas, recipients across many sends): Name/Phone/Template/Status/
// Delivered/Read/Replied/Reply time/Reply text/Error code/Error message/Sent
// at. Extracted out of BatchReportDialog.vue so both it and the new
// Informes → Plantillas report render the exact same columns and formatting
// instead of drifting apart.
defineProps({
  recipients: { type: Array, required: true },
  loading: { type: Boolean, default: false },
  // Whether to render the Template column — the per-batch dialog omits it
  // (every row is the same template already named in the dialog header), the
  // cross-batch Informes page needs it.
  showTemplate: { type: Boolean, default: false },
  // Whether to render the Origin column (bulk/individual) — only the
  // cross-batch Informes → Plantillas report mixes both origins; a per-batch
  // dialog is always 100% bulk, so the column would be redundant there.
  showOrigin: { type: Boolean, default: false },
});

const { t } = useI18n();

// Delivered/read indicators (WhatsApp-style ticks), kept as constants so the
// template stays free of bare literals.
const CHECK = '✓';
const DOUBLE_CHECK = '✓✓';
const DASH = '—';

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

const statusLabel = s =>
  t(`JABVOX_BULK_WA.STATUS.${(s || 'pending').toUpperCase()}`);

const statusClass = s =>
  ({
    sent: 'text-n-teal-11',
    failed: 'text-n-ruby-11',
    pending: 'text-n-slate-10',
  })[s] || 'text-n-slate-10';

// How the reply was matched to this send — 'flow'/'button' are exact (see
// Jabvox::BulkWhatsappReplyStatus), 'message' is a best-effort guess (first
// incoming message afterwards, shown so the agent knows it's less certain).
const replySourceLabel = source =>
  source ? t(`JABVOX_BULK_WA.REPORT.REPLY_SOURCE.${source.toUpperCase()}`) : '';

const replySourceClass = source =>
  ({
    flow: 'bg-n-teal-3 text-n-teal-11',
    button: 'bg-n-blue-3 text-n-blue-11',
    message: 'bg-n-slate-3 text-n-slate-11',
  })[source] || '';

// Where the send itself came from — 'bulk' (a batch, JabvoxBulkWhatsappRecipient)
// or 'individual' (an agent sending a template from the conversation composer,
// a plain Message). Only meaningful in the cross-source Informes → Plantillas
// report (see showOrigin).
const originLabel = origin =>
  t(
    `JABVOX_BULK_WA.REPORT.ORIGIN.${origin === 'individual' ? 'INDIVIDUAL' : 'BULK'}`
  );

defineExpose({
  formatReplyTime,
  statusLabel,
  statusClass,
  replySourceLabel,
  replySourceClass,
  originLabel,
  CHECK,
  DOUBLE_CHECK,
  DASH,
});
</script>

<template>
  <div v-if="loading" class="flex items-center justify-center py-16">
    <Spinner :size="24" />
  </div>
  <div
    v-else-if="!recipients.length"
    class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
  >
    {{ t('JABVOX_BULK_WA.REPORT.EMPTY') }}
  </div>
  <div v-else class="overflow-x-auto">
    <table class="min-w-full text-sm">
      <thead>
        <tr
          class="text-left text-xs font-medium uppercase tracking-wide text-n-slate-10 border-b border-n-weak"
        >
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.NAME') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.PHONE') }}
          </th>
          <th v-if="showTemplate" class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.TEMPLATE') }}
          </th>
          <th v-if="showOrigin" class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.ORIGIN') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.STATUS') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.DELIVERED') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.READ') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.REPLIED') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.REPLY_TIME') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.REPLY_TEXT') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.ERROR_CODE') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.ERROR_MESSAGE') }}
          </th>
          <th class="py-2 px-3 whitespace-nowrap">
            {{ t('JABVOX_BULK_WA.REPORT.COLS.SENT_AT') }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak">
        <tr v-for="r in recipients" :key="r.id">
          <td class="py-2 px-3 text-n-slate-12 whitespace-nowrap">
            {{ r.name }}
          </td>
          <td class="py-2 px-3 text-n-slate-11 whitespace-nowrap">
            {{ r.phone_number }}
          </td>
          <td
            v-if="showTemplate"
            class="py-2 px-3 text-n-slate-11 whitespace-nowrap"
          >
            {{ r.template_name }}
          </td>
          <td
            v-if="showOrigin"
            class="py-2 px-3 text-n-slate-11 whitespace-nowrap"
          >
            {{ originLabel(r.origin) }}
          </td>
          <td
            class="py-2 px-3 font-medium whitespace-nowrap"
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
          <td class="py-2 px-3 text-n-slate-11 whitespace-nowrap">
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
          <td class="py-2 px-3 text-n-slate-11 whitespace-nowrap">
            {{ formatReplyTime(r.reply_time_seconds) }}
          </td>
          <td class="py-2 px-3 text-n-slate-11 max-w-xs">
            <div class="flex items-center gap-1.5">
              <span
                v-if="r.reply_source"
                class="shrink-0 rounded-full px-1.5 py-0.5 text-xs font-medium whitespace-nowrap"
                :class="replySourceClass(r.reply_source)"
              >
                {{ replySourceLabel(r.reply_source) }}
              </span>
              <span class="truncate" :title="r.reply_text || ''">
                {{ r.reply_text }}
              </span>
            </div>
          </td>
          <td class="py-2 px-3 text-n-slate-11 whitespace-nowrap">
            {{ r.error_code }}
          </td>
          <td class="py-2 px-3 text-n-slate-11 max-w-xs truncate">
            {{ r.error_message }}
          </td>
          <td class="py-2 px-3 text-n-slate-11 whitespace-nowrap">
            {{ r.sent_at }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
