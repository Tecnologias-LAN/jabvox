<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { storeToRefs } from 'pinia';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';

const props = defineProps({
  modelValue: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const dashboardsStore = useAnalyticsDashboardsStore();
const { folderTree } = storeToRefs(dashboardsStore);

const form = computed(() => props.modelValue);

const update = (key, value) => {
  emit('update:modelValue', { ...props.modelValue, [key]: value });
};

// Flatten the folder tree into indented options for a plain <select>.
const flatFolders = computed(() => {
  const out = [];
  const walk = (folders, depth) => {
    (folders || []).forEach(folder => {
      out.push({
        id: folder.id,
        label: `${'— '.repeat(depth)}${folder.nameJabvox || folder.name}`,
      });
      walk(folder.children, depth + 1);
    });
  };
  walk(folderTree.value, 0);
  return out;
});

const rules = { nameJabvox: { required } };
const v$ = useVuelidate(rules, form);

defineExpose({ v$ });

const labelClass = 'mb-1 block text-sm font-medium text-n-slate-12';
const inputClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div class="flex flex-col gap-4">
    <div>
      <label :class="labelClass">
        {{ t('JABVOX_ANALYTICS.DASHBOARDS.FORM.NAME') }}
      </label>
      <input
        :value="form.nameJabvox"
        type="text"
        :class="inputClass"
        :placeholder="t('JABVOX_ANALYTICS.DASHBOARDS.FORM.NAME_PLACEHOLDER')"
        @input="update('nameJabvox', $event.target.value)"
      />
      <p v-if="v$.nameJabvox.$error" class="mt-1 text-xs text-n-ruby-11">
        {{ t('JABVOX_ANALYTICS.DASHBOARDS.FORM.REQUIRED') }}
      </p>
    </div>

    <div>
      <label :class="labelClass">
        {{ t('JABVOX_ANALYTICS.DASHBOARDS.FORM.DESCRIPTION') }}
      </label>
      <textarea
        :value="form.descriptionJabvox"
        rows="2"
        :class="inputClass"
        @input="update('descriptionJabvox', $event.target.value)"
      />
    </div>

    <div>
      <label :class="labelClass">
        {{ t('JABVOX_ANALYTICS.DASHBOARDS.FORM.FOLDER') }}
      </label>
      <select
        :value="form.folderId"
        :class="inputClass"
        @change="update('folderId', Number($event.target.value) || null)"
      >
        <option :value="null">
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.FORM.NO_FOLDER') }}
        </option>
        <option
          v-for="folder in flatFolders"
          :key="folder.id"
          :value="folder.id"
        >
          {{ folder.label }}
        </option>
      </select>
    </div>
  </div>
</template>
