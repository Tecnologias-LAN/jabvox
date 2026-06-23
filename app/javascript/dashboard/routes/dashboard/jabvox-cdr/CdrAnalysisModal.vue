<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { cdrReportsAPI } from 'dashboard/api/jabvox/cdr';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  call: { type: Object, required: true },
  existing: { type: Object, default: null },
});

const emit = defineEmits(['close', 'updated']);

const { t } = useI18n();

const analysis = ref(props.existing || null);
const loading = ref(false);

const runAnalysis = async (force = false) => {
  loading.value = true;
  try {
    const { data } = await cdrReportsAPI.analyze({
      uniqueid: props.call.uniqueid,
      force,
    });
    analysis.value = data;
    emit('updated', data);
  } catch (error) {
    analysis.value = { status: 'error', error_message: error?.message };
  } finally {
    loading.value = false;
  }
};

// Auto-run on open only when there is no analyzed result yet.
// (Correctly triggered from onMounted — not from a useState initializer.)
onMounted(() => {
  if (!analysis.value || analysis.value.status !== 'analyzed') {
    runAnalysis(false);
  }
});
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -- symbols (→ — /) are universal -->
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-4"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-2xl max-h-[85vh] overflow-auto rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
    >
      <div class="flex items-start justify-between mb-4 gap-3">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ t('JABVOX_CDR.ANALYSIS.TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-11 truncate">
            {{ call.src }} → {{ call.dst }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          size="sm"
          @click="emit('close')"
        />
      </div>

      <div
        v-if="loading"
        class="flex items-center justify-center gap-2 py-10 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_CDR.ANALYSIS.RUNNING') }}
      </div>

      <div
        v-else-if="analysis?.status === 'error'"
        class="p-4 rounded-xl border border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11 text-sm"
      >
        {{ analysis.error_message || t('JABVOX_CDR.ANALYSIS.ERROR') }}
        <div class="mt-3">
          <Button
            :label="t('JABVOX_CDR.ANALYSIS.RETRY')"
            icon="i-lucide-rotate-cw"
            color="ruby"
            size="sm"
            @click="runAnalysis(true)"
          />
        </div>
      </div>

      <div v-else-if="analysis?.status === 'analyzed'" class="space-y-4">
        <!-- Final score -->
        <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-sm text-n-slate-11">{{
              t('JABVOX_CDR.ANALYSIS.FINAL_SCORE')
            }}</span>
            <span class="text-lg font-semibold text-n-brand">{{
              analysis.final_score ?? '—'
            }}</span>
          </div>
          <div class="h-2 rounded-full bg-n-alpha-3 overflow-hidden">
            <div
              class="h-full bg-n-brand rounded-full transition-all"
              :style="{ width: `${analysis.final_score || 0}%` }"
            />
          </div>
        </div>

        <!-- Stages -->
        <div
          v-for="stage in analysis.stages_data"
          :key="stage.stage_id"
          class="p-3 rounded-xl border border-n-weak bg-n-solid-1"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="font-medium text-n-slate-12">{{ stage.name }}</span>
            <span
              class="text-xs px-2 py-0.5 rounded-full font-medium"
              :class="
                stage.passed
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-ruby-3 text-n-ruby-11'
              "
            >
              {{ stage.score ?? '—' }} / {{ stage.min_score }}
            </span>
          </div>
          <p v-if="stage.reasoning" class="mt-1 text-sm text-n-slate-11">
            {{ stage.reasoning }}
          </p>
          <ul
            v-if="stage.highlights?.length"
            class="mt-2 text-xs text-n-teal-11 list-disc list-inside space-y-0.5"
          >
            <li v-for="(h, i) in stage.highlights" :key="`h${i}`">{{ h }}</li>
          </ul>
          <ul
            v-if="stage.issues?.length"
            class="mt-1 text-xs text-n-ruby-11 list-disc list-inside space-y-0.5"
          >
            <li v-for="(iss, i) in stage.issues" :key="`i${i}`">{{ iss }}</li>
          </ul>
        </div>

        <!-- Transcript -->
        <details class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
          <summary
            class="cursor-pointer text-sm font-medium text-n-slate-11 select-none"
          >
            {{ t('JABVOX_CDR.ANALYSIS.TRANSCRIPT') }}
          </summary>
          <p
            class="mt-2 text-sm whitespace-pre-wrap text-n-slate-12 max-h-64 overflow-y-auto"
          >
            {{ analysis.transcript }}
          </p>
        </details>

        <div class="flex justify-end">
          <Button
            :label="t('JABVOX_CDR.ANALYSIS.REANALYZE')"
            icon="i-lucide-rotate-cw"
            variant="outline"
            color="slate"
            size="sm"
            @click="runAnalysis(true)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
