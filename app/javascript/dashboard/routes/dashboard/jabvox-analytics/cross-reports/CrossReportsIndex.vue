<script setup>
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useAnalyticsCrossReportsStore } from 'dashboard/stores/jabvox/analytics/crossReports';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useAnalyticsCrossReportsStore();

const reports = computed(() => store.list);
const loading = computed(() => store.uiFlags.fetchingList);
const deletingId = ref(null);

onMounted(() => store.fetch());

const goToNew = () =>
  router.push({
    name: 'jabvox_analytics_cross_report_new',
    params: { accountId: route.params.accountId },
  });

const goToEdit = id =>
  router.push({
    name: 'jabvox_analytics_cross_report_edit',
    params: { accountId: route.params.accountId, crossReportId: id },
  });

const removeReport = async report => {
  if (
    !window.confirm(
      t('JABVOX_ANALYTICS.CROSS_REPORTS.CONFIRM_DELETE', { name: report.name })
    )
  ) {
    return;
  }
  deletingId.value = report.id;
  try {
    await store.destroy(report.id);
    useAlert(t('JABVOX_ANALYTICS.CROSS_REPORTS.DELETED'));
  } catch (e) {
    useAlert(t('JABVOX_ANALYTICS.CROSS_REPORTS.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};
</script>

<template>
  <div class="flex flex-col gap-4 p-6">
    <div class="flex items-center justify-between">
      <div>
        <h2 class="text-lg font-medium text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.TITLE') }}
        </h2>
        <p class="mt-0.5 text-sm text-n-slate-11">
          {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.SUBTITLE') }}
        </p>
      </div>
      <Button
        :label="t('JABVOX_ANALYTICS.CROSS_REPORTS.NEW')"
        icon="i-lucide-plus"
        @click="goToNew"
      />
    </div>

    <div v-if="loading" class="py-10 text-center text-sm text-n-slate-10">
      {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.LOADING') }}
    </div>

    <div
      v-else-if="!reports.length"
      class="rounded-xl border border-dashed border-n-weak py-12 text-center"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.EMPTY') }}
      </p>
    </div>

    <div v-else class="overflow-hidden rounded-xl border border-n-weak">
      <table class="w-full text-sm">
        <thead class="bg-n-alpha-1 text-left text-n-slate-11">
          <tr>
            <th class="px-4 py-2.5 font-medium">
              {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.COL_NAME') }}
            </th>
            <th class="px-4 py-2.5 font-medium">
              {{ t('JABVOX_ANALYTICS.CROSS_REPORTS.COL_SOURCES') }}
            </th>
            <th class="px-4 py-2.5" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="report in reports"
            :key="report.id"
            class="cursor-pointer border-t border-n-weak hover:bg-n-alpha-1"
            @click="goToEdit(report.id)"
          >
            <td class="px-4 py-3">
              <div class="font-medium text-n-slate-12">
                {{ report.nameJabvox }}
              </div>
              <div
                v-if="report.descriptionJabvox"
                class="text-xs text-n-slate-10"
              >
                {{ report.descriptionJabvox }}
              </div>
            </td>
            <td class="px-4 py-3 text-n-slate-11">{{ report.sourcesCount }}</td>
            <td class="px-4 py-3 text-right" @click.stop>
              <Button
                variant="ghost"
                color="ruby"
                size="sm"
                icon="i-lucide-trash-2"
                :is-loading="deletingId === report.id"
                @click="removeReport(report)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
