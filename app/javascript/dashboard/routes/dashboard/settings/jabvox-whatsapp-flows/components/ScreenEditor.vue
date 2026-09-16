<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { getComponentMeta } from '../componentCatalog';
import ComponentPropsEditor from './ComponentPropsEditor.vue';

const props = defineProps({
  screen: { type: Object, required: true },
  screens: { type: Array, default: () => [] },
  isFirstScreen: { type: Boolean, default: false },
  readonly: { type: Boolean, default: false },
  componentErrors: { type: Array, default: () => [] }, // [{ component_id, field, message }]
});

const emit = defineEmits([
  'updateScreen',
  'removeComponent',
  'updateComponent',
  'reorderComponents',
]);

const { t } = useI18n();

const selectedComponentId = ref(props.screen.components[0]?.id || '');

watch(
  () => props.screen.id,
  () => {
    selectedComponentId.value = props.screen.components[0]?.id || '';
  }
);

const selectedComponent = computed(() =>
  props.screen.components.find(c => c.id === selectedComponentId.value)
);

const otherScreens = computed(() =>
  props.screens.filter(s => s.id !== props.screen.id)
);

const componentsModel = computed({
  get: () => props.screen.components,
  set: value => emit('reorderComponents', value),
});

const errorsFor = componentId =>
  props.componentErrors.filter(e => e.component_id === componentId);

const hasError = componentId => errorsFor(componentId).length > 0;

const removeComponent = id => {
  emit('removeComponent', id);
  if (selectedComponentId.value === id) {
    selectedComponentId.value = '';
  }
};

const onUpdateProps = patch => {
  emit('updateComponent', {
    componentId: selectedComponentId.value,
    props: patch,
  });
};
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <div class="border-b border-n-weak p-3 shrink-0 flex flex-col gap-2">
      <div class="flex items-center gap-2">
        <input
          class="reset-base wf-field text-sm font-medium flex-1"
          :disabled="readonly"
          :value="screen.title"
          :placeholder="
            t('JABVOX_WA_FLOWS.BUILDER.SCREEN_EDITOR.TITLE_PLACEHOLDER')
          "
          @input="emit('updateScreen', { title: $event.target.value })"
        />
        <label
          class="inline-flex items-center gap-1.5 text-xs text-n-slate-11 shrink-0"
        >
          <input
            type="checkbox"
            class="size-4 accent-n-brand"
            :disabled="readonly"
            :checked="screen.terminal"
            @change="emit('updateScreen', { terminal: $event.target.checked })"
          />
          {{ t('JABVOX_WA_FLOWS.BUILDER.SCREEN_EDITOR.IS_TERMINAL') }}
        </label>
      </div>
      <p class="text-[11px] text-n-slate-9">
        {{ t('JABVOX_WA_FLOWS.BUILDER.SCREEN_EDITOR.ID_LABEL') }}:
        <code>{{ screen.id }}</code>
      </p>
    </div>

    <div class="flex-1 min-h-0 flex overflow-hidden">
      <!-- Lista de componentes de la pantalla -->
      <div class="w-56 shrink-0 border-r border-n-weak overflow-y-auto">
        <div v-if="!screen.components.length" class="p-4 text-center">
          <p class="text-xs text-n-slate-10">
            {{ t('JABVOX_WA_FLOWS.BUILDER.SCREEN_EDITOR.NO_COMPONENTS') }}
          </p>
        </div>
        <Draggable
          v-else
          v-model="componentsModel"
          item-key="id"
          class="flex flex-col gap-1 p-2"
          handle=".wf-cmp-drag-handle"
          :disabled="readonly"
        >
          <template #item="{ element: component }">
            <button
              type="button"
              class="wf-component-item"
              :class="{
                'wf-component-item-active':
                  component.id === selectedComponentId,
              }"
              @click="selectedComponentId = component.id"
            >
              <span
                v-if="!readonly"
                class="wf-cmp-drag-handle i-lucide-grip-vertical size-3 text-n-slate-8 shrink-0 cursor-grab"
                aria-hidden="true"
              />
              <span
                :class="getComponentMeta(component.type)?.icon"
                class="size-3.5 shrink-0"
                aria-hidden="true"
              />
              <span class="truncate flex-1 text-left">
                {{ getComponentMeta(component.type)?.label || component.type }}
              </span>
              <span
                v-if="hasError(component.id)"
                class="i-lucide-alert-triangle size-3 text-n-ruby-11 shrink-0"
                aria-hidden="true"
              />
              <button
                v-if="!readonly"
                type="button"
                class="wf-icon-btn-xs shrink-0 hover:!text-n-ruby-11"
                @click.stop="removeComponent(component.id)"
              >
                <span class="i-lucide-x size-3" aria-hidden="true" />
              </button>
            </button>
          </template>
        </Draggable>
      </div>

      <!-- Editor de props del componente seleccionado -->
      <div class="flex-1 overflow-y-auto">
        <ComponentPropsEditor
          v-if="selectedComponent"
          :component="selectedComponent"
          :screens="screens"
          :current-screen-id="screen.id"
          :is-first-screen="isFirstScreen"
          :other-screens="otherScreens"
          :field-errors="errorsFor(selectedComponent.id)"
          @update="onUpdateProps"
        />
        <div v-else class="p-6 text-center">
          <p class="text-sm text-n-slate-10">
            {{ t('JABVOX_WA_FLOWS.BUILDER.SCREEN_EDITOR.SELECT_COMPONENT') }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
