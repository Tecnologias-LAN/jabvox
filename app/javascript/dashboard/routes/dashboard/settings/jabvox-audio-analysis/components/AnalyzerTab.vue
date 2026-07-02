<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SettingsCard from './SettingsCard.vue';
import BrowserPagination from './BrowserPagination.vue';

const props = defineProps({
  storages: { type: Array, default: () => [] },
  pipelines: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
  typifications: { type: Array, default: () => [] },
  selectedStorageId: { type: [Number, String], default: null },
  selectedPipelineId: { type: [Number, String], default: null },
  prefix: { type: String, default: '' },
  browser: { type: Object, default: () => ({ folders: [], files: [] }) },
  browsing: { type: Boolean, default: false },
  selectedKeys: { type: Set, default: () => new Set() },
  activeJob: { type: Object, default: null },
});

const emit = defineEmits([
  'update:selectedStorageId',
  'update:selectedPipelineId',
  'browse',
  'search',
  'toggle-key',
  'setSelection',
  'clear-selection',
  'launch',
  'assign',
  'assignOne',
  'dismiss-job',
  'play',
]);

const { t } = useI18n();

// File-name search within the current folder. Emits 'search' so the parent
// re-queries the bucket; "1000532535_" returns 1000532535_1, _2, …
const searchTerm = ref('');
const submitSearch = () => emit('search', searchTerm.value.trim());
const clearSearch = () => {
  searchTerm.value = '';
  emit('search', '');
};

const storageOptions = computed(() =>
  props.storages.map(s => ({ value: s.id, label: s.name }))
);
const pipelineOptions = computed(() =>
  props.pipelines.map(p => ({ value: p.id, label: p.name }))
);
const agentOptions = computed(() => [
  { value: null, label: t('JABVOX_AUDIO.ANALYZER.NO_AGENT') },
  ...props.agents.map(a => ({ value: a.id, label: a.name })),
]);

// Quick-assign bar (typification + agent applied to the selection, no analysis).
const assignTypificationId = ref(null);
const assignAgentId = ref(null);
const assignTypificationOptions = computed(() => [
  { value: null, label: t('JABVOX_AUDIO.ANALYZER.NO_TYPIFICATION') },
  ...props.typifications.map(tp => ({ value: tp.id, label: tp.name })),
]);
const submitAssign = () => {
  emit('assign', {
    typificationId: assignTypificationId.value,
    agentId: assignAgentId.value,
  });
};

// Inline per-row assignment: changing a row's typification or agent assigns just
// that file, keeping the other value as-is.
const setRowTypification = (file, typificationId) =>
  emit('assignOne', {
    fileKey: file.key,
    typificationId,
    agentId: file.agent_id || null,
  });
const setRowAgent = (file, agentId) =>
  emit('assignOne', {
    fileKey: file.key,
    typificationId: file.typification_id || null,
    agentId,
  });

// Icon per file kind (audio vs document) returned by the backend.
const fileIcon = file =>
  file.kind === 'document' ? 'i-lucide-file-text' : 'i-lucide-file-audio';

const progressPct = computed(() => {
  const j = props.activeJob;
  if (!j?.total_count) return 0;
  return Math.round((j.processed_count / j.total_count) * 100);
});

// Title for the processing popup, e.g. "analisis1".
const activeJobTitle = computed(
  () => props.activeJob?.label || t('JABVOX_AUDIO.ANALYZER.PROCESSING_TITLE')
);

// Human label for the selected pipeline's timestamp mode, shown in the popup.
const selectedPipeline = computed(() =>
  props.pipelines.find(p => p.id === props.selectedPipelineId)
);
const timestampModeLabel = computed(() => {
  const mode = selectedPipeline.value?.timestamp_mode_jabvox || 'none';
  if (mode === 'word') return t('JABVOX_AUDIO.ANALYZER.TS_WORD');
  if (mode === 'segment') {
    return t('JABVOX_AUDIO.ANALYZER.TS_SEGMENT', {
      seconds: selectedPipeline.value?.segment_seconds_jabvox || 30,
    });
  }
  return t('JABVOX_AUDIO.ANALYZER.TS_NONE');
});

const parentPrefix = () => {
  const parts = props.prefix.split('/');
  return parts.slice(0, -2).join('/') + (parts.length > 2 ? '/' : '');
};

