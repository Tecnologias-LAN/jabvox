<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import FormDialog from './components/FormDialog.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();

const items = ref([]);
const loading = ref(true);
const saving = ref(false);
const search = ref('');

const formDialog = ref(null);
const deleteDialog = ref(null);

const total = computed(() => items.value.length);
const activeCount = computed(() => items.value.filter(i => i.is_active).length);
const inactiveCount = computed(() => total.value - activeCount.value);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return items.value;
  return items.value.filter(
    i =>
      i.name?.toLowerCase().includes(q) ||
      i.description?.toLowerCase().includes(q)
  );
});

const load = async () => {
  loading.value = true;
  try {
    const { data } = await typificationsAPI.getAll(false);
    items.value = data.typifications || [];
  } finally {
    loading.value = false;
  }
};

onMounted(load);

const onSubmit = async ({ id, values }) => {
  if (!values.name) {
    useAlert(t('JABVOX_CLICK_TO_CALL.SETTINGS.NAME_REQUIRED'));
    return;
  }
  saving.value = true;
  try {
    if (id) await typificationsAPI.update(id, values);
    else await typificationsAPI.create(values);
    formDialog.value?.close();
    await load();
    useAlert(t('JABVOX_CLICK_TO_CALL.SETTINGS.SAVED'));
  } catch {
    useAlert(t('JABVOX_CLICK_TO_CALL.SETTINGS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

const askDelete = tp => {
  deleteDialog.value?.open({
    title: t('JABVOX_CLICK_TO_CALL.SETTINGS.DELETE_TITLE'),
    description: t('JABVOX_CLICK_TO_CALL.SETTINGS.DELETE_BODY', {
      name: tp.name,
    }),
    data: tp.id,
  });
};

const doDelete = async id => {
  try {
    await typificationsAPI.destroy(id);
    await load();
  } catch {
    useAlert(t('JABVOX_CLICK_TO_CALL.SETTINGS.SAVE_ERROR'));
  }
};
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-4xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span
            class="i-lucide-tags size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.SUBTITLE') }}
            </p>
          </div>
        </div>
        <Button
          :label="t('JABVOX_CLICK_TO_CALL.SETTINGS.NEW')"
          icon="i-lucide-plus"
          class="shrink-0"
          @click="formDialog?.openCreate()"
        />
      </div>

      <!-- Loading -->
      <div
        v-if="loading"
        class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
      </div>

      <!-- Empty -->
      <EmptyStateLayout
        v-else-if="!items.length"
        :title="t('JABVOX_CLICK_TO_CALL.SETTINGS.EMPTY_TITLE')"
        :subtitle="t('JABVOX_CLICK_TO_CALL.SETTINGS.EMPTY')"
      >
        <template #actions>
          <Button
            icon="i-lucide-plus"
            :label="t('JABVOX_CLICK_TO_CALL.SETTINGS.NEW')"
            size="sm"
            @click="formDialog?.openCreate()"
          />
        </template>
      </EmptyStateLayout>

      <template v-else>
        <!-- KPIs -->
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <span
              class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-11"
            >
              <span class="i-lucide-tags size-5" />
            </span>
            <div>
              <p class="text-xl font-semibold tabular-nums text-n-slate-12">
                {{ total }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.KPI_TOTAL') }}
              </p>
            </div>
          </div>
          <div
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <span
              class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-teal-3 text-n-teal-11"
            >
              <span class="i-lucide-circle-check size-5" />
            </span>
            <div>
              <p class="text-xl font-semibold tabular-nums text-n-slate-12">
                {{ activeCount }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.KPI_ACTIVE') }}
              </p>
            </div>
          </div>
          <div
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <span
              class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-amber-3 text-n-amber-11"
            >
              <span class="i-lucide-circle-pause size-5" />
            </span>
            <div>
              <p class="text-xl font-semibold tabular-nums text-n-slate-12">
                {{ inactiveCount }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.KPI_INACTIVE') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Search + count -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="relative w-full sm:w-64">
            <Input
              v-model="search"
              :placeholder="
                t('JABVOX_CLICK_TO_CALL.SETTINGS.SEARCH_PLACEHOLDER')
              "
              custom-input-class="!pl-9"
            >
              <template #prefix>
                <span
                  class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                />
              </template>
            </Input>
          </div>
          <span class="text-xs text-n-slate-10">
            {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.COUNT', { count: total }) }}
          </span>
        </div>

        <!-- No results -->
        <div
          v-if="!filtered.length"
          class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.NO_RESULTS') }}
        </div>

        <!-- List -->
        <div
          v-else
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm divide-y divide-n-weak overflow-hidden"
        >
          <div
            v-for="tp in filtered"
            :key="tp.id"
            class="flex items-center gap-3 px-4 py-3 hover:bg-n-alpha-1 transition-colors"
          >
            <span
              class="i-lucide-tag size-5 text-n-slate-10 shrink-0 hidden sm:block"
            />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ tp.name }}
              </p>
              <p v-if="tp.description" class="text-xs text-n-slate-10 truncate">
                {{ tp.description }}
              </p>
            </div>
            <Label
              :label="
                tp.is_active
                  ? t('JABVOX_CLICK_TO_CALL.SETTINGS.ACTIVE_BADGE')
                  : t('JABVOX_CLICK_TO_CALL.SETTINGS.INACTIVE')
              "
              :color="tp.is_active ? 'teal' : 'slate'"
              compact
            />
            <Button
              icon="i-lucide-pencil"
              variant="ghost"
              color="slate"
              size="sm"
              :title="t('JABVOX_CLICK_TO_CALL.SETTINGS.EDIT')"
              @click="formDialog?.openEdit(tp)"
            />
            <Button
              icon="i-lucide-trash-2"
              variant="ghost"
              color="ruby"
              size="sm"
              :title="t('JABVOX_CLICK_TO_CALL.SETTINGS.DELETE')"
              @click="askDelete(tp)"
            />
          </div>
        </div>
      </template>
    </div>

    <FormDialog ref="formDialog" :is-saving="saving" @submit="onSubmit" />
    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
