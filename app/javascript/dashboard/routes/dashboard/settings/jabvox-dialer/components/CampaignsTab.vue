<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dialerCampaignsAPI } from 'dashboard/api/jabvox/dialer';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SearchInput from './SearchInput.vue';
import CampaignFormDialog from './CampaignFormDialog.vue';
import ReportDialog from './ReportDialog.vue';
import ConfirmDialog from './ConfirmDialog.vue';

const props = defineProps({
  leadCampaigns: { type: Array, default: () => [] },
  leadCampaignOptions: { type: Array, default: () => [] },
  countryOptions: { type: Array, default: () => [] },
  affiliateOptions: { type: Array, default: () => [] },
  inboxOptions: { type: Array, default: () => [] },
  managementStates: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
});

const store = useStore();
const { t } = useI18n();

const campaigns = useMapGetter('jabvoxDialer/getCampaigns');
const uiFlags = useMapGetter('jabvoxDialer/getUIFlags');

const search = ref('');
const togglingId = ref(null);

const formDialog = ref(null);
const reportDialog = ref(null);
const deleteDialog = ref(null);

const STATUS_COLOR = {
  draft: 'slate',
  active: 'teal',
  paused: 'amber',
  completed: 'blue',
};
const statusColor = status => STATUS_COLOR[status] || 'slate';
const canToggle = c => ['draft', 'paused', 'active'].includes(c.status_jabvox);
const canEdit = c => ['draft', 'paused'].includes(c.status_jabvox);
const canDelete = c => c.status_jabvox !== 'active';

const leadCampaignName = id =>
  props.leadCampaigns.find(c => c.id === id)?.name || '';

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return campaigns.value;
  return campaigns.value.filter(c => c.name_jabvox?.toLowerCase().includes(q));
});

// The lead count comes straight from the index endpoint's leads_count_jabvox,
// which the backend computes with the FULL campaign filter set (countries,
// management states, affiliates, inboxes, custom fields AND excluded_lead_ids).
// We must NOT recompute it here with a partial filter set — that caused the same
// campaign to show wildly different counts (e.g. 4 vs 9100) depending on which
// filters the client happened to send.

const onToggle = async c => {
  togglingId.value = c.id;
  try {
    if (c.status_jabvox === 'active') {
      await store.dispatch('jabvoxDialer/pauseCampaign', c.id);
      useAlert(t('JABVOX_DIALER.CAMPAIGN.PAUSED'));
    } else {
      await store.dispatch('jabvoxDialer/startCampaign', c.id);
      useAlert(t('JABVOX_DIALER.CAMPAIGN.STARTED'));
    }
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  } finally {
    togglingId.value = null;
  }
};

const askDelete = c => {
  deleteDialog.value?.open({
    title: t('JABVOX_DIALER.CAMPAIGN.DELETE_TITLE'),
    description: t('JABVOX_DIALER.CAMPAIGN.DELETE_BODY', {
      name: c.name_jabvox,
    }),
    data: c.id,
  });
};

const doDelete = async id => {
  try {
    await store.dispatch('jabvoxDialer/deleteCampaign', id);
    useAlert(t('JABVOX_DIALER.CAMPAIGN.DELETED'));
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  }
};

const leadsOf = c => c.leads_count_jabvox ?? 0;

// One-by-one campaigns expose a live progress endpoint (dialed / remaining /
// pending_retry). last_state campaigns never surface progress (it doesn't apply).
const progressById = ref({});

const loadProgress = async () => {
  const oneByOne = campaigns.value.filter(
    c => c.dial_mode_jabvox === 'one_by_one'
  );
  if (!oneByOne.length) return;
  const results = await Promise.allSettled(
    oneByOne.map(c => dialerCampaignsAPI.getProgress(c.id))
  );
  const next = { ...progressById.value };
  results.forEach((res, idx) => {
    if (res.status === 'fulfilled') {
      next[oneByOne[idx].id] = res.value.data;
    }
  });
  progressById.value = next;
};

onMounted(loadProgress);
// Campaigns arrive asynchronously; reload progress once the list is populated.
watch(() => campaigns.value.length, loadProgress);

const progressOf = c =>
  c.dial_mode_jabvox === 'one_by_one' ? progressById.value[c.id] : null;

defineExpose({ openCreate: () => formDialog.value?.openCreate() });
</script>

