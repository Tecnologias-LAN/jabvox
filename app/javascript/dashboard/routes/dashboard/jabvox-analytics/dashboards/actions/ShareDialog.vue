<script setup>
import { ref, reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { analyticsDashboardsAPI } from 'dashboard/api/jabvox/analytics';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';

const props = defineProps({
  open: {
    type: Boolean,
    default: false,
  },
  dashboardId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const { showError } = useAnalyticsError();

const shares = ref([]);
const loading = ref(false);
const saving = ref(false);

const form = reactive({
  subjectType: 'user',
  subjectId: '',
  accessLevel: 'view',
});

const SUBJECT_TYPES = ['user', 'role', 'team'];
const ACCESS_LEVELS = ['view', 'edit', 'admin'];

// Labels resolved with static literal keys so the template binds plain strings.
const subjectTypeLabels = computed(() => ({
  user: t('JABVOX_ANALYTICS.SHARE.USER'),
  role: t('JABVOX_ANALYTICS.SHARE.ROLE'),
  team: t('JABVOX_ANALYTICS.SHARE.TEAM'),
}));

const accessLevelLabels = computed(() => ({
  view: t('JABVOX_ANALYTICS.SHARE.ACCESS.view'),
  edit: t('JABVOX_ANALYTICS.SHARE.ACCESS.edit'),
  admin: t('JABVOX_ANALYTICS.SHARE.ACCESS.admin'),
}));

const canAdd = computed(() => String(form.subjectId).trim() !== '');

const loadShares = async () => {
  loading.value = true;
  try {
    const { data } = await analyticsDashboardsAPI.getShares(props.dashboardId);
    shares.value = camelcaseKeys(data, { deep: true });
  } catch (error) {
    showError(error);
  } finally {
    loading.value = false;
  }
};

watch(
  () => props.open,
  isOpen => {
    if (isOpen) loadShares();
  },
  { immediate: true }
);

const addShare = async () => {
  if (!canAdd.value) return;
  saving.value = true;
  try {
    await analyticsDashboardsAPI.createShare(props.dashboardId, {
      subject_type_jabvox: form.subjectType,
      subject_id_jabvox: Number(form.subjectId),
      access_level_jabvox: form.accessLevel,
    });
    useAlert(t('JABVOX_ANALYTICS.SHARE.ADDED'));
    form.subjectId = '';
    await loadShares();
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.SHARE.ADD_ERROR');
  } finally {
    saving.value = false;
  }
};

const removeShare = async shareId => {
  try {
    await analyticsDashboardsAPI.deleteShare(props.dashboardId, shareId);
    useAlert(t('JABVOX_ANALYTICS.SHARE.REMOVED'));
    await loadShares();
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.SHARE.REMOVE_ERROR');
  }
};

const accessLabel = level => accessLevelLabels.value[level] || level;

const subjectTypeLabel = type => subjectTypeLabels.value[type] || type;

// Full label for a share row, e.g. "User #5 · Can edit" — composed here so the template
// has no bare punctuation and no dynamic i18n keys.
const shareLabel = share =>
  `${subjectTypeLabel(share.subjectTypeJabvox)} #${share.subjectIdJabvox} · ${accessLabel(
    share.accessLevelJabvox
  )}`;

const labelClass = 'mb-1 block text-xs font-medium text-n-slate-11';
const inputClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div>
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-n-alpha-3 p-4 pt-16"
    >
      <div
        class="w-full max-w-lg rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <div class="mb-4 flex items-center justify-between">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.SHARE.TITLE') }}
          </h3>
          <button
            type="button"
            class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <!-- Add share -->
        <div class="grid grid-cols-12 items-end gap-2">
          <div class="col-span-4">
            <label :class="labelClass">{{
              t('JABVOX_ANALYTICS.SHARE.SUBJECT_TYPE')
            }}</label>
            <select v-model="form.subjectType" :class="inputClass">
              <option v-for="s in SUBJECT_TYPES" :key="s" :value="s">
                {{ subjectTypeLabels[s] }}
              </option>
            </select>
          </div>
          <div class="col-span-3">
            <label :class="labelClass">{{
              t('JABVOX_ANALYTICS.SHARE.SUBJECT_ID')
            }}</label>
            <input v-model="form.subjectId" type="number" :class="inputClass" />
          </div>
          <div class="col-span-3">
            <label :class="labelClass">{{
              t('JABVOX_ANALYTICS.SHARE.ACCESS_LEVEL')
            }}</label>
            <select v-model="form.accessLevel" :class="inputClass">
              <option v-for="a in ACCESS_LEVELS" :key="a" :value="a">
                {{ accessLevelLabels[a] }}
              </option>
            </select>
          </div>
          <div class="col-span-2">
            <button
              type="button"
              class="w-full rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="!canAdd || saving"
              @click="addShare"
            >
              {{ t('JABVOX_ANALYTICS.SHARE.ADD') }}
            </button>
          </div>
        </div>

        <!-- Current shares -->
        <div class="mt-6">
          <p class="mb-2 text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.SHARE.CURRENT') }}
          </p>
          <div
            v-if="loading"
            class="flex items-center justify-center py-6 text-n-slate-11"
          >
            <span class="i-lucide-loader-circle size-5 animate-spin" />
          </div>
          <p v-else-if="!shares.length" class="py-4 text-sm text-n-slate-11">
            {{ t('JABVOX_ANALYTICS.SHARE.EMPTY') }}
          </p>
          <ul v-else class="flex flex-col gap-1">
            <li
              v-for="share in shares"
              :key="share.id"
              class="flex items-center justify-between rounded-lg border border-n-weak px-3 py-2 text-sm"
            >
              <span class="text-n-slate-12">{{ shareLabel(share) }}</span>
              <button
                type="button"
                class="rounded-lg p-1 text-n-ruby-11 hover:bg-n-alpha-2"
                @click="removeShare(share.id)"
              >
                <span class="i-lucide-trash-2 size-4" />
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
  </div>
</template>
