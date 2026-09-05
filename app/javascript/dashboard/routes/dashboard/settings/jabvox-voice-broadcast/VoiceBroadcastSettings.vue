<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import voiceBroadcastAPI from 'dashboard/api/jabvox/voiceBroadcast';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import VoiceBroadcastFormDialog from './components/VoiceBroadcastFormDialog.vue';
import VoiceBroadcastDetailDialog from './components/VoiceBroadcastDetailDialog.vue';
import HistoryTab from './components/HistoryTab.vue';
import ReportsTab from './components/ReportsTab.vue';

// Voice Broadcast: campañas de voz salientes (audio pregrabado). Módulo independiente
// del marcador, con 3 pestañas: Campañas (lista en tarjetas + crear/editar/abrir),
// Historial (envíos: cuándo, cuántos, cómo resultó) y Reportes (métricas cross-campaña).
const { t } = useI18n();

// Pestañas al estilo del marcador.
const TABS = [
  { key: 'campaigns', icon: 'i-lucide-radio-tower' },
  { key: 'history', icon: 'i-lucide-history' },
  { key: 'reports', icon: 'i-lucide-bar-chart-2' },
];
const activeTab = ref('campaigns');

const broadcasts = ref([]);
const loading = ref(false);
const formDialog = ref(null);
const detailDialog = ref(null);

// Color de la pill de estado — mismo mapeo semántico que el dialer.
const STATUS_COLOR = {
  draft: 'slate',
  running: 'teal',
  paused: 'amber',
  completed: 'blue',
  stopped: 'ruby',
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await voiceBroadcastAPI.get();
    broadcasts.value = data || [];
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('JABVOX_VOICE_BROADCAST.LOAD_ERROR')
    );
  } finally {
    loading.value = false;
  }
};

const hasBroadcasts = computed(() => broadcasts.value.length > 0);

const statusColor = s => STATUS_COLOR[s] || 'slate';
const statusLabel = s =>
  t(`JABVOX_VOICE_BROADCAST.STATUS.${(s || 'draft').toUpperCase()}`);

// Métricas por tarjeta: usa counts si el backend los provee; si no, columnas planas.
const cardCounts = b => {
  const c = b.counts || {};
  return {
    total: c.total ?? b.total ?? 0,
    dialed: c.dialed ?? b.dialed ?? 0,
    answered: c.answered_human ?? b.answered_human ?? 0,
    remaining: (c.total ?? b.total ?? 0) - (c.dialed ?? b.dialed ?? 0),
  };
};

const openCreate = () => formDialog.value?.open();
const openEdit = row => formDialog.value?.open(row);
const openDetail = row => detailDialog.value?.open(row);

const onSaved = () => load();
const onChanged = () => load();

