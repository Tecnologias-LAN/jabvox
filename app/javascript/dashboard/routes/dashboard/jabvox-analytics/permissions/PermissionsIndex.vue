<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import PermissionsMatrix from './PermissionsMatrix.vue';
import RoleManagement from './RoleManagement.vue';
import AuditLogTable from './AuditLogTable.vue';

const { t } = useI18n();

// Labels resolved with static literal keys so the template binds plain strings
// (no dynamic i18n key).
const tabs = computed(() => [
  { key: 'matrix', label: t('JABVOX_ANALYTICS.PERMISSIONS.TAB_MATRIX') },
  { key: 'roles', label: t('JABVOX_ANALYTICS.PERMISSIONS.TAB_ROLES') },
  { key: 'audit', label: t('JABVOX_ANALYTICS.AUDIT.TITLE') },
]);
const activeTab = ref('matrix');
</script>

<template>
  <div>
    <AnalyticsPageHeader
      :title="t('JABVOX_ANALYTICS.PERMISSIONS.TITLE')"
      :description="t('JABVOX_ANALYTICS.PERMISSIONS.ADMIN_NOTICE')"
    />

    <div class="flex items-center gap-1 mb-4 border-b border-n-weak">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        class="px-3 py-2 text-sm font-medium border-b-2 -mb-px transition-colors"
        :class="
          activeTab === tab.key
            ? 'border-n-brand text-n-slate-12'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="activeTab = tab.key"
      >
        {{ tab.label }}
      </button>
    </div>

    <PermissionsMatrix v-if="activeTab === 'matrix'" />
    <RoleManagement v-else-if="activeTab === 'roles'" />
    <AuditLogTable v-else />
  </div>
</template>
