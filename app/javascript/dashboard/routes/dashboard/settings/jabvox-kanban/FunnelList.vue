<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const funnels = useMapGetter('jabvoxKanban/getFunnels');
const uiFlags = useMapGetter('jabvoxKanban/getUIFlags');

const deletingId = ref(null);

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

const onDelete = async funnel => {
  if (
    !window.confirm(
      t('JABVOX_KANBAN.SETTINGS.FUNNELS.DELETE_CONFIRM', {
        name: funnel.name_jabvox,
      })
    )
  )
    return;
  deletingId.value = funnel.id;
  try {
    await store.dispatch('jabvoxKanban/deleteFunnel', funnel.id);
    useAlert(t('JABVOX_KANBAN.SETTINGS.FUNNELS.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_KANBAN.SETTINGS.FUNNELS.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};
</script>

<template>
  <SettingsLayout>
    <div class="px-4 sm:px-6 lg:px-8 pb-6 pt-3 sm:pt-4">
      <BaseSettingsHeader
        :title="$t('JABVOX_KANBAN.SETTINGS.FUNNELS.TITLE')"
        :description="$t('JABVOX_KANBAN.SETTINGS.FUNNELS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            icon="i-lucide-plus"
            :label="$t('JABVOX_KANBAN.SETTINGS.FUNNELS.NEW_BUTTON')"
            @click="onNew"
          />
        </template>
      </BaseSettingsHeader>

      <div
        v-if="uiFlags.isFetchingFunnels"
        class="flex items-center justify-center py-12 text-slate-400 animate-pulse"
      >
        {{ $t('JABVOX_KANBAN.LOADING') }}
      </div>

      <div
        v-else-if="funnels.length === 0"
        class="flex flex-col items-center justify-center py-12 gap-3 text-slate-500"
      >
        <i class="i-lucide-kanban text-4xl opacity-30" />
        <p class="text-sm">{{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.EMPTY') }}</p>
      </div>

      <div v-else class="mt-6">
        <div class="sm:hidden space-y-4">
          <div
            v-for="funnel in funnels"
            :key="funnel.id"
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 shadow-sm"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h3
                  class="text-sm font-semibold text-slate-800 dark:text-slate-100 truncate"
                >
                  {{ funnel.name_jabvox }}
                </h3>
                <p class="text-xs text-slate-500 dark:text-slate-400 mt-1">
                  {{ funnel.description_jabvox || '—' }}
                </p>
              </div>
              <span
                class="text-[11px] px-2 py-0.5 rounded-full font-medium shrink-0"
                :class="[
                  funnel.active_jabvox
                    ? 'bg-green-100 text-green-700'
                    : 'bg-slate-100 text-slate-500',
                ]"
              >
                {{
                  funnel.active_jabvox
                    ? $t('JABVOX_KANBAN.ACTIVE')
                    : $t('JABVOX_KANBAN.INACTIVE')
                }}
              </span>
            </div>

            <div class="mt-3 flex items-center justify-between text-xs">
              <button
                class="text-woot-600 hover:underline"
                @click="onStages(funnel)"
              >
                {{ funnel.stages?.length || 0 }}
                {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.STAGES_LABEL') }}
              </button>
              <Button
                size="small"
                variant="ghost"
                icon="i-lucide-layout-panel-top"
                :label="$t('JABVOX_KANBAN.SETTINGS.FUNNELS.OPEN_BOARD')"
                @click="onBoard(funnel)"
              />
            </div>

            <div class="mt-3 flex flex-wrap gap-2">
              <Button
                size="small"
                variant="ghost"
                icon="i-lucide-pencil"
                :label="$t('EDIT')"
                @click="onEdit(funnel)"
              />
              <Button
                size="small"
                variant="ghost"
                color-scheme="alert"
                icon="i-lucide-trash-2"
                :label="$t('DELETE')"
                :is-loading="deletingId === funnel.id"
                @click="onDelete(funnel)"
              />
            </div>
          </div>
        </div>

        <div class="hidden sm:block overflow-x-auto">
          <div
            class="min-w-full rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 shadow-sm"
          >
            <table
              class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
            >
              <thead>
                <tr class="text-left text-slate-500 dark:text-slate-400">
                  <th class="py-3 px-4 font-medium">
                    {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.COLUMNS.NAME') }}
                  </th>
                  <th class="py-3 px-4 font-medium">
                    {{
                      $t('JABVOX_KANBAN.SETTINGS.FUNNELS.COLUMNS.DESCRIPTION')
                    }}
                  </th>
                  <th class="py-3 px-4 font-medium">
                    {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.COLUMNS.STAGES') }}
                  </th>
                  <th class="py-3 px-4 font-medium">
                    {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.COLUMNS.STATUS') }}
                  </th>
                  <th class="py-3 px-4 font-medium">
                    {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.COLUMNS.ACTIONS') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
                <tr
                  v-for="funnel in funnels"
                  :key="funnel.id"
                  class="hover:bg-slate-50 dark:hover:bg-slate-800/50"
                >
                  <td class="py-3 px-4">
                    <span
                      class="font-medium text-slate-800 dark:text-slate-100"
                    >
                      {{ funnel.name_jabvox }}
                    </span>
                  </td>
                  <td class="py-3 px-4 text-slate-500 dark:text-slate-400">
                    {{ funnel.description_jabvox || '—' }}
                  </td>
                  <td class="py-3 px-4">
                    <button
                      class="text-woot-600 hover:underline"
                      @click="onStages(funnel)"
                    >
                      {{ funnel.stages?.length || 0 }}
                      {{ $t('JABVOX_KANBAN.SETTINGS.FUNNELS.STAGES_LABEL') }}
                    </button>
                  </td>
                  <td class="py-3 px-4">
                    <span
                      class="text-xs px-2 py-1 rounded-full font-medium"
                      :class="[
                        funnel.active_jabvox
                          ? 'bg-green-100 text-green-700'
                          : 'bg-slate-100 text-slate-500',
                      ]"
                    >
                      {{
                        funnel.active_jabvox
                          ? $t('JABVOX_KANBAN.ACTIVE')
                          : $t('JABVOX_KANBAN.INACTIVE')
                      }}
                    </span>
                  </td>
                  <td class="py-3 px-4">
                    <div class="flex items-center gap-2">
                      <Button
                        size="small"
                        variant="ghost"
                        icon="i-lucide-layout-panel-top"
                        :label="$t('JABVOX_KANBAN.SETTINGS.FUNNELS.OPEN_BOARD')"
                        @click="onBoard(funnel)"
                      />
                      <Button
                        size="small"
                        variant="ghost"
                        icon="i-lucide-pencil"
                        @click="onEdit(funnel)"
                      />
                      <Button
                        size="small"
                        variant="ghost"
                        color-scheme="alert"
                        icon="i-lucide-trash-2"
                        :is-loading="deletingId === funnel.id"
                        @click="onDelete(funnel)"
                      />
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
