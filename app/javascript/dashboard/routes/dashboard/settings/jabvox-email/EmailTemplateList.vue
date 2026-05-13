<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

defineProps({
  selectedId: {
    type: [Number, String],
    default: null,
  },
});
const emit = defineEmits(['new', 'edit', 'select']);
const store = useStore();
const { t } = useI18n();

const templates = computed(() => store.getters['jabvoxEmail/getTemplates']);
const meta = computed(() => store.getters['jabvoxEmail/getTemplatesMeta']);
const uiFlags = computed(() => store.getters['jabvoxEmail/getUIFlags']);

const atLimit = computed(() => meta.value.count >= meta.value.limit);

const onDelete = async template => {
  if (
    !window.confirm(
      t('JABVOX_EMAIL.TEMPLATES.CONFIRM_DELETE', {
        name: template.name,
      })
    )
  )
    return;
  try {
    await store.dispatch('jabvoxEmail/deleteTemplate', template.id);
    useAlert(t('JABVOX_EMAIL.TEMPLATES.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_EMAIL.TEMPLATES.DELETE_ERROR'));
  }
};
</script>

<template>
  <div class="h-full flex flex-col">
    <div
      class="flex items-center justify-between px-4 py-4 border-b border-slate-200 dark:border-slate-700"
    >
      <p class="text-xs text-slate-500 dark:text-slate-400">
        {{ `${meta.count}/${meta.limit}` }}
        {{ $t('JABVOX_EMAIL.TEMPLATES.COUNTER') }}
      </p>
      <button
        :disabled="atLimit"
        class="px-3 py-1.5 bg-woot-500 hover:bg-woot-600 text-white text-xs font-medium rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        @click="emit('new')"
      >
        {{ $t('JABVOX_EMAIL.TEMPLATES.NEW') }}
      </button>
    </div>

    <div
      v-if="uiFlags.isFetchingTemplates"
      class="text-center py-12 text-slate-400"
    >
      {{ $t('JABVOX_EMAIL.TEMPLATES.LOADING') }}
    </div>

    <div
      v-else-if="!templates.length"
      class="text-center py-12 text-slate-400 px-4"
    >
      <p>{{ $t('JABVOX_EMAIL.TEMPLATES.EMPTY') }}</p>
    </div>

    <div v-else class="flex-1 overflow-y-auto">
      <div class="grid gap-2 p-3">
        <button
          v-for="tpl in templates"
          :key="tpl.id"
          type="button"
          class="w-full text-left rounded-xl border px-3 py-3 transition-colors"
          :class="
            Number(selectedId) === Number(tpl.id)
              ? 'border-woot-500 bg-woot-50/70 dark:bg-woot-900/20'
              : 'border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-700/40'
          "
          @click="emit('select', tpl)"
        >
          <div class="flex items-center justify-between gap-2">
            <span
              class="font-medium text-sm text-slate-800 dark:text-slate-100 truncate"
            >
              {{ tpl.name }}
            </span>
            <span
              v-if="!tpl.active"
              class="text-[11px] px-1.5 py-0.5 rounded bg-slate-100 dark:bg-slate-700 text-slate-500"
            >
              {{ $t('JABVOX_EMAIL.TEMPLATES.INACTIVE') }}
            </span>
          </div>
          <p class="text-xs text-slate-500 dark:text-slate-400 mt-1 truncate">
            {{ tpl.subject }}
          </p>
          <div class="flex items-center gap-2 mt-3">
            <button
              type="button"
              class="text-xs px-2.5 py-1 rounded-lg border border-slate-200 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
              @click.stop="emit('edit', tpl)"
            >
              {{ $t('JABVOX_EMAIL.TEMPLATES.EDIT') }}
            </button>
            <button
              type="button"
              class="text-xs px-2.5 py-1 rounded-lg border border-ruby-200 dark:border-ruby-800 text-ruby-600 dark:text-ruby-400 hover:bg-ruby-50 dark:hover:bg-ruby-900/20 transition-colors"
              @click.stop="onDelete(tpl)"
            >
              {{ $t('JABVOX_EMAIL.TEMPLATES.DELETE') }}
            </button>
          </div>
        </button>
      </div>
    </div>
  </div>
</template>