<template>
  <div class="flex flex-col gap-5">
    <!-- Loading -->
    <div
      v-if="uiFlags.isFetchingCampaigns"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <!-- Empty -->
    <EmptyStateLayout
      v-else-if="!campaigns.length"
      :title="t('JABVOX_DIALER.CAMPAIGN.EMPTY_TITLE')"
      :subtitle="t('JABVOX_DIALER.CAMPAIGN.EMPTY')"
    >
      <template #actions>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_DIALER.CAMPAIGN.NEW')"
          size="sm"
          @click="formDialog?.openCreate()"
        />
      </template>
    </EmptyStateLayout>

    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <SearchInput
          v-model="search"
          :placeholder="t('JABVOX_DIALER.CAMPAIGN.SEARCH_PLACEHOLDER')"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('JABVOX_DIALER.CAMPAIGN.COUNT', { count: campaigns.length }) }}
        </span>
      </div>

      <div
        v-if="!filtered.length"
        class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_DIALER.CAMPAIGN.NO_RESULTS') }}
      </div>

      <div v-else class="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <div
          v-for="c in filtered"
          :key="c.id"
          class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
        >
          <!-- Header -->
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-center gap-2 min-w-0">
              <span
                class="i-lucide-phone-call size-4 text-n-slate-10 shrink-0"
              />
              <h3 class="text-sm font-semibold text-n-slate-12 truncate">
                {{ c.name_jabvox }}
              </h3>
            </div>
            <Label
              :label="
                t(`JABVOX_DIALER.STATUS.${c.status_jabvox.toUpperCase()}`)
              "
              :color="statusColor(c.status_jabvox)"
              compact
            />
          </div>

          <!-- Source -->
          <p
            v-if="c.jabvox_campaign_id"
            class="flex items-center gap-1.5 text-xs text-n-slate-11 -mt-2"
          >
            <span class="i-lucide-database size-3.5 shrink-0" />
            {{ leadCampaignName(c.jabvox_campaign_id) }}
          </p>

          <!-- One-by-one live progress: dialed / total, remaining, retries -->
          <p
            v-if="progressOf(c)"
            class="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-n-slate-11 -mt-2"
          >
            <span class="i-lucide-list-checks size-3.5 shrink-0 text-n-brand" />
            <span>
              {{
                t('JABVOX_DIALER.CAMPAIGN.PROGRESS_DIALED', {
                  dialed: progressOf(c).dialed,
                  total: progressOf(c).total,
                })
              }}
            </span>
            <span class="text-n-slate-9">·</span>
            <span>
              {{
                t('JABVOX_DIALER.CAMPAIGN.PROGRESS_REMAINING', {
                  count: progressOf(c).remaining,
                })
              }}
            </span>
            <span class="text-n-slate-9">·</span>
            <span>
              {{
                t('JABVOX_DIALER.CAMPAIGN.PROGRESS_RETRY', {
                  count: progressOf(c).pending_retry,
                })
              }}
            </span>
          </p>

          <!-- Metrics grid -->
          <div class="grid grid-cols-4 gap-2">
            <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
              <p class="text-sm font-semibold text-n-slate-12 tabular-nums">
                {{ leadsOf(c).toLocaleString() }}
              </p>
              <p class="text-[11px] text-n-slate-10">
                {{ t('JABVOX_DIALER.CAMPAIGN.METRIC_LEADS') }}
              </p>
            </div>
            <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
              <p class="text-sm font-semibold text-n-slate-12 tabular-nums">
                {{ (c.dialed_count_jabvox || 0).toLocaleString() }}
              </p>
              <p class="text-[11px] text-n-slate-10">
                {{ t('JABVOX_DIALER.CAMPAIGN.METRIC_DIALED') }}
              </p>
            </div>
            <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
              <p class="text-sm font-semibold text-n-teal-11 tabular-nums">
                {{ (c.answered_count_jabvox || 0).toLocaleString() }}
              </p>
              <p class="text-[11px] text-n-slate-10">
                {{ t('JABVOX_DIALER.CAMPAIGN.METRIC_ANSWERED') }}
              </p>
            </div>
            <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
              <p class="text-sm font-semibold text-n-slate-12 tabular-nums">
                {{ (c.agent_ids_jabvox || []).length }}
              </p>
              <p class="text-[11px] text-n-slate-10">
                {{ t('JABVOX_DIALER.CAMPAIGN.METRIC_AGENTS') }}
              </p>
            </div>
          </div>

          <!-- Actions -->
          <div class="flex items-center gap-2 pt-1 border-t border-n-weak">
            <label
              v-if="canToggle(c)"
              class="flex items-center gap-2 text-xs text-n-slate-11 mr-auto pt-3"
            >
              <Spinner v-if="togglingId === c.id" :size="16" />
              <Switch
                v-else
                :model-value="c.status_jabvox === 'active'"
                @update:model-value="onToggle(c)"
              />
              {{
                c.status_jabvox === 'active'
                  ? t('JABVOX_DIALER.CAMPAIGN.PAUSE')
                  : t('JABVOX_DIALER.CAMPAIGN.START')
              }}
            </label>
            <span v-else class="mr-auto" />
            <div class="flex items-center gap-1 pt-3">
              <Button
                icon="i-lucide-bar-chart-2"
                variant="outline"
                color="slate"
                size="sm"
                :title="t('JABVOX_DIALER.CAMPAIGN.REPORT')"
                @click="reportDialog?.open(c)"
              />
              <Button
                v-if="canEdit(c)"
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                :title="t('JABVOX_DIALER.CAMPAIGN.EDIT')"
                @click="formDialog?.openEdit(c)"
              />
              <Button
                v-if="canDelete(c)"
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                :title="t('JABVOX_DIALER.COMMON.DELETE')"
                @click="askDelete(c)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>

    <CampaignFormDialog
      ref="formDialog"
      :is-saving="uiFlags.isSaving"
      :lead-campaign-options="leadCampaignOptions"
      :country-options="countryOptions"
      :affiliate-options="affiliateOptions"
      :inbox-options="inboxOptions"
      :management-states="managementStates"
      :agents="agents"
      @saved="loadProgress"
    />
    <ReportDialog ref="reportDialog" />
    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
