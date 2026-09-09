<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import whatsappGroupsAPI from 'dashboard/api/jabvox/whatsappGroups';
import GroupCreateDialog from './components/GroupCreateDialog.vue';
import GroupDetailDialog from './components/GroupDetailDialog.vue';

const { t } = useI18n();
const allInboxes = useMapGetter('inboxes/getInboxes');

// Only WhatsApp Cloud inboxes can host groups (Meta rule); 360dialog/Twilio excluded.
const inboxes = computed(() =>
  (allInboxes.value || []).filter(ib => ib.channel_type === 'Channel::Whatsapp')
);

const selectedInboxId = ref(null);
const eligibility = ref(null); // { eligible, reason, feature_enabled }
const groups = ref([]);
const loading = ref(false);
const createDialog = ref(null);
const detailDialog = ref(null);

const MAX_MEMBERS = 8;

const ineligibleReasonText = computed(() => {
  const reason = eligibility.value?.reason;
  if (!reason) return '';
  return t(
    `JABVOX_WHATSAPP_GROUPS.ELIGIBILITY.REASONS.${reason.toUpperCase()}`
  );
});

const isEligible = computed(() => eligibility.value?.eligible === true);

// Chip de estado del grupo (activo/archivado/borrador) con color.
const statusChipClass = status => {
  const map = {
    active: 'bg-green-100 text-green-700',
    archived: 'bg-n-alpha-2 text-n-slate-11',
    draft: 'bg-amber-100 text-amber-700',
  };
  return map[status] || 'bg-n-alpha-2 text-n-slate-11';
};

const checkEligibility = async () => {
  if (!selectedInboxId.value) return;
  try {
    const { data } = await whatsappGroupsAPI.eligibility(selectedInboxId.value);
    eligibility.value = data;
  } catch (error) {
    eligibility.value = { eligible: false, reason: 'error' };
  }
};

