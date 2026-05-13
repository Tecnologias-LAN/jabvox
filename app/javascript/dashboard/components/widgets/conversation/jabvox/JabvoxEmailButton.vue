<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { emailTemplatesAPI } from 'dashboard/api/jabvox/email';

const props = defineProps({
  email: { type: String, required: true },
  contactId: { type: Number, default: null },
  showLabel: { type: Boolean, default: false },
});

const { t } = useI18n();
const open = ref(false);
const templates = ref([]);
const selectedId = ref(null);
const sending = ref(false);
const result = ref(null);
const loading = ref(false);

async function toggle() {
  open.value = !open.value;
  result.value = null;
  if (open.value && !templates.value.length) {
    loading.value = true;
    try {
      const { data } = await emailTemplatesAPI.getAll();
      templates.value = (data.templates || []).filter(tpl => tpl.active);
      if (templates.value.length === 1)
        selectedId.value = templates.value[0].id;
    } finally {
      loading.value = false;
    }
  }
}

async function send() {
  if (!selectedId.value || !props.contactId) return;
  sending.value = true;
  result.value = null;
  try {
    await emailTemplatesAPI.sendToContact(selectedId.value, props.contactId);
    result.value = 'success';
    setTimeout(() => {
      open.value = false;
      result.value = null;
    }, 2000);
  } catch {
    result.value = 'error';
  } finally {
    sending.value = false;
  }
}
</script>

<template>
  <div class="relative">
    <button
      v-if="showLabel"
      class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium transition-colors"
      :title="t('JABVOX_ACTIONS.EMAIL_BUTTON.TITLE')"
      @click="toggle"
    >
      <span class="i-lucide-mail size-4" />
      <span>{{ t('JABVOX_ACTIONS.EMAIL_BUTTON.LABEL') }}</span>
    </button>
    <button
      v-else
      class="flex items-center justify-center w-8 h-8 rounded-lg hover:bg-n-alpha-2 text-n-slate-11 hover:text-woot-600 transition-colors"
      :title="t('JABVOX_ACTIONS.EMAIL_BUTTON.TITLE')"
      @click="toggle"
    >
      <span class="i-lucide-mail size-4" />
    </button>

    <div
      v-if="open"
      class="absolute right-0 top-10 z-50 w-72 bg-white dark:bg-n-solid-3 border border-n-weak rounded-lg shadow-lg p-3 space-y-2"
    >
      <p class="text-xs font-medium text-n-slate-12 truncate">
        {{ email }}
      </p>

      <p v-if="loading" class="text-xs text-slate-400 py-2 text-center">
        {{ t('JABVOX_ACTIONS.EMAIL_BUTTON.LOADING') }}
      </p>

      <div
        v-else-if="!templates.length"
        class="flex items-center gap-2 px-3 py-2.5 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700"
      >
        <span class="i-lucide-triangle-alert size-4 text-amber-500 shrink-0" />
        <p class="text-xs text-amber-700 dark:text-amber-400">
          {{ t('JABVOX_ACTIONS.EMAIL_BUTTON.NO_TEMPLATES') }}
        </p>
      </div>

      <template v-else>
        <select
          v-model="selectedId"
          class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 text-slate-700 dark:text-slate-200"
        >
          <option :value="null" disabled>
            {{ t('JABVOX_ACTIONS.EMAIL_BUTTON.SELECT_TEMPLATE') }}
          </option>
          <option v-for="tpl in templates" :key="tpl.id" :value="tpl.id">
            {{ tpl.name }}
          </option>
        </select>

        <button
          :disabled="!selectedId || sending"
          class="w-full py-1.5 rounded bg-woot-600 text-white text-sm font-medium disabled:opacity-50 hover:bg-woot-700 transition-colors"
          @click="send"
        >
          {{
            sending
              ? t('JABVOX_ACTIONS.EMAIL_BUTTON.SENDING')
              : t('JABVOX_ACTIONS.EMAIL_BUTTON.SEND')
          }}
        </button>
      </template>

      <p v-if="result === 'success'" class="text-xs text-green-600 text-center">
        {{ t('JABVOX_ACTIONS.EMAIL_BUTTON.SUCCESS') }}
      </p>
      <p v-if="result === 'error'" class="text-xs text-red-500 text-center">
        {{ t('JABVOX_ACTIONS.EMAIL_BUTTON.ERROR') }}
      </p>
    </div>
  </div>
</template>
