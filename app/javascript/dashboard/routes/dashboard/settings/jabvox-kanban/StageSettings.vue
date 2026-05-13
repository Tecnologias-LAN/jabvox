<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import KanbanStageAutomationPanel from '../../jabvox-kanban/KanbanStageAutomationPanel.vue';

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

const showForm = ref(false);
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

const openNew = () => {
  editingStage.value = null;
  form.value = defaultForm();
  showForm.value = true;
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
  showForm.value = true;
};

const onCancel = () => {
  showForm.value = false;
  editingStage.value = null;
  form.value = defaultForm();
};

const isSubmitting = computed(
  () => uiFlags.value.isCreatingStage || uiFlags.value.isUpdatingStage
);

const otherStages = computed(() =>
  stages.value.filter(s => s.id !== editingStage.value?.id)
);

const onSubmit = async () => {
  if (!form.value.name_jabvox.trim()) {
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
    onCancel();
  } catch (error) {
    useAlert(error.message || t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.ERROR'));
  }
};

const onDelete = async stage => {
  if (stages.value.length <= 1) {
    useAlert(t('JABVOX_KANBAN.SETTINGS.STAGES.CANNOT_DELETE_LAST'));
    return;
  }
  if (
    !window.confirm(
      t('JABVOX_KANBAN.SETTINGS.STAGES.DELETE_CONFIRM', {
        name: stage.name_jabvox,
      })
    )
  )
    return;
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
  <SettingsLayout>
    <div class="px-4 sm:px-6 lg:px-8 pb-6 pt-3 sm:pt-4">
      <BaseSettingsHeader
        :title="
          $t('JABVOX_KANBAN.SETTINGS.STAGES.TITLE', {
            funnel: funnel?.name_jabvox || '',
          })
        "
        :description="$t('JABVOX_KANBAN.SETTINGS.STAGES.DESCRIPTION')"
      >
        <template #actions>
          <Button
            variant="ghost"
            icon="i-lucide-arrow-left"
            :label="$t('JABVOX_KANBAN.SETTINGS.STAGES.BACK')"
            @click="backToFunnels"
          />
          <Button
            icon="i-lucide-plus"
            :label="$t('JABVOX_KANBAN.SETTINGS.STAGES.NEW_BUTTON')"
            @click="openNew"
          />
        </template>
      </BaseSettingsHeader>

      <div class="max-w-3xl mx-auto">
        <div
          v-if="showForm"
          class="mt-6 p-5 sm:p-6 border border-slate-200 dark:border-slate-700 rounded-2xl bg-white dark:bg-slate-800 shadow-sm space-y-4"
        >
          <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-200">
            {{
              editingStage
                ? $t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.EDIT_TITLE')
                : $t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.NEW_TITLE')
            }}
          </h3>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ $t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.NAME_LABEL_REQUIRED') }}
            </label>
            <input
              v-model="form.name_jabvox"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 text-slate-700 dark:text-slate-200"
            />
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ $t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.COLOR_LABEL') }}
            </label>
            <div class="flex items-center gap-2">
              <input
                v-model="form.color_jabvox"
                type="color"
                class="w-10 h-10 rounded cursor-pointer border-0"
              />
              <span class="text-sm text-slate-500 font-mono">{{
                form.color_jabvox
              }}</span>
            </div>
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ $t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.DESCRIPTION_LABEL') }}
            </label>
            <input
              v-model="form.description_jabvox"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 text-slate-700 dark:text-slate-200"
            />
          </div>

          <!-- Auto-advance section (edit only) -->
          <div
            v-if="editingStage && otherStages.length > 0"
            class="border-t border-slate-200 dark:border-slate-700 pt-4 space-y-3"
          >
            <p
              class="text-xs font-semibold text-slate-600 dark:text-slate-400 uppercase tracking-wide"
            >
              {{ $t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.TITLE') }}
            </p>

            <label class="flex items-center gap-2 cursor-pointer">
              <input
                v-model="form.auto_advance_enabled"
                type="checkbox"
                class="rounded"
              />
              <span class="text-sm text-slate-700 dark:text-slate-300">
                {{
                  $t(
                    'JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.ENABLED_LABEL'
                  )
                }}
              </span>
            </label>

            <template v-if="form.auto_advance_enabled">
              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                >
                  {{
                    $t(
                      'JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.HOURS_LABEL'
                    )
                  }}
                </label>
                <input
                  v-model.number="form.auto_advance_hours"
                  type="number"
                  min="1"
                  class="w-32 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 text-slate-700 dark:text-slate-200"
                />
              </div>

              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                >
                  {{
                    $t(
                      'JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.TARGET_LABEL'
                    )
                  }}
                </label>
                <select
                  v-model.number="form.auto_advance_target_stage_id"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 text-slate-700 dark:text-slate-200"
                >
                  <option value="" disabled>
                    {{
                      $t(
                        'JABVOX_KANBAN.SETTINGS.STAGES.FORM.AUTO_ADVANCE.TARGET_PLACEHOLDER'
                      )
                    }}
                  </option>
                  <option v-for="s in otherStages" :key="s.id" :value="s.id">
                    {{ s.name_jabvox }}
                  </option>
                </select>
              </div>
            </template>
          </div>

          <div class="flex flex-wrap gap-2">
            <Button
              size="small"
              :label="
                editingStage
                  ? $t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.UPDATE_BUTTON')
                  : $t('JABVOX_KANBAN.SETTINGS.STAGES.FORM.CREATE_BUTTON')
              "
              :is-loading="isSubmitting"
              @click="onSubmit"
            />
            <Button
              size="small"
              variant="ghost"
              :label="$t('CANCEL')"
              @click="onCancel"
            />
          </div>
        </div>

        <div class="mt-6 space-y-3">
          <div
            v-for="stage in stages"
            :key="stage.id"
            class="flex flex-wrap items-center justify-between gap-3 p-4 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 shadow-sm"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span
                class="w-4 h-4 rounded-full shrink-0"
                :style="{ backgroundColor: stage.color_jabvox }"
              />
              <div class="min-w-0">
                <p
                  class="text-sm font-medium text-slate-800 dark:text-slate-100 truncate"
                >
                  {{ stage.name_jabvox }}
                </p>
                <p
                  v-if="stage.description_jabvox"
                  class="text-xs text-slate-500"
                >
                  {{ stage.description_jabvox }}
                </p>
                <p
                  v-if="stage.auto_advance_enabled && stage.auto_advance_hours"
                  class="text-xs text-woot-500 mt-0.5"
                >
                  {{
                    $t('JABVOX_KANBAN.SETTINGS.STAGES.AUTO_ADVANCE_INDICATOR', {
                      hours: stage.auto_advance_hours,
                    })
                  }}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-1">
              <Button
                size="small"
                variant="ghost"
                icon="i-lucide-zap"
                :label="$t('JABVOX_KANBAN.SETTINGS.STAGES.AUTOMATIONS_BUTTON')"
                @click="automationStage = stage"
              />
              <Button
                size="small"
                variant="ghost"
                icon="i-lucide-pencil"
                @click="openEdit(stage)"
              />
              <Button
                size="small"
                variant="ghost"
                color-scheme="alert"
                icon="i-lucide-trash-2"
                :is-loading="deletingId === stage.id"
                @click="onDelete(stage)"
              />
            </div>
          </div>

          <div
            v-if="stages.length === 0"
            class="flex items-center justify-center py-8 text-slate-400 dark:text-slate-600 text-sm"
          >
            {{ $t('JABVOX_KANBAN.SETTINGS.STAGES.EMPTY') }}
          </div>
        </div>
      </div>
    </div>
  </SettingsLayout>

  <KanbanStageAutomationPanel
    v-if="automationStage"
    :stage="automationStage"
    :funnel-id="funnelId"
    @close="automationStage = null"
  />
</template>
