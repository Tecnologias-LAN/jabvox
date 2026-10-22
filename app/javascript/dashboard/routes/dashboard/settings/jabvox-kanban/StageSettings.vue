<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import KanbanStageAutomationPanel from '../../jabvox-kanban/KanbanStageAutomationPanel.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const funnels = useMapGetter('jabvoxKanban/getFunnels');
const uiFlags = useMapGetter('jabvoxKanban/getUIFlags');

const funnelId = computed(() => parseInt(route.params.funnelId, 10));
const funnel = computed(() => funnels.value.find(f => f.id === funnelId.value));
const stages = computed(
  () =>
    funnel.value?.stages
      ?.slice()
      .sort((a, b) => a.position_jabvox - b.position_jabvox) || []
);

const formDialog = ref(null);
const deleteDialog = ref(null);
const editingStage = ref(null);
const deletingId = ref(null);
const automationStage = ref(null);

const defaultForm = () => ({
  name_jabvox: '',
  description_jabvox: '',
  color_jabvox: '#6B7280',
  auto_advance_enabled: false,
  auto_advance_hours: null,
  auto_advance_target_stage_id: null,
});
const form = ref(defaultForm());

onMounted(() => store.dispatch('jabvoxKanban/fetchFunnels'));

// Reordenar columnas (etapas) arrastrándolas. Orden HTML5 nativo, consistente con
// el resto del kanban. Al soltar, se persiste el nuevo orden en BD (reorderStages).
const dragStageId = ref(null);
const dragOverStageId = ref(null);

const onStageDragStart = stage => {
  dragStageId.value = stage.id;
};

const onStageDragOver = (event, stage) => {
  event.preventDefault();
  dragOverStageId.value = stage.id;
};

const onStageDrop = async targetStage => {
  const fromId = dragStageId.value;
  dragStageId.value = null;
  dragOverStageId.value = null;
  if (!fromId || fromId === targetStage.id) return;

  const ids = stages.value.map(s => s.id);
  const fromIdx = ids.indexOf(fromId);
  const toIdx = ids.indexOf(targetStage.id);
  if (fromIdx === -1 || toIdx === -1) return;

  ids.splice(toIdx, 0, ids.splice(fromIdx, 1)[0]);
  try {
    await store.dispatch('jabvoxKanban/reorderStages', {
      funnelId: funnelId.value,
      stageIds: ids,
    });
  } catch (error) {
    useAlert(t('JABVOX_KANBAN.SETTINGS.STAGES.REORDER_ERROR'));
    store.dispatch('jabvoxKanban/fetchFunnels');
  }
};

const otherStages = computed(() =>
  stages.value.filter(s => s.id !== editingStage.value?.id)
);
const targetStageOptions = computed(() => [
  {
    value: null,
    label: t(
      'JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.TARGET_PLACEHOLDER'
    ),
  },
  ...otherStages.value.map(s => ({ value: s.id, label: s.name_jabvox })),
]);

const isSubmitting = computed(
  () => uiFlags.value.isCreatingStage || uiFlags.value.isUpdatingStage
);
const isValid = computed(() => form.value.name_jabvox.trim().length > 0);

const openNew = () => {
  editingStage.value = null;
  form.value = defaultForm();
  formDialog.value?.open();
};

const openEdit = stage => {
  editingStage.value = stage;
  form.value = {
    name_jabvox: stage.name_jabvox,
    description_jabvox: stage.description_jabvox || '',
    color_jabvox: stage.color_jabvox,
    auto_advance_enabled: stage.auto_advance_enabled ?? false,
    auto_advance_hours: stage.auto_advance_hours ?? null,
    auto_advance_target_stage_id: stage.auto_advance_target_stage_id ?? null,
  };
  formDialog.value?.open();
};

