<script setup>
/**
 * Constructor de formulario (WhatsApp Flow) embebido en el asistente de
 * plantillas, en tres paneles: pantallas · widgets de la pantalla ·
 * configuración del widget seleccionado.
 *
 * La lógica de manipulación de pantallas se comparte con el builder completo
 * del módulo de Flows (screenHelpers/componentCatalog); lo propio de aquí es la
 * disposición y el alta de widgets intercalada (el "+" entre uno y otro).
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
  removeComponentFromScreen,
  updateComponentProps,
  createComponentId,
} from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/screenHelpers';
import {
  createComponentInstance,
  getComponentMeta,
  isAtLimit,
  COMPONENT_CATALOG,
  COMPONENT_CATEGORIES,
  MAX_COMPONENTS_PER_SCREEN,
} from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/componentCatalog';
import ComponentPropsEditor from 'dashboard/routes/dashboard/settings/jabvox-whatsapp-flows/components/ComponentPropsEditor.vue';

const props = defineProps({
  // screens_json del formulario en construcción
  modelValue: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const screens = computed(() => props.modelValue || []);
const selectedScreenId = ref('');
const selectedComponentId = ref('');
// Posición donde insertar al elegir un widget de la lista desplegable.
const pickerIndex = ref(null);

const setScreens = next => emit('update:modelValue', next);

const footerLabels = () => ({
  next: t('JABVOX_WA_TEMPLATES.CREATE.FLOW.NEXT_BUTTON'),
  submit: t('JABVOX_WA_TEMPLATES.CREATE.FLOW.SUBMIT_BUTTON'),
});

/**
 * Reencadena la navegación tras agregar, quitar o reordenar pantallas: cada una
 * avanza a la siguiente y solo la última cierra el formulario. Sin esto, al
 * añadir una segunda pantalla la primera seguiría siendo la final y la nueva
 * quedaría inalcanzable.
 *
 * Respeta el texto que el usuario haya escrito en su botón; solo ajusta a dónde
 * lleva y cuál termina.
 */
const relinkScreens = list => {
  const ordered = [...list].sort((a, b) => a.order - b.order);
  const labels = footerLabels();
  return ordered.map((screen, index) => {
    const isLast = index === ordered.length - 1;
    const nextId = isLast ? '' : ordered[index + 1].id;
    const components = (screen.components || []).map(component => {
      if (component.type !== 'Footer') return component;
      const label = component.props?.label;
      const wasDefault = label === labels.next || label === labels.submit;
      const defaultLabel = isLast ? labels.submit : labels.next;
      return {
        ...component,
        props: {
          ...component.props,
          label: wasDefault ? defaultLabel : label,
          action: isLast
            ? { name: 'complete' }
            : { name: 'navigate', next: nextId },
        },
      };
    });
    return { ...screen, terminal: isLast, components };
  });
};

