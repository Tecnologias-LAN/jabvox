<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const activeTab = ref('management');

// --- Campaigns ---
const jabvoxCampaigns = useMapGetter('jabvoxCampaigns/getCampaigns');
const campaignsUiFlags = useMapGetter('jabvoxCampaigns/getUIFlags');

const showCampaignForm = ref(false);
const editingCampaign = ref(null);
const campaignForm = ref({ name_jabvox: '' });

const openNewCampaign = () => {
  editingCampaign.value = null;
  campaignForm.value = { name_jabvox: '' };
  showCampaignForm.value = true;
};
const openEditCampaign = campaign => {
  editingCampaign.value = campaign;
  campaignForm.value = { name_jabvox: campaign.name };
  showCampaignForm.value = true;
};
const cancelCampaignForm = () => {
  showCampaignForm.value = false;
  editingCampaign.value = null;
};
const onSubmitCampaign = async () => {
  if (!campaignForm.value.name_jabvox.trim()) return;
  try {
    if (editingCampaign.value) {
      await store.dispatch('jabvoxCampaigns/updateCampaign', {
        id: editingCampaign.value.id,
        name_jabvox: campaignForm.value.name_jabvox,
      });
      useAlert(t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.UPDATED'));
    } else {
      await store.dispatch('jabvoxCampaigns/createCampaign', {
        name_jabvox: campaignForm.value.name_jabvox,
      });
      useAlert(t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.CREATED'));
    }
    cancelCampaignForm();
  } catch (error) {
    useAlert(error.message || t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.ERROR'));
  }
};
const onDeleteCampaign = async campaign => {
  if (
    !window.confirm(
      t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.DELETE_CONFIRM', {
        name: campaign.name,
      })
    )
  )
    return;
  try {
    await store.dispatch('jabvoxCampaigns/deleteCampaign', campaign.id);
    useAlert(t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.DELETED'));
  } catch (error) {
    useAlert(error.message || t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.ERROR'));
  }
};
const isCampaignSaving = computed(
  () => campaignsUiFlags.value.isCreating || campaignsUiFlags.value.isUpdating
);

// --- Management States ---
const states = useMapGetter('jabvoxManagementStates/getStates');
const uiFlags = useMapGetter('jabvoxManagementStates/getUIFlags');

const showForm = ref(false);
const editingState = ref(null);
const form = ref({
  name_jabvox: '',
  color_jabvox: '#6366f1',
  is_active_jabvox: true,
});

const openNew = () => {
  editingState.value = null;
  form.value = {
    name_jabvox: '',
    color_jabvox: '#6366f1',
    is_active_jabvox: true,
  };
  showForm.value = true;
};
const openEdit = state => {
  editingState.value = state;
  form.value = {
    name_jabvox: state.name_jabvox,
    color_jabvox: state.color_jabvox,
    is_active_jabvox: state.is_active_jabvox,
  };
  showForm.value = true;
};
const cancelForm = () => {
  showForm.value = false;
  editingState.value = null;
};

const onSubmit = async () => {
  if (!form.value.name_jabvox.trim()) return;
  try {
    if (editingState.value) {
      await store.dispatch('jabvoxManagementStates/updateState', {
        id: editingState.value.id,
        ...form.value,
      });
      useAlert(t('JABVOX_MANAGEMENT_STATES.UPDATED'));
    } else {
      await store.dispatch('jabvoxManagementStates/createState', form.value);
      useAlert(t('JABVOX_MANAGEMENT_STATES.CREATED'));
    }
    cancelForm();
  } catch (error) {
    useAlert(error.message || t('JABVOX_MANAGEMENT_STATES.ERROR'));
  }
};
const onDelete = async state => {
  if (
    !window.confirm(
      t('JABVOX_MANAGEMENT_STATES.DELETE_CONFIRM', { name: state.name_jabvox })
    )
  )
    return;
  try {
    await store.dispatch('jabvoxManagementStates/deleteState', state.id);
    useAlert(t('JABVOX_MANAGEMENT_STATES.DELETED'));
  } catch (error) {
    useAlert(error.message || t('JABVOX_MANAGEMENT_STATES.ERROR'));
  }
};
const isSaving = computed(
  () => uiFlags.value.isCreating || uiFlags.value.isUpdating
);
const activeCount = computed(
  () => states.value.filter(s => s.is_active_jabvox).length
);

// --- App States ---
const appStates = useMapGetter('jabvoxAppStates/getStates');
const appUiFlags = useMapGetter('jabvoxAppStates/getUIFlags');

const showAppForm = ref(false);
const editingAppState = ref(null);
const appForm = ref({ name: '', color: '#6366f1', is_active: true });

const openNewApp = () => {
  editingAppState.value = null;
  appForm.value = { name: '', color: '#6366f1', is_active: true };
  showAppForm.value = true;
};
const openEditApp = state => {
  editingAppState.value = state;
  appForm.value = {
    name: state.name,
    color: state.color,
    is_active: state.is_active,
  };
  showAppForm.value = true;
};
const cancelAppForm = () => {
  showAppForm.value = false;
  editingAppState.value = null;
};

const onSubmitApp = async () => {
  if (!appForm.value.name.trim()) return;
  try {
    if (editingAppState.value) {
      await store.dispatch('jabvoxAppStates/updateState', {
        id: editingAppState.value.id,
        ...appForm.value,
      });
      useAlert(t('JABVOX_MANAGEMENT_STATES.APP_STATES.UPDATED'));
    } else {
      await store.dispatch('jabvoxAppStates/createState', appForm.value);
      useAlert(t('JABVOX_MANAGEMENT_STATES.APP_STATES.CREATED'));
    }
    cancelAppForm();
  } catch (error) {
    useAlert(error.message || t('JABVOX_MANAGEMENT_STATES.APP_STATES.ERROR'));
  }
};
const onDeleteApp = async state => {
  if (
    !window.confirm(
      t('JABVOX_MANAGEMENT_STATES.APP_STATES.DELETE_CONFIRM', {
        name: state.name,
      })
    )
  )
    return;
  try {
    await store.dispatch('jabvoxAppStates/deleteState', state.id);
    useAlert(t('JABVOX_MANAGEMENT_STATES.APP_STATES.DELETED'));
  } catch (error) {
    useAlert(error.message || t('JABVOX_MANAGEMENT_STATES.APP_STATES.ERROR'));
  }
};
const isAppSaving = computed(() => appUiFlags.value.isSaving);
const appActiveCount = computed(
  () => appStates.value.filter(s => s.is_active).length
);

onMounted(() => {
  store.dispatch('jabvoxManagementStates/fetchStates');
  store.dispatch('jabvoxAppStates/fetchStates');
  store.dispatch('jabvoxCampaigns/fetchCampaigns');
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <!-- Page header -->
    <div class="shrink-0 border-b border-n-weak bg-n-surface-1">
      <div class="max-w-3xl mx-auto px-6 sm:px-8 pt-6 pb-0">
        <h1 class="text-heading-1 text-n-slate-12">
          {{ $t('JABVOX_MANAGEMENT_STATES.TITLE') }}
        </h1>
      </div>
      <!-- Tabs -->
      <div class="flex px-6 sm:px-8 gap-1 max-w-3xl mx-auto mt-4">
        <button
          class="flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px"
          :class="
            activeTab === 'management'
              ? 'border-woot-500 text-woot-600'
              : 'border-transparent text-n-slate-10 hover:text-n-slate-12 hover:border-n-weak'
          "
          @click="activeTab = 'management'"
        >
          {{ $t('JABVOX_MANAGEMENT_STATES.TABS.MANAGEMENT') }}
        </button>
        <button
          class="flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px"
          :class="
            activeTab === 'app'
              ? 'border-woot-500 text-woot-600'
              : 'border-transparent text-n-slate-10 hover:text-n-slate-12 hover:border-n-weak'
          "
          @click="activeTab = 'app'"
        >
          {{ $t('JABVOX_MANAGEMENT_STATES.TABS.APP') }}
        </button>
        <button
          class="flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px"
          :class="
            activeTab === 'campaigns'
              ? 'border-woot-500 text-woot-600'
              : 'border-transparent text-n-slate-10 hover:text-n-slate-12 hover:border-n-weak'
          "
          @click="activeTab = 'campaigns'"
        >
          {{ $t('JABVOX_MANAGEMENT_STATES.TABS.CAMPAIGNS') }}
        </button>
      </div>
    </div>

    <!-- Scrollable content -->
    <div class="flex-1 overflow-y-auto">
      <!-- Tab 1: Management states -->
      <div
        v-if="activeTab === 'management'"
        class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-6"
      >
        <div class="flex items-start justify-between gap-4">
          <p class="text-body-main text-n-slate-11 max-w-lg">
            {{ $t('JABVOX_MANAGEMENT_STATES.DESCRIPTION') }}
          </p>
          <div class="shrink-0">
            <Button
              :label="$t('JABVOX_MANAGEMENT_STATES.NEW')"
              icon="i-lucide-plus"
              @click="openNew"
            />
          </div>
        </div>

        <!-- Inline form card -->
        <div
          v-if="showForm"
          class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 shadow-sm overflow-hidden"
        >
          <div
            class="px-6 py-4 border-b border-slate-100 dark:border-slate-700 flex items-center justify-between"
          >
            <h3
              class="text-sm font-semibold text-slate-800 dark:text-slate-100"
            >
              {{
                editingState
                  ? $t('JABVOX_MANAGEMENT_STATES.EDIT')
                  : $t('JABVOX_MANAGEMENT_STATES.NEW')
              }}
            </h3>
            <button
              class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
              @click="cancelForm"
            >
              <span class="i-lucide-x text-base block" />
            </button>
          </div>
          <div class="px-6 py-5 space-y-5">
            <div class="space-y-1.5">
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-300"
              >
                {{ $t('JABVOX_MANAGEMENT_STATES.FORM.NAME') }}
                <span class="text-red-500 ml-0.5">*</span>
              </label>
              <input
                v-model="form.name_jabvox"
                type="text"
                :placeholder="
                  $t('JABVOX_MANAGEMENT_STATES.FORM.NAME_PLACEHOLDER')
                "
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-woot-500 transition"
                @keydown.enter="onSubmit"
              />
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
              <div class="space-y-1.5">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >{{ $t('JABVOX_MANAGEMENT_STATES.FORM.COLOR') }}</label>
                <div class="flex items-center gap-3">
                  <input
                    v-model="form.color_jabvox"
                    type="color"
                    class="w-10 h-10 rounded-lg border border-slate-200 cursor-pointer p-0.5 flex-shrink-0"
                  />
                  <span class="text-xs text-slate-400">{{
                    form.color_jabvox
                  }}</span>
                </div>
              </div>
              <div class="space-y-1.5">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >{{ $t('JABVOX_MANAGEMENT_STATES.FORM.PREVIEW') }}</label>
                <div class="flex items-center h-10">
                  <span
                    class="inline-flex items-center gap-1.5 text-sm font-semibold px-3 py-1.5 rounded-full"
                    :style="{
                      backgroundColor: form.color_jabvox + '22',
                      color: form.color_jabvox,
                      border: '1px solid ' + form.color_jabvox + '55',
                    }"
                  >
                    <span
                      class="w-2 h-2 rounded-full flex-shrink-0"
                      :style="{ backgroundColor: form.color_jabvox }"
                    />
                    {{
                      form.name_jabvox ||
                      $t('JABVOX_MANAGEMENT_STATES.FORM.NAME_PLACEHOLDER')
                    }}
                  </span>
                </div>
              </div>
            </div>
            <label
              class="flex items-center gap-3 cursor-pointer select-none w-fit"
            >
              <input
                v-model="form.is_active_jabvox"
                type="checkbox"
                class="h-4 w-4 rounded border-slate-300 text-woot-600 focus:ring-woot-500"
              />
              <span class="text-sm text-slate-600 dark:text-slate-300">{{
                $t('JABVOX_MANAGEMENT_STATES.FORM.ACTIVE')
              }}</span>
            </label>
          </div>
          <div
            class="px-6 py-4 border-t border-slate-100 dark:border-slate-700 flex gap-2"
          >
            <Button
              :label="
                isSaving
                  ? $t('JABVOX_MANAGEMENT_STATES.SAVING')
                  : $t('JABVOX_MANAGEMENT_STATES.SAVE')
              "
              :disabled="isSaving || !form.name_jabvox.trim()"
              @click="onSubmit"
            />
            <Button
              variant="clear"
              :label="$t('JABVOX_MANAGEMENT_STATES.CANCEL')"
              @click="cancelForm"
            />
          </div>
        </div>

        <div
          v-if="uiFlags.isFetching"
          class="flex items-center justify-center py-20 text-sm text-slate-400 animate-pulse"
        >
          {{ $t('JABVOX_MANAGEMENT_STATES.LOADING') }}
        </div>
        <div
          v-else-if="states.length === 0 && !showForm"
          class="flex flex-col items-center justify-center py-20 text-center space-y-4"
        >
          <div
            class="w-14 h-14 rounded-2xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center"
          >
            <span class="i-lucide-tag text-2xl text-slate-400 block" />
          </div>
          <p class="text-sm font-medium text-slate-700 dark:text-slate-200">
            {{ $t('JABVOX_MANAGEMENT_STATES.EMPTY') }}
          </p>
          <Button
            variant="clear"
            :label="$t('JABVOX_MANAGEMENT_STATES.NEW')"
            icon="i-lucide-plus"
            @click="openNew"
          />
        </div>
        <div v-else-if="states.length" class="space-y-3">
          <p class="text-xs text-slate-400">
            {{ states.length }} {{ states.length === 1 ? 'estado' : 'estados' }}
            <span v-if="activeCount"
class="ml-1"
              >· {{ activeCount }} activos</span>
          </p>
          <div
            class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 divide-y divide-slate-100 dark:divide-slate-700 overflow-hidden shadow-sm"
          >
            <div
              v-for="state in states"
              :key="state.id"
              class="flex items-center justify-between px-5 py-4 hover:bg-slate-50 dark:hover:bg-slate-700/30 transition-colors"
            >
              <div class="flex items-center gap-3 min-w-0">
                <span
                  class="w-3 h-3 rounded-full flex-shrink-0"
                  :style="{ backgroundColor: state.color_jabvox }"
                />
                <span
                  class="inline-flex items-center gap-1.5 text-sm font-medium px-2.5 py-1 rounded-full"
                  :style="{
                    backgroundColor: state.color_jabvox + '18',
                    color: state.color_jabvox,
                    border: '1px solid ' + state.color_jabvox + '40',
                  }"
                >
                  {{ state.name_jabvox }}
                </span>
                <span
                  v-if="!state.is_active_jabvox"
                  class="text-xs px-2 py-0.5 rounded-full bg-slate-100 text-slate-500 dark:bg-slate-700 dark:text-slate-400 font-medium"
                >
                  {{ $t('JABVOX_MANAGEMENT_STATES.INACTIVE') }}
                </span>
              </div>
              <div class="flex items-center gap-1 shrink-0 ml-4">
                <button
                  class="p-1.5 rounded-lg text-slate-400 hover:text-woot-600 hover:bg-woot-50 dark:hover:bg-woot-900/20 transition-colors"
                  @click="openEdit(state)"
                >
                  <span class="i-lucide-pencil text-sm block" />
                </button>
                <button
                  class="p-1.5 rounded-lg text-slate-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                  :disabled="uiFlags.isDeleting"
                  @click="onDelete(state)"
                >
                  <span class="i-lucide-trash-2 text-sm block" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Tab 2: App states -->
      <div
        v-else-if="activeTab === 'app'"
        class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-6"
      >
        <div class="flex items-start justify-between gap-4">
          <p class="text-body-main text-n-slate-11 max-w-lg">
            {{ $t('JABVOX_MANAGEMENT_STATES.APP_STATES.DESCRIPTION') }}
          </p>
          <div class="shrink-0">
            <Button
              :label="$t('JABVOX_MANAGEMENT_STATES.APP_STATES.NEW')"
              icon="i-lucide-plus"
              @click="openNewApp"
            />
          </div>
        </div>

        <!-- Inline form card -->
        <div
          v-if="showAppForm"
          class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 shadow-sm overflow-hidden"
        >
          <div
            class="px-6 py-4 border-b border-slate-100 dark:border-slate-700 flex items-center justify-between"
          >
            <h3
              class="text-sm font-semibold text-slate-800 dark:text-slate-100"
            >
              {{
                editingAppState
                  ? $t('JABVOX_MANAGEMENT_STATES.APP_STATES.EDIT')
                  : $t('JABVOX_MANAGEMENT_STATES.APP_STATES.NEW')
              }}
            </h3>
            <button
              class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
              @click="cancelAppForm"
            >
              <span class="i-lucide-x text-base block" />
            </button>
          </div>
          <div class="px-6 py-5 space-y-5">
            <div class="space-y-1.5">
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-300"
              >
                {{ $t('JABVOX_MANAGEMENT_STATES.APP_STATES.FORM.NAME') }}
                <span class="text-red-500 ml-0.5">*</span>
              </label>
              <input
                v-model="appForm.name"
                type="text"
                :placeholder="
                  $t(
                    'JABVOX_MANAGEMENT_STATES.APP_STATES.FORM.NAME_PLACEHOLDER'
                  )
                "
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-woot-500 transition"
                @keydown.enter="onSubmitApp"
              />
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
              <div class="space-y-1.5">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >{{
                    $t('JABVOX_MANAGEMENT_STATES.APP_STATES.FORM.COLOR')
                  }}</label>
                <div class="flex items-center gap-3">
                  <input
                    v-model="appForm.color"
                    type="color"
                    class="w-10 h-10 rounded-lg border border-slate-200 cursor-pointer p-0.5 flex-shrink-0"
                  />
                  <span class="text-xs text-slate-400">{{
                    appForm.color
                  }}</span>
                </div>
              </div>
              <div class="space-y-1.5">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                  >{{
                    $t('JABVOX_MANAGEMENT_STATES.APP_STATES.FORM.PREVIEW')
                  }}</label>
                <div class="flex items-center h-10">
                  <span
                    class="inline-flex items-center gap-1.5 text-sm font-semibold px-3 py-1.5 rounded-full"
                    :style="{
                      backgroundColor: appForm.color + '22',
                      color: appForm.color,
                      border: '1px solid ' + appForm.color + '55',
                    }"
                  >
                    <span
                      class="w-2 h-2 rounded-full flex-shrink-0"
                      :style="{ backgroundColor: appForm.color }"
                    />
                    {{
                      appForm.name ||
                      $t(
                        'JABVOX_MANAGEMENT_STATES.APP_STATES.FORM.NAME_PLACEHOLDER'
                      )
                    }}
                  </span>
                </div>
              </div>
            </div>
            <label
              class="flex items-center gap-3 cursor-pointer select-none w-fit"
            >
              <input
                v-model="appForm.is_active"
                type="checkbox"
                class="h-4 w-4 rounded border-slate-300 text-woot-600 focus:ring-woot-500"
              />
              <span class="text-sm text-slate-600 dark:text-slate-300">{{
                $t('JABVOX_MANAGEMENT_STATES.APP_STATES.FORM.ACTIVE')
              }}</span>
            </label>
          </div>
          <div
            class="px-6 py-4 border-t border-slate-100 dark:border-slate-700 flex gap-2"
          >
            <Button
              :label="
                isAppSaving
                  ? $t('JABVOX_MANAGEMENT_STATES.APP_STATES.SAVING')
                  : $t('JABVOX_MANAGEMENT_STATES.APP_STATES.SAVE')
              "
              :disabled="isAppSaving || !appForm.name.trim()"
              @click="onSubmitApp"
            />
            <Button
              variant="clear"
              :label="$t('JABVOX_MANAGEMENT_STATES.APP_STATES.CANCEL')"
              @click="cancelAppForm"
            />
          </div>
        </div>

        <div
          v-if="appUiFlags.isFetching"
          class="flex items-center justify-center py-20 text-sm text-slate-400 animate-pulse"
        >
          {{ $t('JABVOX_MANAGEMENT_STATES.APP_STATES.LOADING') }}
        </div>
        <div
          v-else-if="appStates.length === 0 && !showAppForm"
          class="flex flex-col items-center justify-center py-20 text-center space-y-4"
        >
          <div
            class="w-14 h-14 rounded-2xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center"
          >
            <span class="i-lucide-radio text-2xl text-slate-400 block" />
          </div>
          <p class="text-sm font-medium text-slate-700 dark:text-slate-200">
            {{ $t('JABVOX_MANAGEMENT_STATES.APP_STATES.EMPTY') }}
          </p>
          <Button
            variant="clear"
            :label="$t('JABVOX_MANAGEMENT_STATES.APP_STATES.NEW')"
            icon="i-lucide-plus"
            @click="openNewApp"
          />
        </div>
        <div v-else-if="appStates.length" class="space-y-3">
          <p class="text-xs text-slate-400">
            {{ appStates.length }}
            {{ appStates.length === 1 ? 'estado' : 'estados' }}
            <span v-if="appActiveCount"
class="ml-1"
              >· {{ appActiveCount }} activos</span>
          </p>
          <div
            class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 divide-y divide-slate-100 dark:divide-slate-700 overflow-hidden shadow-sm"
          >
            <div
              v-for="state in appStates"
              :key="state.id"
              class="flex items-center justify-between px-5 py-4 hover:bg-slate-50 dark:hover:bg-slate-700/30 transition-colors"
            >
              <div class="flex items-center gap-3 min-w-0">
                <span
                  class="w-3 h-3 rounded-full flex-shrink-0"
                  :style="{ backgroundColor: state.color }"
                />
                <span
                  class="inline-flex items-center gap-1.5 text-sm font-medium px-2.5 py-1 rounded-full"
                  :style="{
                    backgroundColor: state.color + '18',
                    color: state.color,
                    border: '1px solid ' + state.color + '40',
                  }"
                >
                  {{ state.name }}
                </span>
                <span
                  v-if="!state.is_active"
                  class="text-xs px-2 py-0.5 rounded-full bg-slate-100 text-slate-500 dark:bg-slate-700 dark:text-slate-400 font-medium"
                >
                  {{ $t('JABVOX_MANAGEMENT_STATES.APP_STATES.INACTIVE') }}
                </span>
              </div>
              <div class="flex items-center gap-1 shrink-0 ml-4">
                <button
                  class="p-1.5 rounded-lg text-slate-400 hover:text-woot-600 hover:bg-woot-50 dark:hover:bg-woot-900/20 transition-colors"
                  @click="openEditApp(state)"
                >
                  <span class="i-lucide-pencil text-sm block" />
                </button>
                <button
                  class="p-1.5 rounded-lg text-slate-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                  :disabled="appUiFlags.isDeleting"
                  @click="onDeleteApp(state)"
                >
                  <span class="i-lucide-trash-2 text-sm block" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
      <!-- Tab 3: Campaigns -->
      <div
        v-else-if="activeTab === 'campaigns'"
        class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-6"
      >
        <div class="flex items-start justify-between gap-4">
          <p class="text-body-main text-n-slate-11 max-w-lg">
            {{ $t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.DESCRIPTION') }}
          </p>
          <div class="shrink-0">
            <Button
              :label="$t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.NEW')"
              icon="i-lucide-plus"
              @click="openNewCampaign"
            />
          </div>
        </div>

        <!-- Inline form card -->
        <div
          v-if="showCampaignForm"
          class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 shadow-sm overflow-hidden"
        >
          <div
            class="px-6 py-4 border-b border-slate-100 dark:border-slate-700 flex items-center justify-between"
          >
            <h3
              class="text-sm font-semibold text-slate-800 dark:text-slate-100"
            >
              {{
                editingCampaign
                  ? $t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.EDIT')
                  : $t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.NEW')
              }}
            </h3>
            <button
              class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
              @click="cancelCampaignForm"
            >
              <span class="i-lucide-x text-base block" />
            </button>
          </div>
          <div class="px-6 py-5">
            <div class="space-y-1.5">
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-300"
              >
                {{ $t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.FORM.NAME') }}
                <span class="text-red-500 ml-0.5">*</span>
              </label>
              <input
                v-model="campaignForm.name_jabvox"
                type="text"
                :placeholder="
                  $t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.FORM.NAME_PLACEHOLDER')
                "
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-woot-500 transition"
                @keydown.enter="onSubmitCampaign"
              />
            </div>
          </div>
          <div
            class="px-6 py-4 border-t border-slate-100 dark:border-slate-700 flex gap-2"
          >
            <Button
              :label="
                isCampaignSaving
                  ? $t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.SAVING')
                  : $t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.SAVE')
              "
              :disabled="isCampaignSaving || !campaignForm.name_jabvox.trim()"
              @click="onSubmitCampaign"
            />
            <Button
              variant="clear"
              :label="$t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.CANCEL')"
              @click="cancelCampaignForm"
            />
          </div>
        </div>

        <div
          v-if="campaignsUiFlags.isFetching"
          class="flex items-center justify-center py-20 text-sm text-slate-400 animate-pulse"
        >
          {{ $t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.LOADING') }}
        </div>
        <div
          v-else-if="jabvoxCampaigns.length === 0 && !showCampaignForm"
          class="flex flex-col items-center justify-center py-20 text-center space-y-4"
        >
          <div
            class="w-14 h-14 rounded-2xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center"
          >
            <span class="i-lucide-megaphone text-2xl text-slate-400 block" />
          </div>
          <p class="text-sm font-medium text-slate-700 dark:text-slate-200">
            {{ $t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.EMPTY') }}
          </p>
          <Button
            variant="clear"
            :label="$t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.NEW')"
            icon="i-lucide-plus"
            @click="openNewCampaign"
          />
        </div>
        <div v-else-if="jabvoxCampaigns.length" class="space-y-3">
          <p class="text-xs text-slate-400">
            {{ jabvoxCampaigns.length }}
            {{ jabvoxCampaigns.length === 1 ? 'campaña' : 'campañas' }}
          </p>
          <div
            class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 divide-y divide-slate-100 dark:divide-slate-700 overflow-hidden shadow-sm"
          >
            <div
              v-for="campaign in jabvoxCampaigns"
              :key="campaign.id"
              class="flex items-center justify-between px-5 py-4 hover:bg-slate-50 dark:hover:bg-slate-700/30 transition-colors"
            >
              <div class="flex items-center gap-3 min-w-0">
                <span
                  class="i-lucide-megaphone w-4 h-4 text-slate-400 shrink-0"
                />
                <span
                  class="text-sm font-medium text-slate-800 dark:text-slate-100 truncate"
                >
                  {{ campaign.name }}
                </span>
              </div>
              <div class="flex items-center gap-1 shrink-0 ml-4">
                <button
                  class="p-1.5 rounded-lg text-slate-400 hover:text-woot-600 hover:bg-woot-50 dark:hover:bg-woot-900/20 transition-colors"
                  @click="openEditCampaign(campaign)"
                >
                  <span class="i-lucide-pencil text-sm block" />
                </button>
                <button
                  class="p-1.5 rounded-lg text-slate-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                  :disabled="campaignsUiFlags.isDeleting"
                  @click="onDeleteCampaign(campaign)"
                >
                  <span class="i-lucide-trash-2 text-sm block" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