const onSubmit = async () => {
  if (!isValid.value) {
    useAlert(t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.NAME_REQUIRED'));
    return;
  }
  const payload = { ...form.value };
  if (!payload.auto_advance_enabled) {
    payload.auto_advance_hours = null;
    payload.auto_advance_target_stage_id = null;
  }
  try {
    if (editingStage.value) {
      await store.dispatch('jabvoxKanban/updateStage', {
        funnelId: funnelId.value,
        stageId: editingStage.value.id,
        ...payload,
      });
      useAlert(t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.UPDATE_SUCCESS'));
    } else {
      await store.dispatch('jabvoxKanban/createStage', {
        funnelId: funnelId.value,
        ...payload,
      });
      useAlert(t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.CREATE_SUCCESS'));
    }
    formDialog.value?.close();
  } catch (error) {
    useAlert(error.message || t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.ERROR'));
  }
};

const askDelete = stage => {
  if (stages.value.length <= 1) {
    useAlert(t('JABVOX_KANBAN.SETTINGS.STAGES.CANNOT_DELETE_LAST'));
    return;
  }
  deleteDialog.value?.open({
    title: t('JABVOX_KANBAN.SETTINGS.STAGES.DELETE_TITLE'),
    description: t('JABVOX_KANBAN.SETTINGS.STAGES.DELETE_BODY', {
      name: stage.name_jabvox,
    }),
    data: stage,
  });
};
const doDelete = async stage => {
  deletingId.value = stage.id;
  try {
    await store.dispatch('jabvoxKanban/deleteStage', {
      funnelId: funnelId.value,
      stageId: stage.id,
    });
    useAlert(t('JABVOX_KANBAN.SETTINGS.STAGES.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(error.message || t('JABVOX_KANBAN.SETTINGS.STAGES.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};

const backToFunnels = () =>
  router.push({ name: 'jabvox_kanban_funnels_index' });
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-3xl flex flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-center gap-3 min-w-0">
          <Button
            icon="i-lucide-arrow-left"
            variant="ghost"
            color="slate"
            size="sm"
            @click="backToFunnels"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{
                t('JABVOX_KANBAN.SETTINGS.STAGES.TITLE', {
                  funnel: funnel?.name_jabvox || '',
                })
              }}
            </h1>
            <p class="mt-0.5 text-sm text-n-slate-11">
              {{ t('JABVOX_KANBAN.SETTINGS.STAGES.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_KANBAN.SETTINGS.STAGES.NEW_BUTTON')"
          class="shrink-0"
          @click="openNew"
        />
      </div>

      <!-- Loading -->
      <div
        v-if="uiFlags.isFetchingFunnels"
        class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
      </div>

      <!-- Empty -->
      <EmptyStateLayout
        v-else-if="!stages.length"
        :title="t('JABVOX_KANBAN.SETTINGS.STAGES.EMPTY_TITLE')"
        :subtitle="t('JABVOX_KANBAN.SETTINGS.STAGES.EMPTY')"
      >
        <template #actions>
          <Button
            icon="i-lucide-plus"
            :label="t('JABVOX_KANBAN.SETTINGS.STAGES.NEW_BUTTON')"
            size="sm"
            @click="openNew"
          />
        </template>
      </EmptyStateLayout>

      <!-- Stage list -->
      <div
        v-else
        class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm divide-y divide-n-weak overflow-hidden"
      >
        <div
          v-for="stage in stages"
          :key="stage.id"
          draggable="true"
          class="flex items-center gap-3 px-4 py-3 hover:bg-n-alpha-1 transition-colors"
          :class="{
            'ring-2 ring-inset ring-n-brand/40 bg-n-alpha-1':
              dragOverStageId === stage.id && dragStageId !== stage.id,
            'opacity-50': dragStageId === stage.id,
          }"
          @dragstart="onStageDragStart(stage)"
          @dragover="onStageDragOver($event, stage)"
          @dragleave="dragOverStageId = null"
          @drop="onStageDrop(stage)"
        >
          <!-- Agarre para arrastrar y reordenar la columna. -->
          <span
            class="i-lucide-grip-vertical size-4 text-n-slate-9 cursor-grab active:cursor-grabbing shrink-0"
            :title="t('JABVOX_KANBAN.SETTINGS.STAGES.DRAG_HINT')"
          />
          <span
            class="size-7 rounded-lg shrink-0 ring-1 ring-inset ring-n-weak"
            :style="{ backgroundColor: stage.color_jabvox }"
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ stage.name_jabvox }}
            </p>
            <p
              v-if="stage.description_jabvox"
              class="text-xs text-n-slate-10 truncate"
            >
              {{ stage.description_jabvox }}
            </p>
            <p
              v-if="stage.auto_advance_enabled && stage.auto_advance_hours"
              class="text-xs text-n-brand mt-0.5 inline-flex items-center gap-1"
            >
              <span class="i-lucide-timer size-3" />
              {{
                t('JABVOX_KANBAN.SETTINGS.STAGES.AUTO_ADVANCE_INDICATOR', {
                  hours: stage.auto_advance_hours,
                })
              }}
            </p>
          </div>
          <Button
            icon="i-lucide-zap"
            variant="ghost"
            color="slate"
            size="sm"
            :title="t('JABVOX_KANBAN.SETTINGS.STAGES.AUTOMATIONS_BUTTON')"
            @click="automationStage = stage"
          />
          <Button
            icon="i-lucide-pencil"
            variant="ghost"
            color="slate"
            size="sm"
            @click="openEdit(stage)"
          />
          <Button
            icon="i-lucide-trash-2"
            variant="ghost"
            color="ruby"
            size="sm"
            :is-loading="deletingId === stage.id"
            @click="askDelete(stage)"
          />
        </div>
      </div>
    </div>

    <!-- Stage form dialog -->
    <Dialog
      ref="formDialog"
      :title="
        editingStage
          ? t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.EDIT_TITLE')
          : t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.NEW_TITLE')
      "
      :confirm-button-label="
        editingStage
          ? t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.UPDATE_BUTTON')
          : t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.CREATE_BUTTON')
      "
      :cancel-button-label="t('JABVOX_KANBAN.COMMON.CANCEL')"
      :disable-confirm-button="!isValid"
      :is-loading="isSubmitting"
      width="lg"
      overflow-y-auto
      @confirm="onSubmit"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.name_jabvox"
          :label="t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.NAME_LABEL_REQUIRED')"
          autofocus
        />
        <Input
          v-model="form.description_jabvox"
          :label="t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.DESCRIPTION_LABEL')"
        />
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.COLOR_LABEL') }}
          </label>
          <div class="flex items-center gap-2">
            <input
              v-model="form.color_jabvox"
              type="color"
              class="w-10 h-9 rounded-lg cursor-pointer border border-n-weak p-0.5 bg-n-solid-1 shrink-0"
            />
            <div class="flex-1">
              <Input
                v-model="form.color_jabvox"
                size="sm"
                custom-input-class="font-mono"
              />
            </div>
          </div>
        </div>

        <!-- Auto-advance (edit only, needs other stages) -->
        <div
          v-if="editingStage && otherStages.length > 0"
          class="flex flex-col gap-3 border-t border-n-weak pt-4"
        >
          <p
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.TITLE') }}
          </p>
          <div
            class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
          >
            <span class="text-sm text-n-slate-12">
              {{
                t(
                  'JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.ENABLED_LABEL'
                )
              }}
            </span>
            <Switch v-model="form.auto_advance_enabled" />
          </div>
          <template v-if="form.auto_advance_enabled">
            <Input
              v-model.number="form.auto_advance_hours"
              type="number"
              min="1"
              :label="
                t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.HOURS_LABEL')
              "
            />
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{
                  t(
                    'JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.TARGET_LABEL'
                  )
                }}
              </label>
              <Select
                v-model="form.auto_advance_target_stage_id"
                :options="targetStageOptions"
              />
            </div>
          </template>
        </div>
      </div>
    </Dialog>

    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />

    <KanbanStageAutomationPanel
      v-if="automationStage"
      :stage="automationStage"
      :funnel-id="funnelId"
      @close="automationStage = null"
    />
  </div>
</template>