// Arranca con una pantalla para que el usuario no vea un lienzo vacío sin saber
// por dónde empezar.
watch(
  screens,
  value => {
    if (!value.length) {
      setScreens(
        addScreen(
          [],
          t('JABVOX_WA_TEMPLATES.CREATE.FLOW.FIRST_SCREEN'),
          footerLabels()
        )
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

const screenComponents = computed(() => selectedScreen.value?.components || []);

const selectedComponent = computed(() =>
  screenComponents.value.find(c => c.id === selectedComponentId.value)
);

// Al cambiar de pantalla se selecciona su primer widget, para que el panel de
// configuración nunca quede en blanco sin motivo.
watch(selectedScreenId, () => {
  selectedComponentId.value = screenComponents.value[0]?.id || '';
  pickerIndex.value = null;
});

const componentLabel = type => getComponentMeta(type)?.label || type;
const componentIcon = type => getComponentMeta(type)?.icon || 'i-lucide-square';

// Widgets agrupados por categoría para la lista de "agregar".
const widgetGroups = computed(() =>
  COMPONENT_CATEGORIES.map(category => ({
    ...category,
    types: Object.keys(COMPONENT_CATALOG).filter(
      type => COMPONENT_CATALOG[type].category === category.key
    ),
  })).filter(group => group.types.length)
);

const canAddWidget = type =>
  selectedScreen.value &&
  !isAtLimit(screenComponents.value, type) &&
  screenComponents.value.length < MAX_COMPONENTS_PER_SCREEN;

// ─── Pantallas ─────────────────────────────────────────────────────────────

const onAddScreen = () => {
  const next = relinkScreens(
    addScreen(
      screens.value,
      t('JABVOX_WA_TEMPLATES.CREATE.FLOW.NEW_SCREEN'),
      footerLabels()
    )
  );
  setScreens(next);
  selectedScreenId.value = next[next.length - 1].id;
};

const onRemoveScreen = screenId => {
  const wasSelected = selectedScreenId.value === screenId;
  const next = relinkScreens(removeScreen(screens.value, screenId));
  setScreens(next);
  if (wasSelected) selectedScreenId.value = next[0]?.id || '';
};

const onDuplicateScreen = screenId =>
  setScreens(relinkScreens(duplicateScreen(screens.value, screenId)));
const onMoveScreenUp = screenId =>
  setScreens(relinkScreens(moveScreenUp(screens.value, screenId)));
const onMoveScreenDown = screenId =>
  setScreens(relinkScreens(moveScreenDown(screens.value, screenId)));

const renameScreen = title =>
  setScreens(
    screens.value.map(s =>
      s.id === selectedScreenId.value ? { ...s, title } : s
    )
  );

// ─── Widgets ───────────────────────────────────────────────────────────────

// `index` es la posición donde insertar: el "+" entre dos widgets agrega ahí
// mismo, sin obligar a crear al final y arrastrar.
const addWidget = (type, index) => {
  if (!canAddWidget(type)) return;
  const component = createComponentInstance(type, createComponentId());
  const list = [...screenComponents.value];
  list.splice(index ?? list.length, 0, component);
  setScreens(
    screens.value.map(s =>
      s.id === selectedScreenId.value ? { ...s, components: list } : s
    )
  );
  selectedComponentId.value = component.id;
  pickerIndex.value = null;
};

const removeWidget = componentId => {
  setScreens(
    removeComponentFromScreen(
      screens.value,
      selectedScreenId.value,
      componentId
    )
  );
  if (selectedComponentId.value === componentId) {
    selectedComponentId.value = '';
  }
};

const moveWidget = (from, to) => {
  if (to < 0 || to >= screenComponents.value.length) return;
  const list = [...screenComponents.value];
  const [moved] = list.splice(from, 1);
  list.splice(to, 0, moved);
  setScreens(
    screens.value.map(s =>
      s.id === selectedScreenId.value ? { ...s, components: list } : s
    )
  );
};

const onUpdateComponent = patch =>
  setScreens(
    updateComponentProps(
      screens.value,
      selectedScreenId.value,
      selectedComponentId.value,
      patch
    )
  );

const togglePicker = index => {
  pickerIndex.value = pickerIndex.value === index ? null : index;
};

// Avisos de lo que Meta exige, resueltos en vivo mientras se construye.
const issues = computed(() => {
  const list = [];
  if (!screens.value.length) return list;
  if (!screens.value.some(s => s.terminal)) {
    list.push(t('JABVOX_WA_TEMPLATES.CREATE.FLOW.NEEDS_TERMINAL'));
  }
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

    <!-- Tres paneles: pantallas · widgets · configuración del widget -->
    <div
      class="grid grid-cols-1 lg:grid-cols-[220px_minmax(0,1fr)_280px] rounded-xl border border-n-weak overflow-hidden min-h-[460px]"
    >
      <!-- Panel 1: pantallas -->
      <div
        class="lg:border-r border-b lg:border-b-0 border-n-weak bg-n-alpha-1 flex flex-col"
      >
        <div
          class="fb-panel-head px-3 py-2.5 flex items-center justify-between shrink-0"
        >
          <p class="fb-panel-title">
            {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.PANEL_SCREENS') }}
          </p>
          <button
            type="button"
            class="text-[11px] text-n-brand hover:underline"
            @click="onAddScreen"
          >
            {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.ADD_SCREEN') }}
          </button>
        </div>
        <div
          class="flex-1 overflow-y-auto max-h-[520px] p-2 flex flex-col gap-1"
        >
          <div
            v-for="(screen, index) in orderedScreens"
            :key="screen.id"
            class="fb-item px-2.5 py-2 cursor-pointer"
            :class="{ 'fb-item-active': screen.id === selectedScreenId }"
            @click="selectedScreenId = screen.id"
          >
            <div class="flex items-center justify-between gap-1">
              <span
                class="text-xs font-medium truncate"
                :class="
                  screen.id === selectedScreenId
                    ? 'text-n-brand'
                    : 'text-n-slate-12'
                "
              >
                {{ index + 1 }}. {{ screen.title }}
              </span>
              <span v-if="screen.terminal" class="fb-badge shrink-0">
                {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.FINAL_BADGE') }}
              </span>
            </div>
            <div class="flex items-center gap-0.5 mt-1">
              <span class="text-[10px] text-n-slate-10 flex-1">
                {{
                  t('JABVOX_WA_TEMPLATES.CREATE.FLOW.WIDGET_COUNT', {
                    count: (screen.components || []).length,
                  })
                }}
              </span>
              <button
                type="button"
                class="fb-mini-btn fb-actions"
                :disabled="index === 0"
                @click.stop="onMoveScreenUp(screen.id)"
              >
                <span class="i-lucide-chevron-up size-3" aria-hidden="true" />
              </button>
              <button
                type="button"
                class="fb-mini-btn fb-actions"
                :disabled="index === orderedScreens.length - 1"
                @click.stop="onMoveScreenDown(screen.id)"
              >
                <span class="i-lucide-chevron-down size-3" aria-hidden="true" />
              </button>
              <button
                type="button"
                class="fb-mini-btn fb-actions"
                @click.stop="onDuplicateScreen(screen.id)"
              >
                <span class="i-lucide-copy size-3" aria-hidden="true" />
              </button>
              <button
                v-if="orderedScreens.length > 1"
                type="button"
                class="fb-mini-btn fb-mini-btn-danger fb-actions"
                @click.stop="onRemoveScreen(screen.id)"
              >
                <span class="i-lucide-trash-2 size-3" aria-hidden="true" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Panel 2: widgets de la pantalla, con "+" entre cada uno -->
      <div class="flex flex-col min-w-0 border-b lg:border-b-0">
        <div class="fb-panel-head px-3 py-2.5 shrink-0">
          <p class="fb-panel-title mb-1.5">
            {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.PANEL_WIDGETS') }}
          </p>
          <input
            v-if="selectedScreen"
            :value="selectedScreen.title"
            class="reset-base text-xs w-full wa-field wa-field-valid"
            :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.FLOW.SCREEN_NAME')"
            @input="renameScreen($event.target.value)"
          />
        </div>

        <div class="flex-1 overflow-y-auto max-h-[520px] p-2">
          <template v-if="selectedScreen">
            <div
              v-for="(component, index) in screenComponents"
              :key="component.id"
            >
              <!-- Insertar antes de este widget -->
              <button
                type="button"
                class="fb-insert"
                :class="{ 'fb-insert-open': pickerIndex === index }"
                @click="togglePicker(index)"
              >
                <span class="i-lucide-plus size-3" aria-hidden="true" />
              </button>
              <div
                v-if="pickerIndex === index"
                class="fb-picker p-2.5 mb-1.5 space-y-2"
              >
                <div v-for="group in widgetGroups" :key="group.key">
                  <p class="text-[10px] text-n-slate-10 mb-0.5">
                    {{ group.label }}
                  </p>
                  <div class="flex flex-wrap gap-1">
                    <button
                      v-for="type in group.types"
                      :key="type"
                      type="button"
                      class="fb-chip text-[11px] px-2 py-1 flex items-center gap-1"
                      :disabled="!canAddWidget(type)"
                      @click="addWidget(type, index)"
                    >
                      <span
                        :class="componentIcon(type)"
                        class="size-3"
                        aria-hidden="true"
                      />
                      {{ componentLabel(type) }}
                    </button>
                  </div>
                </div>
              </div>

              <div
                class="fb-widget px-2.5 py-2 cursor-pointer flex items-center gap-2"
                :class="{
                  'fb-widget-active': component.id === selectedComponentId,
                }"
                @click="selectedComponentId = component.id"
              >
                <span
                  :class="componentIcon(component.type)"
                  class="size-3.5 shrink-0 text-n-slate-10"
                  aria-hidden="true"
                />
                <span class="text-xs truncate flex-1 text-n-slate-12">
                  {{ componentLabel(component.type) }}
                </span>
                <button
                  type="button"
                  class="fb-mini-btn fb-actions"
                  :disabled="index === 0"
                  @click.stop="moveWidget(index, index - 1)"
                >
                  <span class="i-lucide-chevron-up size-3" aria-hidden="true" />
                </button>
                <button
                  type="button"
                  class="fb-mini-btn fb-actions"
                  :disabled="index === screenComponents.length - 1"
                  @click.stop="moveWidget(index, index + 1)"
                >
                  <span
                    class="i-lucide-chevron-down size-3"
                    aria-hidden="true"
                  />
                </button>
                <button
                  type="button"
                  class="fb-mini-btn fb-mini-btn-danger fb-actions"
                  @click.stop="removeWidget(component.id)"
                >
                  <span class="i-lucide-trash-2 size-3" aria-hidden="true" />
                </button>
              </div>
            </div>

            <!-- Pantalla sin elementos todavía -->
            <div
              v-if="!screenComponents.length"
              class="flex flex-col items-center gap-1 py-6 text-center"
            >
              <span
                class="i-lucide-layout-template size-6 text-n-slate-9"
                aria-hidden="true"
              />
              <p class="text-[11px] text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.EMPTY_SCREEN') }}
              </p>
            </div>

            <!-- Insertar al final -->
            <div class="flex justify-center mt-1">
              <button
                type="button"
                class="text-[11px] text-n-brand hover:underline flex items-center gap-1 px-2 py-1"
                @click="togglePicker(screenComponents.length)"
              >
                <span class="i-lucide-plus size-3" aria-hidden="true" />
                {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.ADD_WIDGET') }}
              </button>
            </div>
            <div
              v-if="pickerIndex === screenComponents.length"
              class="fb-picker p-2.5 mt-1.5 space-y-2"
            >
              <div v-for="group in widgetGroups" :key="group.key">
                <p class="text-[10px] text-n-slate-10 mb-0.5">
                  {{ group.label }}
                </p>
                <div class="flex flex-wrap gap-1">
                  <button
                    v-for="type in group.types"
                    :key="type"
                    type="button"
                    class="fb-chip text-[11px] px-2 py-1 flex items-center gap-1"
                    :disabled="!canAddWidget(type)"
                    @click="addWidget(type, screenComponents.length)"
                  >
                    <span
                      :class="componentIcon(type)"
                      class="size-3"
                      aria-hidden="true"
                    />
                    {{ componentLabel(type) }}
                  </button>
                </div>
              </div>
            </div>
          </template>
        </div>
      </div>

      <!-- Panel 3: configuración del widget seleccionado -->
      <div class="lg:border-l border-n-weak bg-n-alpha-1 flex flex-col">
        <div class="fb-panel-head px-3 py-2.5 shrink-0">
          <p class="fb-panel-title">
            {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.PANEL_CONFIG') }}
          </p>
        </div>
        <div class="flex-1 overflow-y-auto max-h-[520px]">
          <ComponentPropsEditor
            v-if="selectedComponent"
            :component="selectedComponent"
            :screens="orderedScreens"
            :current-screen-id="selectedScreenId"
            :is-first-screen="isFirstScreen"
            :other-screens="
              orderedScreens.filter(s => s.id !== selectedScreenId)
            "
            @update="onUpdateComponent"
          />
          <p v-else class="text-[11px] text-n-slate-10 p-3">
            {{ t('JABVOX_WA_TEMPLATES.CREATE.FLOW.SELECT_WIDGET') }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Mismos tokens de diseño (n-*/ /* y --color-*) que el resto del módulo, para
   que el editor se vea igual en tema claro y oscuro. */

/* Cabecera de cada panel */
.fb-panel-head {
  background: var(--color-background);
  border-bottom: 1px solid var(--color-border-weak, var(--color-border));
}
.fb-panel-title {
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--color-body);
  /* Jerarquía sin depender de un token de gris que no existe en el tema. */
  opacity: 0.65;
}

/* Tarjeta de pantalla / de elemento */
.fb-item {
  border: 1px solid transparent;
  border-radius: 10px;
  transition:
    background 0.16s ease,
    border-color 0.16s ease,
    box-shadow 0.16s ease;
}
.fb-item:hover {
  background: var(--color-background-light);
}
.fb-item-active {
  border-color: var(--color-woot);
  background: color-mix(in srgb, var(--color-woot) 8%, transparent);
  box-shadow: 0 0 0 1px var(--color-woot) inset;
}

/* Elemento de la lista de widgets: borde visible para que se distingan entre sí */
.fb-widget {
  border: 1px solid var(--color-border-weak, var(--color-border));
  border-radius: 10px;
  background: var(--color-background);
  transition:
    border-color 0.16s ease,
    box-shadow 0.16s ease;
}
.fb-widget:hover {
  border-color: var(--color-woot);
}
.fb-widget-active {
  border-color: var(--color-woot);
  box-shadow: 0 0 0 1px var(--color-woot) inset;
  background: color-mix(in srgb, var(--color-woot) 6%, transparent);
}

/* Botón "+" entre elementos: discreto hasta que se pasa el cursor */
.fb-insert {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 2px 0;
  color: transparent;
  transition: color 0.16s ease;
}
.fb-insert::before,
.fb-insert::after {
  content: '';
  flex: 1;
  height: 1px;
  background: var(--color-border-weak, var(--color-border));
  opacity: 0;
  transition: opacity 0.16s ease;
}
.fb-insert:hover,
.fb-insert-open {
  color: var(--color-woot);
}
.fb-insert:hover::before,
.fb-insert:hover::after,
.fb-insert-open::before,
.fb-insert-open::after {
  opacity: 1;
}

/* Paleta desplegable de elementos */
.fb-picker {
  border: 1px solid var(--color-border-weak, var(--color-border));
  border-radius: 10px;
  background: var(--color-background);
  box-shadow: 0 8px 24px -12px rgb(0 0 0 / 35%);
}
.fb-chip {
  border: 1px solid var(--color-border-weak, var(--color-border));
  border-radius: 8px;
  background: var(--color-background);
  color: var(--color-body);
  transition:
    border-color 0.16s ease,
    color 0.16s ease,
    background 0.16s ease;
}
.fb-chip:hover:not(:disabled) {
  border-color: var(--color-woot);
  color: var(--color-woot);
  background: color-mix(in srgb, var(--color-woot) 6%, transparent);
}
.fb-chip:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

/* Acciones de cada fila: aparecen al pasar el cursor para no saturar */
.fb-actions {
  opacity: 0;
  transition: opacity 0.16s ease;
}
.fb-item:hover .fb-actions,
.fb-item-active .fb-actions,
.fb-widget:hover .fb-actions,
.fb-widget-active .fb-actions {
  opacity: 1;
}
.fb-mini-btn {
  padding: 3px;
  border-radius: 6px;
  color: var(--color-body);
  opacity: 0.7;
  transition:
    background 0.16s ease,
    color 0.16s ease;
}
.fb-mini-btn:hover:not(:disabled) {
  background: var(--color-background-light);
  color: var(--color-heading);
  opacity: 1;
}
.fb-mini-btn-danger:hover:not(:disabled) {
  color: var(--color-error, #dc2626);
}
.fb-mini-btn:disabled {
  opacity: 0.25;
  cursor: not-allowed;
}

/* Badge de pantalla final */
.fb-badge {
  font-size: 9px;
  padding: 2px 6px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--color-woot) 14%, transparent);
  color: var(--color-woot);
  font-weight: 600;
}
</style>
