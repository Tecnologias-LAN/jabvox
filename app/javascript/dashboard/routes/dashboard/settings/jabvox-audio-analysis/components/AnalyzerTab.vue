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
  'toggle-key',
  'setSelection',
  'clear-selection',
  'launch',
  'assign',
]);

const { t } = useI18n();

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

const progressPct = computed(() => {
  const j = props.activeJob;
  if (!j?.total_count) return 0;
  return Math.round((j.processed_count / j.total_count) * 100);
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

const folders = computed(() => props.browser.folders || []);
const files = computed(() => props.browser.files || []);
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
  <!-- eslint-disable vue/no-bare-strings-in-template -- emoji/symbols are universal -->
  <div class="flex flex-col gap-5">
    <!-- Selection controls -->
    <SettingsCard
      :title="t('JABVOX_AUDIO.ANALYZER.TITLE')"
      :description="t('JABVOX_AUDIO.ANALYZER.SUBTITLE')"
      icon="i-lucide-audio-lines"
    >
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="flex flex-col gap-1.5">
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
        <div class="flex flex-col gap-1.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AUDIO.ANALYZER.PIPELINE') }}
          </span>
          <Select
            :model-value="selectedPipelineId"
            :options="pipelineOptions"
            :placeholder="t('JABVOX_AUDIO.ANALYZER.PIPELINE')"
            @update:model-value="emit('update:selectedPipelineId', $event)"
          />
        </div>
      </div>

      <!-- Bulk selection + launch -->
      <div
        class="flex flex-wrap items-center gap-2 mt-4 pt-4 border-t border-n-weak"
      >
        <template v-if="browser.files.length">
          <span class="text-xs text-n-slate-11">
            {{ t('JABVOX_AUDIO.ANALYZER.SELECT') }}
          </span>
          <!-- Select the selectable files on the current page -->
          <button
            class="px-2.5 py-1 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 disabled:opacity-40"
            :disabled="!pageSelectableKeys.length"
            @click="selectPage"
          >
            {{ t('JABVOX_AUDIO.ANALYZER.SELECT_PAGE') }} ({{
              pageSelectableKeys.length
            }})
          </button>
          <!-- Select everything selectable in the prefix -->
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
          <!-- Include already-verified audios in bulk selection -->
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
        </template>
        <Button
          class="ml-auto"
          :label="`${t('JABVOX_AUDIO.ANALYZER.LAUNCH')} (${selectedKeys.size})`"
          icon="i-lucide-sparkles"
          :disabled="!selectedKeys.size || !selectedPipelineId"
          @click="emit('launch')"
        />
      </div>

      <!-- Quick-assign bar: tag selected audios without analyzing -->
      <div
        v-if="selectedKeys.size"
        class="flex flex-wrap items-end gap-3 mt-3 pt-3 border-t border-n-weak"
      >
        <span class="text-xs text-n-slate-11 self-center">
          {{
            t('JABVOX_AUDIO.ANALYZER.ASSIGN_TO', { count: selectedKeys.size })
          }}
        </span>
        <div class="flex flex-col gap-1 w-44">
          <span class="text-xs text-n-slate-10">{{
            t('JABVOX_AUDIO.ANALYZER.TYPIFICATION')
          }}</span>
          <Select
            v-model="assignTypificationId"
            :options="assignTypificationOptions"
          />
        </div>
        <div class="flex flex-col gap-1 w-44">
          <span class="text-xs text-n-slate-10">{{
            t('JABVOX_AUDIO.ANALYZER.ASSIGN_AGENT')
          }}</span>
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
    </SettingsCard>

    <!-- Active job progress -->
    <SettingsCard v-if="activeJob">
      <div class="flex items-center justify-between text-sm mb-2">
        <span class="flex items-center gap-2 text-n-slate-12 font-medium">
          <Spinner
            v-if="
              activeJob.status !== 'completed' && activeJob.status !== 'failed'
            "
            :size="16"
          />
          {{ t('JABVOX_AUDIO.ANALYZER.PROGRESS') }}
          <span class="text-n-slate-11 font-normal capitalize">
            · {{ activeJob.status }}
          </span>
        </span>
        <span class="text-n-slate-11">
          {{ activeJob.processed_count }} / {{ activeJob.total_count }}
          <span class="text-n-slate-12 font-medium">({{ progressPct }}%)</span>
        </span>
      </div>
      <div class="h-2 rounded-full bg-n-alpha-2 overflow-hidden">
        <div
          class="h-full bg-n-brand transition-all duration-300"
          :style="{ width: `${progressPct}%` }"
        />
      </div>
    </SettingsCard>

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
          <!-- Column header -->
          <div
            v-if="totalEntries"
            class="grid grid-cols-[auto_1fr_8rem_8rem_7rem_5rem_5rem] items-center gap-3 px-3 py-2 bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
          >
            <span class="w-4" />
            <span>{{ t('JABVOX_AUDIO.ANALYZER.COL_NAME') }}</span>
            <span>{{ t('JABVOX_AUDIO.ANALYZER.COL_TYPIFICATION') }}</span>
            <span>{{ t('JABVOX_AUDIO.ANALYZER.COL_AGENT') }}</span>
            <span class="text-center">{{
              t('JABVOX_AUDIO.ANALYZER.COL_VERIFIED')
            }}</span>
            <span class="text-center">{{
              t('JABVOX_AUDIO.ANALYZER.COL_SCORE')
            }}</span>
            <span class="text-center">{{
              t('JABVOX_AUDIO.ANALYZER.COL_STAGES')
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
              class="grid grid-cols-[auto_1fr_8rem_8rem_7rem_5rem_5rem] items-center gap-3 px-3 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
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
                  class="i-lucide-file-audio size-4 text-n-brand shrink-0"
                />
                <span class="truncate">{{
                  entry.value.key.split('/').pop()
                }}</span>
              </span>
              <!-- Typification -->
              <span class="min-w-0">
                <span
                  v-if="entry.value.typification_name"
                  class="inline-flex items-center text-xs px-2 py-0.5 rounded-full bg-n-iris-3 text-n-iris-11 truncate max-w-full"
                >
                  {{ entry.value.typification_name }}
                </span>
                <span v-else class="text-xs text-n-slate-10">—</span>
              </span>
              <!-- Agent -->
              <span class="min-w-0">
                <span
                  v-if="entry.value.agent_name"
                  class="inline-flex items-center text-xs px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11 truncate max-w-full"
                >
                  {{ entry.value.agent_name }}
                </span>
                <span v-else class="text-xs text-n-slate-10">—</span>
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
