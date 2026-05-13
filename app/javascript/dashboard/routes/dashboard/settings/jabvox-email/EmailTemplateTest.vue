<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

const store = useStore();
const { t } = useI18n();

const templates = computed(() => store.getters['jabvoxEmail/getTemplates']);
const uiFlags = computed(() => store.getters['jabvoxEmail/getUIFlags']);

const selectedTemplateId = ref('');
const recipientEmail = ref('');

watch(
  templates,
  list => {
    if (!selectedTemplateId.value && list?.length) {
      selectedTemplateId.value = String(list[0].id);
    }
  },
  { immediate: true }
);

const canSend = computed(() => {
  return selectedTemplateId.value && recipientEmail.value.trim();
});

const onSend = async () => {
  if (!canSend.value) return;
  try {
    await store.dispatch('jabvoxEmail/sendTestTemplate', {
      id: selectedTemplateId.value,
      to: recipientEmail.value.trim(),
    });
    useAlert(t('JABVOX_EMAIL.TEST.SUCCESS'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_EMAIL.TEST.ERROR'));
  }
};
</script>

<template>
  <div class="w-full flex justify-center">
    <div class="w-full max-w-3xl space-y-6">
      <div
        class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 p-6 space-y-5"
      >
        <div class="flex items-center justify-between gap-3">
          <h2
            class="text-base font-semibold text-slate-800 dark:text-slate-100"
          >
            {{ $t('JABVOX_EMAIL.TEST.TITLE') }}
          </h2>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_EMAIL.TEST.TEMPLATE') }}
            </label>
            <select
              v-model="selectedTemplateId"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option value="" disabled>
                {{ $t('JABVOX_EMAIL.TEST.TEMPLATE_PLACEHOLDER') }}
              </option>
              <option v-for="tpl in templates" :key="tpl.id" :value="tpl.id">
                {{ tpl.name }}
              </option>
            </select>
          </div>

          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ $t('JABVOX_EMAIL.TEST.RECIPIENT') }}
            </label>
            <input
              v-model="recipientEmail"
              type="email"
              :placeholder="$t('JABVOX_EMAIL.TEST.RECIPIENT_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
        </div>

        <div class="flex gap-3 pt-2">
          <button
            :disabled="uiFlags.isSendingTest || !canSend"
            class="px-4 py-2 bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium rounded-lg transition-colors disabled:opacity-50"
            @click="onSend"
          >
            {{
              uiFlags.isSendingTest
                ? $t('JABVOX_EMAIL.TEST.SENDING')
                : $t('JABVOX_EMAIL.TEST.SEND')
            }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
