<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SectionCard from './components/SectionCard.vue';
import leadCampaignsAPI from 'dashboard/api/jabvox/leadCampaigns';
import affiliatesAPI from 'dashboard/api/jabvox/affiliates';
import contactsListAPI from 'dashboard/api/jabvox/contactsList';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const funnels = useMapGetter('jabvoxKanban/getFunnels');
const uiFlags = useMapGetter('jabvoxKanban/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

const campaigns = ref([]);
const lifecycleStages = ref([]);
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
  lifecycle_stages_jabvox: [],
  include_own_contacts: false,
});

onMounted(async () => {
  const [, , campaignsResult, affiliatesResult, stagesResult] =
    await Promise.allSettled([
      store.dispatch('jabvoxKanban/fetchFunnels'),
      store.dispatch('inboxes/get'),
      leadCampaignsAPI.getAll(),
      affiliatesAPI.getAll(),
      contactsListAPI.lifecycleStages(),
    ]);
  lifecycleStages.value =
    stagesResult.status === 'fulfilled'
      ? stagesResult.value?.data?.lifecycle_stages || []
      : [];
  campaigns.value =
    campaignsResult.status === 'fulfilled' &&
    Array.isArray(campaignsResult.value?.data)
      ? campaignsResult.value.data
      : [];
  affiliates.value =
    affiliatesResult.status === 'fulfilled' &&
    Array.isArray(affiliatesResult.value?.data)
      ? affiliatesResult.value.data
      : [];

  if (existingFunnel.value) {
    form.value = {
      name_jabvox: existingFunnel.value.name_jabvox,
      description_jabvox: existingFunnel.value.description_jabvox || '',
      active_jabvox: existingFunnel.value.active_jabvox,
      inbox_ids: existingFunnel.value.inbox_ids || [],
      campaign_ids: existingFunnel.value.campaign_ids || [],
      affiliate_ids: existingFunnel.value.affiliate_ids || [],
      lifecycle_stages_jabvox:
        existingFunnel.value.lifecycle_stages_jabvox || [],
      include_own_contacts: existingFunnel.value.include_own_contacts ?? false,
    };
  }
});

const toggleIn = (list, id) => {
  const arr = form.value[list];
  form.value[list] = arr.includes(id)
    ? arr.filter(x => x !== id)
    : [...arr, id];
};
const isInboxSelected = id => form.value.inbox_ids.includes(id);
const isCampaignSelected = id => form.value.campaign_ids.includes(id);
const isAffiliateSelected = id => form.value.affiliate_ids.includes(id);
const isLifecycleSelected = id =>
  form.value.lifecycle_stages_jabvox.includes(id);

const isSubmitting = computed(
  () => uiFlags.value.isCreatingFunnel || uiFlags.value.isUpdatingFunnel
);
const isValid = computed(() => form.value.name_jabvox.trim().length > 0);

