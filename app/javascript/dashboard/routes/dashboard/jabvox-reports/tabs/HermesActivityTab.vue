<script setup>
// Reporte de ACTIVIDAD de Hermes (bot IA): qué ha hecho sobre la cuenta.
// Se alimenta de la auditoría del backend (JabvoxHermesActionLog), nunca de Hermes.
import { ref, computed, onMounted } from 'vue';
import reportsAPI from 'dashboard/api/jabvox/reports';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import KpiCard from '../components/KpiCard.vue';

const loading = ref(false);
const report = ref(null);

const filters = ref({ date_from: '', date_to: '' });

const STATUS_LABEL = {
  success: 'Éxito',
  forbidden: 'Bloqueada',
  module_disabled: 'Módulo no activo',
  error: 'Error',
};

// Textos en objeto para evitar strings sueltos en la plantilla (regla i18n del proyecto).
const TXT = {
  from: 'Desde',
  to: 'Hasta',
  apply: 'Aplicar',
  clear: 'Limpiar',
  emptyTitle: 'Sin actividad de Hermes',
  emptySubtitle:
    'Cuando Hermes ejecute acciones en la app aparecerán aquí sus métricas.',
  kpiTotal: 'Acciones totales',
  kpiSuccess: 'Exitosas',
  kpiBlocked: 'Bloqueadas',
  kpiErrors: 'Errores',
  byAgent: 'Por agente de Hermes',
  perDay: 'Acciones por día',
  topTools: 'Herramientas más usadas',
  recent: 'Últimas acciones',
  colDate: 'Fecha',
  colAgent: 'Agente',
  colTool: 'Herramienta',
  colStatus: 'Estado',
  colData: 'Datos',
};

const totals = computed(() => report.value?.totals || {});
const byTool = computed(() => report.value?.by_tool || []);
const byIdentity = computed(() => report.value?.by_identity || []);
const recent = computed(() => report.value?.recent || []);
const perDay = computed(() => report.value?.per_day || []);

// Máximo para dibujar barras proporcionales en la serie diaria.
const maxPerDay = computed(() =>
  perDay.value.reduce((m, d) => Math.max(m, d.count), 0)
);
const maxByTool = computed(() =>
  byTool.value.reduce((m, t) => Math.max(m, t.count), 0)
);

const fetch = async () => {
  loading.value = true;
  try {
    const { data } = await reportsAPI.getHermesActivity(filters.value);
    report.value = data;
  } catch {
    report.value = null;
  } finally {
    loading.value = false;
  }
};

const resetFilters = () => {
  filters.value = { date_from: '', date_to: '' };
  fetch();
};

const statusClass = status => {
  if (status === 'success') return 'bg-n-teal-3 text-n-teal-11';
  if (status === 'error') return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-amber-3 text-n-amber-11';
};

const fmtDate = iso => (iso ? new Date(iso).toLocaleString() : '');
const fmtParams = p => {
  if (!p || !Object.keys(p).length) return '—';
  try {
    return JSON.stringify(p);
  } catch {
    return '—';
  }
};

const hasData = computed(() => (totals.value.total || 0) > 0);

onMounted(fetch);
</script>