onMounted(load);
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-6xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <header
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span
            class="i-lucide-megaphone size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_VOICE_BROADCAST.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_VOICE_BROADCAST.SUBTITLE') }}
            </p>
          </div>
        </div>
        <Button
          v-if="activeTab === 'campaigns'"
          :label="t('JABVOX_VOICE_BROADCAST.NEW')"
          icon="i-lucide-plus"
          size="sm"
          class="shrink-0"
          @click="openCreate"
        />
      </header>

      <!-- Pestañas -->
      <div
        class="flex items-center gap-1 p-1 rounded-xl bg-n-alpha-1 border border-n-weak w-full sm:w-fit overflow-x-auto"
      >
        <button
          v-for="tab in TABS"
          :key="tab.key"
          type="button"
          class="flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg whitespace-nowrap transition-colors flex-1 sm:flex-none"
          :class="
            activeTab === tab.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          <span :class="tab.icon" class="size-4 shrink-0" />
          {{ t(`JABVOX_VOICE_BROADCAST.TABS.${tab.key.toUpperCase()}`) }}
        </button>
      </div>

      <!-- Tab: Historial -->
      <HistoryTab v-if="activeTab === 'history'" @open="openDetail" />

      <!-- Tab: Reportes -->
      <ReportsTab v-else-if="activeTab === 'reports'" />

      <!-- Tab: Campañas -->
      <template v-else>
        <!-- Loading -->
        <div
          v-if="loading"
          class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
        >
          <Spinner :size="18" />
          {{ t('JABVOX_VOICE_BROADCAST.LOADING') }}
        </div>

        <!-- Empty -->
        <div
          v-else-if="!hasBroadcasts"
          class="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-n-weak bg-n-solid-1 py-14 text-center"
        >
          <span
            class="i-lucide-megaphone size-10 rounded-xl bg-n-alpha-1 p-2 text-n-slate-10"
          />
          <div>
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_VOICE_BROADCAST.EMPTY_TITLE') }}
            </p>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ t('JABVOX_VOICE_BROADCAST.EMPTY') }}
            </p>
          </div>
          <Button
            :label="t('JABVOX_VOICE_BROADCAST.NEW')"
            icon="i-lucide-plus"
            size="sm"
            @click="openCreate"
          />
        </div>

        <!-- Grid de campañas -->
        <div v-else class="grid grid-cols-1 xl:grid-cols-2 gap-4">
          <div
            v-for="b in broadcasts"
            :key="b.id"
            class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
          >
            <!-- Header de tarjeta -->
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-2 min-w-0">
                <span
                  class="i-lucide-radio-tower size-4 text-n-slate-10 shrink-0"
                />
                <h3 class="text-sm font-semibold text-n-slate-12 truncate">
                  {{ b.name }}
                </h3>
              </div>
              <Label
                :label="statusLabel(b.status)"
                :color="statusColor(b.status)"
                compact
              />
            </div>

            <!-- Línea de audio -->
            <div
              class="flex items-center gap-1.5 text-xs -mt-2"
              :class="b.audio_ready ? 'text-n-teal-11' : 'text-n-slate-10'"
            >
              <span
                :class="
                  b.audio_ready ? 'i-lucide-volume-2' : 'i-lucide-volume-x'
                "
                class="size-3.5 shrink-0"
              />
              {{
                b.audio_ready
                  ? t('JABVOX_VOICE_BROADCAST.AUDIO_READY')
                  : t('JABVOX_VOICE_BROADCAST.AUDIO_MISSING')
              }}
            </div>

            <!-- Métricas -->
            <div class="grid grid-cols-4 gap-2">
              <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
                <p class="text-sm font-semibold text-n-slate-12 tabular-nums">
                  {{ cardCounts(b).total }}
                </p>
                <p class="text-[11px] text-n-slate-10">
                  {{ t('JABVOX_VOICE_BROADCAST.COUNTS.TOTAL') }}
                </p>
              </div>
              <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
                <p class="text-sm font-semibold text-n-slate-12 tabular-nums">
                  {{ cardCounts(b).dialed }}
                </p>
                <p class="text-[11px] text-n-slate-10">
                  {{ t('JABVOX_VOICE_BROADCAST.COLS.DIALED') }}
                </p>
              </div>
              <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
                <p class="text-sm font-semibold text-n-teal-11 tabular-nums">
                  {{ cardCounts(b).answered }}
                </p>
                <p class="text-[11px] text-n-slate-10">
                  {{ t('JABVOX_VOICE_BROADCAST.COUNTS.ANSWERED_HUMAN') }}
                </p>
              </div>
              <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
                <p class="text-sm font-semibold text-n-slate-12 tabular-nums">
                  {{ cardCounts(b).remaining }}
                </p>
                <p class="text-[11px] text-n-slate-10">
                  {{ t('JABVOX_VOICE_BROADCAST.DETAIL.REMAINING') }}
                </p>
              </div>
            </div>

            <!-- Acciones -->
            <div class="flex items-center gap-2 pt-1 border-t border-n-weak">
              <span class="mr-auto" />
              <div class="flex items-center gap-1 pt-3">
                <Button
                  :label="t('JABVOX_VOICE_BROADCAST.OPEN')"
                  icon="i-lucide-radio"
                  size="sm"
                  variant="outline"
                  :color="b.status === 'running' ? 'teal' : 'slate'"
                  :title="t('JABVOX_VOICE_BROADCAST.OPEN')"
                  @click="openDetail(b)"
                />
                <Button
                  v-if="b.status === 'draft'"
                  icon="i-lucide-pencil"
                  size="sm"
                  variant="ghost"
                  color="slate"
                  :title="t('JABVOX_VOICE_BROADCAST.FORM.EDIT_TITLE')"
                  @click="openEdit(b)"
                />
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>

    <VoiceBroadcastFormDialog ref="formDialog" @saved="onSaved" />
    <VoiceBroadcastDetailDialog ref="detailDialog" @changed="onChanged" />
  </div>
</template>
