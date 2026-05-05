<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import leadCampaignsAPI from 'dashboard/api/jabvox/leadCampaigns';
import affiliatesAPI from 'dashboard/api/jabvox/affiliates';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const funnels = useMapGetter('jabvoxKanban/getFunnels');
const uiFlags = useMapGetter('jabvoxKanban/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

const campaigns = ref([]);
const affiliates = ref([]);

const isEditing = computed(() => !!route.params.funnelId);
const funnelId = computed(() =>
  route.params.funnelId ? parseInt(route.params.funnelId, 10) : null
);

const existingFunnel = computed(() =>
  isEditing.value ? funnels.value.find(f => f.id === funnelId.value) : null
);

const form = ref({
  name_jabvox: '',
  description_jabvox: '',
  active_jabvox: true,
  inbox_ids: [],
  campaign_ids: [],
  affiliate_ids: [],
});

onMounted(async () => {
  const [, , campaignsRes, affiliatesRes] = await Promise.all([
    store.dispatch('jabvoxKanban/fetchFunnels'),
    store.dispatch('inboxes/get'),
    leadCampaignsAPI.getAll(),
    affiliatesAPI.getAll(),
  ]);
  campaigns.value = Array.isArray(campaignsRes?.data) ? campaignsRes.data : [];
  affiliates.value = Array.isArray(affiliatesRes?.data)
    ? affiliatesRes.data
    : [];

  if (existingFunnel.value) {
    form.value = {
      name_jabvox: existingFunnel.value.name_jabvox,
      description_jabvox: existingFunnel.value.description_jabvox || '',
      active_jabvox: existingFunnel.value.active_jabvox,
      inbox_ids: existingFunnel.value.inbox_ids || [],
      campaign_ids: existingFunnel.value.campaign_ids || [],
      affiliate_ids: existingFunnel.value.affiliate_ids || [],
    };
  }
});

const isInboxSelected = inboxId => form.value.inbox_ids.includes(inboxId);
const toggleInbox = inboxId => {
  if (isInboxSelected(inboxId)) {
    form.value.inbox_ids = form.value.inbox_ids.filter(id => id !== inboxId);
  } else {
    form.value.inbox_ids = [...form.value.inbox_ids, inboxId];
  }
};

const isCampaignSelected = id => form.value.campaign_ids.includes(id);
const toggleCampaign = id => {
  if (isCampaignSelected(id)) {
    form.value.campaign_ids = form.value.campaign_ids.filter(c => c !== id);
  } else {
    form.value.campaign_ids = [...form.value.campaign_ids, id];
  }
};

const isAffiliateSelected = id => form.value.affiliate_ids.includes(id);
const toggleAffiliate = id => {
  if (isAffiliateSelected(id)) {
    form.value.affiliate_ids = form.value.affiliate_ids.filter(a => a !== id);
  } else {
    form.value.affiliate_ids = [...form.value.affiliate_ids, id];
  }
};

const isSubmitting = computed(
  () => uiFlags.value.isCreatingFunnel || uiFlags.value.isUpdatingFunnel
);

const onSubmit = async () => {
  if (!form.value.name_jabvox.trim()) {
    useAlert(t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.NAME_REQUIRED'));
    return;
  }

  try {
    const payload = {
      funnel: {
        name_jabvox: form.value.name_jabvox.trim(),
        description_jabvox: form.value.description_jabvox,
        active_jabvox: form.value.active_jabvox,
      },
      inbox_ids: form.value.inbox_ids,
      campaign_ids: form.value.campaign_ids,
      affiliate_ids: form.value.affiliate_ids,
    };

    if (isEditing.value) {
      await store.dispatch('jabvoxKanban/updateFunnel', {
        id: funnelId.value,
        ...payload,
      });
      await store.dispatch('jabvoxKanban/fetchFunnels');
      useAlert(t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.UPDATE_SUCCESS'));
      router.push({ name: 'jabvox_kanban_funnels_index' });
    } else {
      const createdFunnel = await store.dispatch(
        'jabvoxKanban/createFunnel',
        payload
      );
      await store.dispatch('jabvoxKanban/fetchFunnels');
      useAlert(t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.CREATE_SUCCESS'));
      router.push({
        name: 'jabvox_kanban_stages',
        params: { funnelId: createdFunnel.id },
      });
    }
  } catch (error) {
    useAlert(error.message || t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.ERROR'));
  }
};

const onCancel = () => router.push({ name: 'jabvox_kanban_funnels_index' });
</script>

<template>
  <SettingsLayout>
    <div class="px-4 sm:px-6 lg:px-8 pb-6 pt-3 sm:pt-4">
      <BaseSettingsHeader
        :title="
          isEditing
            ? $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.EDIT_TITLE')
            : $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.NEW_TITLE')
        "
        :description="$t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.DESCRIPTION')"
      />

      <div class="max-w-2xl mx-auto">
        <div
          class="mt-6 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-2xl p-6 sm:p-8 shadow-sm space-y-6"
        >
          <!-- Name -->
          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.NAME_LABEL') }} *
            </label>
            <input
              v-model="form.name_jabvox"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="
                $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.NAME_PLACEHOLDER')
              "
            />
          </div>

          <!-- Description -->
          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.DESCRIPTION_LABEL') }}
            </label>
            <textarea
              v-model="form.description_jabvox"
              rows="3"
              class="w-full resize-none rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="
                $t(
                  'JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.DESCRIPTION_PLACEHOLDER'
                )
              "
            />
          </div>

          <!-- Inboxes -->
          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2"
            >
              {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.INBOXES_LABEL') }}
            </label>
            <div
              class="space-y-2 max-h-48 overflow-y-auto border border-slate-200 dark:border-slate-700 rounded-lg p-3"
            >
              <p
                v-if="!inboxes.length"
                class="text-xs text-slate-400 text-center py-2"
              >
                {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.INBOXES_EMPTY') }}
              </p>
              <label
                v-for="inbox in inboxes"
                :key="inbox.id"
                class="flex items-center gap-3 p-2 rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 cursor-pointer"
              >
                <input
                  type="checkbox"
                  :checked="isInboxSelected(inbox.id)"
                  class="rounded text-woot-500 focus:ring-woot-500"
                  @change="toggleInbox(inbox.id)"
                />
                <span class="text-sm text-slate-700 dark:text-slate-300">{{
                  inbox.name
                }}</span>
              </label>
            </div>
            <p class="mt-1 text-xs text-slate-400">
              {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.INBOXES_HINT') }}
            </p>
          </div>

          <!-- Campaigns -->
          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2"
            >
              {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.CAMPAIGNS_LABEL') }}
            </label>
            <div
              class="space-y-2 max-h-48 overflow-y-auto border border-slate-200 dark:border-slate-700 rounded-lg p-3"
            >
              <p
                v-if="!campaigns.length"
                class="text-xs text-slate-400 text-center py-2"
              >
                {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.CAMPAIGNS_EMPTY') }}
              </p>
              <label
                v-for="campaign in campaigns"
                :key="campaign.id"
                class="flex items-center gap-3 p-2 rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 cursor-pointer"
              >
                <input
                  type="checkbox"
                  :checked="isCampaignSelected(campaign.id)"
                  class="rounded text-woot-500 focus:ring-woot-500"
                  @change="toggleCampaign(campaign.id)"
                />
                <span class="text-sm text-slate-700 dark:text-slate-300">{{
                  campaign.name
                }}</span>
              </label>
            </div>
            <p class="mt-1 text-xs text-slate-400">
              {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.CAMPAIGNS_HINT') }}
            </p>
          </div>

          <!-- Affiliates -->
          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2"
            >
              {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.AFFILIATES_LABEL') }}
            </label>
            <div
              class="space-y-2 max-h-48 overflow-y-auto border border-slate-200 dark:border-slate-700 rounded-lg p-3"
            >
              <p
                v-if="!affiliates.length"
                class="text-xs text-slate-400 text-center py-2"
              >
                {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.AFFILIATES_EMPTY') }}
              </p>
              <label
                v-for="affiliate in affiliates"
                :key="affiliate.id"
                class="flex items-center gap-3 p-2 rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 cursor-pointer"
              >
                <input
                  type="checkbox"
                  :checked="isAffiliateSelected(affiliate.id)"
                  class="rounded text-woot-500 focus:ring-woot-500"
                  @change="toggleAffiliate(affiliate.id)"
                />
                <span class="text-sm text-slate-700 dark:text-slate-300">{{
                  affiliate.name
                }}</span>
              </label>
            </div>
            <p class="mt-1 text-xs text-slate-400">
              {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.AFFILIATES_HINT') }}
            </p>
          </div>

          <!-- Active toggle -->
          <div class="flex items-center gap-3">
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                v-model="form.active_jabvox"
                type="checkbox"
                class="rounded text-woot-500 focus:ring-woot-500"
              />
              <span
                class="text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.ACTIVE_LABEL') }}
              </span>
            </label>
          </div>

          <!-- Actions -->
          <div class="flex flex-wrap items-center gap-3 pt-2">
            <Button
              :label="
                isEditing
                  ? $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.UPDATE_BUTTON')
                  : $t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.CREATE_BUTTON')
              "
              :is-loading="isSubmitting"
              @click="onSubmit"
            />
            <Button variant="ghost" :label="$t('CANCEL')" @click="onCancel" />
          </div>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
