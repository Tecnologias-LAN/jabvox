<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dialerCampaignsAPI } from 'dashboard/api/jabvox/dialer';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

defineProps({
  isSaving: { type: Boolean, default: false },
  leadCampaignOptions: { type: Array, default: () => [] },
  countryOptions: { type: Array, default: () => [] },
  affiliateOptions: { type: Array, default: () => [] },
  inboxOptions: { type: Array, default: () => [] },
  managementStates: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved']);
const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const editingId = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  jabvox_campaign_id: null,
  countries_jabvox: [],
  wrapup_time_jabvox: 30,
  lines_per_agent_jabvox: 1,
  wait_in_queue_jabvox: true,
  management_state_ids_jabvox: [],
  agent_ids_jabvox: [],
  affiliate_ids_jabvox: [],
  inbox_ids_jabvox: [],
});
const form = ref(emptyForm());

const title = computed(() =>
  editingId.value
    ? t('JABVOX_DIALER.CAMPAIGN.EDIT_TITLE')
    : t('JABVOX_DIALER.CAMPAIGN.NEW')
);
const isValid = computed(
  () =>
    form.value.name_jabvox.trim().length > 0 && !!form.value.jabvox_campaign_id
);

// ─── lead count live preview ───
const leadCount = ref(null);
const loadingLeadCount = ref(false);
let leadCountTimer = null;

const fetchLeadCount = async () => {
  if (!form.value.jabvox_campaign_id) {
    leadCount.value = null;
    return;
  }
  loadingLeadCount.value = true;
  try {
    const { data } = await dialerCampaignsAPI.leadCount({
      jabvox_campaign_id: form.value.jabvox_campaign_id,
      countries: form.value.countries_jabvox,
      management_state_ids: form.value.management_state_ids_jabvox,
      affiliate_ids: form.value.affiliate_ids_jabvox,
      inbox_ids: form.value.inbox_ids_jabvox,
    });
    leadCount.value = data.count;
  } catch {
    leadCount.value = null;
  } finally {
    loadingLeadCount.value = false;
  }
};

const debouncedFetchLeadCount = () => {
  clearTimeout(leadCountTimer);
  leadCountTimer = setTimeout(fetchLeadCount, 400);
};

watch(
  () => [
    form.value.jabvox_campaign_id,
    form.value.countries_jabvox.length,
    form.value.management_state_ids_jabvox.length,
    form.value.affiliate_ids_jabvox.length,
    form.value.inbox_ids_jabvox.length,
  ],
  debouncedFetchLeadCount
);

const toggleManagementState = id => {
  const list = form.value.management_state_ids_jabvox;
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};

const toggleAgent = id => {
  const list = form.value.agent_ids_jabvox;
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};

const openCreate = () => {
  editingId.value = null;
  form.value = emptyForm();
  leadCount.value = null;
  nextTick(() => dialogRef.value?.open());
};

const openEdit = c => {
  editingId.value = c.id;
  leadCount.value = null;
  form.value = {
    name_jabvox: c.name_jabvox,
    jabvox_campaign_id: c.jabvox_campaign_id || null,
    countries_jabvox: [...(c.countries_jabvox || [])],
    wrapup_time_jabvox: c.wrapup_time_jabvox ?? 30,
    lines_per_agent_jabvox: c.lines_per_agent_jabvox ?? 1,
    wait_in_queue_jabvox: c.wait_in_queue_jabvox ?? true,
    management_state_ids_jabvox: [...(c.management_state_ids_jabvox || [])],
    agent_ids_jabvox: [...(c.agent_ids_jabvox || [])],
    affiliate_ids_jabvox: [...(c.affiliate_ids_jabvox || [])],
    inbox_ids_jabvox: [...(c.inbox_ids_jabvox || [])],
  };
  nextTick(() => dialogRef.value?.open());
  if (c.jabvox_campaign_id) debouncedFetchLeadCount();
};

const close = () => dialogRef.value?.close();

const handleConfirm = async () => {
  if (!isValid.value) return;
  try {
    const payload = {
      ...form.value,
      jabvox_campaign_id: form.value.jabvox_campaign_id || null,
      leads_count_jabvox: leadCount.value ?? 0,
    };
    if (editingId.value) {
      await store.dispatch('jabvoxDialer/updateCampaign', {
        id: editingId.value,
        ...payload,
      });
    } else {
      await store.dispatch('jabvoxDialer/createCampaign', payload);
    }
    close();
    useAlert(t('JABVOX_DIALER.CAMPAIGN.SAVE_SUCCESS'));
    emit('saved');
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  }
};

const stateChecked = id => form.value.management_state_ids_jabvox.includes(id);
const agentChecked = id => form.value.agent_ids_jabvox.includes(id);

