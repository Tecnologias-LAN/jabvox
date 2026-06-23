<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const store = useStore();
const { t } = useI18n();

const entries = useMapGetter('jabvoxIpWhitelist/getEntries');
const uiFlags = useMapGetter('jabvoxIpWhitelist/getUIFlags');

const form = ref({ ip: '', comment: '', is_active: true });
const search = ref('');
const deleteDialog = ref(null);

const IPV4_RE = /^(\d{1,3}\.){3}\d{1,3}$/;
const ipError = computed(() => {
  const v = form.value.ip.trim();
  if (!v) return '';
  return IPV4_RE.test(v) ? '' : t('JABVOX_IP_WHITELIST.IP_INVALID');
});
const canAdd = computed(
  () => form.value.ip.trim().length > 0 && !ipError.value
);

const total = computed(() => entries.value.length);
const activeCount = computed(
  () => entries.value.filter(e => e.is_active).length
);
const inactiveCount = computed(() => total.value - activeCount.value);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return entries.value;
  return entries.value.filter(
    e => e.ip?.toLowerCase().includes(q) || e.comment?.toLowerCase().includes(q)
  );
});

onMounted(() => store.dispatch('jabvoxIpWhitelist/fetchEntries'));

const onAdd = async () => {
  if (!canAdd.value) return;
  try {
    await store.dispatch('jabvoxIpWhitelist/createEntry', { ...form.value });
    form.value = { ip: '', comment: '', is_active: true };
    useAlert(t('JABVOX_IP_WHITELIST.CREATE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_IP_WHITELIST.ERROR'));
  }
};

const onToggle = async entry => {
  try {
    await store.dispatch('jabvoxIpWhitelist/updateEntry', {
      id: entry.id,
      is_active: !entry.is_active,
    });
  } catch {
    useAlert(t('JABVOX_IP_WHITELIST.ERROR'));
  }
};

const askDelete = entry => {
  deleteDialog.value?.open({
    title: t('JABVOX_IP_WHITELIST.DELETE_TITLE'),
    description: t('JABVOX_IP_WHITELIST.DELETE_BODY', { ip: entry.ip }),
    data: entry.id,
  });
};

const doDelete = async id => {
  try {
    await store.dispatch('jabvoxIpWhitelist/deleteEntry', id);
    useAlert(t('JABVOX_IP_WHITELIST.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_IP_WHITELIST.ERROR'));
  }
};

