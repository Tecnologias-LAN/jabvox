<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  // The selected management state object (carries `questions`).
  state: { type: Object, default: null },
  // Answers map keyed by question id: { [questionId]: value }.
  modelValue: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const questions = computed(() => props.state?.questions || []);

const answers = computed({
  get: () => props.modelValue || {},
  set: value => emit('update:modelValue', value),
});

const setAnswer = (questionId, value) => {
  emit('update:modelValue', { ...answers.value, [questionId]: value });
};

const isAnswered = question => {
  const value = answers.value[question.id];
  if (question.question_type === 'boolean')
    return value === true || value === false;
  if (Array.isArray(value)) return value.length > 0;
  return value !== undefined && value !== null && `${value}`.trim() !== '';
};

// Exposed so the parent can block saving when required answers are missing.
const isValid = computed(() =>
  questions.value.every(q => !q.required || isAnswered(q))
);

defineExpose({ isValid });
</script>

<template>
  <!-- eslint-disable-next-line vue/no-root-v-if -->
  <div v-if="questions.length" class="space-y-3">
    <div v-for="question in questions" :key="question.id" class="flex flex-col">
      <label class="text-xs font-medium text-n-slate-11 mb-1">
        {{ question.label }}
        <span v-if="question.required" class="text-n-ruby-11">*</span>
      </label>

      <!-- text -->
      <input
        v-if="question.question_type === 'text'"
        type="text"
        class="reset-base text-sm"
        :value="answers[question.id] || ''"
        @input="setAnswer(question.id, $event.target.value)"
      />

      <!-- number -->
      <input
        v-else-if="question.question_type === 'number'"
        type="number"
        class="reset-base text-sm"
        :value="answers[question.id] ?? ''"
        @input="setAnswer(question.id, $event.target.value)"
      />

      <!-- date -->
      <input
        v-else-if="question.question_type === 'date'"
        type="date"
        class="reset-base text-sm"
        :value="answers[question.id] || ''"
        @input="setAnswer(question.id, $event.target.value)"
      />

      <!-- boolean -->
      <label
        v-else-if="question.question_type === 'boolean'"
        class="flex items-center gap-2 text-sm text-n-slate-12"
      >
        <input
          type="checkbox"
          :checked="answers[question.id] === true"
          @change="setAnswer(question.id, $event.target.checked)"
        />
        {{ t('JABVOX_MANAGEMENT_STATES.QUESTIONS.YES') }}
      </label>

      <!-- list -->
      <select
        v-else-if="question.question_type === 'list'"
        class="reset-base text-sm"
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
    </div>
  </div>
</template>
