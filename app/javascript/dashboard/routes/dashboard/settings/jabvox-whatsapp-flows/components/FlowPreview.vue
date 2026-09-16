<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  screens: { type: Array, default: () => [] },
  flowName: { type: String, default: '' },
});

const { t } = useI18n();

const orderedScreens = computed(() =>
  [...props.screens].sort((a, b) => a.order - b.order)
);

// Pila de navegación simulada: permite click-through real entre pantallas
// (navigate) y "volver" para probar el flujo completo, no solo una imagen
// estática de la primera pantalla.
const historyStack = ref([]);
const currentScreenId = computed(
  () => historyStack.value[historyStack.value.length - 1]
);
const currentScreen = computed(() =>
  orderedScreens.value.find(s => s.id === currentScreenId.value)
);

// Respuestas simuladas del usuario de prueba, por componente `name`, para que
// el preview se sienta real al navegar (no persiste nada).
const answers = ref({});

const resetPreview = () => {
  historyStack.value = orderedScreens.value.length
    ? [orderedScreens.value[0].id]
    : [];
  answers.value = {};
};

watch(() => props.screens, resetPreview, { immediate: true, deep: false });

const goBack = () => {
  if (historyStack.value.length > 1) historyStack.value.pop();
};

const handleAction = action => {
  if (!action) return;
  if (action.name === 'navigate' && action.next) {
    historyStack.value.push(action.next);
  } else if (action.name === 'complete') {
    historyStack.value.push('__SUCCESS__');
  }
  // open_url no navega dentro del preview — se documenta como no simulable.
};

const setAnswer = (name, value) => {
  answers.value = { ...answers.value, [name]: value };
};

const toggleChip = (name, optionId) => {
  const current = answers.value[name] || [];
  const next = current.includes(optionId)
    ? current.filter(v => v !== optionId)
    : [...current, optionId];
  setAnswer(name, next);
};
</script>

