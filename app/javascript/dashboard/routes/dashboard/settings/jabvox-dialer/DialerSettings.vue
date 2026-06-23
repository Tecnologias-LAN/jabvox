<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import allCountries from 'shared/constants/countries.js';
import Button from 'dashboard/components-next/button/Button.vue';
import CampaignsTab from './components/CampaignsTab.vue';
import StatesTab from './components/StatesTab.vue';
import PermissionsTab from './components/PermissionsTab.vue';

const store = useStore();
const { t } = useI18n();

const agents = useMapGetter('agents/getAgents');
const leadCampaigns = useMapGetter('jabvoxCampaigns/getCampaigns');
const managementStates = useMapGetter('jabvoxManagementStates/getStates');
const affiliates = useMapGetter('jabvoxAffiliates/getAffiliates');
const inboxes = useMapGetter('inboxes/getInboxes');

const activeTab = ref('campaigns');
const campaignsTab = ref(null);
const statesTab = ref(null);

const tabs = [
  {
    key: 'campaigns',
    label: () => t('JABVOX_DIALER.SETTINGS.TABS.CAMPAIGNS'),
    icon: 'i-lucide-phone-call',
  },
  {
    key: 'states',
    label: () => t('JABVOX_DIALER.SETTINGS.TABS.STATES'),
    icon: 'i-lucide-sliders-horizontal',
  },
  {
    key: 'permissions',
    label: () => t('JABVOX_DIALER.SETTINGS.TABS.PERMISSIONS'),
    icon: 'i-lucide-shield-check',
  },
];

// ─── options for the campaign form ───
const countryOptions = computed(() =>
  allCountries.map(c => ({ value: c.name, label: c.name }))
);
const leadCampaignOptions = computed(() =>
  (leadCampaigns.value || []).map(c => ({ value: c.id, label: c.name }))
);
const affiliateOptions = computed(() =>
  (affiliates.value || []).map(a => ({ value: a.id, label: a.name }))
);
const inboxOptions = computed(() =>
  (inboxes.value || []).map(i => ({ value: i.id, label: i.name }))
);

const onNew = () => {
  if (activeTab.value === 'campaigns') campaignsTab.value?.openCreate();
  else if (activeTab.value === 'states') statesTab.value?.openCreate();
};

onMounted(async () => {
  await store.dispatch('jabvoxDialer/fetchCampaigns');
  store.dispatch('jabvoxDialer/fetchDialerStates');
  store.dispatch('jabvoxDialer/fetchDialerAccesses');
  store.dispatch('agents/get');
  store.dispatch('jabvoxCampaigns/fetchCampaigns');
  store.dispatch('jabvoxManagementStates/fetchStates');
  store.dispatch('jabvoxAffiliates/fetchAffiliates');
  store.dispatch('inboxes/get');
});
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-6xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span
            class="i-lucide-phone-outgoing size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_DIALER.SETTINGS.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_DIALER.SETTINGS.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <Button
          v-if="activeTab !== 'permissions'"
          :label="
            activeTab === 'campaigns'
              ? t('JABVOX_DIALER.CAMPAIGN.NEW')
              : t('JABVOX_DIALER.DIALER_STATES.NEW')
          "
          icon="i-lucide-plus"
          class="shrink-0"
          @click="onNew"
        />
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

      <!-- Tab content -->
      <CampaignsTab
        v-show="activeTab === 'campaigns'"
        ref="campaignsTab"
        :lead-campaigns="leadCampaigns"
        :lead-campaign-options="leadCampaignOptions"
        :country-options="countryOptions"
        :affiliate-options="affiliateOptions"
        :inbox-options="inboxOptions"
        :management-states="managementStates"
        :agents="agents"
      />
      <StatesTab v-show="activeTab === 'states'" ref="statesTab" />
      <PermissionsTab v-if="activeTab === 'permissions'" />
    </div>
  </div>
</template>
