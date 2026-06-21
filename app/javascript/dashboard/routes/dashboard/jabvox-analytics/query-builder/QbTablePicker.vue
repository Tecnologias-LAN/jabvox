<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  modelValue: {
    type: String,
    default: null,
  },
  tables: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
</script>

<template>
  <div>
    <label class="mb-1 block text-sm font-medium text-n-slate-12">
      {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.TABLE') }}
    </label>
    <select
      :value="modelValue"
      class="block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong"
      @change="emit('update:modelValue', $event.target.value)"
    >
      <option :value="null" disabled>
        {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.TABLE') }}
      </option>
      <option v-for="tbl in tables" :key="tbl.name" :value="tbl.name">
        {{ tbl.name }}
      </option>
    </select>
  </div>
</template>
