<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectableCard from './SelectableCard.vue';
import WizardProgress from './WizardProgress.vue';

// Asistente para registrar un ticket por pasos: tipo → tema → subtema → detalles →
// confirmar → recibo. Conserva la lógica original (createTicket, adjuntos vía
// FormData, herencia de conversación); solo cambia el flujo y la presentación.
const props = defineProps({
  conversationId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close', 'created']);

const { t } = useI18n();
const store = useStore();
const categories = useMapGetter('jabvoxTickets/getCategories');
const uiFlags = useMapGetter('jabvoxTickets/getUIFlags');

const form = ref({
  title_jabvox: '',
  ticket_category_id: '', // se fija al subtema si existe, si no al tema
  priority_jabvox: 'medium',
  description_jabvox: '',
});
const selectedType = ref('');
const selectedTopicId = ref('');
const files = ref([]);
const fileInput = ref(null);
const isDragging = ref(false);
const createdTicket = ref(null); // pantalla de éxito

const PRIORITIES = ['low', 'medium', 'high', 'urgent'];
const TYPES = [
  { key: 'incident', icon: 'i-lucide-triangle-alert' },
  { key: 'requirement', icon: 'i-lucide-sparkles' },
  { key: 'request', icon: 'i-lucide-inbox' },
];

// Tipos realmente disponibles (que tienen al menos una categoría raíz).
const availableTypes = computed(() => {
  const present = new Set(
    (categories.value || []).filter(c => !c.parent_id).map(c => c.category_type)
  );
  return TYPES.filter(ty => present.has(ty.key));
});

// Temas raíz del tipo elegido.
const topics = computed(() =>
  (categories.value || []).filter(
    c => !c.parent_id && c.category_type === selectedType.value
  )
);

// Subtemas del tema elegido.
const subtopics = computed(() =>
  (categories.value || []).filter(c => c.parent_id === selectedTopicId.value)
);

const hasSubtopics = computed(() => subtopics.value.length > 0);

// Pasos dinámicos: el paso "subtema" solo existe si el tema tiene hijos.
const steps = computed(() => {
  const base = [
    { key: 'type', label: t('JABVOX_TICKETS.WIZARD.STEP_TYPE') },
    { key: 'topic', label: t('JABVOX_TICKETS.WIZARD.STEP_TOPIC') },
  ];
  if (hasSubtopics.value)
    base.push({
      key: 'subtopic',
      label: t('JABVOX_TICKETS.WIZARD.STEP_SUBTOPIC'),
    });
  base.push({ key: 'details', label: t('JABVOX_TICKETS.WIZARD.STEP_DETAILS') });
  base.push({ key: 'confirm', label: t('JABVOX_TICKETS.WIZARD.STEP_CONFIRM') });
  return base;
});

const stepIndex = ref(0);
const currentStep = computed(() => steps.value[stepIndex.value]?.key);

// Objetos elegidos (para el resumen).
const chosenTopic = computed(() =>
  (categories.value || []).find(c => c.id === selectedTopicId.value)
);
const chosenSubtopic = computed(() =>
  (categories.value || []).find(
    c => c.id === form.value.ticket_category_id && c.parent_id
  )
);

// --- Navegación ---
const canNext = computed(() => {
  switch (currentStep.value) {
    case 'type':
      return !!selectedType.value;
    case 'topic':
      return !!selectedTopicId.value;
    case 'subtopic':
      return !!form.value.ticket_category_id;
    case 'details':
      return !!form.value.title_jabvox.trim();
    default:
      return true;
  }
});

const isLastStep = computed(() => stepIndex.value === steps.value.length - 1);

const next = () => {
  if (!canNext.value) return;
  if (stepIndex.value < steps.value.length - 1) stepIndex.value += 1;
};
const back = () => {
  if (stepIndex.value > 0) stepIndex.value -= 1;
};

// --- Selecciones ---
const selectType = key => {
  selectedType.value = key;
  selectedTopicId.value = '';
  form.value.ticket_category_id = '';
  next();
};

const selectTopic = topic => {
  selectedTopicId.value = topic.id;
  // Si el tema NO tiene subtemas, el ticket va con el tema como categoría.
  const children = (categories.value || []).filter(
    c => c.parent_id === topic.id
  );
  form.value.ticket_category_id = children.length ? '' : topic.id;
  next();
};

const selectSubtopic = sub => {
  form.value.ticket_category_id = sub.id;
  next();
};

// --- Adjuntos: SOLO imágenes (drag & drop + click) ---
const pickFiles = () => fileInput.value?.click();
const addFiles = list => {
  const incoming = Array.from(list || []);
  const images = incoming.filter(f => f.type.startsWith('image/'));
  if (images.length < incoming.length) {
    useAlert(t('JABVOX_TICKETS.WIZARD.ONLY_IMAGES'));
  }
  files.value = [...files.value, ...images];
};
const onFiles = e => addFiles(e.target.files);
const onDrop = e => {
  isDragging.value = false;
  addFiles(e.dataTransfer?.files);
};
const removeFile = idx => {
  files.value = files.value.filter((_, i) => i !== idx);
};
const humanSize = bytes => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
};

// Miniaturas: URL de objeto por archivo, cacheada y revocada al desmontar.
const previewCache = new WeakMap();
const previewUrl = file => {
  if (!previewCache.has(file))
    previewCache.set(file, URL.createObjectURL(file));
  return previewCache.get(file);
};

// --- Envío ---
const submit = async () => {
  if (uiFlags.value.isCreating) return;
  try {
    let payload;
    if (files.value.length) {
      payload = new FormData();
      Object.entries(form.value).forEach(([k, v]) => payload.append(k, v));
      if (props.conversationId)
        payload.append('conversation_id', props.conversationId);
      files.value.forEach(f => payload.append('attachments[]', f));
    } else {
      payload = { ...form.value };
      if (props.conversationId) payload.conversation_id = props.conversationId;
    }
    const ticket = await store.dispatch('jabvoxTickets/createTicket', payload);
    createdTicket.value = ticket; // pantalla de éxito
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_TICKETS.FORM.ERROR'));
  }
};

const resetWizard = () => {
  form.value = {
    title_jabvox: '',
    ticket_category_id: '',
    priority_jabvox: 'medium',
    description_jabvox: '',
  };
  selectedType.value = '';
  selectedTopicId.value = '';
  files.value = [];
  stepIndex.value = 0;
  createdTicket.value = null;
};

const viewCreated = () => emit('created', createdTicket.value);
</script>

<template>
  <teleport to="body">
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      @click.self="emit('close')"
    >
      <div
        class="flex flex-col w-full max-w-2xl max-h-[90vh] rounded-3xl bg-n-solid-1 border border-n-weak shadow-xl overflow-hidden"
      >
        <!-- ===== Pantalla de éxito (recibo) ===== -->
        <div
          v-if="createdTicket"
          class="flex flex-col items-center text-center px-8 py-12 gap-5"
        >
          <span
            class="flex items-center justify-center w-20 h-20 rounded-full bg-n-teal-3 tk-pop"
            aria-hidden="true"
          >
            <span class="i-lucide-check w-10 h-10 text-n-teal-11" />
          </span>
          <div>
            <p class="text-sm text-n-slate-11">
              {{ t('JABVOX_TICKETS.SUCCESS.LABEL') }}
            </p>
            <p class="text-4xl font-bold text-n-slate-12 tabular-nums mt-1">
              {{ `#${createdTicket.display_id}` }}
            </p>
          </div>
          <p class="text-sm text-n-slate-11 max-w-sm leading-relaxed">
            {{ t('JABVOX_TICKETS.SUCCESS.MESSAGE') }}
          </p>
          <div class="flex items-center gap-2 mt-2">
            <Button
              :label="t('JABVOX_TICKETS.SUCCESS.VIEW')"
              icon="i-lucide-eye"
              size="sm"
              @click="viewCreated"
            />
            <Button
              :label="t('JABVOX_TICKETS.SUCCESS.ANOTHER')"
              icon="i-lucide-plus"
              size="sm"
              variant="outline"
              color="slate"
              @click="resetWizard"
            />
          </div>
        </div>

        <!-- ===== Asistente ===== -->
        <template v-else>
          <!-- Cabecera + progreso -->
          <div class="px-6 pt-5 pb-4 border-b border-n-weak">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-base font-semibold text-n-slate-12">
                {{ t('JABVOX_TICKETS.FORM.TITLE') }}
              </h3>
              <Button
                icon="i-lucide-x"
                variant="ghost"
                color="slate"
                size="sm"
                :aria-label="t('JABVOX_TICKETS.FORM.CANCEL')"
                @click="emit('close')"
              />
            </div>
            <WizardProgress :steps="steps" :current="stepIndex" />
          </div>

          <!-- Cuerpo del paso -->
          <div class="flex-1 overflow-y-auto px-6 py-5">
            <!-- Paso: Tipo -->
            <div v-if="currentStep === 'type'" class="tk-step">
              <p class="text-sm text-n-slate-11 mb-4">
                {{ t('JABVOX_TICKETS.WIZARD.TYPE_HINT') }}
              </p>
              <div class="grid sm:grid-cols-3 gap-3">
                <SelectableCard
                  v-for="ty in availableTypes"
                  :key="ty.key"
                  :icon="ty.icon"
                  :title="t(`JABVOX_TICKETS.TYPE.${ty.key.toUpperCase()}`)"
                  :description="
                    t(`JABVOX_TICKETS.WIZARD.TYPE_DESC.${ty.key.toUpperCase()}`)
                  "
                  :selected="selectedType === ty.key"
                  @select="selectType(ty.key)"
                />
              </div>
              <p
                v-if="!availableTypes.length"
                class="text-sm text-n-slate-10 text-center py-8"
              >
                {{ t('JABVOX_TICKETS.WIZARD.NO_TOPICS') }}
              </p>
            </div>

            <!-- Paso: Tema -->
            <div v-else-if="currentStep === 'topic'" class="tk-step">
              <p class="text-sm text-n-slate-11 mb-4">
                {{ t('JABVOX_TICKETS.WIZARD.TOPIC_HINT') }}
              </p>
              <div class="grid sm:grid-cols-2 gap-3">
                <SelectableCard
                  v-for="topic in topics"
                  :key="topic.id"
                  :title="topic.name"
                  :description="topic.description || ''"
                  :accent="topic.color"
                  :selected="selectedTopicId === topic.id"
                  @select="selectTopic(topic)"
                />
              </div>
            </div>

            <!-- Paso: Subtema -->
            <div v-else-if="currentStep === 'subtopic'" class="tk-step">
              <p class="text-sm text-n-slate-11 mb-4">
                {{ t('JABVOX_TICKETS.WIZARD.SUBTOPIC_HINT') }}
              </p>
              <div class="grid sm:grid-cols-2 gap-3">
                <SelectableCard
                  v-for="sub in subtopics"
                  :key="sub.id"
                  :title="sub.name"
                  :description="sub.description || ''"
                  :accent="sub.color"
                  :selected="form.ticket_category_id === sub.id"
                  @select="selectSubtopic(sub)"
                />
              </div>
            </div>

            <!-- Paso: Detalles -->
            <div
              v-else-if="currentStep === 'details'"
              class="tk-step flex flex-col gap-4"
            >
              <label class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('JABVOX_TICKETS.FORM.FIELD_TITLE') }}
                </span>
                <Input
                  v-model="form.title_jabvox"
                  :placeholder="t('JABVOX_TICKETS.WIZARD.TITLE_PLACEHOLDER')"
                />
              </label>

              <label class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('JABVOX_TICKETS.FORM.DESCRIPTION') }}
                </span>
                <textarea
                  v-model="form.description_jabvox"
                  rows="4"
                  :placeholder="t('JABVOX_TICKETS.WIZARD.DESC_PLACEHOLDER')"
                  class="text-sm rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
                />
              </label>

              <div class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('JABVOX_TICKETS.FORM.PRIORITY') }}
                </span>
                <div class="flex flex-wrap gap-2">
                  <button
                    v-for="pr in PRIORITIES"
                    :key="pr"
                    type="button"
                    class="px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                    :class="
                      form.priority_jabvox === pr
                        ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                        : 'border-n-weak text-n-slate-11 hover:border-n-strong'
                    "
                    @click="form.priority_jabvox = pr"
                  >
                    {{ t(`JABVOX_TICKETS.PRIORITY.${pr.toUpperCase()}`) }}
                  </button>
                </div>
              </div>

              <!-- Adjuntos con drag & drop -->
              <div class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('JABVOX_TICKETS.FORM.ATTACH') }}
                </span>
                <div
                  class="flex flex-col items-center justify-center gap-1 py-6 px-4 rounded-xl border border-dashed transition-colors cursor-pointer"
                  :class="
                    isDragging
                      ? 'border-n-brand bg-n-brand/5'
                      : 'border-n-weak hover:border-n-strong bg-n-alpha-1'
                  "
                  role="button"
                  tabindex="0"
                  @click="pickFiles"
                  @keydown.enter="pickFiles"
                  @dragover.prevent="isDragging = true"
                  @dragleave.prevent="isDragging = false"
                  @drop.prevent="onDrop"
                >
                  <span
                    class="i-lucide-upload-cloud w-6 h-6 text-n-slate-10"
                    aria-hidden="true"
                  />
                  <span class="text-xs text-n-slate-11">
                    {{ t('JABVOX_TICKETS.WIZARD.DROP_HINT') }}
                  </span>
                  <span class="text-[11px] text-n-slate-9">
                    {{ t('JABVOX_TICKETS.WIZARD.IMAGES_ONLY_HINT') }}
                  </span>
                  <input
                    ref="fileInput"
                    type="file"
                    accept="image/*"
                    multiple
                    class="hidden"
                    @change="onFiles"
                  />
                </div>
                <ul
                  v-if="files.length"
                  class="grid grid-cols-3 sm:grid-cols-4 gap-2 mt-2"
                >
                  <li
                    v-for="(f, idx) in files"
                    :key="`${f.name}-${idx}`"
                    class="relative group aspect-square rounded-lg overflow-hidden border border-n-weak bg-n-alpha-1"
                  >
                    <img
                      :src="previewUrl(f)"
                      :alt="f.name"
                      class="w-full h-full object-cover"
                    />
                    <button
                      type="button"
                      class="absolute top-1 right-1 flex items-center justify-center w-5 h-5 rounded-full bg-n-alpha-black2 text-white opacity-0 group-hover:opacity-100 transition-opacity"
                      :aria-label="t('JABVOX_TICKETS.FORM.CANCEL')"
                      @click="removeFile(idx)"
                    >
                      <span class="i-lucide-x w-3 h-3" aria-hidden="true" />
                    </button>
                    <span
                      class="absolute bottom-0 inset-x-0 px-1.5 py-0.5 text-[10px] text-white bg-gradient-to-t from-black/60 to-transparent truncate"
                    >
                      {{ humanSize(f.size) }}
                    </span>
                  </li>
                </ul>
              </div>
            </div>

            <!-- Paso: Confirmar -->
            <div v-else-if="currentStep === 'confirm'" class="tk-step">
              <p class="text-sm text-n-slate-11 mb-4">
                {{ t('JABVOX_TICKETS.WIZARD.CONFIRM_HINT') }}
              </p>
              <div
                class="rounded-2xl border border-n-weak bg-n-alpha-1 divide-y divide-n-weak"
              >
                <div class="flex items-center gap-2 px-4 py-3 text-sm">
                  <span class="w-24 text-n-slate-10 shrink-0">
                    {{ t('JABVOX_TICKETS.WIZARD.STEP_TYPE') }}
                  </span>
                  <span class="font-medium text-n-slate-12">
                    {{
                      t(
                        `JABVOX_TICKETS.TYPE.${(selectedType || '').toUpperCase()}`
                      )
                    }}
                  </span>
                </div>
                <div class="flex items-center gap-2 px-4 py-3 text-sm">
                  <span class="w-24 text-n-slate-10 shrink-0">
                    {{ t('JABVOX_TICKETS.WIZARD.STEP_TOPIC') }}
                  </span>
                  <span class="font-medium text-n-slate-12">
                    {{ chosenTopic?.name || '—' }}
                  </span>
                </div>
                <div
                  v-if="chosenSubtopic"
                  class="flex items-center gap-2 px-4 py-3 text-sm"
                >
                  <span class="w-24 text-n-slate-10 shrink-0">
                    {{ t('JABVOX_TICKETS.WIZARD.STEP_SUBTOPIC') }}
                  </span>
                  <span class="font-medium text-n-slate-12">
                    {{ chosenSubtopic.name }}
                  </span>
                </div>
                <div class="flex items-center gap-2 px-4 py-3 text-sm">
                  <span class="w-24 text-n-slate-10 shrink-0">
                    {{ t('JABVOX_TICKETS.FORM.PRIORITY') }}
                  </span>
                  <span class="font-medium text-n-slate-12">
                    {{
                      t(
                        `JABVOX_TICKETS.PRIORITY.${form.priority_jabvox.toUpperCase()}`
                      )
                    }}
                  </span>
                </div>
                <div class="flex items-start gap-2 px-4 py-3 text-sm">
                  <span class="w-24 text-n-slate-10 shrink-0">
                    {{ t('JABVOX_TICKETS.FORM.FIELD_TITLE') }}
                  </span>
                  <span class="font-medium text-n-slate-12 break-words">
                    {{ form.title_jabvox }}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!-- Pie: navegación -->
          <div
            class="flex items-center justify-between gap-2 px-6 py-4 border-t border-n-weak"
          >
            <Button
              :label="t('JABVOX_TICKETS.WIZARD.BACK')"
              icon="i-lucide-arrow-left"
              variant="ghost"
              color="slate"
              size="sm"
              :disabled="stepIndex === 0"
              @click="back"
            />
            <Button
              v-if="!isLastStep"
              :label="t('JABVOX_TICKETS.WIZARD.NEXT')"
              trailing-icon="i-lucide-arrow-right"
              size="sm"
              :disabled="!canNext"
              @click="next"
            />
            <Button
              v-else
              :label="t('JABVOX_TICKETS.WIZARD.SUBMIT')"
              icon="i-lucide-send"
              size="sm"
              :is-loading="uiFlags.isCreating"
              @click="submit"
            />
          </div>
        </template>
      </div>
    </div>
  </teleport>
</template>

<style scoped>
.tk-step {
  animation: tk-step-in 0.25s ease-out;
}
@keyframes tk-step-in {
  from {
    opacity: 0;
    transform: translateY(6px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
.tk-pop {
  animation: tk-pop 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
}
@keyframes tk-pop {
  from {
    opacity: 0;
    transform: scale(0.6);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}
@media (prefers-reduced-motion: reduce) {
  .tk-step,
  .tk-pop {
    animation: none;
  }
}
</style>
