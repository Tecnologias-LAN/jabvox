<script setup>
import { ref, computed, watch } from 'vue';
import { GridLayout, GridItem } from 'grid-layout-plus';
import { useDebounceFn } from '@vueuse/core';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';
import WidgetContainer from './WidgetContainer.vue';

const props = defineProps({
  dashboardId: {
    type: [Number, String],
    required: true,
  },
  widgets: {
    type: Array,
    default: () => [],
  },
  layout: {
    type: Array,
    default: () => [],
  },
  editMode: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['duplicate', 'remove', 'refresh', 'configure']);

const store = useAnalyticsDashboardsStore();
const { showError } = useAnalyticsError();

const COLS = 12;
const DEFAULT_W = 4;
const DEFAULT_H = 6;

// Build the layout consumed by grid-layout-plus. Every widget needs a layout
// entry keyed by its id (as string `i`); auto-place anything missing one.
const buildLayout = () => {
  const existing = new Map(
    (props.layout || []).map(item => [String(item.i), item])
  );
  let cursorX = 0;
  let cursorY = 0;
  return props.widgets.map(widget => {
    const key = String(widget.id);
    if (existing.has(key)) {
      return { ...existing.get(key), i: key };
    }
    const placed = {
      i: key,
      x: cursorX,
      y: cursorY,
      w: DEFAULT_W,
      h: DEFAULT_H,
    };
    cursorX += DEFAULT_W;
    if (cursorX >= COLS) {
      cursorX = 0;
      cursorY += DEFAULT_H;
    }
    return placed;
  });
};

const internalLayout = ref(buildLayout());

watch(
  () => [props.widgets, props.layout],
  () => {
    internalLayout.value = buildLayout();
  },
  { deep: true }
);

const widgetById = computed(() => {
  const map = {};
  props.widgets.forEach(widget => {
    map[String(widget.id)] = widget;
  });
  return map;
});

// Persist layout changes, debounced; optimistic — surface errors only.
const persistLayout = useDebounceFn(async () => {
  try {
    await store.saveLayout(props.dashboardId, internalLayout.value);
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.DASHBOARDS.SAVE_ERROR');
  }
}, 800);

const onLayoutUpdated = () => {
  if (props.editMode) persistLayout();
};
</script>

<template>
  <GridLayout
    v-model:layout="internalLayout"
    :col-num="COLS"
    :row-height="32"
    :is-draggable="editMode"
    :is-resizable="editMode"
    :margin="[12, 12]"
    use-css-transforms
    @layout-updated="onLayoutUpdated"
  >
    <GridItem
      v-for="item in internalLayout"
      :key="item.i"
      :x="item.x"
      :y="item.y"
      :w="item.w"
      :h="item.h"
      :i="item.i"
      drag-allow-from=".drag-handle"
    >
      <WidgetContainer
        v-if="widgetById[item.i]"
        :widget="widgetById[item.i]"
        :dashboard-id="dashboardId"
        :edit-mode="editMode"
        @duplicate="emit('duplicate', widgetById[item.i])"
        @remove="emit('remove', widgetById[item.i])"
        @refresh="emit('refresh', widgetById[item.i])"
        @configure="emit('configure', widgetById[item.i])"
      />
    </GridItem>
  </GridLayout>
</template>
