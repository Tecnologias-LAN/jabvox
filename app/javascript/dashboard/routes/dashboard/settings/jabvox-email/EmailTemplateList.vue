<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConfirmDeleteDialog from './components/ConfirmDeleteDialog.vue';

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

const deleteDialog = ref(null);

const askDelete = template => {
  deleteDialog.value?.open({
    title: t('JABVOX_EMAIL.TEMPLATES.DELETE'),
    description: t('JABVOX_EMAIL.TEMPLATES.CONFIRM_DELETE', {
      name: template.name,
    }),
    data: template.id,
  });
};

const doDelete = async id => {
  try {
    await store.dispatch('jabvoxEmail/deleteTemplate', id);
    useAlert(t('JABVOX_EMAIL.TEMPLATES.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_EMAIL.TEMPLATES.DELETE_ERROR'));
  }
};
</script>

<template>
  <div class="h-full flex flex-col">
    <div
      class="flex items-center justify-between px-4 py-4 border-b border-n-weak shrink-0"
    >
      <p class="text-xs text-n-slate-11 tabular-nums">
        {{ `${meta.count}/${meta.limit}` }}
        {{ t('JABVOX_EMAIL.TEMPLATES.COUNTER') }}
      </p>
      <Button
        icon="i-lucide-plus"
        :label="t('JABVOX_EMAIL.TEMPLATES.NEW')"
        size="sm"
        :disabled="atLimit"
        @click="emit('new')"
      />
    </div>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetchingTemplates"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
      {{ t('JABVOX_EMAIL.TEMPLATES.LOADING') }}
    </div>

    <!-- Empty -->
    <div
      v-else-if="!templates.length"
      class="flex flex-col items-center justify-center text-center py-12 px-4 gap-3 text-n-slate-11"
    >
      <span class="i-lucide-layout-template size-7 text-n-slate-10" />
      <p class="text-sm">{{ t('JABVOX_EMAIL.TEMPLATES.EMPTY') }}</p>
      <Button
        icon="i-lucide-plus"
        :label="t('JABVOX_EMAIL.TEMPLATES.NEW')"
        size="sm"
        :disabled="atLimit"
        @click="emit('new')"
      />
    </div>

    <div v-else class="flex-1 overflow-y-auto">
      <div class="flex flex-col gap-2 p-3">
        <button
          v-for="tpl in templates"
          :key="tpl.id"
          type="button"
          class="w-full text-left rounded-xl border px-3 py-3 transition-colors"
          :class="
            Number(selectedId) === Number(tpl.id)
              ? 'border-n-brand bg-n-alpha-2'
              : 'border-n-weak hover:bg-n-alpha-1'
          "
          @click="emit('select', tpl)"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="font-medium text-sm text-n-slate-12 truncate">
              {{ tpl.name }}
            </span>
            <Label
              v-if="!tpl.active"
              :label="t('JABVOX_EMAIL.TEMPLATES.INACTIVE')"
              color="slate"
              compact
            />
          </div>
          <p class="text-xs text-n-slate-11 mt-1 truncate">
            {{ tpl.subject }}
          </p>
          <div class="flex items-center gap-1 mt-3">
            <Button
              icon="i-lucide-pencil"
              :label="t('JABVOX_EMAIL.TEMPLATES.EDIT')"
              variant="outline"
              color="slate"
              size="sm"
              @click.stop="emit('edit', tpl)"
            />
            <Button
              icon="i-lucide-trash-2"
              variant="ghost"
              color="ruby"
              size="sm"
              @click.stop="askDelete(tpl)"
            />
          </div>
        </button>
      </div>
    </div>

    <ConfirmDeleteDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
