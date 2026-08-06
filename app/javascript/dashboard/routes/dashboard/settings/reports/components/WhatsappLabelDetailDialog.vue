<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ReportsAPI from 'dashboard/api/reports';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Drill-down por etiqueta: al abrir una etiqueta lista los leads que la tienen
// (o tuvieron) aplicada, con el contacto, desde cuándo y cuánto tiempo lleva puesta.
const { t } = useI18n();

const show = ref(false);
const loading = ref(false);
const label = ref(null);
const leads = ref([]);
// Filtros heredados del reporte (fecha) para que el detalle coincida con la tabla.
let baseParams = {};

const load = async () => {
  if (!label.value) return;
  loading.value = true;
  try {
    const { data } = await ReportsAPI.getWhatsappLabelLeads({
      ...baseParams,
      label: label.value,
    });
    leads.value = data || [];
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('WHATSAPP_REPORTS.LABELS.DETAIL.LOAD_ERROR')
    );
  } finally {
    loading.value = false;
  }
};

const open = (labelRow, params) => {
  label.value = labelRow?.label || labelRow;
  baseParams = params || {};
  leads.value = [];
  show.value = true;
  load();
};

const close = () => {
  show.value = false;
  label.value = null;
};

// El backend entrega epoch en segundos.
const fmtDate = epoch => {
  if (!epoch) return '—';
  return new Date(Number(epoch) * 1000).toLocaleString();
};

// Duración legible a partir de segundos.
const fmtDuration = secs => {
  const s = Number(secs);
  if (!Number.isFinite(s) || s <= 0) return '0m';
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  const parts = [];
  if (d > 0) parts.push(`${d}d`);
  if (h > 0) parts.push(`${h}h`);
  if (m > 0 && d === 0) parts.push(`${m}m`);
  return parts.slice(0, 2).join(' ') || '0m';
};

const title = computed(() =>
  t('WHATSAPP_REPORTS.LABELS.DETAIL.TITLE', { label: label.value || '' })
);

defineExpose({ open });
</script>

<template>
  <teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
      @click.self="close"
    >
      <div
        class="flex flex-col w-full max-w-4xl max-h-[90vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-lg overflow-hidden"
      >
        <!-- Header -->
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <h3 class="text-base font-semibold text-n-slate-12">
            {{ title }}
          </h3>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            @click="close"
          />
        </div>

        <!-- Body -->
        <div class="flex-1 overflow-y-auto px-5 py-4">
          <div v-if="loading" class="flex items-center justify-center py-16">
            <Spinner :size="24" />
          </div>
          <div
            v-else-if="!leads.length"
            class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
          >
            {{ t('WHATSAPP_REPORTS.LABELS.DETAIL.EMPTY') }}
          </div>
          <table v-else class="min-w-full text-sm">
            <thead
              class="sticky top-0 z-[1] bg-n-alpha-1 text-n-slate-11 text-left text-xs uppercase tracking-wide"
            >
              <tr>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.LABELS.DETAIL.COLS.LEAD') }}
                </th>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.LABELS.DETAIL.COLS.PHONE') }}
                </th>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.LABELS.DETAIL.COLS.APPLIED_AT') }}
                </th>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.LABELS.DETAIL.COLS.DURATION') }}
                </th>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.LABELS.DETAIL.COLS.STATE') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="row in leads"
                :key="`${row.conversation_id}-${row.applied_at}`"
                class="text-n-slate-12 hover:bg-n-alpha-1"
              >
                <td class="py-2 px-3">{{ row.contact_name || '—' }}</td>
                <td class="py-2 px-3 text-n-slate-11">
                  {{ row.contact_phone || '—' }}
                </td>
                <td class="py-2 px-3 text-n-slate-11 whitespace-nowrap">
                  {{ fmtDate(row.applied_at) }}
                </td>
                <td class="py-2 px-3 font-medium whitespace-nowrap">
                  {{ fmtDuration(row.duration_seconds) }}
                </td>
                <td class="py-2 px-3">
                  <span
                    class="inline-flex items-center gap-1 text-xs"
                    :class="row.active ? 'text-n-amber-11' : 'text-n-slate-10'"
                  >
                    <span
                      class="inline-block w-1.5 h-1.5 rounded-full"
                      :class="row.active ? 'bg-n-amber-9' : 'bg-n-slate-8'"
                    />
                    {{
                      row.active
                        ? t('WHATSAPP_REPORTS.LABELS.DETAIL.ACTIVE')
                        : t('WHATSAPP_REPORTS.LABELS.DETAIL.REMOVED')
                    }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </teleport>
</template>
