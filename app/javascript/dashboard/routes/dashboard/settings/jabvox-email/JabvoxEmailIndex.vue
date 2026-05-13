<script setup>
import { ref, onMounted, computed } from 'vue';
import { useStore } from 'vuex';
import SmtpConfigForm from './SmtpConfigForm.vue';
import EmailTemplateList from './EmailTemplateList.vue';
import EmailTemplateEditor from './EmailTemplateEditor.vue';
import EmailTemplateTest from './EmailTemplateTest.vue';
import CalendarSettings from './CalendarSettings.vue';

const store = useStore();

const activeTab = ref('smtp');
const editingTemplate = ref(null);
const isCreating = ref(false);

const hasEditor = computed(() => isCreating.value || !!editingTemplate.value);

onMounted(() => {
  store.dispatch('jabvoxEmail/fetchSmtpConfig');
  store.dispatch('jabvoxEmail/fetchTemplates');
  store.dispatch('jabvoxEmail/fetchCalendarSetting');
});

const openNewTemplate = () => {
  editingTemplate.value = null;
  isCreating.value = true;
};

const openEditTemplate = template => {
  editingTemplate.value = template;
  isCreating.value = false;
};

const closeEditor = () => {
  isCreating.value = false;
  editingTemplate.value = null;
};
</script>

<template>
  <div class="flex flex-col h-full bg-n-background">
    <div
      class="flex items-center gap-4 px-6 py-4 border-b border-n-slate-3 dark:border-n-slate-6"
    >
      <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_EMAIL.TITLE') }}
      </h1>
    </div>

    <div
      class="flex gap-1 px-6 pt-4 border-b border-n-slate-3 dark:border-n-slate-6"
    >
      <button
        class="px-4 py-2 text-sm font-medium rounded-t-lg transition-colors"
        :class="
          activeTab === 'smtp'
            ? 'text-woot-500 border-b-2 border-woot-500'
            : 'text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200'
        "
        @click="activeTab = 'smtp'"
      >
        {{ $t('JABVOX_EMAIL.TABS.SMTP') }}
      </button>
      <button
        class="px-4 py-2 text-sm font-medium rounded-t-lg transition-colors"
        :class="
          activeTab === 'templates'
            ? 'text-woot-500 border-b-2 border-woot-500'
            : 'text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200'
        "
        @click="activeTab = 'templates'"
      >
        {{ $t('JABVOX_EMAIL.TABS.TEMPLATES') }}
      </button>
      <button
        class="px-4 py-2 text-sm font-medium rounded-t-lg transition-colors"
        :class="
          activeTab === 'test'
            ? 'text-woot-500 border-b-2 border-woot-500'
            : 'text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200'
        "
        @click="activeTab = 'test'"
      >
        {{ $t('JABVOX_EMAIL.TABS.TEST') }}
      </button>
      <button
        class="px-4 py-2 text-sm font-medium rounded-t-lg transition-colors"
        :class="
          activeTab === 'calendar'
            ? 'text-woot-500 border-b-2 border-woot-500'
            : 'text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200'
        "
        @click="activeTab = 'calendar'"
      >
        {{ $t('JABVOX_EMAIL.TABS.CALENDAR') }}
      </button>
    </div>

    <div class="flex-1 min-h-0">
      <div v-if="activeTab === 'smtp'" class="h-full overflow-y-auto p-6">
        <SmtpConfigForm />
      </div>

      <div v-else-if="activeTab === 'templates'" class="h-full p-6">
        <div class="flex h-full min-h-0 gap-6">
          <div
            class="w-80 shrink-0 h-full overflow-y-auto rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800"
          >
            <EmailTemplateList
              :selected-id="editingTemplate?.id"
              @new="openNewTemplate"
              @edit="openEditTemplate"
              @select="openEditTemplate"
            />
          </div>
          <div
            class="flex-1 min-w-0 h-full overflow-y-auto rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-5"
          >
            <EmailTemplateEditor
              v-if="hasEditor"
              :key="editingTemplate?.id || 'new'"
              :template="editingTemplate"
              @close="closeEditor"
            />
            <div
              v-else
              class="h-full flex flex-col items-center justify-center text-center text-slate-400 px-6"
            >
              <span class="i-lucide-mail size-8 mb-3" />
              <p class="text-sm">
                {{ $t('JABVOX_EMAIL.TEMPLATES.SELECT_HELP') }}
              </p>
              <button
                class="mt-4 px-4 py-2 bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium rounded-lg transition-colors"
                @click="openNewTemplate"
              >
                {{ $t('JABVOX_EMAIL.TEMPLATES.NEW') }}
              </button>
            </div>
          </div>
        </div>
      </div>

      <div v-else-if="activeTab === 'test'" class="h-full overflow-y-auto p-6">
        <EmailTemplateTest />
      </div>

      <div v-else class="h-full overflow-y-auto p-6">
        <CalendarSettings />
      </div>
    </div>
  </div>
</template>
