<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Comentarios de resolución bajo los detalles de la tarea: lo que se va haciendo para
// cerrarla, escrito sin entrar en modo edición.
//
// Los mismos comentarios salen también en el historial de la derecha, donde se mezclan con
// los cambios de campos. Aquí aparecen solos, que es como se sigue la conversación de
// resolución sin el ruido de "cambió la prioridad".
const props = defineProps({
  activities: { type: Array, default: () => [] },
  modelValue: { type: String, default: '' },
  isSending: { type: Boolean, default: false },
  formatDate: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue', 'submit']);

const { t } = useI18n();

// Más antiguo primero: se lee como una conversación, de arriba abajo.
const comments = computed(() =>
  props.activities
    .filter(a => a.action === 'comment')
    .slice()
    .reverse()
);

const body = computed({
  get: () => props.modelValue,
  set: value => emit('update:modelValue', value),
});
</script>

<template>
  <section class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm">
    <h3
      class="flex items-center gap-2 text-sm font-semibold text-n-slate-12 mb-4"
    >
      <span
        class="i-lucide-message-square size-4 text-n-slate-10"
        aria-hidden="true"
      />
      {{ t('JABVOX_TASKS.TASK.COMMENTS.TITLE') }}
      <span v-if="comments.length" class="text-n-slate-10 font-normal">
        ({{ comments.length }})
      </span>
    </h3>

    <ol v-if="comments.length" class="space-y-3 mb-4">
      <li v-for="comment in comments" :key="comment.id" class="flex gap-3">
        <span
          class="flex items-center justify-center size-8 rounded-full bg-n-alpha-1 text-n-slate-11 shrink-0 text-xs font-medium"
        >
          {{ (comment.userName || '?').charAt(0).toUpperCase() }}
        </span>
        <div class="min-w-0 flex-1">
          <p
            class="text-sm text-n-slate-12 break-words whitespace-pre-line rounded-lg bg-n-alpha-1 px-3 py-2"
          >
            {{ comment.metadata?.body }}
          </p>
          <p class="text-[11px] text-n-slate-10 mt-1">
            <span v-if="comment.userName">{{ comment.userName }} · </span>
            {{ formatDate(comment.createdAt) }}
          </p>
        </div>
      </li>
    </ol>

    <p v-else class="text-sm text-n-slate-10 mb-4">
      {{ t('JABVOX_TASKS.TASK.COMMENTS.EMPTY') }}
    </p>

    <textarea
      v-model="body"
      rows="3"
      :placeholder="t('JABVOX_TASKS.TASK.HISTORY.COMMENT_PLACEHOLDER')"
      class="w-full rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-3 py-2 resize-y"
      @keydown.meta.enter="emit('submit')"
      @keydown.ctrl.enter="emit('submit')"
    />
    <div class="flex items-center justify-between mt-2">
      <span class="text-[11px] text-n-slate-10">
        {{ t('JABVOX_TASKS.TASK.HISTORY.COMMENT_HINT') }}
      </span>
      <button
        type="button"
        class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-n-brand text-white text-sm font-medium disabled:opacity-50"
        :disabled="!body.trim() || isSending"
        @click="emit('submit')"
      >
        <span class="i-lucide-message-square-plus size-4" aria-hidden="true" />
        {{ t('JABVOX_TASKS.TASK.HISTORY.COMMENT_SEND') }}
      </button>
    </div>
  </section>
</template>
