<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAnalyticsWidgetsStore } from 'dashboard/stores/jabvox/analytics/widgets';
import WidgetRenderer from './WidgetRenderer.vue';

const props = defineProps({
  widget: {
    type: Object,
    required: true,
  },
  editMode: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['duplicate', 'remove', 'refresh', 'configure']);

const { t } = useI18n();
const widgetsStore = useAnalyticsWidgetsStore();

const menuOpen = ref(false);

const loading = computed(() =>
  Boolean(widgetsStore.uiFlags.loadingWidget[props.widget.id])
);
const hasData = computed(() => Boolean(widgetsStore.dataFor(props.widget.id)));

const onConfigure = () => {
  menuOpen.value = false;
  emit('configure');
};
const onRefresh = () => {
  menuOpen.value = false;
  emit('refresh');
};
const onDuplicate = () => {
  menuOpen.value = false;
  emit('duplicate');
};
const onRemove = () => {
  menuOpen.value = false;
  emit('remove');
};

const menuItemClass =
  'flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2';
</script>

<template>
  <div
    class="flex size-full flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
  >
    <!-- Title bar -->
    <div
      class="flex shrink-0 items-center justify-between gap-2 border-b border-n-weak px-3 py-2"
    >
      <span
        class="truncate text-sm font-medium text-n-slate-12"
        :class="{ 'drag-handle cursor-move': editMode }"
      >
        {{ widget.titleJabvox }}
      </span>
      <div v-if="editMode" class="relative shrink-0">
        <button
          type="button"
          class="rounded-lg p-1 text-n-slate-11 hover:bg-n-alpha-2"
          @click="menuOpen = !menuOpen"
        >
          <span class="i-lucide-more-vertical size-4" />
        </button>
        <div
          v-if="menuOpen"
          class="absolute right-0 z-20 mt-1 w-44 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 py-1 shadow-lg"
        >
          <button type="button" :class="menuItemClass" @click="onConfigure">
            <span class="i-lucide-settings-2 size-4" />
            {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIGURE') }}
          </button>
          <button type="button" :class="menuItemClass" @click="onRefresh">
            <span class="i-lucide-refresh-cw size-4" />
            {{ t('JABVOX_ANALYTICS.WIDGETS.REFRESH') }}
          </button>
          <button type="button" :class="menuItemClass" @click="onDuplicate">
            <span class="i-lucide-copy size-4" />
            {{ t('JABVOX_ANALYTICS.WIDGETS.DUPLICATE') }}
          </button>
          <button
            type="button"
            class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-ruby-11 hover:bg-n-alpha-2"
            @click="onRemove"
          >
            <span class="i-lucide-trash-2 size-4" />
            {{ t('JABVOX_ANALYTICS.WIDGETS.REMOVE') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Body -->
    <div class="relative min-h-0 flex-1 overflow-auto p-2">
      <div
        v-if="loading"
        class="flex size-full items-center justify-center text-n-slate-11"
      >
        <span class="i-lucide-loader-circle size-5 animate-spin" />
      </div>
      <div
        v-else-if="!hasData"
        class="flex size-full items-center justify-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_ANALYTICS.WIDGETS.NO_DATA') }}
      </div>
      <WidgetRenderer v-else :widget="widget" />
    </div>
  </div>
</template>
