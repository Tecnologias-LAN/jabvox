<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import voiceBroadcastAPI from 'dashboard/api/jabvox/voiceBroadcast';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Historial de envíos: cada campaña con cuándo, cuántos y cómo resultó
// (marcados, contestó humano/máquina, reprodujo el audio, fallidos, tasa).
const emit = defineEmits(['open']);
const { t } = useI18n();

const STATUS_COLOR = {
  draft: 'slate',
  running: 'teal',
  paused: 'amber',
  completed: 'blue',
  stopped: 'ruby',
};

const items = ref([]);
const loading = ref(false);
const page = ref(1);
const totalPages = ref(1);
const statusFilter = ref('');
const from = ref('');
const to = ref('');

const statusColor = s => STATUS_COLOR[s] || 'slate';
const statusLabel = s =>
  t(`JABVOX_VOICE_BROADCAST.STATUS.${(s || 'draft').toUpperCase()}`);

const fmtDate = iso => {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleString();
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await voiceBroadcastAPI.history({
      page: page.value,
      status: statusFilter.value || undefined,
      from: from.value || undefined,
      to: to.value || undefined,
    });
    items.value = data.items || [];
    totalPages.value = data.total_pages || 1;
  } catch (e) {
    items.value = [];
  } finally {
    loading.value = false;
  }
};

const applyFilters = () => {
  page.value = 1;
  load();
};

const goToPage = p => {
  if (p < 1 || p > totalPages.value) return;
  page.value = p;
  load();
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-4">
    <!-- Filtros -->
    <div class="flex flex-wrap items-end gap-3">
      <div class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_VOICE_BROADCAST.HISTORY.FROM') }}
        </span>
        <input
          v-model="from"
          type="date"
          class="reset-base text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12"
          @change="applyFilters"
        />
      </div>
      <div class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_VOICE_BROADCAST.HISTORY.TO') }}
        </span>
        <input
          v-model="to"
          type="date"
          class="reset-base text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12"
          @change="applyFilters"
        />
      </div>
      <div class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_VOICE_BROADCAST.COLS.STATUS') }}
        </span>
        <select
          v-model="statusFilter"
          class="reset-base text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12"
          @change="applyFilters"
        >
          <option value="">
            {{ t('JABVOX_VOICE_BROADCAST.HISTORY.ALL') }}
          </option>
          <option value="running">
            {{ t('JABVOX_VOICE_BROADCAST.STATUS.RUNNING') }}
          </option>
          <option value="paused">
            {{ t('JABVOX_VOICE_BROADCAST.STATUS.PAUSED') }}
          </option>
          <option value="completed">
            {{ t('JABVOX_VOICE_BROADCAST.STATUS.COMPLETED') }}
          </option>
          <option value="stopped">
            {{ t('JABVOX_VOICE_BROADCAST.STATUS.STOPPED') }}
          </option>
          <option value="draft">
            {{ t('JABVOX_VOICE_BROADCAST.STATUS.DRAFT') }}
          </option>
        </select>
      </div>
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 py-10 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <div
      v-else-if="!items.length"
      class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
    >
      {{ t('JABVOX_VOICE_BROADCAST.HISTORY.EMPTY') }}
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
              {{ t('JABVOX_VOICE_BROADCAST.COLS.NAME') }}
            </th>
            <th class="text-left px-4 py-2.5">
              {{ t('JABVOX_VOICE_BROADCAST.COLS.STATUS') }}
            </th>
            <th class="text-right px-4 py-2.5">
              {{ t('JABVOX_VOICE_BROADCAST.COLS.TOTAL') }}
            </th>
            <th class="text-right px-4 py-2.5">
              {{ t('JABVOX_VOICE_BROADCAST.COLS.DIALED') }}
            </th>
            <th class="text-right px-4 py-2.5 text-n-teal-11">
              {{ t('JABVOX_VOICE_BROADCAST.COUNTS.ANSWERED_HUMAN') }}
            </th>
            <th class="text-right px-4 py-2.5 text-n-blue-11">
              {{ t('JABVOX_VOICE_BROADCAST.COUNTS.PLAYED_COMPLETE') }}
            </th>
            <th class="text-right px-4 py-2.5 text-n-ruby-11">
              {{ t('JABVOX_VOICE_BROADCAST.COUNTS.FAILED') }}
            </th>
            <th class="text-right px-4 py-2.5">
              {{ t('JABVOX_VOICE_BROADCAST.REPORT.ANSWER_RATE') }}
            </th>
            <th class="text-left px-4 py-2.5">
              {{ t('JABVOX_VOICE_BROADCAST.HISTORY.CREATED') }}
            </th>
            <th class="px-4 py-2.5" />
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr
            v-for="row in items"
            :key="row.id"
            class="hover:bg-n-alpha-1 transition-colors"
          >
            <td class="px-4 py-2.5 text-n-slate-12 truncate max-w-48">
              {{ row.name }}
            </td>
            <td class="px-4 py-2.5">
              <Label
                :label="statusLabel(row.status)"
                :color="statusColor(row.status)"
                compact
              />
            </td>
            <td class="px-4 py-2.5 text-right tabular-nums">{{ row.total }}</td>
            <td class="px-4 py-2.5 text-right tabular-nums">
              {{ row.dialed }}
            </td>
            <td class="px-4 py-2.5 text-right tabular-nums text-n-teal-11">
              {{ row.answered_human }}
            </td>
            <td class="px-4 py-2.5 text-right tabular-nums text-n-blue-11">
              {{ row.played_complete }}
            </td>
            <td class="px-4 py-2.5 text-right tabular-nums text-n-ruby-11">
              {{ row.failed }}
            </td>
            <td class="px-4 py-2.5 text-right tabular-nums font-medium">
              {{ row.answer_rate }}%
            </td>
            <td class="px-4 py-2.5 text-xs text-n-slate-11 whitespace-nowrap">
              {{ fmtDate(row.created_at) }}
            </td>
            <td class="px-4 py-2.5 text-right">
              <Button
                icon="i-lucide-external-link"
                size="xs"
                variant="ghost"
                color="slate"
                :title="t('JABVOX_VOICE_BROADCAST.OPEN')"
                @click="emit('open', row)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Paginación -->
    <div
      v-if="totalPages > 1"
      class="flex items-center justify-center gap-2 text-xs text-n-slate-11"
    >
      <Button
        icon="i-lucide-chevron-left"
        size="xs"
        variant="ghost"
        :disabled="page <= 1"
        @click="goToPage(page - 1)"
      />
      <span class="tabular-nums">{{ page }} / {{ totalPages }}</span>
      <Button
        icon="i-lucide-chevron-right"
        size="xs"
        variant="ghost"
        :disabled="page >= totalPages"
        @click="goToPage(page + 1)"
      />
    </div>
  </div>
</template>