// ----- Client-side pagination over the full prefix listing -----
const PAGE_SIZE_OPTIONS = [5, 10, 25, 50, 100];
const pageSize = ref(5);
const page = ref(1);

// Whether bulk "select N" includes audios that were already analyzed.
const includeVerified = ref(true);

// ----- Column sorting -----
// Sortable columns and the value extracted from a file for each.
const SORT_KEYS = {
  name: f => (f.key.split('/').pop() || '').toLowerCase(),
  typification: f => (f.typification_name || '').toLowerCase(),
  agent: f => (f.agent_name || '').toLowerCase(),
  verified: f => (f.analyzed ? 1 : 0),
  kind: f => f.kind || 'audio',
};
const sortKey = ref('name');
const sortDir = ref('asc'); // 'asc' | 'desc'
const toggleSort = key => {
  if (sortKey.value === key) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc';
  } else {
    sortKey.value = key;
    sortDir.value = 'asc';
  }
};
const sortIcon = key => {
  if (sortKey.value !== key) return 'i-lucide-chevrons-up-down';
  return sortDir.value === 'asc'
    ? 'i-lucide-chevron-up'
    : 'i-lucide-chevron-down';
};

const folders = computed(() => props.browser.folders || []);
const files = computed(() => {
  const list = [...(props.browser.files || [])];
  const getVal = SORT_KEYS[sortKey.value] || SORT_KEYS.name;
  list.sort((a, b) => {
    const va = getVal(a);
    const vb = getVal(b);
    if (va < vb) return sortDir.value === 'asc' ? -1 : 1;
    if (va > vb) return sortDir.value === 'asc' ? 1 : -1;
    return 0;
  });
  return list;
});
// Folders first, then audio files — paginated as a single combined list so the
// page size applies to everything the user sees.
const entries = computed(() => [
  ...folders.value.map(f => ({ type: 'folder', value: f })),
  ...files.value.map(f => ({ type: 'file', value: f })),
]);
const totalEntries = computed(() => entries.value.length);
const totalFolders = computed(
  () => props.browser.total_folders ?? folders.value.length
);
const totalFiles = computed(
  () => props.browser.total_files ?? files.value.length
);
const totalPages = computed(() =>
  Math.max(1, Math.ceil(totalEntries.value / pageSize.value))
);
const pagedEntries = computed(() => {
  const start = (page.value - 1) * pageSize.value;
  return entries.value.slice(start, start + pageSize.value);
});

// A file is selectable unless it's verified and the toggle is off.
const isSelectable = file => includeVerified.value || !file.analyzed;
// Selectable files on the CURRENT page (folders excluded).
const pageSelectableKeys = computed(() =>
  pagedEntries.value
    .filter(e => e.type === 'file' && isSelectable(e.value))
    .map(e => e.value.key)
);
// Selectable files across the whole prefix.
const allSelectableKeys = computed(() =>
  files.value.filter(isSelectable).map(f => f.key)
);

const selectPage = () => emit('setSelection', pageSelectableKeys.value);
const selectAll = () => emit('setSelection', allSelectableKeys.value);
const rangeStart = computed(() =>
  totalEntries.value === 0 ? 0 : (page.value - 1) * pageSize.value + 1
);
const rangeEnd = computed(() =>
  Math.min(page.value * pageSize.value, totalEntries.value)
);

const pageSizeOptions = computed(() =>
  PAGE_SIZE_OPTIONS.map(n => ({ value: n, label: String(n) }))
);

// Reset to page 1 whenever the listing changes (new folder) or page size changes.
watch([() => props.browser, pageSize], () => {
  page.value = 1;
});

