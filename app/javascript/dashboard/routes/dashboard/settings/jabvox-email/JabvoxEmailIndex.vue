<script setup>
import { ref, onMounted, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import SmtpConfigForm from './SmtpConfigForm.vue';
import EmailTemplateList from './EmailTemplateList.vue';
import EmailTemplateEditor from './EmailTemplateEditor.vue';
import EmailTemplateTest from './EmailTemplateTest.vue';
import CalendarSettings from './CalendarSettings.vue';

const store = useStore();
const { t } = useI18n();

const activeTab = ref('smtp');
const editingTemplate = ref(null);
const isCreating = ref(false);

const hasEditor = computed(() => isCreating.value || !!editingTemplate.value);

const tabs = [
  {
    key: 'smtp',
    icon: 'i-lucide-server',
    label: () => t('JABVOX_EMAIL.TABS.SMTP'),
  },
  {
    key: 'templates',
    icon: 'i-lucide-layout-template',
    label: () => t('JABVOX_EMAIL.TABS.TEMPLATES'),
  },
  {
    key: 'test',
    icon: 'i-lucide-send',
    label: () => t('JABVOX_EMAIL.TABS.TEST'),
  },
  {
    key: 'calendar',
    icon: 'i-lucide-calendar-clock',
    label: () => t('JABVOX_EMAIL.TABS.CALENDAR'),
  },
];

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
  <div class="w-full h-full bg-n-background overflow-y-auto">
    <div
      class="mx-auto w-full flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
      :class="activeTab === 'templates' ? 'max-w-6xl' : 'max-w-4xl'"
    >
      <!-- Header -->
      <div class="flex items-start gap-3">
        <span
          class="i-lucide-mail size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('JABVOX_EMAIL.TITLE') }}
          </h1>
          <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
            {{ t('JABVOX_EMAIL.SUBTITLE') }}
          </p>
        </div>
      </div>

      <!-- Segmented tabs -->
      <div
        class="flex items-center gap-1 p-1 rounded-xl bg-n-alpha-1 border border-n-weak w-full sm:w-fit overflow-x-auto"
      >
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg whitespace-nowrap transition-colors flex-1 sm:flex-none"
          :class="
            activeTab === tab.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          <span :class="tab.icon" class="size-4 shrink-0" />
          {{ tab.label() }}
        </button>
      </div>

      <!-- SMTP -->
      <SmtpConfigForm v-if="activeTab === 'smtp'" />

      <!-- Templates: list + editor split (stacks on mobile) -->
      <div
        v-else-if="activeTab === 'templates'"
        class="flex flex-col lg:flex-row gap-6 min-h-[60vh]"
      >
        <div
          class="w-full lg:w-80 shrink-0 rounded-2xl border border-n-weak bg-n-solid-1 overflow-hidden"
        >
          <EmailTemplateList
            :selected-id="editingTemplate?.id"
            @new="openNewTemplate"
            @edit="openEditTemplate"
            @select="openEditTemplate"
          />
        </div>
        <div
          class="flex-1 min-w-0 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
        >
          <EmailTemplateEditor
            v-if="hasEditor"
            :key="editingTemplate?.id || 'new'"
            :template="editingTemplate"
            @close="closeEditor"
          />
          <div
            v-else
            class="h-full min-h-[40vh] flex flex-col items-center justify-center text-center text-n-slate-11 px-6"
          >
            <span class="i-lucide-mail size-8 mb-3 text-n-slate-10" />
            <p class="text-sm">
              {{ t('JABVOX_EMAIL.TEMPLATES.SELECT_HELP') }}
            </p>
            <Button
              icon="i-lucide-plus"
              :label="t('JABVOX_EMAIL.TEMPLATES.NEW')"
              size="sm"
              class="mt-4"
              @click="openNewTemplate"
            />
          </div>
        </div>
      </div>

      <!-- Test -->
      <EmailTemplateTest v-else-if="activeTab === 'test'" />

      <!-- Calendar reminders -->
      <CalendarSettings v-else />
    </div>
  </div>
</template>
