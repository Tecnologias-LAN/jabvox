<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ReportsAPI from 'dashboard/api/reports';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Drill-down por agente: al abrir un agente muestra el detalle de cada mensaje
// saliente — contacto/número, estado (enviado/entregado/leído/fallido), plantilla,
// error de Meta y fecha — con pestañas por estado (todos/fallidos/…).
const { t } = useI18n();

const show = ref(false);
const loading = ref(false);
const agent = ref(null);
const summary = ref(null);
const messages = ref([]);
const statusFilter = ref('');
// Filtros heredados del reporte (fecha/plantilla/bandeja) para que el detalle
// coincida con lo que se ve en la tabla.
let baseParams = {};

const STATUS_TABS = ['', 'sent', 'delivered', 'read', 'failed'];

const statusClass = s =>
  ({
    read: 'text-n-teal-11',
    delivered: 'text-n-teal-11',
    failed: 'text-n-ruby-11',
    sent: 'text-n-slate-11',
  })[s] || 'text-n-slate-10';

const tabCount = key => {
  const s = summary.value;
  if (!s) return null;
  return key === '' ? s.total : s[key];
};

const load = async () => {
  if (!agent.value) return;
  loading.value = true;
  try {
    const { data } = await ReportsAPI.getWhatsappAgentDetail(agent.value.id, {
      ...baseParams,
      msgStatus: statusFilter.value || undefined,
    });
    summary.value = data.summary;
    messages.value = data.messages || [];
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('WHATSAPP_REPORTS.DETAIL.LOAD_ERROR')
    );
  } finally {
    loading.value = false;
  }
};

const open = (agentRow, params) => {
  agent.value = agentRow;
  baseParams = params || {};
  statusFilter.value = '';
  summary.value = null;
  messages.value = [];
  show.value = true;
  load();
};

const close = () => {
  show.value = false;
  agent.value = null;
};

const applyStatus = value => {
  statusFilter.value = value;
  load();
};

const fmtDate = iso => {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleString();
};

const title = computed(() =>
  t('WHATSAPP_REPORTS.DETAIL.TITLE', { name: agent.value?.name || '' })
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
        class="flex flex-col w-full max-w-5xl max-h-[90vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-lg overflow-hidden"
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

        <!-- Pestañas por estado -->
        <div class="px-5 pt-4 flex flex-wrap items-center gap-1">
          <Button
            v-for="tab in STATUS_TABS"
            :key="tab || 'all'"
            :label="`${t(`WHATSAPP_REPORTS.DETAIL.TABS.${(tab || 'all').toUpperCase()}`)}${tabCount(tab) != null ? ` (${tabCount(tab)})` : ''}`"
            size="xs"
            :variant="statusFilter === tab ? 'solid' : 'outline'"
            color="slate"
            @click="applyStatus(tab)"
          />
        </div>

        <!-- Body -->
        <div class="flex-1 overflow-y-auto px-5 py-4">
          <div v-if="loading" class="flex items-center justify-center py-16">
            <Spinner :size="24" />
          </div>
          <div
            v-else-if="!messages.length"
            class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
          >
            {{ t('WHATSAPP_REPORTS.DETAIL.EMPTY') }}
          </div>
          <table v-else class="min-w-full text-sm">
            <thead
              class="sticky top-0 z-[1] bg-n-alpha-1 text-n-slate-11 text-left text-xs uppercase tracking-wide"
            >
              <tr>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.DETAIL.COLS.CONTACT') }}
                </th>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.DETAIL.COLS.PHONE') }}
                </th>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.DETAIL.COLS.STATUS') }}
                </th>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.DETAIL.COLS.TEMPLATE') }}
                </th>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.DETAIL.COLS.ERROR') }}
                </th>
                <th class="py-2 px-3 font-medium">
                  {{ t('WHATSAPP_REPORTS.DETAIL.COLS.DATE') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="m in messages"
                :key="m.id"
                class="text-n-slate-12 hover:bg-n-alpha-1"
              >
                <td class="py-2 px-3">{{ m.name || '—' }}</td>
                <td class="py-2 px-3 text-n-slate-11">{{ m.phone || '—' }}</td>
                <td
                  class="py-2 px-3 font-medium"
                  :class="statusClass(m.status)"
                >
                  {{
                    t(
                      `WHATSAPP_REPORTS.DETAIL.STATUS.${m.status.toUpperCase()}`
                    )
                  }}
                </td>
                <td class="py-2 px-3 text-n-slate-11">
                  {{ m.template || '—' }}
                </td>
                <td class="py-2 px-3 text-n-ruby-11 max-w-xs truncate">
                  {{ m.error || '' }}
                </td>
                <td class="py-2 px-3 text-n-slate-11 whitespace-nowrap">
                  {{ fmtDate(m.created_at) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </teleport>
</template>