<template>
  <div class="flex flex-col h-full">
    <div
      class="flex items-center justify-between px-3 py-2 border-b border-n-weak shrink-0"
    >
      <h3 class="text-xs font-semibold uppercase tracking-wide text-n-slate-10">
        {{ t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.TITLE') }}
      </h3>
      <button
        class="wf-icon-btn-xs"
        :title="t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.RESTART')"
        @click="resetPreview"
      >
        <span class="i-lucide-rotate-ccw size-3.5" aria-hidden="true" />
      </button>
    </div>

    <div class="flex-1 overflow-y-auto p-3 bg-n-alpha-1">
      <div
        class="mx-auto max-w-[300px] rounded-[28px] border border-n-weak bg-[#0b141a] shadow-lg overflow-hidden"
      >
        <!-- Header estilo WhatsApp -->
        <div class="flex items-center gap-2 bg-[#202c33] px-3 py-2.5">
          <button
            v-if="historyStack.length > 1"
            class="text-white/80 hover:text-white"
            @click="goBack"
          >
            <span class="i-lucide-chevron-left size-4" aria-hidden="true" />
          </button>
          <span class="i-lucide-x size-4 text-white/60" aria-hidden="true" />
          <p class="text-white text-sm font-medium truncate flex-1">
            {{ flowName || t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.UNTITLED_FLOW') }}
          </p>
        </div>

        <!-- Contenido -->
        <div class="bg-white min-h-[420px] p-4 flex flex-col gap-3">
          <template v-if="!orderedScreens.length">
            <p class="text-sm text-gray-400 text-center py-10">
              {{ t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.EMPTY') }}
            </p>
          </template>

          <template v-else-if="currentScreenId === '__SUCCESS__'">
            <div class="flex flex-col items-center justify-center py-16 gap-2">
              <span
                class="i-lucide-check-circle-2 size-10 text-green-600"
                aria-hidden="true"
              />
              <p class="text-sm text-gray-700">
                {{ t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.COMPLETED') }}
              </p>
            </div>
          </template>

          <template v-else-if="currentScreen">
            <p class="text-[11px] text-gray-400">{{ currentScreen.title }}</p>

            <template
              v-for="component in currentScreen.components"
              :key="component.id"
            >
              <h2
                v-if="component.type === 'TextHeading'"
                class="text-lg font-bold text-gray-900"
              >
                {{ component.props.text }}
              </h2>
              <h3
                v-else-if="component.type === 'TextSubheading'"
                class="text-base font-semibold text-gray-800"
              >
                {{ component.props.text }}
              </h3>
              <p
                v-else-if="component.type === 'TextBody'"
                class="text-sm text-gray-700 whitespace-pre-wrap"
              >
                {{ component.props.text }}
              </p>
              <p
                v-else-if="component.type === 'TextCaption'"
                class="text-xs text-gray-500"
              >
                {{ component.props.text }}
              </p>

              <div
                v-else-if="component.type === 'TextInput'"
                class="flex flex-col gap-1"
              >
                <label class="text-xs text-gray-600">{{
                  component.props.label
                }}</label>
                <input
                  class="border border-gray-300 rounded-lg px-2.5 py-1.5 text-sm"
                  :type="
                    component.props.input_type === 'number' ? 'number' : 'text'
                  "
                  :value="answers[component.props.name] || ''"
                  @input="setAnswer(component.props.name, $event.target.value)"
                />
              </div>

              <div
                v-else-if="component.type === 'TextArea'"
                class="flex flex-col gap-1"
              >
                <label class="text-xs text-gray-600">{{
                  component.props.label
                }}</label>
                <textarea
                  rows="3"
                  class="border border-gray-300 rounded-lg px-2.5 py-1.5 text-sm"
                  :value="answers[component.props.name] || ''"
                  @input="setAnswer(component.props.name, $event.target.value)"
                />
              </div>

              <div
                v-else-if="component.type === 'RadioButtonsGroup'"
                class="flex flex-col gap-1.5"
              >
                <label class="text-xs text-gray-600">{{
                  component.props.label
                }}</label>
                <label
                  v-for="opt in component.props.data_source || []"
                  :key="opt.id"
                  class="flex items-center gap-2 text-sm text-gray-800"
                >
                  <input
                    type="radio"
                    :name="component.id"
                    :checked="answers[component.props.name] === opt.id"
                    @change="setAnswer(component.props.name, opt.id)"
                  />
                  {{ opt.title }}
                </label>
              </div>

              <div
                v-else-if="component.type === 'CheckboxGroup'"
                class="flex flex-col gap-1.5"
              >
                <label class="text-xs text-gray-600">{{
                  component.props.label
                }}</label>
                <label
                  v-for="opt in component.props.data_source || []"
                  :key="opt.id"
                  class="flex items-center gap-2 text-sm text-gray-800"
                >
                  <input
                    type="checkbox"
                    :checked="
                      (answers[component.props.name] || []).includes(opt.id)
                    "
                    @change="toggleChip(component.props.name, opt.id)"
                  />
                  {{ opt.title }}
                </label>
              </div>

              <div
                v-else-if="component.type === 'Dropdown'"
                class="flex flex-col gap-1"
              >
                <label class="text-xs text-gray-600">{{
                  component.props.label
                }}</label>
                <select
                  class="border border-gray-300 rounded-lg px-2.5 py-1.5 text-sm"
                  :value="answers[component.props.name] || ''"
                  @change="setAnswer(component.props.name, $event.target.value)"
                >
                  <option value="">
                    {{
                      t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.SELECT_PLACEHOLDER')
                    }}
                  </option>
                  <option
                    v-for="opt in component.props.data_source || []"
                    :key="opt.id"
                    :value="opt.id"
                  >
                    {{ opt.title }}
                  </option>
                </select>
              </div>

              <div
                v-else-if="component.type === 'ChipsSelector'"
                class="flex flex-col gap-1.5"
              >
                <label class="text-xs text-gray-600">{{
                  component.props.label
                }}</label>
                <div class="flex flex-wrap gap-1.5">
                  <button
                    v-for="opt in component.props.data_source || []"
                    :key="opt.id"
                    type="button"
                    class="px-2.5 py-1 rounded-full text-xs border"
                    :class="
                      (answers[component.props.name] || []).includes(opt.id)
                        ? 'bg-[#00a884] text-white border-[#00a884]'
                        : 'border-gray-300 text-gray-700'
                    "
                    @click="toggleChip(component.props.name, opt.id)"
                  >
                    {{ opt.title }}
                  </button>
                </div>
              </div>

              <div
                v-else-if="component.type === 'DatePicker'"
                class="flex flex-col gap-1"
              >
                <label class="text-xs text-gray-600">{{
                  component.props.label
                }}</label>
                <input
                  type="date"
                  class="border border-gray-300 rounded-lg px-2.5 py-1.5 text-sm"
                  :value="answers[component.props.name] || ''"
                  @input="setAnswer(component.props.name, $event.target.value)"
                />
              </div>

              <label
                v-else-if="component.type === 'OptIn'"
                class="flex items-start gap-2 text-sm text-gray-800"
              >
                <input
                  type="checkbox"
                  class="mt-0.5"
                  :checked="!!answers[component.props.name]"
                  @change="
                    setAnswer(component.props.name, $event.target.checked)
                  "
                />
                {{ component.props.label }}
              </label>

              <img
                v-else-if="component.type === 'Image' && component.props.src"
                :src="component.props.src"
                :alt="component.props.alt_text || ''"
                class="rounded-lg max-h-40 object-contain"
              />

              <button
                v-else-if="component.type === 'EmbeddedLink'"
                type="button"
                class="text-sm text-[#0a7cff] underline text-left"
                @click="handleAction(component.props.action)"
              >
                {{ component.props.text }}
              </button>

              <button
                v-else-if="component.type === 'Footer'"
                type="button"
                class="mt-auto w-full rounded-lg bg-[#00a884] text-white text-sm font-medium py-2.5"
                @click="handleAction(component.props.action)"
              >
                {{
                  component.props.label ||
                  t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.CONTINUE')
                }}
              </button>
            </template>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
