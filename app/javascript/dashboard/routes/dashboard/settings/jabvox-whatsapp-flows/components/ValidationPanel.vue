<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  errors: { type: Array, default: () => [] },
  validating: { type: Boolean, default: false },
  validated: { type: Boolean, default: false },
});

const emit = defineEmits(['go-to-field']);

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <div class="px-3 py-2 border-b border-n-weak shrink-0">
      <h3 class="text-xs font-semibold uppercase tracking-wide text-n-slate-10">
        {{ t('JABVOX_WA_FLOWS.BUILDER.VALIDATION.TITLE') }}
      </h3>
    </div>

    <div class="flex-1 overflow-y-auto p-3">
      <div
        v-if="validating"
        class="flex items-center gap-2 text-sm text-n-slate-10"
      >
        <span
          class="i-lucide-loader-2 animate-spin size-4"
          aria-hidden="true"
        />
        {{ t('JABVOX_WA_FLOWS.BUILDER.VALIDATION.RUNNING') }}
      </div>

      <div v-else-if="!validated" class="text-sm text-n-slate-10">
        {{ t('JABVOX_WA_FLOWS.BUILDER.VALIDATION.NOT_RUN') }}
      </div>

      <div
        v-else-if="!errors.length"
        class="flex items-center gap-2 text-sm text-n-teal-11"
      >
        <span class="i-lucide-check-circle-2 size-4" aria-hidden="true" />
        {{ t('JABVOX_WA_FLOWS.BUILDER.VALIDATION.NO_ERRORS') }}
      </div>

      <ul v-else class="flex flex-col gap-2">
        <li
          v-for="(error, index) in errors"
          :key="index"
          class="rounded-lg border border-n-ruby-11/30 bg-n-ruby-11/5 p-2.5"
        >
          <div class="flex items-start gap-2">
            <span
              class="i-lucide-alert-triangle size-4 text-n-ruby-11 shrink-0 mt-0.5"
              aria-hidden="true"
            />
            <div class="flex-1 min-w-0">
              <p class="text-xs text-n-slate-12">{{ error.message }}</p>
              <p
                v-if="error.screen_id"
                class="text-[11px] text-n-slate-9 mt-0.5"
              >
                {{ t('JABVOX_WA_FLOWS.BUILDER.VALIDATION.SCREEN_LABEL') }}:
                {{ error.screen_id }}
                <template v-if="error.component_id">
                  ·
                  {{ t('JABVOX_WA_FLOWS.BUILDER.VALIDATION.COMPONENT_LABEL') }}:
                  {{ error.component_id }}
                </template>
              </p>
              <button
                v-if="error.screen_id"
                type="button"
                class="text-[11px] text-n-brand hover:underline mt-1"
                @click="emit('go-to-field', error)"
              >
                {{ t('JABVOX_WA_FLOWS.BUILDER.VALIDATION.GO_TO_FIELD') }}
              </button>
            </div>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>