const onSubmit = async () => {
  if (!isValid.value) {
    useAlert(t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.NAME_REQUIRED'));
    return;
  }
  try {
    const payload = {
      funnel: {
        name_jabvox: form.value.name_jabvox.trim(),
        description_jabvox: form.value.description_jabvox,
        active_jabvox: form.value.active_jabvox,
        include_own_contacts_jabvox: form.value.include_own_contacts,
      },
      inbox_ids: form.value.inbox_ids,
      campaign_ids: form.value.campaign_ids,
      affiliate_ids: form.value.affiliate_ids,
      lifecycle_stages_jabvox: form.value.lifecycle_stages_jabvox,
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
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-3xl flex flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div class="flex items-center gap-3">
        <Button
          icon="i-lucide-arrow-left"
          variant="ghost"
          color="slate"
          size="sm"
          @click="onCancel"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{
              isEditing
                ? t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.EDIT_TITLE')
                : t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.NEW_TITLE')
            }}
          </h1>
          <p class="mt-0.5 text-sm text-n-slate-11">
            {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.DESCRIPTION') }}
          </p>
        </div>
      </div>

      <!-- General -->
      <SectionCard
        :title="t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.SECTION_GENERAL')"
        icon="i-lucide-settings-2"
      >
        <div class="flex flex-col gap-4">
          <Input
            v-model="form.name_jabvox"
            :label="`${t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.NAME_LABEL')} *`"
            :placeholder="
              t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.NAME_PLACEHOLDER')
            "
            autofocus
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.DESCRIPTION_LABEL') }}
            </label>
            <textarea
              v-model="form.description_jabvox"
              rows="3"
              :placeholder="
                t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.DESCRIPTION_PLACEHOLDER')
              "
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y"
            />
          </div>
          <div
            class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
          >
            <div class="flex flex-col">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.ACTIVE_LABEL') }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.ACTIVE_HINT') }}
              </span>
            </div>
            <Switch v-model="form.active_jabvox" />
          </div>
        </div>
      </SectionCard>

      <!-- Sources -->
      <SectionCard
        :title="t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.SECTION_SOURCES')"
        icon="i-lucide-filter"
      >
        <div class="flex flex-col gap-5">
          <!-- Inboxes -->
          <div class="flex flex-col gap-2">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.INBOXES_LABEL') }}
            </label>
            <div
              class="flex flex-col gap-1 max-h-48 overflow-y-auto rounded-xl border border-n-weak p-2"
            >
              <p
                v-if="!inboxes.length"
                class="text-xs text-n-slate-10 text-center py-2"
              >
                {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.INBOXES_EMPTY') }}
              </p>
              <label
                v-for="inbox in inboxes"
                :key="inbox.id"
                class="flex items-center gap-2 rounded-lg px-2 py-1.5 cursor-pointer hover:bg-n-alpha-1 text-sm text-n-slate-12"
              >
                <input
                  type="checkbox"
                  :checked="isInboxSelected(inbox.id)"
                  class="rounded accent-n-brand"
                  @change="toggleIn('inbox_ids', inbox.id)"
                />
                {{ inbox.name }}
              </label>
            </div>
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.INBOXES_HINT') }}
            </p>
          </div>

          <!-- Campaigns -->
          <div class="flex flex-col gap-2">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.CAMPAIGNS_LABEL') }}
            </label>
            <div
              class="flex flex-col gap-1 max-h-48 overflow-y-auto rounded-xl border border-n-weak p-2"
            >
              <p
                v-if="!campaigns.length"
                class="text-xs text-n-slate-10 text-center py-2"
              >
                {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.CAMPAIGNS_EMPTY') }}
              </p>
              <label
                v-for="campaign in campaigns"
                :key="campaign.id"
                class="flex items-center gap-2 rounded-lg px-2 py-1.5 cursor-pointer hover:bg-n-alpha-1 text-sm text-n-slate-12"
              >
                <input
                  type="checkbox"
                  :checked="isCampaignSelected(campaign.id)"
                  class="rounded accent-n-brand"
                  @change="toggleIn('campaign_ids', campaign.id)"
                />
                {{ campaign.name }}
              </label>
            </div>
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.CAMPAIGNS_HINT') }}
            </p>
          </div>

          <!-- Etapa del contacto: sustituye a la distinción "es lead / no es lead" y permite
               embudos como "reactivación de inactivos" sin depender de bandeja ni campaña. -->
          <div class="flex flex-col gap-2">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.STAGES_LABEL') }}
            </label>
            <div
              class="flex flex-col gap-1 rounded-xl border border-n-weak p-2"
            >
              <label
                v-for="stage in lifecycleStages"
                :key="stage.id"
                class="flex items-center gap-2 rounded-lg px-2 py-1.5 cursor-pointer hover:bg-n-alpha-1 text-sm text-n-slate-12"
              >
                <input
                  type="checkbox"
                  :checked="isLifecycleSelected(stage.id)"
                  class="rounded accent-n-brand"
                  @change="toggleIn('lifecycle_stages_jabvox', stage.id)"
                />
                {{ stage.name }}
              </label>
            </div>
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.STAGES_HINT') }}
            </p>
          </div>

          <!-- Affiliates -->
          <div class="flex flex-col gap-2">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.AFFILIATES_LABEL') }}
            </label>
            <div
              class="flex flex-col gap-1 max-h-48 overflow-y-auto rounded-xl border border-n-weak p-2"
            >
              <label
                class="flex items-center gap-2 rounded-lg px-2 py-1.5 cursor-pointer hover:bg-n-alpha-1 text-sm font-medium text-n-slate-12"
              >
                <input
                  v-model="form.include_own_contacts"
                  type="checkbox"
                  class="rounded accent-n-brand"
                />
                {{ t('JABVOX_LEADS.TABLE.AFFILIATE_OWN') }}
              </label>
              <label
                v-for="affiliate in affiliates"
                :key="affiliate.id"
                class="flex items-center gap-2 rounded-lg px-2 py-1.5 cursor-pointer hover:bg-n-alpha-1 text-sm text-n-slate-12"
              >
                <input
                  type="checkbox"
                  :checked="isAffiliateSelected(affiliate.id)"
                  class="rounded accent-n-brand"
                  @change="toggleIn('affiliate_ids', affiliate.id)"
                />
                {{ affiliate.name }}
              </label>
            </div>
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.AFFILIATES_HINT') }}
            </p>
          </div>
        </div>

        <template #footer>
          <div class="flex items-center justify-end gap-2">
            <Button
              :label="t('JABVOX_KANBAN.COMMON.CANCEL')"
              variant="outline"
              color="slate"
              @click="onCancel"
            />
            <Button
              :label="
                isEditing
                  ? t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.UPDATE_BUTTON')
                  : t('JABVOX_KANBAN.SETTINGS.FUNNELS.FORM.CREATE_BUTTON')
              "
              :is-loading="isSubmitting"
              :disabled="!isValid"
              @click="onSubmit"
            />
          </div>
        </template>
      </SectionCard>
    </div>
  </div>
</template>