<template>
  <div class="flex flex-col gap-5">
    <!-- Filtros de fecha -->
    <div class="flex flex-wrap items-end gap-3">
      <div class="flex flex-col gap-1">
        <Label>{{ TXT.from }}</Label>
        <Input v-model="filters.date_from" type="date" />
      </div>
      <div class="flex flex-col gap-1">
        <Label>{{ TXT.to }}</Label>
        <Input v-model="filters.date_to" type="date" />
      </div>
      <Button
        variant="solid"
        :label="TXT.apply"
        :disabled="loading"
        @click="fetch"
      />
      <Button
        variant="ghost"
        :label="TXT.clear"
        :disabled="loading"
        @click="resetFilters"
      />
    </div>

    <div v-if="loading" class="flex items-center justify-center py-10">
      <Spinner :size="24" />
    </div>

    <EmptyStateLayout
      v-else-if="!hasData"
      :title="TXT.emptyTitle"
      :subtitle="TXT.emptySubtitle"
    />

    <template v-else>
      <!-- KPIs -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <KpiCard :label="TXT.kpiTotal" :value="totals.total" />
        <KpiCard :label="TXT.kpiSuccess" :value="totals.success" />
        <KpiCard
          :label="TXT.kpiBlocked"
          :value="(totals.forbidden || 0) + (totals.module_disabled || 0)"
        />
        <KpiCard :label="TXT.kpiErrors" :value="totals.error" />
      </div>

      <!-- Por agente de Hermes -->
      <div v-if="byIdentity.length" class="rounded-xl border border-n-weak p-4">
        <h3 class="text-sm font-medium text-n-slate-12 mb-2">
          {{ TXT.byAgent }}
        </h3>
        <div class="flex flex-wrap gap-2">
          <span
            v-for="it in byIdentity"
            :key="it.identity"
            class="inline-flex items-center gap-1.5 rounded-lg bg-n-alpha-2 px-2.5 py-1 text-sm"
          >
            <span class="text-n-slate-12">{{ `🤖 ${it.identity}` }}</span>
            <span class="text-n-slate-10 font-mono">{{ it.count }}</span>
          </span>
        </div>
      </div>

      <!-- Serie diaria -->
      <div v-if="perDay.length" class="rounded-xl border border-n-weak p-4">
        <h3 class="text-sm font-medium text-n-slate-12 mb-3">
          {{ TXT.perDay }}
        </h3>
        <div class="flex items-end gap-1 h-32">
          <div
            v-for="d in perDay"
            :key="d.date"
            class="flex-1 flex flex-col items-center justify-end gap-1"
            :title="`${d.date}: ${d.count}`"
          >
            <div
              class="w-full rounded-t bg-n-teal-9 min-h-[2px]"
              :style="{
                height: `${maxPerDay ? (d.count / maxPerDay) * 100 : 0}%`,
              }"
            />
            <span
              class="text-[10px] text-n-slate-10 rotate-45 origin-left whitespace-nowrap mt-1"
            >
              {{ d.date.slice(5) }}
            </span>
          </div>
        </div>
      </div>

      <!-- Desglose por herramienta -->
      <div class="rounded-xl border border-n-weak p-4">
        <h3 class="text-sm font-medium text-n-slate-12 mb-3">
          {{ TXT.topTools }}
        </h3>
        <div class="flex flex-col gap-2">
          <div
            v-for="tool in byTool"
            :key="tool.tool"
            class="flex items-center gap-3"
          >
            <span
              class="font-mono text-xs text-n-slate-11 w-56 truncate"
              :title="tool.tool"
            >
              {{ tool.tool }}
            </span>
            <div class="flex-1 bg-n-alpha-2 rounded h-4 overflow-hidden">
              <div
                class="h-full bg-n-teal-9 rounded"
                :style="{
                  width: `${maxByTool ? (tool.count / maxByTool) * 100 : 0}%`,
                }"
              />
            </div>
            <span class="text-xs text-n-slate-11 w-10 text-right">{{
              tool.count
            }}</span>
          </div>
        </div>
      </div>

      <!-- Acciones recientes -->
      <div class="rounded-xl border border-n-weak p-4">
        <h3 class="text-sm font-medium text-n-slate-12 mb-3">
          {{ TXT.recent }}
        </h3>
        <div class="overflow-x-auto">
          <table class="w-full text-sm border-collapse">
            <thead>
              <tr
                class="text-left text-xs text-n-slate-10 border-b border-n-weak"
              >
                <th class="py-2 pr-3 font-medium">{{ TXT.colDate }}</th>
                <th class="py-2 pr-3 font-medium">{{ TXT.colAgent }}</th>
                <th class="py-2 pr-3 font-medium">{{ TXT.colTool }}</th>
                <th class="py-2 pr-3 font-medium">{{ TXT.colStatus }}</th>
                <th class="py-2 pr-3 font-medium">{{ TXT.colData }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="log in recent"
                :key="log.id"
                class="border-b border-n-weak/50 align-top"
              >
                <td class="py-2 pr-3 whitespace-nowrap text-n-slate-11">
                  {{ fmtDate(log.created_at) }}
                </td>
                <td class="py-2 pr-3 text-n-slate-11">
                  {{ log.identity || 'Hermes' }}
                </td>
                <td class="py-2 pr-3 font-mono text-n-slate-12">
                  {{ log.tool }}
                </td>
                <td class="py-2 pr-3">
                  <span
                    class="inline-block rounded px-2 py-0.5 text-xs"
                    :class="statusClass(log.status)"
                  >
                    {{ STATUS_LABEL[log.status] || log.status }}
                  </span>
                </td>
                <td
                  class="py-2 pr-3 font-mono text-xs text-n-slate-10 max-w-xs truncate"
                  :title="fmtParams(log.params)"
                >
                  {{ fmtParams(log.params) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </div>
</template>
