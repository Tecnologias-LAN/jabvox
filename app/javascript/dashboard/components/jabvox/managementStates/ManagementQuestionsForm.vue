<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  isQuestionVisible,
  seedAnswersFromLead,
} from 'dashboard/composables/jabvox/useManagementState';

const props = defineProps({
  // The selected management state object (carries `questions`).
  state: { type: Object, default: null },
  // Answers map keyed by question id: { [questionId]: value }.
  modelValue: { type: Object, default: () => ({}) },
  // Live contact/lead so questions mapped to a lead field can auto-fill.
  contact: { type: Object, default: null },
  lead: { type: Object, default: null },
  // Max height (CSS value) of the scrollable questions body. States can carry
  // many questions, so the body scrolls on its own while the header stays put.
  maxBodyHeight: { type: String, default: '22rem' },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const allQuestions = computed(() => props.state?.questions || []);

const answers = computed({
  get: () => props.modelValue || {},
  set: value => emit('update:modelValue', value),
});

// Pre-fill lead-mapped questions when the state or the lead changes. Existing
// answers are preserved (seedAnswersFromLead only fills blanks), so this never
// overwrites what the agent already typed.
watch(
  () => [props.state?.id, props.contact, props.lead],
  () => {
    if (!props.state) return;
    const seeded = seedAnswersFromLead(
      props.state,
      answers.value,
      props.contact,
      props.lead
    );
    // Only emit if something actually changed, to avoid update loops.
    const changed = Object.keys(seeded).some(
      k => seeded[k] !== answers.value[k]
    );
    if (changed) emit('update:modelValue', seeded);
  },
  { immediate: true, deep: true }
);

// A question whose value is locked to a lead field is shown read-only.
const isLocked = question =>
  Boolean(question.lead_field) && question.lead_field_locked === true;

// Only the questions whose visibility conditions are currently met. Everything
// downstream (count, sections, validity) works off this list, so a hidden
// question is invisible to the agent and never blocks saving.
const questions = computed(() =>
  allQuestions.value.filter(q =>
    isQuestionVisible(q, answers.value, allQuestions.value)
  )
);

const setAnswer = (questionId, value) => {
  emit('update:modelValue', { ...answers.value, [questionId]: value });
};

// Toggle a single option in a multiselect answer (stored as an array).
const toggleMultiselect = (questionId, option) => {
  const current = Array.isArray(answers.value[questionId])
    ? [...answers.value[questionId]]
    : [];
  const idx = current.indexOf(option);
  if (idx === -1) current.push(option);
  else current.splice(idx, 1);
  emit('update:modelValue', { ...answers.value, [questionId]: current });
};

const isOptionChecked = (questionId, option) =>
  Array.isArray(answers.value[questionId]) &&
  answers.value[questionId].includes(option);

const isAnswered = question => {
  const value = answers.value[question.id];
  if (question.question_type === 'boolean')
    return value === true || value === false;
  if (Array.isArray(value)) return value.length > 0;
  return value !== undefined && value !== null && `${value}`.trim() !== '';
};

const answeredCount = computed(
  () => questions.value.filter(q => isAnswered(q)).length
);

// Visual grouping: the standard classification questions go under
// "Información de gestión"; everything else under "Resultado de interacción".
// States with only custom questions fall back to a single untitled section.
const INFO_LABELS = ['¿Gestionado?', '¿Hubo contacto?', '¿Contacto efectivo?'];
const sections = computed(() => {
  const info = questions.value.filter(q => INFO_LABELS.includes(q.label));
  const rest = questions.value.filter(q => !INFO_LABELS.includes(q.label));
  if (!info.length) return [{ key: 'all', title: '', items: rest }];
  return [
    {
      key: 'info',
      title: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.GROUP_INFO'),
      items: info,
    },
    {
      key: 'result',
      title: t('JABVOX_MANAGEMENT_STATES.QUESTIONS.GROUP_RESULT'),
      items: rest,
    },
  ].filter(section => section.items.length);
});

const inputClass =
  'reset-base w-full text-sm text-n-slate-12 bg-n-solid-1 border border-n-weak rounded-lg px-3 py-2 ' +
  'transition-colors duration-150 hover:border-n-slate-7 focus:outline-none focus:border-n-brand';

// Exposed so the parent can block saving when required answers are missing.
const isValid = computed(() =>
  questions.value.every(q => !q.required || isAnswered(q))
);

defineExpose({ isValid });
</script>

<template>
  <div
    v-show="questions.length"
    class="rounded-xl border border-n-weak bg-n-alpha-1 overflow-hidden flex flex-col min-h-0 max-h-full"
  >
    <!-- Header with progress (stays fixed while the body scrolls) -->
    <div
      class="shrink-0 flex items-center justify-between px-3 py-2 border-b border-n-weak bg-n-solid-1"
    >
      <span
        class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
      >
        {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.TITLE') }}
      </span>
      <span
        class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium transition-colors duration-150"
        :class="
          isValid
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-amber-3 text-n-amber-11'
        "
      >
        <span
          class="size-3"
          :class="isValid ? 'i-lucide-check-circle-2' : 'i-lucide-circle-dot'"
        />
        {{
          t('JABVOX_MANAGEMENT_STATES.QUESTIONS.PROGRESS', {
            answered: answeredCount,
            total: questions.length,
          })
        }}
      </span>
    </div>

    <div
      class="p-3 flex flex-col gap-4 overflow-y-auto min-h-0"
      :style="{ maxHeight: maxBodyHeight }"
    >
      <section v-for="section in sections" :key="section.key">
        <h4
          v-if="section.title"
          class="text-xs font-semibold text-n-slate-11 mb-2 flex items-center gap-1.5"
        >
          <span
            class="size-3.5 text-n-slate-9"
            :class="
              section.key === 'info'
                ? 'i-lucide-clipboard-list'
                : 'i-lucide-target'
            "
          />
          {{ section.title }}
        </h4>

        <div class="flex flex-col gap-2">
          <div
            v-for="question in section.items"
            :key="question.id"
            class="rounded-lg border bg-n-solid-1 px-3 py-2.5 transition-colors duration-150"
            :class="
              isAnswered(question)
                ? 'border-n-weak'
                : question.required
                  ? 'border-n-amber-6'
                  : 'border-n-weak'
            "
          >
            <!-- boolean: label left, Sí/No segmented toggle right -->
            <div
              v-if="question.question_type === 'boolean'"
              class="flex items-center justify-between gap-3"
            >
              <span class="text-sm font-medium text-n-slate-12">
                {{ question.label }}
                <span v-if="question.required" class="text-n-ruby-11">*</span>
              </span>
              <div
                class="inline-flex rounded-lg border border-n-weak overflow-hidden shrink-0"
              >
                <button
                  type="button"
                  class="px-3 py-1 text-xs font-semibold transition-colors duration-150"
                  :class="
                    answers[question.id] === true
                      ? 'bg-n-teal-9 text-white'
                      : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
                  "
                  @click="setAnswer(question.id, true)"
                >
                  {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.YES') }}
                </button>
                <button
                  type="button"
                  class="px-3 py-1 text-xs font-semibold border-l border-n-weak transition-colors duration-150"
                  :class="
                    answers[question.id] === false
                      ? 'bg-n-ruby-9 text-white'
                      : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
                  "
                  @click="setAnswer(question.id, false)"
                >
                  {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.NO') }}
                </button>
              </div>
            </div>

            <!-- other types: label on top, control below -->
            <div v-else class="flex flex-col gap-1.5">
              <label
                class="text-sm font-medium text-n-slate-12 flex items-center gap-1"
              >
                {{ question.label }}
                <span v-if="question.required" class="text-n-ruby-11">*</span>
                <span
                  v-if="isAnswered(question)"
                  class="i-lucide-check-circle-2 size-3.5 text-n-teal-10 ml-auto"
                />
              </label>

              <input
                v-if="question.question_type === 'text'"
                type="text"
                :class="inputClass"
                :disabled="isLocked(question)"
                :value="answers[question.id] || ''"
                @input="setAnswer(question.id, $event.target.value)"
              />

              <input
                v-else-if="question.question_type === 'number'"
                type="number"
                :class="inputClass"
                :disabled="isLocked(question)"
                :value="answers[question.id] ?? ''"
                @input="setAnswer(question.id, $event.target.value)"
              />

              <input
                v-else-if="question.question_type === 'date'"
                type="date"
                :class="inputClass"
                :disabled="isLocked(question)"
                :value="answers[question.id] || ''"
                @input="setAnswer(question.id, $event.target.value)"
              />

              <select
                v-else-if="question.question_type === 'list'"
                :class="inputClass"
                :disabled="isLocked(question)"
                :value="answers[question.id] || ''"
                @change="setAnswer(question.id, $event.target.value)"
              >
                <option value="">
                  {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.SELECT') }}
                </option>
                <option v-for="opt in question.options" :key="opt" :value="opt">
                  {{ opt }}
                </option>
              </select>

              <!-- multiselect: checkbox list, answer stored as an array -->
              <div
                v-else-if="question.question_type === 'multiselect'"
                class="flex flex-col gap-1"
              >
                <label
                  v-for="opt in question.options"
                  :key="opt"
                  class="flex items-center gap-2 rounded-lg px-2 py-1.5 cursor-pointer hover:bg-n-alpha-1 transition-colors duration-150"
                >
                  <input
                    type="checkbox"
                    class="reset-base size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
                    :checked="isOptionChecked(question.id, opt)"
                    @change="toggleMultiselect(question.id, opt)"
                  />
                  <span class="text-sm text-n-slate-12">{{ opt }}</span>
                </label>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
