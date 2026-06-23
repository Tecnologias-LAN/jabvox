<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  // Whether to show the sort control (manual position only makes sense
  // when the list supports ordering — all tabs do).
  showSort: { type: Boolean, default: true },
});

const emit = defineEmits(['reset']);
const search = defineModel('search', { type: String, default: '' });
const status = defineModel('status', { type: String, default: 'all' });
const sort = defineModel('sort', { type: String, default: 'position' });
const view = defineModel('view', { type: String, default: 'cards' });

const { t } = useI18n();

const statusOptions = computed(() => [
  { value: 'all', label: t('JABVOX_MANAGEMENT_STATES.FILTERS.STATUS_ALL') },
  {
    value: 'active',
    label: t('JABVOX_MANAGEMENT_STATES.FILTERS.STATUS_ACTIVE'),
  },
  {
    value: 'inactive',
    label: t('JABVOX_MANAGEMENT_STATES.FILTERS.STATUS_INACTIVE'),
  },
]);

const sortOptions = computed(() => [
  {
    value: 'position',
    label: t('JABVOX_MANAGEMENT_STATES.FILTERS.SORT_POSITION'),
  },
  { value: 'name', label: t('JABVOX_MANAGEMENT_STATES.FILTERS.SORT_NAME') },
]);

const isDirty = computed(
  () =>
    search.value.trim() !== '' ||
    status.value !== 'all' ||
    sort.value !== 'position'
);
</script>

<template>
  <div
    class="sticky top-0 z-10 -mx-1 px-1 py-2 bg-n-background flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between"
  >
    <div class="flex flex-col sm:flex-row sm:flex-wrap gap-2">
      <div class="relative w-full sm:w-56">
        <Input
          v-model="search"
          :placeholder="
            t('JABVOX_MANAGEMENT_STATES.FILTERS.SEARCH_PLACEHOLDER')
          "
          custom-input-class="!pl-9"
        >
          <template #prefix>
            <span
              class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
            />
          </template>
        </Input>
      </div>
      <div class="w-full sm:w-40">
        <Select v-model="status" :options="statusOptions" />
      </div>
      <div v-if="showSort" class="w-full sm:w-44">
        <Select v-model="sort" :options="sortOptions" />
      </div>
      <Button
        v-if="isDirty"
        :label="t('JABVOX_MANAGEMENT_STATES.FILTERS.RESET')"
        icon="i-lucide-x"
        variant="ghost"
        color="slate"
        size="sm"
        @click="emit('reset')"
      />
    </div>

    <!-- View toggle -->
    <div
      class="flex items-center gap-1 p-1 rounded-lg bg-n-alpha-1 border border-n-weak shrink-0 self-start lg:self-auto"
    >
      <button
        class="flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium rounded-md transition-colors"
        :class="
          view === 'cards'
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="view = 'cards'"
      >
        <span class="i-lucide-layout-grid size-3.5" />
        {{ t('JABVOX_MANAGEMENT_STATES.FILTERS.VIEW_CARDS') }}
      </button>
      <button
        class="flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium rounded-md transition-colors"
        :class="
          view === 'table'
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="view = 'table'"
      >
        <span class="i-lucide-table-2 size-3.5" />
        {{ t('JABVOX_MANAGEMENT_STATES.FILTERS.VIEW_TABLE') }}
      </button>
    </div>
  </div>
</template>
