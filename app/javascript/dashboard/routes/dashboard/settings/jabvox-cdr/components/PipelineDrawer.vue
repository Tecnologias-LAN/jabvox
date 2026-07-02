<script setup>
/* eslint-disable no-underscore-dangle */
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { cdrPipelinesAPI } from 'dashboard/api/jabvox/cdr';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SideDrawer from './SideDrawer.vue';

const props = defineProps({
  aiModels: { type: Array, default: () => [] },
  typifications: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();

const open = ref(false);
const saving = ref(false);
const editing = ref(null);

const title = computed(() =>
  editing.value?.id
    ? t('JABVOX_CDR.SETTINGS.PIPELINE.EDIT_TITLE')
    : t('JABVOX_CDR.SETTINGS.PIPELINE.NEW')
);

const transcriptionOptions = computed(() => [
  { value: null, label: t('JABVOX_CDR.SETTINGS.PIPELINE.NO_TRANSCRIPTION') },
  ...props.aiModels.map(m => ({ value: m.id, label: m.name_jabvox })),
]);
const typificationOptions = computed(() => [
  { value: null, label: t('JABVOX_CDR.SETTINGS.PIPELINE.NO_TYPIFICATION') },
  ...props.typifications.map(tp => ({ value: tp.id, label: tp.name })),
]);
const llmOptions = computed(() => [
  { value: null, label: t('JABVOX_CDR.SETTINGS.PIPELINE.DEFAULT_MODEL') },
  ...props.aiModels.map(m => ({ value: m.id, label: m.name_jabvox })),
]);
const timestampModeOptions = computed(() => [
  { value: 'none', label: t('JABVOX_CDR.SETTINGS.PIPELINE.TS_NONE') },
  { value: 'word', label: t('JABVOX_CDR.SETTINGS.PIPELINE.TS_WORD') },
  { value: 'segment', label: t('JABVOX_CDR.SETTINGS.PIPELINE.TS_SEGMENT') },
]);

const visibleStages = computed(() =>
  (editing.value?.stages || []).filter(s => !s._destroy)
);

const openCreate = () => {
  editing.value = {
    name: '',
    is_default: false,
    transcription_model_id: null,
    typification_id: null,
    timestamp_mode_jabvox: 'none',
    segment_seconds_jabvox: 30,
    stages: [],
  };
  open.value = true;
};

const openEdit = pipeline => {
  editing.value = JSON.parse(JSON.stringify(pipeline));
  open.value = true;
};

const close = () => {
  open.value = false;
};

const addStage = () => {
  editing.value.stages.push({
    name: '',
    prompt: '',
    min_score: 50,
    llm_model_id: null,
    position: editing.value.stages.length,
  });
};

const removeStage = stage => {
  if (stage.id) {
    stage._destroy = true;
  } else {
    editing.value.stages = editing.value.stages.filter(s => s !== stage);
  }
};

const handleSave = async () => {
  if (!editing.value.name.trim()) {
    useAlert(t('JABVOX_CDR.SETTINGS.PIPELINE.NAME_REQUIRED'));
    return;
  }
  if (!visibleStages.value.length) {
    useAlert(t('JABVOX_CDR.SETTINGS.PIPELINE.STAGES_REQUIRED'));
    return;
  }
  saving.value = true;
  const payload = {
    name: editing.value.name.trim(),
    is_default: editing.value.is_default,
    transcription_model_id: editing.value.transcription_model_id,
    typification_id: editing.value.typification_id,
    timestamp_mode_jabvox: editing.value.timestamp_mode_jabvox || 'none',
    segment_seconds_jabvox: editing.value.segment_seconds_jabvox || 30,
    stages_attributes: editing.value.stages.map((s, i) => ({
      id: s.id,
      name: s.name,
      prompt: s.prompt,
      min_score: s.min_score,
      llm_model_id: s.llm_model_id,
      position: i,
      _destroy: s._destroy,
    })),
  };
  try {
    if (editing.value.id) {
      await cdrPipelinesAPI.update(editing.value.id, payload);
    } else {
      await cdrPipelinesAPI.create(payload);
    }
    close();
    useAlert(t('JABVOX_CDR.SETTINGS.SAVED'));
    emit('saved');
  } catch {
    useAlert(t('JABVOX_CDR.SETTINGS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

defineExpose({ openCreate, openEdit, close });
</script>

<template>
  <SideDrawer v-model:open="open" :title="title">
    <div v-if="editing" class="flex flex-col gap-6">
      <!-- Pipeline meta -->
      <section class="flex flex-col gap-4">
        <Input
          v-model="editing.name"
          :label="t('JABVOX_CDR.SETTINGS.PIPELINE.NAME')"
          autofocus
        />
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_CDR.SETTINGS.PIPELINE.TRANSCRIPTION_MODEL') }}
            </label>
            <Select
              v-model="editing.transcription_model_id"
              :options="transcriptionOptions"
            />
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_CDR.SETTINGS.PIPELINE.TYPIFICATION') }}
            </label>
            <Select
              v-model="editing.typification_id"
              :options="typificationOptions"
            />
          </div>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_CDR.SETTINGS.PIPELINE.TIMESTAMP_MODE') }}
            </label>
            <Select
              v-model="editing.timestamp_mode_jabvox"
              :options="timestampModeOptions"
            />
          </div>
          <div
            v-if="editing.timestamp_mode_jabvox === 'segment'"
            class="flex flex-col gap-1.5"
          >
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_CDR.SETTINGS.PIPELINE.SEGMENT_SECONDS') }}
            </label>
            <input
              v-model="editing.segment_seconds_jabvox"
              type="number"
              min="1"
              max="600"
              class="reset-base text-sm w-full rounded-lg border border-n-weak bg-n-alpha-black1 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
            />
          </div>
        </div>

        <div
          class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_CDR.SETTINGS.PIPELINE.SET_DEFAULT') }}
          </span>
          <Switch v-model="editing.is_default" />
        </div>
      </section>

      <!-- Stages -->
      <section class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <h3
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_CDR.SETTINGS.PIPELINE.STAGES') }}
          </h3>
          <Button
            :label="t('JABVOX_CDR.SETTINGS.PIPELINE.ADD_STAGE')"
            icon="i-lucide-plus"
            variant="outline"
            color="slate"
            size="sm"
            @click="addStage"
          />
        </div>

        <div
          v-for="(stage, index) in visibleStages"
          :key="stage.id ?? `new-${index}`"
          class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-3"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="text-xs font-medium text-n-slate-10">
              {{
                t('JABVOX_CDR.SETTINGS.PIPELINE.STAGE_NUMBER', { n: index + 1 })
              }}
            </span>
            <Button
              icon="i-lucide-trash-2"
              variant="ghost"
              color="ruby"
              size="sm"
              @click="removeStage(stage)"
            />
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
            <div class="sm:col-span-2">
              <Input
                v-model="stage.name"
                size="sm"
                :placeholder="t('JABVOX_CDR.SETTINGS.PIPELINE.STAGE_NAME')"
              />
            </div>
            <Input
              v-model.number="stage.min_score"
              type="number"
              size="sm"
              min="0"
              max="100"
              :placeholder="t('JABVOX_CDR.SETTINGS.PIPELINE.MIN_SCORE')"
            />
          </div>
          <textarea
            v-model="stage.prompt"
            rows="3"
            :placeholder="t('JABVOX_CDR.SETTINGS.PIPELINE.PROMPT')"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y"
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_CDR.SETTINGS.PIPELINE.LLM_MODEL') }}
            </label>
            <Select v-model="stage.llm_model_id" :options="llmOptions" />
          </div>
        </div>
      </section>
    </div>

    <template #footer>
      <div class="flex items-center justify-end gap-2">
        <Button
          :label="t('JABVOX_CDR.SETTINGS.COMMON.CANCEL')"
          variant="outline"
          color="slate"
          @click="close"
        />
        <Button
          :label="t('JABVOX_CDR.SETTINGS.COMMON.SAVE')"
          :is-loading="saving"
          @click="handleSave"
        />
      </div>
    </template>
  </SideDrawer>
</template>
