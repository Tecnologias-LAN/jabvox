<script setup>
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import { analyticsPermissionsAPI } from 'dashboard/api/jabvox/analytics';
import AnalyticsLoadingState from '../components/AnalyticsLoadingState.vue';

const { t } = useI18n();
const { showError } = useAnalyticsError();

// Decorative separator rendered via a binding so it is not flagged as
// untranslatable raw text.
const DASH = '—';

const loadingUsers = ref(true);
const loadingAccess = ref(false);
const saving = ref(false);

const users = ref([]);
const selectedUserId = ref(null);
const seesAll = ref(false);
const dashboards = ref([]); // [{ id, name_jabvox, has_access }]

const selectableUsers = computed(() =>
  users.value.filter(u => !u.is_account_admin)
);

const loadUsers = async () => {
  loadingUsers.value = true;
  try {
    const { data } = await analyticsPermissionsAPI.getUserPermissions();
    users.value = data.users;
  } catch (error) {
    showError(error);
  } finally {
    loadingUsers.value = false;
  }
};

const loadAccess = async userId => {
  if (!userId) {
    dashboards.value = [];
    seesAll.value = false;
    return;
  }
  loadingAccess.value = true;
  try {
    const { data } =
      await analyticsPermissionsAPI.getUserDashboardAccess(userId);
    seesAll.value = data.sees_all;
    dashboards.value = data.dashboards;
  } catch (error) {
    showError(error);
  } finally {
    loadingAccess.value = false;
  }
};

const onUserChange = event => {
  selectedUserId.value = event.target.value ? Number(event.target.value) : null;
  loadAccess(selectedUserId.value);
};

const toggle = dashboard => {
  const index = dashboards.value.findIndex(d => d.id === dashboard.id);
  if (index === -1) return;
  const next = {
    ...dashboards.value[index],
    has_access: !dashboard.has_access,
  };
  dashboards.value.splice(index, 1, next);
};

const save = async () => {
  if (!selectedUserId.value) return;
  saving.value = true;
  try {
    const ids = dashboards.value.filter(d => d.has_access).map(d => d.id);
    await analyticsPermissionsAPI.updateUserDashboardAccess(
      selectedUserId.value,
      ids
    );
    useAlert(t('JABVOX_ANALYTICS.PERMISSIONS.SAVED'));
    await loadAccess(selectedUserId.value);
  } catch (error) {
    showError(error, t('JABVOX_ANALYTICS.PERMISSIONS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

onMounted(loadUsers);
</script>

<template>
  <AnalyticsLoadingState v-if="loadingUsers" />
  <div v-else class="space-y-4">
    <p class="text-sm text-n-slate-11">
      {{ t('JABVOX_ANALYTICS.PERMISSIONS.DASHBOARD_ACCESS.DESCRIPTION') }}
    </p>

    <div class="flex flex-wrap items-center gap-3">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_ANALYTICS.PERMISSIONS.DASHBOARD_ACCESS.USER') }}
      </label>
      <select
        :value="selectedUserId || ''"
        class="rounded-md border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12 min-w-56"
        @change="onUserChange"
      >
        <option value="">
          {{ t('JABVOX_ANALYTICS.PERMISSIONS.DASHBOARD_ACCESS.SELECT_USER') }}
        </option>
        <option
          v-for="user in selectableUsers"
          :key="user.user_id"
          :value="user.user_id"
        >
          {{ user.name }} {{ DASH }} {{ user.email }}
        </option>
      </select>
    </div>

    <AnalyticsLoadingState v-if="loadingAccess" />

    <template v-else-if="selectedUserId">
      <div
        v-if="seesAll"
        class="rounded-lg border border-n-amber-6 bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
      >
        {{ t('JABVOX_ANALYTICS.PERMISSIONS.DASHBOARD_ACCESS.SEES_ALL') }}
      </div>

      <p
        v-if="!dashboards.length"
        class="text-sm text-n-slate-10 py-6 text-center"
      >
        {{ t('JABVOX_ANALYTICS.PERMISSIONS.DASHBOARD_ACCESS.EMPTY') }}
      </p>

      <div
        v-else
        class="border rounded-lg border-n-weak divide-y divide-n-weak"
      >
        <label
          v-for="dashboard in dashboards"
          :key="dashboard.id"
          class="flex items-center gap-3 px-3 py-2.5 cursor-pointer hover:bg-n-alpha-1"
        >
          <input
            type="checkbox"
            class="size-4"
            :checked="dashboard.has_access"
            @change="toggle(dashboard)"
          />
          <span class="text-sm text-n-slate-12">{{
            dashboard.name_jabvox
          }}</span>
        </label>
      </div>

      <div class="flex justify-end">
        <button
          type="button"
          class="rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="saving || !dashboards.length"
          @click="save"
        >
          {{ t('JABVOX_ANALYTICS.COMMON.SAVE') }}
        </button>
      </div>
    </template>
  </div>
</template>
