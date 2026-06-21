<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';

const props = defineProps({
  dashboard: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['delete']);

const { t } = useI18n();
const router = useRouter();
const route = useRoute();

const menuOpen = ref(false);

const openDashboard = () => {
  router.push({
    name: 'jabvox_analytics_dashboard_show',
    params: {
      accountId: route.params.accountId,
      dashboardId: props.dashboard.id,
    },
  });
};

const onDelete = () => {
  menuOpen.value = false;
  emit('delete', props.dashboard);
};

const menuItemClass =
  'flex w-full items-center gap-2 px-3 py-2 text-left text-sm hover:bg-n-alpha-2';
</script>

<template>
  <div
    class="group relative flex cursor-pointer flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-4 hover:border-n-strong"
    @click="openDashboard"
  >
    <div class="flex items-start justify-between gap-2">
      <span class="i-lucide-layout-dashboard size-5 text-n-slate-11" />
      <div class="relative" @click.stop>
        <button
          type="button"
          class="rounded-lg p-1 text-n-slate-11 opacity-0 hover:bg-n-alpha-2 group-hover:opacity-100"
          @click="menuOpen = !menuOpen"
        >
          <span class="i-lucide-more-vertical size-4" />
        </button>
        <div
          v-if="menuOpen"
          class="absolute right-0 z-20 mt-1 w-40 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 py-1 shadow-lg"
        >
          <button
            type="button"
            :class="menuItemClass"
            class="text-n-slate-12"
            @click="openDashboard"
          >
            <span class="i-lucide-external-link size-4" />
            {{ t('JABVOX_ANALYTICS.DASHBOARDS.OPEN') }}
          </button>
          <button
            type="button"
            :class="menuItemClass"
            class="text-n-ruby-11"
            @click="onDelete"
          >
            <span class="i-lucide-trash-2 size-4" />
            {{ t('JABVOX_ANALYTICS.COMMON.DELETE') }}
          </button>
        </div>
      </div>
    </div>
    <div class="min-w-0">
      <h3 class="truncate text-sm font-medium text-n-slate-12">
        {{ dashboard.nameJabvox }}
      </h3>
      <p
        v-if="dashboard.descriptionJabvox"
        class="mt-1 line-clamp-2 text-xs text-n-slate-11"
      >
        {{ dashboard.descriptionJabvox }}
      </p>
    </div>
  </div>
</template>
