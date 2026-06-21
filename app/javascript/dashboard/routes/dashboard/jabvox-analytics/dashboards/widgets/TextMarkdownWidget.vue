<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const props = defineProps({
  widget: { type: Object, required: true },
});

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();

const markdown = computed(() => props.widget?.configJabvox?.markdown || '');
const html = computed(() => formatMessage(markdown.value, false, false));
</script>

<template>
  <div class="size-full overflow-y-auto p-2">
    <div
      v-if="markdown"
      v-dompurify-html="html"
      class="prose-sm max-w-none text-sm text-n-slate-12"
    />
    <p v-else class="text-sm text-n-slate-11">
      {{ t('JABVOX_ANALYTICS.WIDGETS.NO_DATA') }}
    </p>
  </div>
</template>