const goPrev = () => {
  if (page.value > 1) page.value -= 1;
};
const goNext = () => {
  if (page.value < totalPages.value) page.value += 1;
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <!-- Analyzer: storage origin only -->
    <SettingsCard
      :title="t('JABVOX_AUDIO.ANALYZER.TITLE')"
      :description="t('JABVOX_AUDIO.ANALYZER.SUBTITLE')"
      icon="i-lucide-audio-lines"
    >
      <div class="max-w-md flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_AUDIO.ANALYZER.STORAGE') }}
        </span>
        <Select
          :model-value="selectedStorageId"
          :options="storageOptions"
          :placeholder="t('JABVOX_AUDIO.ANALYZER.STORAGE')"
          @update:model-value="
            emit('update:selectedStorageId', $event);
            emit('browse', '');
          "
        />
      </div>
    </SettingsCard>

    <!-- Processing popup: shown while a launched job runs -->
    <div
      v-if="activeJob"
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-4"
    >
      <div
        class="w-full max-w-md rounded-2xl bg-n-solid-1 shadow-xl border border-n-weak p-6 flex flex-col gap-4"
      >
        <div class="flex items-center gap-3">
          <span
            class="flex items-center justify-center size-11 rounded-xl bg-n-brand/10 text-n-brand shrink-0"
          >
            <Spinner
              v-if="
                activeJob.status !== 'completed' &&
                activeJob.status !== 'failed'
              "
              :size="22"
            />
            <span
              v-else-if="activeJob.status === 'completed'"
              class="i-lucide-check-circle-2 size-6"
            />
            <span v-else class="i-lucide-x-circle size-6 text-n-ruby-11" />
          </span>
          <div class="min-w-0">
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ activeJobTitle }}
            </h3>
            <p class="text-sm text-n-slate-11">
              {{
                t(
                  `JABVOX_AUDIO.ANALYZER.STATUS_${activeJob.status.toUpperCase()}`
                )
              }}
            </p>
          </div>
        </div>

        <!-- Batch label + timestamp mode badges -->
        <div class="flex flex-wrap items-center gap-2">
          <span
            v-if="activeJob.label"
            class="inline-flex items-center gap-1 text-xs font-medium px-2.5 py-1 rounded-full bg-n-brand/10 text-n-brand"
          >
            <span class="i-lucide-tag size-3" />
            {{ activeJob.label }}
          </span>
          <span
            class="inline-flex items-center gap-1 text-xs px-2.5 py-1 rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            <span class="i-lucide-clock size-3" />
            {{ timestampModeLabel }}
          </span>
        </div>

        <!-- Progress -->
        <div>
          <div class="flex items-center justify-between text-sm mb-1.5">
            <span class="text-n-slate-11">
              {{ t('JABVOX_AUDIO.ANALYZER.PROGRESS') }}
            </span>
            <span class="text-n-slate-12 font-medium tabular-nums">
              {{ activeJob.processed_count }} / {{ activeJob.total_count }} ({{
                progressPct
              }}%)
            </span>
          </div>
          <div class="h-2.5 rounded-full bg-n-alpha-2 overflow-hidden">
            <div
              class="h-full bg-n-brand transition-all duration-300"
              :style="{ width: `${progressPct}%` }"
            />
          </div>
        </div>

        <Button
          v-if="
            activeJob.status === 'completed' || activeJob.status === 'failed'
          "
          class="self-end"
          :label="t('JABVOX_AUDIO.ANALYZER.CLOSE')"
          @click="emit('dismiss-job')"
        />
      </div>
    </div>

    <!-- File browser -->
    <SettingsCard
      :title="t('JABVOX_AUDIO.ANALYZER.BROWSER_TITLE')"
      icon="i-lucide-folder-open"
    >
      <template #actions>
        <span
          class="text-xs font-medium text-n-slate-11 bg-n-alpha-2 rounded-full px-2.5 py-1"
        >
          {{
            t('JABVOX_AUDIO.ANALYZER.ITEM_COUNT', {
              folders: totalFolders,
              files: totalFiles,
            })
          }}
        </span>
      </template>

      <!-- Search by file name within the current folder -->
      <div class="flex items-center gap-2 mb-3">
        <div
          class="flex items-center gap-2 flex-1 px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak"
        >
          <span class="i-lucide-search size-4 text-n-slate-10" />
          <input
            v-model="searchTerm"
            type="text"
            class="flex-1 min-w-0 bg-transparent text-sm text-n-slate-12 focus:outline-none"
            :placeholder="t('JABVOX_AUDIO.ANALYZER.SEARCH_PLACEHOLDER')"
            @keyup.enter="submitSearch"
          />
          <button
            v-if="searchTerm"
            type="button"
            class="p-0.5 rounded text-n-slate-10 hover:text-n-slate-12"
            @click="clearSearch"
          >
            <span class="i-lucide-x size-4" aria-hidden="true" />
          </button>
        </div>
        <Button
          :label="t('JABVOX_AUDIO.ANALYZER.SEARCH')"
          variant="outline"
          color="slate"
          icon="i-lucide-search"
          @click="submitSearch"
        />
      </div>

      <!-- Pipeline + selection + launch (moved here from the analyzer card) -->
      <div
        class="rounded-xl border border-n-weak bg-n-alpha-1 p-3 mb-3 flex flex-col gap-3"
      >
        <div class="flex flex-wrap items-end gap-3">
          <div class="flex flex-col gap-1 flex-1 min-w-[12rem]">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_AUDIO.ANALYZER.PIPELINE') }}
            </span>
            <Select
              :model-value="selectedPipelineId"
              :options="pipelineOptions"
              :placeholder="t('JABVOX_AUDIO.ANALYZER.PIPELINE')"
              @update:model-value="emit('update:selectedPipelineId', $event)"
            />
          </div>
          <Button
            :label="`${t('JABVOX_AUDIO.ANALYZER.LAUNCH')} (${selectedKeys.size})`"
            icon="i-lucide-sparkles"
            :disabled="!selectedKeys.size || !selectedPipelineId"
            @click="emit('launch')"
          />
        </div>

        <!-- Bulk selection controls -->
        <div
          v-if="browser.files.length"
          class="flex flex-wrap items-center gap-2 pt-2 border-t border-n-weak"
        >
          <span class="text-xs text-n-slate-11">
            {{ t('JABVOX_AUDIO.ANALYZER.SELECT') }}
          </span>
          <button
            class="px-2.5 py-1 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 disabled:opacity-40"
            :disabled="!pageSelectableKeys.length"
            @click="selectPage"
          >
            {{ t('JABVOX_AUDIO.ANALYZER.SELECT_PAGE') }} ({{
              pageSelectableKeys.length
            }})
          </button>
          <button
            class="px-2.5 py-1 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 disabled:opacity-40"
            :disabled="!allSelectableKeys.length"
            @click="selectAll"
          >
            {{ t('JABVOX_AUDIO.ANALYZER.SELECT_ALL') }} ({{
              allSelectableKeys.length
            }})
          </button>
          <button
            v-if="selectedKeys.size"
            class="px-2.5 py-1 text-xs rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
            @click="emit('clear-selection')"
          >
            {{ t('JABVOX_AUDIO.ANALYZER.CLEAR') }}
          </button>
          <label
            class="flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer ml-1"
          >
            <input
              v-model="includeVerified"
              type="checkbox"
              class="accent-n-brand size-3.5"
            />
            {{ t('JABVOX_AUDIO.ANALYZER.INCLUDE_VERIFIED') }}
          </label>
        </div>

        <!-- Quick-assign: tag selected files (typification + agent) at once -->
        <div
          v-if="selectedKeys.size"
          class="flex flex-wrap items-end gap-3 pt-2 border-t border-n-weak"
        >
          <span class="text-xs text-n-slate-11 self-center">
            {{
              t('JABVOX_AUDIO.ANALYZER.ASSIGN_TO', { count: selectedKeys.size })
            }}
          </span>
          <div class="flex flex-col gap-1 w-44">
            <span class="text-xs text-n-slate-10">
              {{ t('JABVOX_AUDIO.ANALYZER.TYPIFICATION') }}
            </span>
            <Select
              v-model="assignTypificationId"
              :options="assignTypificationOptions"
            />
          </div>
          <div class="flex flex-col gap-1 w-44">
            <span class="text-xs text-n-slate-10">
              {{ t('JABVOX_AUDIO.ANALYZER.ASSIGN_AGENT') }}
            </span>
            <Select v-model="assignAgentId" :options="agentOptions" />
          </div>
          <Button
            :label="t('JABVOX_AUDIO.ANALYZER.ASSIGN')"
            variant="outline"
            color="slate"
            icon="i-lucide-tag"
            @click="submitAssign"
          />
        </div>
      </div>

      <div
        v-if="browsing"
        class="flex items-center gap-2 py-8 justify-center text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_AUDIO.ANALYZER.LOADING') }}
      </div>

      <template v-else>
        <!-- Pagination header (mirrors the footer) -->
        <BrowserPagination
          v-if="totalEntries"
          v-model:page-size="pageSize"
          class="mb-3"
          :page="page"
          :total-pages="totalPages"
          :range-start="rangeStart"
          :range-end="rangeEnd"
          :total="totalEntries"
          :page-size-options="pageSizeOptions"
          @prev="goPrev"
          @next="goNext"
        />

        <div
          class="rounded-xl border border-n-weak divide-y divide-n-weak overflow-hidden"
        >
          <!-- Column header (sortable columns are clickable) -->
          <div
            v-if="totalEntries"
            class="grid grid-cols-[auto_1fr_7rem_8rem_8rem_6rem_4rem_4rem_4rem] items-center gap-3 px-3 py-2 bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
          >
            <span class="w-4" />
            <button
              type="button"
              class="flex items-center gap-1 hover:text-n-slate-12"
              @click="toggleSort('name')"
            >
              {{ t('JABVOX_AUDIO.ANALYZER.COL_NAME') }}
              <span :class="sortIcon('name')" class="size-3" />
            </button>
            <button
              type="button"
              class="flex items-center gap-1 hover:text-n-slate-12"
              @click="toggleSort('kind')"
            >
              {{ t('JABVOX_AUDIO.ANALYZER.COL_KIND') }}
              <span :class="sortIcon('kind')" class="size-3" />
            </button>
            <button
              type="button"
              class="flex items-center gap-1 hover:text-n-slate-12"
              @click="toggleSort('typification')"
            >
              {{ t('JABVOX_AUDIO.ANALYZER.COL_TYPIFICATION') }}
              <span :class="sortIcon('typification')" class="size-3" />
            </button>
            <button
              type="button"
              class="flex items-center gap-1 hover:text-n-slate-12"
              @click="toggleSort('agent')"
            >
              {{ t('JABVOX_AUDIO.ANALYZER.COL_AGENT') }}
              <span :class="sortIcon('agent')" class="size-3" />
            </button>
            <button
              type="button"
              class="flex items-center justify-center gap-1 hover:text-n-slate-12"
              @click="toggleSort('verified')"
            >
              {{ t('JABVOX_AUDIO.ANALYZER.COL_VERIFIED') }}
              <span :class="sortIcon('verified')" class="size-3" />
            </button>
            <span class="text-center">{{
              t('JABVOX_AUDIO.ANALYZER.COL_SCORE')
            }}</span>
            <span class="text-center">{{
              t('JABVOX_AUDIO.ANALYZER.COL_STAGES')
            }}</span>
            <span class="text-center">{{
              t('JABVOX_AUDIO.ANALYZER.COL_LISTEN')
            }}</span>
          </div>

          <!-- Up one level (always shown, not part of pagination) -->
          <button
            v-if="prefix"
            class="flex items-center gap-2 w-full text-left px-3 py-2.5 text-sm text-n-slate-11 hover:bg-n-alpha-1"
            @click="emit('browse', parentPrefix())"
          >
            <span class="i-lucide-corner-left-up size-4" /> ..
          </button>

          <template v-for="entry in pagedEntries">
            <!-- Folder (full-width row) -->
            <button
              v-if="entry.type === 'folder'"
              :key="`d-${entry.value}`"
              class="flex items-center gap-2 w-full text-left px-3 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
              @click="emit('browse', entry.value)"
            >
              <span class="i-lucide-folder size-4 text-n-amber-10" />
              {{ entry.value }}
            </button>
            <!-- Audio file (table row). Verified rows are not selectable when
                 'include verified' is off. -->
            <label
              v-else
              :key="`f-${entry.value.key}`"
              class="grid grid-cols-[auto_1fr_7rem_8rem_8rem_6rem_4rem_4rem_4rem] items-center gap-3 px-3 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
              :class="
                !includeVerified && entry.value.analyzed
                  ? 'opacity-60'
                  : 'cursor-pointer'
              "
            >
              <input
                v-if="includeVerified || !entry.value.analyzed"
                type="checkbox"
                class="accent-n-brand size-4"
                :checked="selectedKeys.has(entry.value.key)"
                @change="emit('toggle-key', entry.value.key)"
              />
              <span v-else class="w-4" />
              <span class="flex items-center gap-2 min-w-0">
                <span
                  :class="fileIcon(entry.value)"
                  class="size-4 text-n-brand shrink-0"
                />
                <span class="truncate">{{
                  entry.value.key.split('/').pop()
                }}</span>
              </span>
              <!-- File type -->
              <span class="min-w-0">
                <span
                  class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
                >
                  {{
                    entry.value.kind === 'document'
                      ? t('JABVOX_AUDIO.ANALYZER.KIND_DOCUMENT')
                      : t('JABVOX_AUDIO.ANALYZER.KIND_AUDIO')
                  }}
                </span>
              </span>
              <!-- Typification (editable per row) -->
              <span class="min-w-0" @click.prevent.stop>
                <Select
                  :model-value="entry.value.typification_id || null"
                  :options="assignTypificationOptions"
                  @update:model-value="setRowTypification(entry.value, $event)"
                />
              </span>
              <!-- Agent (editable per row) -->
              <span class="min-w-0" @click.prevent.stop>
                <Select
                  :model-value="entry.value.agent_id || null"
                  :options="agentOptions"
                  @update:model-value="setRowAgent(entry.value, $event)"
                />
              </span>
              <!-- Verified? -->
              <span class="flex justify-center">
                <span
                  v-if="entry.value.analyzed"
                  class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
                >
                  <span class="i-lucide-check size-3" />
                  {{ t('JABVOX_AUDIO.ANALYZER.VERIFIED_YES') }}
                </span>
                <span
                  v-else-if="
                    entry.value.status === 'processing' ||
                    entry.value.status === 'pending'
                  "
                  class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11"
                >
                  {{ t('JABVOX_AUDIO.ANALYZER.VERIFIED_RUNNING') }}
                </span>
                <span
                  v-else-if="entry.value.status === 'error'"
                  class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-n-ruby-3 text-n-ruby-11"
                >
                  {{ t('JABVOX_AUDIO.ANALYZER.VERIFIED_ERROR') }}
                </span>
                <span v-else class="text-xs text-n-slate-10">
                  {{ t('JABVOX_AUDIO.ANALYZER.VERIFIED_NO') }}
                </span>
              </span>
              <!-- Score -->
              <span
                class="text-center text-xs font-medium tabular-nums"
                :class="
                  entry.value.score == null
                    ? 'text-n-slate-10'
                    : entry.value.passed
                      ? 'text-n-teal-11'
                      : 'text-n-ruby-11'
                "
              >
                {{ entry.value.score == null ? '—' : `${entry.value.score}%` }}
              </span>
              <!-- Stages that scored it -->
              <span class="text-center text-xs text-n-slate-11 tabular-nums">
                {{ entry.value.stages_count || '—' }}
              </span>
              <!-- Listen (audio only) -->
              <span class="flex justify-center" @click.prevent.stop>
                <button
                  v-if="entry.value.kind !== 'document'"
                  type="button"
                  class="p-1 rounded-full text-n-brand hover:bg-n-brand/10"
                  :title="t('JABVOX_AUDIO.ANALYZER.LISTEN')"
                  @click="emit('play', entry.value.key)"
                >
                  <span class="i-lucide-play size-4" aria-hidden="true" />
                </button>
                <span v-else class="text-xs text-n-slate-10">—</span>
              </span>
            </label>
          </template>

          <p
            v-if="!totalEntries"
            class="px-3 py-8 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_AUDIO.ANALYZER.EMPTY') }}
          </p>
        </div>

        <p
          v-if="browser.truncated"
          class="mt-2 text-xs text-n-amber-11 flex items-center gap-1.5"
        >
          <span class="i-lucide-triangle-alert size-3.5" />
          {{ t('JABVOX_AUDIO.ANALYZER.TRUNCATED') }}
        </p>

        <!-- Pagination footer -->
        <BrowserPagination
          v-if="totalEntries"
          v-model:page-size="pageSize"
          class="mt-3"
          :page="page"
          :total-pages="totalPages"
          :range-start="rangeStart"
          :range-end="rangeEnd"
          :total="totalEntries"
          :page-size-options="pageSizeOptions"
          @prev="goPrev"
          @next="goNext"
        />
      </template>
    </SettingsCard>
  </div>
</template>
