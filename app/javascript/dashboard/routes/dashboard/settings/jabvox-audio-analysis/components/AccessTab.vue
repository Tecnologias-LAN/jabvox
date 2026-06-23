<script setup>
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SettingsCard from './SettingsCard.vue';

defineProps({
  users: { type: Array, default: () => [] },
});
const emit = defineEmits(['update-user']);

const { t } = useI18n();
</script>

<template>
  <SettingsCard
    :title="t('JABVOX_AUDIO.ACCESS.TITLE')"
    :description="t('JABVOX_AUDIO.ACCESS.DESCRIPTION')"
    icon="i-lucide-shield-check"
  >
    <div v-if="users.length" class="flex flex-col">
      <div
        class="grid grid-cols-[1fr_auto_auto] gap-4 px-1 pb-2 text-xs font-medium uppercase tracking-wide text-n-slate-10"
      >
        <span>{{ t('JABVOX_AUDIO.ACCESS.USER') }}</span>
        <span class="w-24 text-center">{{
          t('JABVOX_AUDIO.ACCESS.CAN_ACCESS')
        }}</span>
        <span class="w-24 text-center">{{
          t('JABVOX_AUDIO.ACCESS.CAN_VIEW_REPORTS')
        }}</span>
      </div>
      <div
        v-for="u in users"
        :key="u.user_id"
        class="grid grid-cols-[1fr_auto_auto] items-center gap-4 px-1 py-2.5 border-t border-n-weak"
      >
        <span class="text-sm text-n-slate-12 truncate">{{ u.name }}</span>
        <div class="w-24 flex justify-center">
          <Switch v-model="u.can_access" @change="emit('update-user', u)" />
        </div>
        <div class="w-24 flex justify-center">
          <Switch
            v-model="u.can_view_reports"
            @change="emit('update-user', u)"
          />
        </div>
      </div>
    </div>

    <EmptyStateLayout
      v-else
      :title="t('JABVOX_AUDIO.ACCESS.EMPTY_TITLE')"
      :subtitle="t('JABVOX_AUDIO.ACCESS.EMPTY_SUBTITLE')"
      :show-backdrop="false"
    />
  </SettingsCard>
</template>