defineExpose({ openCreate, openEdit, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('JABVOX_DIALER.CAMPAIGN.FORM_SUBTITLE')"
    :confirm-button-label="t('JABVOX_DIALER.COMMON.SAVE')"
    :cancel-button-label="t('JABVOX_DIALER.COMMON.CANCEL')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    width="2xl"
    overflow-y-auto
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-6">
      <!-- Group: source -->
      <section class="flex flex-col gap-4">
        <h3
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_SOURCE') }}
        </h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model="form.name_jabvox"
            :label="t('JABVOX_DIALER.FORM.NAME')"
            :placeholder="t('JABVOX_DIALER.FORM.NAME_PLACEHOLDER')"
            autofocus
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DIALER.FORM.LEAD_CAMPAIGN') }}
            </label>
            <ComboBox
              v-model="form.jabvox_campaign_id"
              :options="leadCampaignOptions"
              :placeholder="t('JABVOX_DIALER.FORM.LEAD_CAMPAIGN_PLACEHOLDER')"
              :search-placeholder="
                t('JABVOX_DIALER.FORM.LEAD_CAMPAIGN_PLACEHOLDER')
              "
            />
          </div>
        </div>
      </section>

      <!-- Group: targeting -->
      <section class="flex flex-col gap-4">
        <h3
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_TARGETING') }}
        </h3>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_DIALER.FORM.COUNTRIES') }}
          </label>
          <TagMultiSelectComboBox
            v-model="form.countries_jabvox"
            :options="countryOptions"
            :placeholder="t('JABVOX_DIALER.FORM.COUNTRIES_PLACEHOLDER')"
            :search-placeholder="t('JABVOX_DIALER.FORM.COUNTRIES_SEARCH')"
          />
          <p class="text-xs text-n-slate-10">
            {{ t('JABVOX_DIALER.FORM.COUNTRIES_HINT') }}
          </p>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DIALER.FORM.AFFILIATES') }}
            </label>
            <TagMultiSelectComboBox
              v-model="form.affiliate_ids_jabvox"
              :options="affiliateOptions"
              :placeholder="t('JABVOX_DIALER.FORM.AFFILIATES')"
              :search-placeholder="t('JABVOX_DIALER.FORM.AFFILIATES')"
            />
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DIALER.FORM.INBOXES') }}
            </label>
            <TagMultiSelectComboBox
              v-model="form.inbox_ids_jabvox"
              :options="inboxOptions"
              :placeholder="t('JABVOX_DIALER.FORM.INBOXES')"
              :search-placeholder="t('JABVOX_DIALER.FORM.INBOXES')"
            />
          </div>
        </div>
        <!-- Management states -->
        <div class="flex flex-col gap-2">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_DIALER.FORM.MANAGEMENT_STATES') }}
          </label>
          <p class="text-xs text-n-slate-10 -mt-1">
            {{ t('JABVOX_DIALER.FORM.MANAGEMENT_STATES_HINT') }}
          </p>
          <div
            class="flex flex-col gap-1 max-h-44 overflow-y-auto rounded-xl border border-n-weak p-2"
          >
            <label
              class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-12 select-none rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                :checked="stateChecked('none')"
                class="rounded accent-n-brand"
                @change="toggleManagementState('none')"
              />
              {{ t('JABVOX_DIALER.FORM.NO_MANAGEMENT_STATE') }}
            </label>
            <label
              v-for="ms in managementStates"
              :key="ms.id"
              class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-12 select-none rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                :checked="stateChecked(ms.id)"
                class="rounded accent-n-brand"
                @change="toggleManagementState(ms.id)"
              />
              <span
                class="w-2.5 h-2.5 rounded-full shrink-0"
                :style="{ backgroundColor: ms.color_jabvox }"
              />
              {{ ms.name_jabvox }}
            </label>
          </div>
        </div>
      </section>

      <!-- Group: dialing -->
      <section class="flex flex-col gap-4">
        <h3
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_DIALING') }}
        </h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model.number="form.wrapup_time_jabvox"
            type="number"
            min="0"
            :label="t('JABVOX_DIALER.FORM.WRAPUP_TIME')"
            :message="t('JABVOX_DIALER.FORM.WRAPUP_TIME_HINT')"
          />
          <Input
            v-model.number="form.lines_per_agent_jabvox"
            type="number"
            min="1"
            max="10"
            :label="t('JABVOX_DIALER.FORM.LINES_PER_AGENT')"
            :message="t('JABVOX_DIALER.FORM.LINES_PER_AGENT_HINT')"
          />
        </div>
        <div
          class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
        >
          <div class="flex flex-col">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DIALER.FORM.WAIT_IN_QUEUE') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('JABVOX_DIALER.FORM.WAIT_IN_QUEUE_HINT') }}
            </span>
          </div>
          <Switch v-model="form.wait_in_queue_jabvox" />
        </div>
      </section>

      <!-- Group: assignment -->
      <section class="flex flex-col gap-2">
        <h3
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_ASSIGNMENT') }}
        </h3>
        <p class="text-xs text-n-slate-10">
          {{ t('JABVOX_DIALER.FORM.AGENTS_HINT') }}
        </p>
        <div
          class="flex flex-col gap-1 max-h-44 overflow-y-auto rounded-xl border border-n-weak p-2"
        >
          <label
            v-for="agent in agents"
            :key="agent.id"
            class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-12 select-none rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              :checked="agentChecked(agent.id)"
              class="rounded accent-n-brand"
              @change="toggleAgent(agent.id)"
            />
            <span class="truncate">{{ agent.name }}</span>
            <span class="text-xs text-n-slate-10 truncate">{{
              agent.email
            }}</span>
          </label>
        </div>
      </section>

      <!-- Lead count preview -->
      <div
        v-if="form.jabvox_campaign_id"
        class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
      >
        <span class="flex items-center gap-2 text-sm text-n-slate-12">
          <span class="i-lucide-users size-4 text-n-brand" />
          {{ t('JABVOX_DIALER.FORM.LEAD_COUNT_LABEL') }}
        </span>
        <span
          v-if="loadingLeadCount"
          class="flex items-center gap-1.5 text-sm text-n-slate-10"
        >
          <Spinner :size="14" />
        </span>
        <span
          v-else-if="leadCount != null"
          class="text-sm font-semibold text-n-brand tabular-nums"
        >
          {{ leadCount.toLocaleString() }}
          {{ t('JABVOX_DIALER.FORM.LEAD_COUNT_UNIT') }}
        </span>
        <span v-else class="text-sm text-n-slate-10">—</span>
      </div>
    </div>
  </Dialog>
</template>
