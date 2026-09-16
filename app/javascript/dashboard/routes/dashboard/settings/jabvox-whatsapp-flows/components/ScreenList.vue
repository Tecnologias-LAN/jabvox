<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

const props = defineProps({
  screens: { type: Array, default: () => [] },
  selectedScreenId: { type: String, default: '' },
  readonly: { type: Boolean, default: false },
  errorScreenIds: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'select',
  'add',
  'remove',
  'duplicate',
  'reorder',
  'move-up',
  'move-down',
]);

const { t } = useI18n();

// v-model interno para vuedraggable; reordenar emite 'reorder' con la nueva
// lista completa para que el padre (WhatsappFlowBuilder.vue) reindexe order.
const orderedScreens = computed({
  get: () => [...props.screens].sort((a, b) => a.order - b.order),
  set: value => emit('reorder', value),
});

const hasError = screenId => props.errorScreenIds.includes(screenId);
</script>

<template>
  <div class="flex flex-col h-full">
    <div
      class="flex items-center justify-between px-3 py-2.5 border-b border-n-weak shrink-0"
    >
      <h3 class="text-xs font-semibold uppercase tracking-wide text-n-slate-10">
        {{ t('JABVOX_WA_FLOWS.BUILDER.SCREENS.TITLE') }}
      </h3>
      <button
        v-if="!readonly"
        class="wf-icon-btn"
        :title="t('JABVOX_WA_FLOWS.BUILDER.SCREENS.ADD')"
        @click="emit('add')"
      >
        <span class="i-lucide-plus size-3.5" aria-hidden="true" />
      </button>
    </div>

    <div v-if="!screens.length" class="px-3 py-6 text-center">
      <p class="text-xs text-n-slate-10">
        {{ t('JABVOX_WA_FLOWS.BUILDER.SCREENS.EMPTY') }}
      </p>
    </div>

    <Draggable
      v-else
      v-model="orderedScreens"
      item-key="id"
      class="flex-1 overflow-y-auto p-2 flex flex-col gap-1.5"
      handle=".wf-screen-drag-handle"
      :disabled="readonly"
    >
      <template #item="{ element: screen, index }">
        <div
          class="wf-screen-item group"
          :class="{ 'wf-screen-item-active': screen.id === selectedScreenId }"
          @click="emit('select', screen.id)"
        >
          <span
            v-if="!readonly"
            class="wf-screen-drag-handle i-lucide-grip-vertical size-3.5 text-n-slate-8 shrink-0 cursor-grab"
            aria-hidden="true"
          />
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-1.5">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{
                  screen.title || t('JABVOX_WA_FLOWS.BUILDER.SCREENS.UNTITLED')
                }}
              </p>
              <span
                v-if="index === 0"
                class="text-[10px] px-1.5 py-0.5 rounded-full bg-n-brand/10 text-n-brand shrink-0"
              >
                {{ t('JABVOX_WA_FLOWS.BUILDER.SCREENS.START_BADGE') }}
              </span>
              <span
                v-if="screen.terminal"
                class="text-[10px] px-1.5 py-0.5 rounded-full bg-n-teal-11/10 text-n-teal-11 shrink-0"
              >
                {{ t('JABVOX_WA_FLOWS.BUILDER.SCREENS.TERMINAL_BADGE') }}
              </span>
              <span
                v-if="hasError(screen.id)"
                class="i-lucide-alert-triangle size-3.5 text-n-ruby-11 shrink-0"
                :title="t('JABVOX_WA_FLOWS.BUILDER.SCREENS.HAS_ERRORS')"
                aria-hidden="true"
              />
            </div>
            <p class="text-[11px] text-n-slate-10 mt-0.5">
              {{
                t('JABVOX_WA_FLOWS.BUILDER.SCREENS.COMPONENT_COUNT', {
                  count: screen.components.length,
                })
              }}
            </p>
          </div>

          <div
            v-if="!readonly"
            class="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
          >
            <button
              class="wf-icon-btn-xs"
              :disabled="index === 0"
              :title="t('JABVOX_WA_FLOWS.BUILDER.SCREENS.MOVE_UP')"
              @click.stop="emit('move-up', screen.id)"
            >
              <span class="i-lucide-chevron-up size-3" aria-hidden="true" />
            </button>
            <button
              class="wf-icon-btn-xs"
              :disabled="index === screens.length - 1"
              :title="t('JABVOX_WA_FLOWS.BUILDER.SCREENS.MOVE_DOWN')"
              @click.stop="emit('move-down', screen.id)"
            >
              <span class="i-lucide-chevron-down size-3" aria-hidden="true" />
            </button>
            <button
              class="wf-icon-btn-xs"
              :title="t('JABVOX_WA_FLOWS.BUILDER.SCREENS.DUPLICATE')"
              @click.stop="emit('duplicate', screen.id)"
            >
              <span class="i-lucide-copy size-3" aria-hidden="true" />
            </button>
            <button
              class="wf-icon-btn-xs hover:!text-n-ruby-11"
              :title="t('JABVOX_WA_FLOWS.BUILDER.SCREENS.REMOVE')"
              @click.stop="emit('remove', screen.id)"
            >
              <span class="i-lucide-trash-2 size-3" aria-hidden="true" />
            </button>
          </div>
        </div>
      </template>
    </Draggable>
  </div>
</template>
