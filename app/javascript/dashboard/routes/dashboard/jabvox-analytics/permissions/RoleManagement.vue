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
  export: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.export'),
  view_all_data: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.view_all_data'),
  manage_data_sources: t(
    'JABVOX_ANALYTICS.PERMISSIONS.CAPS.manage_data_sources'
  ),
  use_custom_sql: t('JABVOX_ANALYTICS.PERMISSIONS.CAPS.use_custom_sql'),
}));
const capLabel = key => capLabels.value[key] || key;

const loading = ref(true);
const savingId = ref(null);
const keys = ref([]);
const roles = ref([]);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await analyticsPermissionsAPI.getRolePermissions();
    keys.value = data.keys;
    roles.value = data.roles;
  } catch (error) {
    showError(error);
  } finally {
    loading.value = false;
  }
};

onMounted(load);

const toggle = (roleId, key) => {
  const index = roles.value.findIndex(r => r.id === roleId);
  if (index === -1 || roles.value[index].is_system_jabvox) return;
  const role = roles.value[index];
  const next = {
    ...role,
    grants: { ...role.grants, [key]: !role.grants[key] },
  };
  roles.value.splice(index, 1, next);
};

const saveRole = async role => {
  savingId.value = role.id;
  try {
    await analyticsPermissionsAPI.updateRolePermissions(role.id, role.grants);
    useAlert(t('JABVOX_ANALYTICS.PERMISSIONS.SAVED'));
  } catch (error) {
    showError(error, t('JABVOX_ANALYTICS.PERMISSIONS.SAVE_ERROR'));
  } finally {
    savingId.value = null;
  }
};
</script>

<template>
  <AnalyticsLoadingState v-if="loading" />
  <div v-else class="flex flex-col gap-4">
    <div
      v-for="role in roles"
      :key="role.id"
      class="p-4 border rounded-lg border-n-weak"
    >
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <h3 class="font-medium text-n-slate-12">{{ role.name_jabvox }}</h3>
          <span
            v-if="role.is_system_jabvox"
            class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-10"
          >
            {{ t('JABVOX_ANALYTICS.PERMISSIONS.ROLES.SYSTEM') }}
          </span>
        </div>
        <button
          v-if="!role.is_system_jabvox"
          type="button"
          class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white disabled:opacity-50"
          :disabled="savingId === role.id"
          @click="saveRole(role)"
        >
          {{ t('JABVOX_ANALYTICS.COMMON.SAVE') }}
        </button>
      </div>
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
        <label
          v-for="key in keys"
          :key="key"
          class="flex items-center gap-2 text-sm"
          :class="
            role.is_system_jabvox
              ? 'text-n-slate-10 cursor-not-allowed'
              : 'text-n-slate-12 cursor-pointer'
          "
        >
          <input
            type="checkbox"
            :checked="role.grants[key]"
            :disabled="role.is_system_jabvox"
            @change="toggle(role.id, key)"
          />
          {{ capLabel(key) }}
        </label>
      </div>
    </div>
  </div>
</template>
