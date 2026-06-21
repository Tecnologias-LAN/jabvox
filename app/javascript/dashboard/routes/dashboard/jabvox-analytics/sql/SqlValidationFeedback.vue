<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  validation: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();

const isValid = computed(() => Boolean(props.validation?.valid));
</script>

<template>
  <div>
    <div
      v-if="validation"
      class="flex items-start gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm"
    >
      <span
        class="mt-0.5 size-4 shrink-0"
        :class="
          isValid
            ? 'i-lucide-circle-check text-n-teal-11'
            : 'i-lucide-circle-x text-n-ruby-11'
        "
      />
      <div class="min-w-0">
        <p
          class="font-medium"
          :class="isValid ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          {{
            isValid
              ? t('JABVOX_ANALYTICS.SQL.VALID')
              : t('JABVOX_ANALYTICS.SQL.INVALID')
          }}
        </p>
        <p v-if="validation.message" class="mt-0.5 break-words text-n-slate-11">
          {{ validation.message }}
        </p>
      </div>
    </div>
  </div>
</template>
