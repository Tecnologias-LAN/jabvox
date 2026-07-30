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
  <div class="flex flex-col gap-4 p-6">
    <header>
      <h1 class="text-xl font-medium text-slate-800 dark:text-slate-100">
        {{ t('JABVOX_WHATSAPP_GROUPS.TITLE') }}
      </h1>
      <p class="text-sm text-slate-500 dark:text-slate-400">
        {{ t('JABVOX_WHATSAPP_GROUPS.SUBTITLE') }}
      </p>
    </header>

    <!-- Inbox selector -->
    <div v-if="inboxes.length" class="flex items-center gap-2">
      <label class="text-sm text-slate-600 dark:text-slate-300">
        {{ t('JABVOX_WHATSAPP_GROUPS.INBOX_LABEL') }}
      </label>
      <select v-model="selectedInboxId" class="text-sm" @change="onInboxChange">
        <option v-for="ib in inboxes" :key="ib.id" :value="ib.id">
          {{ ib.name }}
        </option>
      </select>
    </div>
    <p v-else class="text-sm text-slate-500">
      {{ t('JABVOX_WHATSAPP_GROUPS.NO_CLOUD_INBOX') }}
    </p>

    <!-- Ineligibility banner: explains why groups are blocked for this inbox -->
    <div
      v-if="selectedInboxId && !isEligible"
      class="rounded-md border border-yellow-300 bg-yellow-50 dark:bg-yellow-900/20 dark:border-yellow-700 p-4"
    >
      <p class="text-sm font-medium text-yellow-800 dark:text-yellow-200">
        {{ t('JABVOX_WHATSAPP_GROUPS.ELIGIBILITY.BLOCKED_TITLE') }}
      </p>
      <p class="text-sm text-yellow-700 dark:text-yellow-300 mt-1">
        {{ ineligibleReasonText }}
      </p>
    </div>

    <!-- Group management (only when eligible) -->
    <template v-if="isEligible">
      <div class="flex items-center justify-between">
        <p class="text-xs text-slate-500 dark:text-slate-400">
          {{
            t('JABVOX_WHATSAPP_GROUPS.INVITE_ONLY_HINT', { max: MAX_MEMBERS })
          }}
        </p>
        <woot-button size="small" icon="add" @click="openCreate">
          {{ t('JABVOX_WHATSAPP_GROUPS.CREATE.BUTTON') }}
        </woot-button>
      </div>

      <table v-if="groups.length" class="woot-table">
        <thead>
          <tr>
            <th>{{ t('JABVOX_WHATSAPP_GROUPS.TABLE.NAME') }}</th>
            <th>{{ t('JABVOX_WHATSAPP_GROUPS.TABLE.MEMBERS') }}</th>
            <th>{{ t('JABVOX_WHATSAPP_GROUPS.TABLE.STATUS') }}</th>
            <th />
          </tr>
        </thead>
        <tbody>
          <tr v-for="g in groups" :key="g.id">
            <td>{{ g.name }}</td>
            <td>{{ g.active_members_count }} / {{ g.max_members }}</td>
            <td>
              {{ t(`JABVOX_WHATSAPP_GROUPS.STATUS.${g.status.toUpperCase()}`) }}
            </td>
            <td class="text-right">
              <woot-button size="tiny" variant="clear" @click="openDetail(g)">
                {{ t('JABVOX_WHATSAPP_GROUPS.TABLE.MANAGE') }}
              </woot-button>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-else-if="!loading" class="text-sm text-slate-500">
        {{ t('JABVOX_WHATSAPP_GROUPS.LIST.EMPTY') }}
      </p>
    </template>

    <GroupCreateDialog ref="createDialog" @created="onCreated" />
    <GroupDetailDialog ref="detailDialog" @updated="loadGroups" />
  </div>
</template>