const loadGroups = async () => {
  loading.value = true;
  try {
    const { data } = await whatsappGroupsAPI.getGroups();
    groups.value = data;
  } catch (error) {
    useAlert(t('JABVOX_WHATSAPP_GROUPS.LIST.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const onInboxChange = async () => {
  await checkEligibility();
};

const openCreate = () => {
  createDialog.value?.open(selectedInboxId.value);
};

const openDetail = group => {
  detailDialog.value?.open(group.id);
};

const onCreated = () => {
  loadGroups();
};

onMounted(async () => {
  if (inboxes.value.length) {
    selectedInboxId.value = inboxes.value[0].id;
    await checkEligibility();
  }
  await loadGroups();
});
</script>

<template>
  <div class="flex flex-col gap-6 p-6 max-w-5xl mx-auto w-full">
    <!-- Header -->
    <header class="flex items-start justify-between gap-4 flex-wrap">
      <div class="flex items-start gap-3">
        <span
          class="flex items-center justify-center w-11 h-11 rounded-xl bg-gradient-to-br from-green-500 to-teal-600 text-white shadow-sm shrink-0"
        >
          <fluent-icon icon="people-team" size="22" />
        </span>
        <div>
          <h1
            class="text-xl font-semibold tracking-tight text-n-slate-12 leading-tight"
          >
            {{ t('JABVOX_WHATSAPP_GROUPS.TITLE') }}
          </h1>
          <p class="text-sm text-n-slate-11 mt-0.5 max-w-xl">
            {{ t('JABVOX_WHATSAPP_GROUPS.SUBTITLE') }}
          </p>
        </div>
      </div>
      <woot-button
        v-if="isEligible"
        size="small"
        icon="add"
        color-scheme="success"
        @click="openCreate"
      >
        {{ t('JABVOX_WHATSAPP_GROUPS.CREATE.BUTTON') }}
      </woot-button>
    </header>

    <!-- Inbox selector card -->
    <div
      v-if="inboxes.length"
      class="flex flex-col sm:flex-row sm:items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    >
      <label
        class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 sm:w-40 shrink-0"
      >
        {{ t('JABVOX_WHATSAPP_GROUPS.INBOX_LABEL') }}
      </label>
      <select
        v-model="selectedInboxId"
        class="reset-base flex-1 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-background text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors"
        @change="onInboxChange"
      >
        <option v-for="ib in inboxes" :key="ib.id" :value="ib.id">
          {{ ib.name }}
        </option>
      </select>
      <span
        v-if="isEligible"
        class="shrink-0 inline-flex items-center gap-1.5 rounded-full bg-green-100 px-2.5 py-1 text-[11px] font-semibold text-green-700"
      >
        <span class="w-1.5 h-1.5 rounded-full bg-green-500" />
        {{ t('JABVOX_WHATSAPP_GROUPS.ELIGIBILITY.ELIGIBLE') }}
      </span>
    </div>
    <div
      v-else
      class="rounded-xl border border-n-weak bg-n-alpha-1 p-6 text-center"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('JABVOX_WHATSAPP_GROUPS.NO_CLOUD_INBOX') }}
      </p>
    </div>

    <!-- Ineligibility banner -->
    <div
      v-if="selectedInboxId && !isEligible"
      class="flex items-start gap-3 rounded-xl border border-amber-300 bg-amber-50 dark:bg-amber-900/20 dark:border-amber-700 p-4"
    >
      <fluent-icon
        icon="warning"
        size="18"
        class="text-amber-600 dark:text-amber-300 shrink-0 mt-0.5"
      />
      <div>
        <p class="text-sm font-semibold text-amber-800 dark:text-amber-200">
          {{ t('JABVOX_WHATSAPP_GROUPS.ELIGIBILITY.BLOCKED_TITLE') }}
        </p>
        <p class="text-sm text-amber-700 dark:text-amber-300 mt-1">
          {{ ineligibleReasonText }}
        </p>
      </div>
    </div>

    <!-- Group management (only when eligible) -->
    <template v-if="isEligible">
      <p class="flex items-center gap-1.5 text-xs text-n-slate-10 -mt-2">
        <fluent-icon icon="info" size="13" />
        {{ t('JABVOX_WHATSAPP_GROUPS.INVITE_ONLY_HINT', { max: MAX_MEMBERS }) }}
      </p>

      <!-- Group cards grid -->
      <div
        v-if="groups.length"
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
      >
        <button
          v-for="g in groups"
          :key="g.id"
          type="button"
          class="reset-base flex flex-col text-left rounded-xl border border-n-weak bg-n-solid-1 p-4 hover:border-n-slate-6 hover:shadow-sm transition-all"
          @click="openDetail(g)"
        >
          <div class="flex items-start justify-between gap-2 mb-2">
            <span
              class="flex items-center justify-center w-9 h-9 rounded-lg bg-n-teal-9/12 text-n-teal-11 shrink-0"
            >
              <fluent-icon icon="people-team" size="18" />
            </span>
            <span
              class="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
              :class="statusChipClass(g.status)"
            >
              {{ t(`JABVOX_WHATSAPP_GROUPS.STATUS.${g.status.toUpperCase()}`) }}
            </span>
          </div>
          <h3 class="text-sm font-semibold text-n-slate-12 truncate">
            {{ g.name }}
          </h3>
          <!-- Members progress -->
          <div class="mt-3">
            <div
              class="flex items-center justify-between text-[11px] text-n-slate-10 mb-1"
            >
              <span>{{ t('JABVOX_WHATSAPP_GROUPS.TABLE.MEMBERS') }}</span>
              <span class="tabular-nums font-medium text-n-slate-11">
                {{ g.active_members_count }} / {{ g.max_members }}
              </span>
            </div>
            <div class="h-1.5 w-full rounded-full bg-n-alpha-2 overflow-hidden">
              <div
                class="h-full rounded-full bg-n-teal-9"
                :style="{
                  width: `${Math.min(100, (g.active_members_count / g.max_members) * 100)}%`,
                }"
              />
            </div>
          </div>
          <span
            class="mt-3 inline-flex items-center gap-1 text-xs font-medium text-n-teal-11"
          >
            {{ t('JABVOX_WHATSAPP_GROUPS.TABLE.MANAGE') }}
            <fluent-icon icon="chevron-right" size="12" />
          </span>
        </button>
      </div>

      <!-- Empty state -->
      <div
        v-else-if="!loading"
        class="flex flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-n-weak bg-n-alpha-1 py-12 px-6 text-center"
      >
        <span
          class="flex items-center justify-center w-14 h-14 rounded-2xl bg-n-teal-9/10 text-n-teal-11"
        >
          <fluent-icon icon="people-team" size="28" />
        </span>
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_WHATSAPP_GROUPS.LIST.EMPTY') }}
        </p>
        <woot-button
          size="small"
          icon="add"
          color-scheme="success"
          @click="openCreate"
        >
          {{ t('JABVOX_WHATSAPP_GROUPS.CREATE.BUTTON') }}
        </woot-button>
      </div>
    </template>

    <GroupCreateDialog ref="createDialog" @created="onCreated" />
    <GroupDetailDialog ref="detailDialog" @updated="loadGroups" />
  </div>
</template>
