<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import { DESTROY_KEY } from 'dashboard/helper/jabvox/nestedAttributes';
import SettingsCard from './SettingsCard.vue';

const props = defineProps({
  pipelines: { type: Array, default: () => [] },
  aiModels: { type: Array, default: () => [] },
  typifications: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'new',
  'edit',
  'delete',
  'save',
  'cancel',
  'add-stage',
  'remove-stage',
]);

// The pipeline being created/edited (null when listing). v-model so the editor
// inputs/stages mutate it directly; the parent watches the same object.
const editing = defineModel('editing', { type: Object, default: null });

const { t } = useI18n();

// Select option lists (value/label) derived from the reused AI models + typifications.
const modelOptions = computed(() => [
  { value: null, label: t('JABVOX_AUDIO.PIPELINE.NO_TRANSCRIPTION') },
  ...props.aiModels.map(m => ({ value: m.id, label: m.name_jabvox })),
]);
const stageModelOptions = computed(() => [
  { value: null, label: t('JABVOX_AUDIO.PIPELINE.DEFAULT_MODEL') },
  ...props.aiModels.map(m => ({ value: m.id, label: m.name_jabvox })),
]);
const typificationOptions = computed(() => [
  { value: null, label: t('JABVOX_AUDIO.PIPELINE.NO_TYPIFICATION') },
  ...props.typifications.map(tp => ({ value: tp.id, label: tp.name })),
]);

const visibleStageCount = computed(
  () => editing.value?.stages?.filter(s => !s[DESTROY_KEY]).length || 0
);

// Transcript timestamp granularity: none / per-word / per-segment.
const timestampModeOptions = computed(() => [
  { value: 'none', label: t('JABVOX_AUDIO.PIPELINE.TS_NONE') },
  { value: 'word', label: t('JABVOX_AUDIO.PIPELINE.TS_WORD') },
  { value: 'segment', label: t('JABVOX_AUDIO.PIPELINE.TS_SEGMENT') },
]);
</script>

