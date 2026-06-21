<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  columns: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();
</script>

<template>
  <div class="overflow-x-auto">
    <table class="w-full text-xs">
      <thead>
        <tr class="text-left text-n-slate-10">
          <th class="py-1.5 pr-4 font-medium">
            {{ t('JABVOX_ANALYTICS.COMMON.NAME') }}
          </th>
          <th class="py-1.5 pr-4 font-medium">
            {{ t('JABVOX_ANALYTICS.SCHEMA.TYPE') }}
          </th>
          <th class="py-1.5 font-medium" />
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="column in columns"
          :key="column.name"
          class="border-t border-n-weak"
        >
          <td class="py-1.5 pr-4 font-medium text-n-slate-12">
            {{ column.name }}
          </td>
          <td class="py-1.5 pr-4 text-n-slate-11">{{ column.type }}</td>
          <td class="py-1.5">
            <span class="flex flex-wrap gap-1">
              <span
                v-if="column.primaryKey"
                class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-n-blue-11"
              >
                {{ t('JABVOX_ANALYTICS.SCHEMA.PRIMARY_KEY') }}
              </span>
              <span
                v-if="column.foreignKey"
                class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-n-teal-11"
              >
                {{ t('JABVOX_ANALYTICS.SCHEMA.FOREIGN_KEY') }}
              </span>
              <span
                v-if="column.nullable"
                class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-n-slate-10"
              >
                {{ t('JABVOX_ANALYTICS.SCHEMA.NULLABLE') }}
              </span>
              <span
                v-if="column.length"
                class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-n-slate-10"
              >
                {{
                  t('JABVOX_ANALYTICS.SCHEMA.LENGTH_VALUE', {
                    length: column.length,
                  })
                }}
              </span>
            </span>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
