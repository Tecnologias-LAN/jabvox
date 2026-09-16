<script setup>
/**
 * Constructor de formulario (WhatsApp Flow) embebido en el wizard de plantillas.
 *
 * Reutiliza las mismas piezas del builder completo del módulo de Flows
 * (lista de pantallas, paleta, editor de props, previa) para no mantener dos
 * editores distintos; aquí solo se presentan en un layout compacto que cabe
 * dentro del formulario de la plantilla.
 *
 * Meta obliga a que el Flow sea un objeto aparte y publicado antes de que la
 * plantilla lo referencie: de esa secuencia se encarga el backend
 * (Jabvox::WhatsappTemplates::FlowTemplateCreator), no esta vista.
 */
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  addScreen,
  removeScreen,
  duplicateScreen,
  moveScreenUp,
  moveScreenDown,
  reindexScreens,
  addComponentToScreen,
  removeComponentFromScreen,
  updateComponentProps,
  createComponentId,
} from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/screenHelpers';
import {
  createComponentInstance,
  isAtLimit,
  MAX_COMPONENTS_PER_SCREEN,
} from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/componentCatalog';
import ScreenList from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/components/ScreenList.vue';
import ScreenEditor from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/components/ScreenEditor.vue';
import ComponentPalette from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/components/ComponentPalette.vue';
import FlowPreview from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/components/FlowPreview.vue';

const props = defineProps({
  // screens_json del formulario en construcción
  modelValue: { type: Array, default: () => [] },
  flowName: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const screens = computed(() => props.modelValue || []);
const selectedScreenId = ref('');

const setScreens = next => emit('update:modelValue', next);

// Arranca con una pantalla para que el usuario no vea un lienzo vacío sin saber
// por dónde empezar.
watch(
  screens,
  value => {
    if (!value.length) {
      setScreens(
        addScreen([], t('JABVOX_WA_TEMPLATES.CREATE.FLOW.FIRST_SCREEN'))
      );
      return;
    }
    if (!value.some(s => s.id === selectedScreenId.value)) {
      selectedScreenId.value = value[0].id;
    }
  },
  { immediate: true }
);

const orderedScreens = computed(() =>
  [...screens.value].sort((a, b) => a.order - b.order)
);

const selectedScreen = computed(() =>
  screens.value.find(s => s.id === selectedScreenId.value)
);

const isFirstScreen = computed(
  () => orderedScreens.value[0]?.id === selectedScreenId.value
);

const onAddScreen = () => {
  const next = addScreen(
    screens.value,
    t('JABVOX_WA_TEMPLATES.CREATE.FLOW.NEW_SCREEN')
  );
  setScreens(next);
  selectedScreenId.value = next[next.length - 1].id;
};

const onRemoveScreen = screenId => {
  const wasSelected = selectedScreenId.value === screenId;
  const next = removeScreen(screens.value, screenId);
  setScreens(next);
  if (wasSelected) selectedScreenId.value = next[0]?.id || '';
};

const onDuplicateScreen = screenId =>
  setScreens(duplicateScreen(screens.value, screenId));
const onMoveScreenUp = screenId =>
  setScreens(moveScreenUp(screens.value, screenId));
const onMoveScreenDown = screenId =>
  setScreens(moveScreenDown(screens.value, screenId));
const onReorderScreens = newOrder => setScreens(reindexScreens(newOrder));

const onUpdateScreen = patch =>
  setScreens(
    screens.value.map(s =>
      s.id === selectedScreenId.value ? { ...s, ...patch } : s
    )
  );

const onAddComponent = type => {
  const screen = selectedScreen.value;
  if (!screen) return;
  if (isAtLimit(screen.components, type)) return;
  if (screen.components.length >= MAX_COMPONENTS_PER_SCREEN) return;
  const component = createComponentInstance(type, createComponentId());
  setScreens(
    addComponentToScreen(screens.value, selectedScreenId.value, component)
  );
};

const onRemoveComponent = componentId =>
  setScreens(
    removeComponentFromScreen(
      screens.value,
      selectedScreenId.value,
      componentId
    )
  );

const onUpdateComponent = ({ componentId, props: componentProps }) =>
  setScreens(
    updateComponentProps(
      screens.value,
      selectedScreenId.value,
      componentId,
      componentProps
    )
  );

const onReorderComponents = newComponents =>
  setScreens(
    screens.value.map(s =>
      s.id === selectedScreenId.value ? { ...s, components: newComponents } : s
    )
  );

// Avisos de lo que Meta exige, resueltos en vivo mientras se construye.
const issues = computed(() => {
  const list = [];
  if (!screens.value.length) return list;
  const hasTerminal = screens.value.some(s => s.terminal);
  if (!hasTerminal)
    list.push(t('JABVOX_WA_TEMPLATES.CREATE.FLOW.NEEDS_TERMINAL'));
  const withoutFooter = orderedScreens.value.filter(
    s => !(s.components || []).some(c => c.type === 'Footer')
  );
  if (withoutFooter.length) {
    list.push(
      t('JABVOX_WA_TEMPLATES.CREATE.FLOW.NEEDS_FOOTER', {
        screens: withoutFooter.map(s => s.title).join(', '),
      })
    );
  }
  return list;
});

defineExpose({ issues });
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-if="issues.length"
      class="rounded-lg border border-n-amber-8 bg-n-amber-2 p-2.5 flex flex-col gap-1"
    >
      <p
        v-for="issue in issues"
        :key="issue"
        class="text-[11px] text-n-amber-11 flex items-start gap-1.5"
      >
        <span
          class="i-lucide-alert-triangle size-3 shrink-0 mt-px"
          aria-hidden="true"
        />
        {{ issue }}
      </p>
    </div>

    <div
      class="grid grid-cols-1 lg:grid-cols-[170px_1fr_200px] gap-2 rounded-xl border border-n-weak overflow-hidden min-h-[380px]"
    >
      <div class="border-r border-n-weak overflow-y-auto max-h-[460px]">
        <ScreenList
          :screens="orderedScreens"
          :selected-screen-id="selectedScreenId"
          @select="id => (selectedScreenId = id)"
          @add="onAddScreen"
          @remove="onRemoveScreen"
          @duplicate="onDuplicateScreen"
          @move-up="onMoveScreenUp"
          @move-down="onMoveScreenDown"
          @reorder="onReorderScreens"
        />
      </div>

      <div class="flex flex-col min-w-0 overflow-hidden">
        <div class="flex-1 overflow-y-auto max-h-[400px]">
          <ScreenEditor
            v-if="selectedScreen"
            :screen="selectedScreen"
            :screens="orderedScreens"
            :is-first-screen="isFirstScreen"
            @update-screen="onUpdateScreen"
            @remove-component="onRemoveComponent"
            @update-component="onUpdateComponent"
            @reorder-components="onReorderComponents"
          />
        </div>
        <div class="border-t border-n-weak shrink-0">
          <ComponentPalette
            :disabled="!selectedScreen"
            :screen-components="selectedScreen?.components || []"
            @add="onAddComponent"
          />
        </div>
      </div>

      <div class="border-l border-n-weak overflow-y-auto max-h-[460px]">
        <FlowPreview :screens="orderedScreens" :flow-name="flowName" />
      </div>
    </div>
  </div>
</template>