<template>
  <!-- List view -->
  <SettingsCard
    v-if="!editing"
    :title="t('JABVOX_AUDIO.PIPELINE.TITLE')"
    :description="t('JABVOX_AUDIO.PIPELINE.SUBTITLE')"
    icon="i-lucide-workflow"
  >
    <template #actions>
      <Button
        :label="t('JABVOX_AUDIO.PIPELINE.NEW')"
        icon="i-lucide-plus"
        size="sm"
        @click="emit('new')"
      />
    </template>

    <div v-if="pipelines.length" class="flex flex-col gap-2">
      <div
        v-for="p in pipelines"
        :key="p.id"
        class="flex items-center justify-between gap-3 rounded-xl border border-n-weak px-4 py-3 transition-colors hover:bg-n-alpha-1"
      >
        <div class="flex items-center gap-3 min-w-0">
          <span
            class="flex items-center justify-center size-8 rounded-lg bg-n-alpha-2 text-n-slate-11 shrink-0"
          >
            <span class="i-lucide-git-branch size-4" />
          </span>
          <p class="text-sm font-medium text-n-slate-12 truncate">
            {{ p.name }}
          </p>
        </div>
        <div class="flex items-center gap-1 shrink-0">
          <Label
            v-if="p.is_default"
            :label="t('JABVOX_AUDIO.PIPELINE.DEFAULT')"
            color="teal"
            compact
          />
          <Button
            icon="i-lucide-pencil"
            variant="ghost"
            color="slate"
            size="sm"
            @click="emit('edit', p)"
          />
          <Button
            icon="i-lucide-trash-2"
            variant="ghost"
            color="ruby"
            size="sm"
            @click="emit('delete', p.id)"
          />
        </div>
      </div>
    </div>

    <EmptyStateLayout
      v-else
      :title="t('JABVOX_AUDIO.PIPELINE.EMPTY_TITLE')"
      :subtitle="t('JABVOX_AUDIO.PIPELINE.EMPTY_SUBTITLE')"
      :show-backdrop="false"
    >
      <template #actions>
        <Button
          :label="t('JABVOX_AUDIO.PIPELINE.NEW')"
          icon="i-lucide-plus"
          @click="emit('new')"
        />
      </template>
    </EmptyStateLayout>
  </SettingsCard>

  <!-- Editor view -->
  <SettingsCard
    v-else
    :title="
      editing.id
        ? t('JABVOX_AUDIO.PIPELINE.EDIT_TITLE')
        : t('JABVOX_AUDIO.PIPELINE.NEW')
    "
    icon="i-lucide-workflow"
  >
    <div class="flex flex-col gap-5">
      <Input
        v-model="editing.name"
        :label="t('JABVOX_AUDIO.PIPELINE.NAME')"
        :placeholder="t('JABVOX_AUDIO.PIPELINE.NAME')"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="flex flex-col gap-1.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AUDIO.PIPELINE.TRANSCRIPTION_MODEL') }}
          </span>
          <Select
            v-model="editing.transcription_model_id"
            :options="modelOptions"
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AUDIO.PIPELINE.TYPIFICATION') }}
          </span>
          <Select
            v-model="editing.typification_id"
            :options="typificationOptions"
          />
        </div>
      </div>

      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_AUDIO.PIPELINE.TRANSCRIPTION_PROMPT') }}
        </span>
        <textarea
          v-model="editing.transcription_prompt"
          rows="2"
          class="reset-base text-sm w-full rounded-lg border border-n-weak bg-n-alpha-black1 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
          :placeholder="t('JABVOX_AUDIO.PIPELINE.TRANSCRIPTION_PROMPT')"
        />
      </div>

      <!-- Transcript timestamps -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="flex flex-col gap-1.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AUDIO.PIPELINE.TIMESTAMP_MODE') }}
          </span>
          <Select
            v-model="editing.timestamp_mode_jabvox"
            :options="timestampModeOptions"
          />
        </div>
        <div
          v-if="editing.timestamp_mode_jabvox === 'segment'"
          class="flex flex-col gap-1.5"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AUDIO.PIPELINE.SEGMENT_SECONDS') }}
          </span>
          <Input
            v-model="editing.segment_seconds_jabvox"
            type="number"
            min="1"
            max="600"
          />
        </div>
      </div>

      <label
        class="flex items-center justify-between gap-3 rounded-xl border border-n-weak px-4 py-3"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_AUDIO.PIPELINE.SET_DEFAULT') }}
        </span>
        <Switch v-model="editing.is_default" />
      </label>

      <!-- Stages -->
      <div class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <span class="text-sm font-semibold text-n-slate-12">
            {{ t('JABVOX_AUDIO.PIPELINE.STAGES_TITLE') }}
            <span class="text-n-slate-10 font-normal">
              ({{ visibleStageCount }})
            </span>
          </span>
          <Button
            :label="t('JABVOX_AUDIO.PIPELINE.ADD_STAGE')"
            icon="i-lucide-plus"
            variant="outline"
            color="slate"
            size="sm"
            @click="emit('add-stage')"
          />
        </div>

        <div
          v-for="(stage, index) in editing.stages"
          v-show="!stage['_destroy']"
          :key="index"
          class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 flex flex-col gap-3"
        >
          <div class="flex items-center gap-2">
            <span
              class="flex items-center justify-center size-6 rounded-md bg-n-brand/10 text-n-brand text-xs font-semibold shrink-0"
            >
              {{ index + 1 }}
            </span>
            <Input
              v-model="stage.name"
              size="sm"
              class="flex-1"
              :placeholder="t('JABVOX_AUDIO.PIPELINE.STAGE_NAME')"
            />
            <div class="w-24">
              <Input
                v-model.number="stage.min_score"
                type="number"
                size="sm"
                min="0"
                max="100"
                :placeholder="t('JABVOX_AUDIO.PIPELINE.MIN_SCORE')"
              />
            </div>
            <Button
              icon="i-lucide-trash-2"
              variant="ghost"
              color="ruby"
              size="sm"
              @click="emit('remove-stage', index)"
            />
          </div>
          <textarea
            v-model="stage.prompt"
            rows="3"
            class="reset-base text-sm w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
            :placeholder="t('JABVOX_AUDIO.PIPELINE.PROMPT')"
          />
          <div class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_AUDIO.PIPELINE.LLM_MODEL') }}
            </span>
            <Select v-model="stage.llm_model_id" :options="stageModelOptions" />
          </div>
        </div>
      </div>

      <div class="flex items-center gap-2 pt-1">
        <Button :label="t('JABVOX_AUDIO.SAVE')" @click="emit('save')" />
        <Button
          :label="t('JABVOX_AUDIO.CANCEL')"
          variant="ghost"
          color="slate"
          @click="emit('cancel')"
        />
      </div>
    </div>
  </SettingsCard>
</template>
