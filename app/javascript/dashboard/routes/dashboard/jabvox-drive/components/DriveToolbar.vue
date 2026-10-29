<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { FILE_TYPES } from '../helper';

const props = defineProps({
  // Breadcrumb: array de { label, to? } del nivel actual.
  breadcrumb: {
    type: Array,
    default: () => [],
  },
  query: { type: String, default: '' },
  type: { type: String, default: '' },
  from: { type: String, default: '' },
  to: { type: String, default: '' },
  canManage: { type: Boolean, default: true },
  viewMode: { type: String, default: 'grid' },
});

const emit = defineEmits([
  'update:query',
  'update:type',
  'update:from',
  'update:to',
  'update:viewMode',
  'clearFilters',
  'upload',
  'newFolder',
  'navigate',
]);

const { t } = useI18n();

const showFilters = ref(false);

const hasActiveFilters = computed(() => props.type || props.from || props.to);

const typeOptions = computed(() =>
  FILE_TYPES.map(value => ({
    value,
    label: t(`JABVOX_DRIVE.TYPES.${value.toUpperCase()}`),
  }))
);
</script>

<template>
  <div class="flex flex-col gap-3">
    <!-- Breadcrumb + acciones -->
    <div class="flex flex-wrap items-center justify-between gap-2">
      <nav
        :aria-label="t('JABVOX_DRIVE.TOOLBAR.BREADCRUMB')"
        class="flex items-center gap-1 text-sm min-w-0 flex-wrap"
      >
        <template v-for="(crumb, index) in breadcrumb" :key="index">
          <button
            type="button"
            class="truncate max-w-[12rem] rounded px-1.5 py-0.5 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="
              index === breadcrumb.length - 1
                ? 'font-semibold text-n-slate-12 cursor-default'
                : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1'
            "
            :disabled="index === breadcrumb.length - 1"
            :aria-current="index === breadcrumb.length - 1 ? 'page' : undefined"
            @click="emit('navigate', crumb)"
          >
            {{ crumb.label }}
          </button>
          <span
            v-if="index < breadcrumb.length - 1"
            class="i-lucide-chevron-right size-4 text-n-slate-9 shrink-0"
            aria-hidden="true"
          />
        </template>
      </nav>

      <div class="flex flex-wrap items-center gap-2">
        <div
          class="flex rounded-lg border border-n-weak overflow-hidden shrink-0"
        >
          <button
            type="button"
            class="flex items-center justify-center size-8 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="
              viewMode === 'grid'
                ? 'bg-n-alpha-1 text-n-slate-12'
                : 'text-n-slate-10 hover:text-n-slate-12'
            "
            :title="t('JABVOX_DRIVE.TOOLBAR.VIEW_GRID')"
            :aria-label="t('JABVOX_DRIVE.TOOLBAR.VIEW_GRID')"
            :aria-pressed="viewMode === 'grid'"
            @click="emit('update:viewMode', 'grid')"
          >
            <span class="i-lucide-layout-grid size-4" aria-hidden="true" />
          </button>
          <button
            type="button"
            class="flex items-center justify-center size-8 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="
              viewMode === 'list'
                ? 'bg-n-alpha-1 text-n-slate-12'
                : 'text-n-slate-10 hover:text-n-slate-12'
            "
            :title="t('JABVOX_DRIVE.TOOLBAR.VIEW_LIST')"
            :aria-label="t('JABVOX_DRIVE.TOOLBAR.VIEW_LIST')"
            :aria-pressed="viewMode === 'list'"
            @click="emit('update:viewMode', 'list')"
          >
            <span class="i-lucide-list size-4" aria-hidden="true" />
          </button>
        </div>

        <Button
          variant="outline"
          color="slate"
          size="sm"
          icon="i-lucide-sliders-horizontal"
          :label="t('JABVOX_DRIVE.TOOLBAR.FILTERS')"
          @click="showFilters = !showFilters"
        />
        <Button
          v-if="canManage"
          variant="outline"
          color="slate"
          size="sm"
          icon="i-lucide-folder-plus"
          :label="t('JABVOX_DRIVE.TOOLBAR.NEW_FOLDER')"
          @click="emit('newFolder')"
        />
        <Button
          v-if="canManage"
          color="blue"
          size="sm"
          icon="i-lucide-upload"
          :label="t('JABVOX_DRIVE.TOOLBAR.UPLOAD')"
          @click="emit('upload')"
        />
      </div>
    </div>

    <!-- Búsqueda -->
    <div class="relative">
      <input
        :value="query"
        type="text"
        :aria-label="t('JABVOX_DRIVE.TOOLBAR.SEARCH_PLACEHOLDER')"
        class="w-full h-9 rounded-lg border border-n-weak bg-n-solid-1 py-2 pl-3 pr-9 text-sm text-n-slate-12 placeholder:text-n-slate-10 outline-none transition-colors focus:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/40"
        :placeholder="t('JABVOX_DRIVE.TOOLBAR.SEARCH_PLACEHOLDER')"
        @input="emit('update:query', $event.target.value)"
      />
      <button
        v-if="query"
        type="button"
        class="absolute right-2 top-1/2 flex -translate-y-1/2 items-center justify-center size-6 rounded-md text-n-slate-10 transition-colors hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :title="t('JABVOX_DRIVE.TOOLBAR.CLEAR_SEARCH')"
        :aria-label="t('JABVOX_DRIVE.TOOLBAR.CLEAR_SEARCH')"
        @click="emit('update:query', '')"
      >
        <span class="i-lucide-x size-4" aria-hidden="true" />
      </button>
    </div>

    <!-- Filtros expandibles -->
    <div
      v-if="showFilters"
      class="flex flex-wrap items-end gap-3 rounded-lg border border-n-weak bg-n-solid-1 p-3"
    >
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('JABVOX_DRIVE.TOOLBAR.TYPE') }}
        <select
          :value="type"
          class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12 outline-none transition-colors focus:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/40"
          @change="emit('update:type', $event.target.value)"
        >
          <option value="">{{ t('JABVOX_DRIVE.TOOLBAR.ALL_TYPES') }}</option>
          <option
            v-for="opt in typeOptions"
            :key="opt.value"
            :value="opt.value"
          >
            {{ opt.label }}
          </option>
        </select>
      </label>

      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('JABVOX_DRIVE.TOOLBAR.FROM') }}
        <input
          :value="from"
          type="date"
          class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12 outline-none transition-colors focus:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/40"
          @change="emit('update:from', $event.target.value)"
        />
      </label>

      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('JABVOX_DRIVE.TOOLBAR.TO') }}
        <input
          :value="to"
          type="date"
          class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12 outline-none transition-colors focus:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/40"
          @change="emit('update:to', $event.target.value)"
        />
      </label>

      <Button
        v-if="hasActiveFilters"
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-x"
        :label="t('JABVOX_DRIVE.TOOLBAR.CLEAR_FILTERS')"
        @click="emit('clearFilters')"
      />
    </div>
  </div>
</template>
