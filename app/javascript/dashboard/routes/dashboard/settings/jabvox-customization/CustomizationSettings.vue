<script setup>
import { ref, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import TablesTab from './components/TablesTab.vue';
import ColumnsTab from './components/ColumnsTab.vue';
import ButtonsTab from './components/ButtonsTab.vue';

const store = useStore();
const { t } = useI18n();

const activeTab = ref('tables');

const tabs = [
  {
    key: 'tables',
    label: () => t('JABVOX_CUSTOMIZATION.TABS.TABLES'),
    icon: 'i-lucide-table',
  },
  {
    key: 'columns',
    label: () => t('JABVOX_CUSTOMIZATION.TABS.COLUMNS'),
    icon: 'i-lucide-columns-3',
  },
  {
    key: 'buttons',
    label: () => t('JABVOX_CUSTOMIZATION.TABS.BUTTONS'),
    icon: 'i-lucide-mouse-pointer-click',
  },
];

onMounted(async () => {
  await Promise.all([
    store.dispatch('jabvoxCustomization/fetchTables'),
    // force: la pantalla de ajustes relee siempre, para ver lo que se haya cambiado
    // desde otra pestaña.
    store.dispatch('jabvoxCustomization/fetchButtons', { force: true }),
  ]);
});
</script>

<template>
  <div class="w-full overflow-y-auto">
    <div
      class="mx-auto w-full max-w-[1600px] flex flex-col gap-6 p-4 sm:p-6 lg:p-8"
    >
      <!-- Header -->
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold text-n-slate-12">
          {{ t('JABVOX_CUSTOMIZATION.SETTINGS.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 max-w-3xl">
          {{ t('JABVOX_CUSTOMIZATION.SETTINGS.SUBTITLE') }}
        </p>
      </div>

      <!-- Segmented tabs -->
      <div
        class="flex items-center gap-1 p-1 rounded-xl bg-n-alpha-1 border border-n-weak w-full sm:w-fit overflow-x-auto"
      >
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="flex items-center justify-center gap-2 px-3.5 py-2 text-sm font-medium rounded-lg whitespace-nowrap transition-colors flex-1 sm:flex-none"
          :class="
            activeTab === tab.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          <span :class="tab.icon" class="size-4" />
          {{ tab.label() }}
        </button>
      </div>

      <!-- Tab content -->
      <div class="rounded-2xl border border-n-weak bg-n-background p-4 sm:p-6">
        <TablesTab v-if="activeTab === 'tables'" />
        <ColumnsTab v-else-if="activeTab === 'columns'" />
        <ButtonsTab v-else-if="activeTab === 'buttons'" />
      </div>
    </div>
  </div>
</template>