const formatDate = iso =>
  new Date(iso).toLocaleDateString([], {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-4xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div class="flex items-start gap-3">
        <span
          class="i-lucide-shield-check size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('JABVOX_IP_WHITELIST.TITLE') }}
          </h1>
          <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
            {{ t('JABVOX_IP_WHITELIST.SUBTITLE') }}
          </p>
        </div>
      </div>

      <!-- KPIs -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div
          class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
        >
          <span
            class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-11"
          >
            <span class="i-lucide-list size-5" />
          </span>
          <div>
            <p class="text-xl font-semibold tabular-nums text-n-slate-12">
              {{ total }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_IP_WHITELIST.KPI.TOTAL') }}
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
              {{ t('JABVOX_IP_WHITELIST.KPI.ACTIVE') }}
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
              {{ t('JABVOX_IP_WHITELIST.KPI.INACTIVE') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Add form -->
      <div
        class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
      >
        <div class="border-b border-n-weak px-5 py-4 sm:px-6">
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ t('JABVOX_IP_WHITELIST.ADD_TITLE') }}
          </h2>
          <p class="mt-0.5 text-sm text-n-slate-11">
            {{ t('JABVOX_IP_WHITELIST.ADD_SUBTITLE') }}
          </p>
        </div>
        <div class="px-5 py-5 sm:px-6 flex flex-col gap-4">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model="form.ip"
              :label="t('JABVOX_IP_WHITELIST.TABLE.IP')"
              :placeholder="t('JABVOX_IP_WHITELIST.FORM.IP_PLACEHOLDER')"
              :message="ipError || t('JABVOX_IP_WHITELIST.FORM.IP_HINT')"
              :message-type="ipError ? 'error' : 'info'"
              custom-input-class="font-mono"
              @keydown.enter="onAdd"
            />
            <Input
              v-model="form.comment"
              :label="t('JABVOX_IP_WHITELIST.TABLE.COMMENT')"
              :placeholder="t('JABVOX_IP_WHITELIST.FORM.COMMENT_PLACEHOLDER')"
              @keydown.enter="onAdd"
            />
          </div>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <label class="flex items-center gap-2 cursor-pointer select-none">
              <Switch v-model="form.is_active" />
              <span class="text-sm text-n-slate-12">
                {{ t('JABVOX_IP_WHITELIST.FORM.ACTIVE_LABEL') }}
              </span>
            </label>
            <Button
              :label="t('JABVOX_IP_WHITELIST.ADD_IP')"
              icon="i-lucide-plus"
              :is-loading="uiFlags.isSaving"
              :disabled="!canAdd || uiFlags.isSaving"
              @click="onAdd"
            />
          </div>
        </div>
      </div>

      <!-- IP list -->
      <div class="flex flex-col gap-4">
        <!-- Loading -->
        <div
          v-if="uiFlags.isFetching"
          class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
        >
          <Spinner :size="18" />
        </div>

        <!-- Empty -->
        <EmptyStateLayout
          v-else-if="!entries.length"
          :title="t('JABVOX_IP_WHITELIST.EMPTY_TITLE')"
          :subtitle="t('JABVOX_IP_WHITELIST.EMPTY')"
        />

        <template v-else>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="relative w-full sm:w-64">
              <Input
                v-model="search"
                :placeholder="t('JABVOX_IP_WHITELIST.SEARCH_PLACEHOLDER')"
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
              {{ t('JABVOX_IP_WHITELIST.COUNT', { count: entries.length }) }}
            </span>
          </div>

          <!-- No results -->
          <div
            v-if="!filtered.length"
            class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_IP_WHITELIST.NO_RESULTS') }}
          </div>

          <!-- List -->
          <div
            v-else
            class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm divide-y divide-n-weak overflow-hidden"
          >
            <div
              v-for="entry in filtered"
              :key="entry.id"
              class="flex items-center gap-3 px-4 py-3 hover:bg-n-alpha-1 transition-colors"
            >
              <span
                class="i-lucide-globe size-5 text-n-slate-10 shrink-0 hidden sm:block"
              />
              <div class="flex-1 min-w-0">
                <p
                  class="font-mono text-sm font-medium text-n-slate-12 truncate"
                >
                  {{ entry.ip }}
                </p>
                <p
                  v-if="entry.comment"
                  class="text-xs text-n-slate-10 truncate"
                >
                  {{ entry.comment }}
                </p>
              </div>
              <p
                class="hidden md:block text-xs text-n-slate-10 shrink-0 tabular-nums"
              >
                {{ formatDate(entry.created_at) }}
              </p>
              <Label
                :label="
                  entry.is_active
                    ? t('JABVOX_IP_WHITELIST.STATUS.ACTIVE')
                    : t('JABVOX_IP_WHITELIST.STATUS.INACTIVE')
                "
                :color="entry.is_active ? 'teal' : 'slate'"
                compact
              />
              <label
                class="shrink-0 cursor-pointer"
                :title="
                  entry.is_active
                    ? t('JABVOX_IP_WHITELIST.STATUS.INACTIVE')
                    : t('JABVOX_IP_WHITELIST.STATUS.ACTIVE')
                "
              >
                <Switch
                  :model-value="entry.is_active"
                  @update:model-value="onToggle(entry)"
                />
              </label>
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                :title="t('JABVOX_IP_WHITELIST.DELETE')"
                @click="askDelete(entry)"
              />
            </div>
          </div>
        </template>
      </div>
    </div>

    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
