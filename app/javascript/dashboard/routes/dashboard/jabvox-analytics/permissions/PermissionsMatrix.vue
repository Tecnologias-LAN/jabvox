<script setup>
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import { analyticsPermissionsAPI } from 'dashboard/api/jabvox/analytics';
import AnalyticsLoadingState from '../components/AnalyticsLoadingState.vue';

const { t } = useI18n();
const { showError } = useAnalyticsError();

// Capability labels resolved with static literal keys so the template binds
// plain strings (no dynamic i18n key). Unknown keys fall back to the raw key.
const capLabels = computed(() => ({
  access: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.access'),
  create: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.create'),
  edit_own: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.edit_own'),
  edit_all: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.edit_all'),
  delete_own: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.delete_own'),
  delete_all: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.delete_all'),
  share: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.share'),
  view_all_data: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.view_all_data'),
  manage_data_sources: t(
    'JABVOX_ANALYTICS.PERMISSIONS.CAPS.manage_data_sources'
  ),
  use_custom_sql: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.use_custom_sql'),
}));
const capLabel = key => capLabels.value[key] || key;

const loading = ref(true);
const saving = ref(false);
const keys = ref([]);
const roles = ref([]);
const users = ref([]);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await analyticsPermissionsAPI.getUserPermissions();
    keys.value = data.keys;
    roles.value = data.roles;
    users.value = data.users;
  } catch (error) {
    showError(error);
  } finally {
    loading.value = false;
  }
};

onMounted(load);

const roleName = roleId =>
  roles.value.find(r => r.id === roleId)?.name_jabvox || '—';

const assignments = computed(() =>
  users.value
    .filter(u => !u.is_account_admin)
    .map(u => ({
      user_id: u.user_id,
      role_id: u.role_id,
      overrides: u.overrides,
    }))
);

const onRoleChange = (userId, roleId) => {
  const index = users.value.findIndex(u => u.user_id === userId);
  if (index === -1) return;
  const next = {
    ...users.value[index],
    role_id: roleId ? Number(roleId) : null,
  };
  users.value.splice(index, 1, next);
};

const save = async () => {
  saving.value = true;
  try {
    await analyticsPermissionsAPI.bulkUpdateUserPermissions({
      assignments: assignments.value,
    });
    useAlert(t('JABVOX_ANALYTICS.PERMISSIONS.SAVED'));
    await load();
  } catch (error) {
    showError(error, t('JABVOX_ANALYTICS.PERMISSIONS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <AnalyticsLoadingState v-if="loading" />
  <div v-else>
    <div class="flex justify-end mb-3">
      <button
        type="button"
        class="rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="saving"
        @click="save"
      >
        {{ t('JABVOX_ANALYTICS.COMMON.SAVE') }}
      </button>
    </div>

    <div class="overflow-x-auto border rounded-lg border-n-weak">
      <table class="w-full text-sm">
        <thead class="bg-n-alpha-1 text-n-slate-11">
          <tr>
            <th class="px-3 py-2 text-left">
              {{ t('JABVOX_ANALYTICS.PERMISSIONS.MATRIX.USER') }}
            </th>
            <th class="px-3 py-2 text-left">
              {{ t('JABVOX_ANALYTICS.PERMISSIONS.MATRIX.ROLE') }}
            </th>
            <th
              v-for="key in keys"
              :key="key"
              class="px-2 py-2 text-center whitespace-nowrap"
            >
              {{ capLabel(key) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="user in users"
            :key="user.user_id"
            class="border-t border-n-weak"
          >
            <td class="px-3 py-2 text-n-slate-12">
              <div class="font-medium">{{ user.name }}</div>
              <div class="text-xs text-n-slate-10">{{ user.email }}</div>
            </td>
            <td class="px-3 py-2">
              <span
                v-if="user.is_account_admin"
                class="text-xs font-medium text-n-teal-11"
              >
                {{ t('JABVOX_ANALYTICS.PERMISSIONS.ADMIN_NOTICE') }}
              </span>
              <select
                v-else
                :value="user.role_id || ''"
                class="rounded-md border border-n-weak bg-n-background px-2 py-1 text-sm text-n-slate-12"
                @change="onRoleChange(user.user_id, $event.target.value)"
              >
                <option value="">
                  {{ t('JABVOX_ANALYTICS.COMMON.NONE') }}
                </option>
                <option v-for="role in roles" :key="role.id" :value="role.id">
                  {{ role.name_jabvox }}
                </option>
              </select>
            </td>
            <td v-for="key in keys" :key="key" class="px-2 py-2 text-center">
              <span
                v-if="user.effective[key]"
                class="i-lucide-check size-4 text-n-teal-11"
                :title="roleName(user.role_id)"
              />
              <span v-else class="i-lucide-minus size-4 text-n-slate-9" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
