<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import KpiCard from './components/KpiCard.vue';
import SearchInput from './components/SearchInput.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const funnels = useMapGetter('jabvoxKanban/getFunnels');
const uiFlags = useMapGetter('jabvoxKanban/getUIFlags');

const search = ref('');
const deletingId = ref(null);
const deleteDialog = ref(null);

const total = computed(() => funnels.value.length);
const activeCount = computed(
  () => funnels.value.filter(f => f.active_jabvox).length
);
const totalStages = computed(() =>
  funnels.value.reduce((sum, f) => sum + (f.stages?.length || 0), 0)
);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return funnels.value;
  return funnels.value.filter(
    f =>
      f.name_jabvox?.toLowerCase().includes(q) ||
      f.description_jabvox?.toLowerCase().includes(q)
  );
});

onMounted(() => store.dispatch('jabvoxKanban/fetchFunnels'));

const onNew = () => router.push({ name: 'jabvox_kanban_funnels_new' });
const onEdit = funnel =>
  router.push({
    name: 'jabvox_kanban_funnels_edit',
    params: { funnelId: funnel.id },
  });
const onStages = funnel =>
  router.push({
    name: 'jabvox_kanban_stages',
    params: { funnelId: funnel.id },
  });
const onBoard = funnel =>
  router.push({
    name: 'jabvox_kanban_funnel',
    params: { funnelId: funnel.id },
  });

const askDelete = funnel => {
  deleteDialog.value?.open({
    title: t('JABVOX_KANBAN.SETTINGS.FUNNELS.DELETE_TITLE'),
    description: t('JABVOX_KANBAN.SETTINGS.FUNNELS.DELETE_BODY', {
      name: funnel.name_jabvox,
    }),
    data: funnel.id,
  });
};
const doDelete = async id => {
  deletingId.value = id;
  try {
    await store.dispatch('jabvoxKanban/deleteFunnel', id);
    useAlert(t('JABVOX_KANBAN.SETTINGS.FUNNELS.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_KANBAN.SETTINGS.FUNNELS.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-6xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span
            class="i-lucide-kanban size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_KANBAN.SETTINGS.FUNNELS.NEW_BUTTON')"
          class="shrink-0"
          @click="onNew"
        />
      </div>

      <!-- Loading -->
      <div
        v-if="uiFlags.isFetchingFunnels"
        class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
      </div>

      <!-- Empty -->
      <EmptyStateLayout
        v-else-if="!funnels.length"
        :title="t('JABVOX_KANBAN.SETTINGS.FUNNELS.EMPTY_TITLE')"
        :subtitle="t('JABVOX_KANBAN.SETTINGS.FUNNELS.EMPTY')"
      >
        <template #actions>
          <Button
            icon="i-lucide-plus"
            :label="t('JABVOX_KANBAN.SETTINGS.FUNNELS.NEW_BUTTON')"
            size="sm"
            @click="onNew"
          />
        </template>
      </EmptyStateLayout>

      <template v-else>
        <!-- KPIs -->
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <KpiCard
            :label="t('JABVOX_KANBAN.SETTINGS.FUNNELS.KPI_TOTAL')"
            :value="total"
            icon="i-lucide-kanban"
            tone="iris"
          />
          <KpiCard
            :label="t('JABVOX_KANBAN.SETTINGS.FUNNELS.KPI_ACTIVE')"
            :value="activeCount"
            icon="i-lucide-circle-check"
            tone="teal"
          />
          <KpiCard
            :label="t('JABVOX_KANBAN.SETTINGS.FUNNELS.KPI_STAGES')"
            :value="totalStages"
            icon="i-lucide-columns-3"
            tone="slate"
          />
        </div>

        <!-- Search -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <SearchInput
            v-model="search"
            :placeholder="
              t('JABVOX_KANBAN.SETTINGS.FUNNELS.SEARCH_PLACEHOLDER')
            "
          />
          <span class="text-xs text-n-slate-10">
            {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.COUNT', { count: total }) }}
          </span>
        </div>

        <!-- No results -->
        <div
          v-if="!filtered.length"
          class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.NO_RESULTS') }}
        </div>

        <!-- Funnel cards -->
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
        >
          <div
            v-for="funnel in filtered"
            :key="funnel.id"
            class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm transition-all hover:shadow-md hover:-translate-y-0.5"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="flex items-center gap-2 min-w-0">
                <span class="i-lucide-kanban size-4 text-n-slate-10 shrink-0" />
                <h3 class="text-sm font-semibold text-n-slate-12 truncate">
                  {{ funnel.name_jabvox }}
                </h3>
              </div>
              <Label
                :label="
                  funnel.active_jabvox
                    ? t('JABVOX_KANBAN.ACTIVE')
                    : t('JABVOX_KANBAN.INACTIVE')
                "
                :color="funnel.active_jabvox ? 'teal' : 'slate'"
                compact
              />
            </div>

            <p class="text-xs text-n-slate-11 line-clamp-2 min-h-[2rem]">
              {{ funnel.description_jabvox || '—' }}
            </p>

            <button
              class="inline-flex items-center gap-1.5 self-start text-xs text-n-brand hover:underline"
              @click="onStages(funnel)"
            >
              <span class="i-lucide-columns-3 size-3.5" />
              {{ funnel.stages?.length || 0 }}
              {{ t('JABVOX_KANBAN.SETTINGS.FUNNELS.STAGES_LABEL') }}
            </button>

            <div class="flex items-center gap-1 pt-2 border-t border-n-weak">
              <Button
                :label="t('JABVOX_KANBAN.SETTINGS.FUNNELS.OPEN_BOARD')"
                icon="i-lucide-layout-panel-top"
                variant="outline"
                color="slate"
                size="sm"
                @click="onBoard(funnel)"
              />
              <div class="flex-1" />
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                :title="t('JABVOX_KANBAN.COMMON.EDIT')"
                @click="onEdit(funnel)"
              />
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                :title="t('JABVOX_KANBAN.COMMON.DELETE')"
                :is-loading="deletingId === funnel.id"
                @click="askDelete(funnel)"
              />
            </div>
          </div>
        </div>
      </template>
    </div>

    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
