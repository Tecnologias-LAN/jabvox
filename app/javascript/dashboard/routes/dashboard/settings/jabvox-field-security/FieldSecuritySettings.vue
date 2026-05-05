<script setup>
import { onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const store = useStore();
const { t } = useI18n();

const userRows = useMapGetter('jabvoxFieldVisibilities/getUserRows');
const uiFlags = useMapGetter('jabvoxFieldVisibilities/getUIFlags');

const GROUPS = [
  {
    label: t('JABVOX_FIELD_SECURITY.GROUP_CONTACT'),
    fields: ['name', 'phone', 'email', 'identification'],
  },
  {
    label: t('JABVOX_FIELD_SECURITY.GROUP_PROFILE'),
    fields: ['company', 'contact_type', 'country', 'city'],
  },
  {
    label: t('JABVOX_FIELD_SECURITY.GROUP_SOCIAL'),
    fields: [
      'social_facebook',
      'social_twitter',
      'social_linkedin',
      'social_github',
      'social_telegram',
      'social_tiktok',
    ],
  },
];

const ALL_FIELDS = GROUPS.flatMap(g => g.fields);

const GROUP_LAST_FIELDS = new Set(
  GROUPS.slice(0, -1).map(g => g.fields[g.fields.length - 1])
);

onMounted(() => store.dispatch('jabvoxFieldVisibilities/fetchAll'));

const toggle = async (userId, fieldName, currentValue) => {
  try {
    await store.dispatch('jabvoxFieldVisibilities/toggleField', {
      userId,
      fieldName,
      canView: !currentValue,
    });
    useAlert(t('JABVOX_FIELD_SECURITY.SAVED'));
  } catch {
    useAlert(t('JABVOX_FIELD_SECURITY.ERROR'));
  }
};

const fieldLabel = field => t(`JABVOX_FIELD_SECURITY.FIELDS.${field}`);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <!-- Page header -->
    <div class="shrink-0 border-b border-n-weak bg-n-surface-1">
      <div class="max-w-full mx-auto px-6 sm:px-8 py-6">
        <h1 class="text-heading-1 text-n-slate-12">
          {{ $t('JABVOX_FIELD_SECURITY.TITLE') }}
        </h1>
        <p class="mt-1 text-body-main text-n-slate-11 max-w-2xl">
          {{ $t('JABVOX_FIELD_SECURITY.DESCRIPTION') }}
        </p>
      </div>
    </div>

    <!-- Scrollable content -->
    <div class="flex-1 overflow-auto">
      <div class="px-6 sm:px-8 py-8">
        <!-- Loading -->
        <div
          v-if="uiFlags.isFetching"
          class="flex items-center justify-center py-20 text-sm text-slate-400 animate-pulse"
        >
          {{ $t('JABVOX_FIELD_SECURITY.LOADING') }}
        </div>

        <!-- Empty -->
        <div
          v-else-if="!userRows.length"
          class="flex items-center justify-center py-20 text-sm text-slate-400"
        >
          {{ $t('JABVOX_FIELD_SECURITY.EMPTY') }}
        </div>

        <!-- Table -->
        <div
          v-else
          class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 shadow-sm overflow-hidden"
        >
          <div class="overflow-x-auto">
            <table class="w-full text-sm border-collapse">
              <thead>
                <!-- Group header row -->
                <tr
                  class="bg-slate-50 dark:bg-slate-700/40 border-b border-slate-200 dark:border-slate-700"
                >
                  <th
                    class="sticky left-0 z-10 bg-slate-50 dark:bg-slate-700/40 text-left px-4 py-2 text-xs font-semibold text-slate-500 uppercase tracking-wide border-r border-slate-200 dark:border-slate-700 min-w-[180px]"
                    rowspan="2"
                  >
                    Usuario
                  </th>
                  <th
                    v-for="(group, idx) in GROUPS"
                    :key="group.label"
                    :colspan="group.fields.length"
                    class="text-center px-2 py-2 text-xs font-bold text-slate-600 dark:text-slate-300 uppercase tracking-wide border-b border-slate-200 dark:border-slate-600"
                    :class="{
                      'bg-indigo-50 dark:bg-indigo-900/20':
                        group.label ===
                        $t('JABVOX_FIELD_SECURITY.GROUP_CONTACT'),
                      'bg-amber-50 dark:bg-amber-900/20':
                        group.label ===
                        $t('JABVOX_FIELD_SECURITY.GROUP_PROFILE'),
                      'bg-sky-50 dark:bg-sky-900/20':
                        group.label ===
                        $t('JABVOX_FIELD_SECURITY.GROUP_SOCIAL'),
                      'border-r-2 border-r-slate-300 dark:border-r-slate-500':
                        idx < GROUPS.length - 1,
                    }"
                  >
                    {{ group.label }}
                  </th>
                </tr>
                <!-- Field name row -->
                <tr
                  class="bg-slate-50 dark:bg-slate-700/40 border-b border-slate-200 dark:border-slate-700"
                >
                  <th
                    v-for="field in ALL_FIELDS"
                    :key="field"
                    class="text-center px-2 py-2 text-xs font-semibold text-slate-500 dark:text-slate-400 whitespace-nowrap min-w-[72px]"
                    :class="{
                      'border-r-2 border-r-slate-300 dark:border-r-slate-500':
                        GROUP_LAST_FIELDS.has(field),
                    }"
                  >
                    {{ fieldLabel(field) }}
                  </th>
                </tr>
              </thead>

              <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
                <tr
                  v-for="user in userRows"
                  :key="user.id"
                  class="hover:bg-slate-50/60 dark:hover:bg-slate-700/20 transition-colors"
                >
                  <!-- Sticky user column -->
                  <td
                    class="sticky left-0 z-10 bg-white dark:bg-slate-800 px-4 py-3 border-r border-slate-100 dark:border-slate-700 min-w-[180px]"
                  >
                    <div class="flex flex-col min-w-0">
                      <span
                        class="text-sm font-medium text-slate-800 dark:text-slate-100 truncate"
                      >
                        {{ user.name }}
                      </span>
                      <span class="text-xs text-slate-400 truncate">
                        {{ user.email }}
                      </span>
                    </div>
                  </td>

                  <!-- Field toggles -->
                  <td
                    v-for="field in ALL_FIELDS"
                    :key="field"
                    class="px-2 py-3 text-center"
                    :class="{
                      'border-r-2 border-r-slate-200 dark:border-r-slate-600':
                        GROUP_LAST_FIELDS.has(field),
                    }"
                  >
                    <button
                      class="inline-flex items-center justify-center w-7 h-7 rounded-lg transition-colors"
                      :class="
                        user.visibilities[field] !== false
                          ? 'bg-green-50 text-green-600 dark:bg-green-900/30 dark:text-green-400 hover:bg-green-100'
                          : 'bg-red-50 text-red-500 dark:bg-red-900/30 dark:text-red-400 hover:bg-red-100'
                      "
                      :disabled="uiFlags.isSaving"
                      :title="
                        user.visibilities[field] !== false
                          ? 'Visible'
                          : 'Restringido'
                      "
                      @click="
                        toggle(
                          user.id,
                          field,
                          user.visibilities[field] !== false
                        )
                      "
                    >
                      <span
                        class="text-sm block"
                        :class="
                          user.visibilities[field] !== false
                            ? 'i-lucide-eye'
                            : 'i-lucide-eye-off'
                        "
                      />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- Legend -->
          <div
            class="px-5 py-3 border-t border-slate-100 dark:border-slate-700 flex items-center gap-4 text-xs text-slate-400"
          >
            <span class="flex items-center gap-1.5">
              <span
                class="inline-flex items-center justify-center w-5 h-5 rounded bg-green-50 text-green-600 dark:bg-green-900/30"
              >
                <span class="i-lucide-eye text-xs block" />
              </span>
              Visible
            </span>
            <span class="flex items-center gap-1.5">
              <span
                class="inline-flex items-center justify-center w-5 h-5 rounded bg-red-50 text-red-500 dark:bg-red-900/30"
              >
                <span class="i-lucide-eye-off text-xs block" />
              </span>
              Restringido — muestra ***
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
