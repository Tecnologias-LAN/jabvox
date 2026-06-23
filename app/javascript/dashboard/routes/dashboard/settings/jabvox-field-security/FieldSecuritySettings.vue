<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

const store = useStore();
const { t } = useI18n();

const userRows = useMapGetter('jabvoxFieldVisibilities/getUserRows');
const uiFlags = useMapGetter('jabvoxFieldVisibilities/getUIFlags');

const search = ref('');

const GROUPS = [
  {
    key: 'contact',
    label: t('JABVOX_FIELD_SECURITY.GROUP_CONTACT'),
    fields: ['name', 'phone', 'email', 'identification'],
  },
  {
    key: 'profile',
    label: t('JABVOX_FIELD_SECURITY.GROUP_PROFILE'),
    fields: ['company', 'contact_type', 'country', 'city'],
  },
  {
    key: 'social',
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

const GROUP_TONE = {
  contact: 'bg-n-iris-3 text-n-slate-12',
  profile: 'bg-n-amber-3 text-n-slate-12',
  social: 'bg-n-teal-3 text-n-slate-12',
};

const ALL_FIELDS = GROUPS.flatMap(g => g.fields);

const GROUP_LAST_FIELDS = new Set(
  GROUPS.slice(0, -1).map(g => g.fields[g.fields.length - 1])
);

onMounted(() => store.dispatch('jabvoxFieldVisibilities/fetchAll'));

const isVisible = (user, field) => user.visibilities[field] !== false;

const filteredRows = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return userRows.value;
  return userRows.value.filter(
    u => u.name?.toLowerCase().includes(q) || u.email?.toLowerCase().includes(q)
  );
});

const totalUsers = computed(() => userRows.value.length);
const totalFields = computed(() => ALL_FIELDS.length);
const totalRestricted = computed(() =>
  userRows.value.reduce(
    (sum, u) => sum + ALL_FIELDS.filter(f => !isVisible(u, f)).length,
    0
  )
);

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

const allVisible = user => ALL_FIELDS.every(f => isVisible(user, f));

const toggleRow = async user => {
  const target = !allVisible(user);
  const toUpdate = ALL_FIELDS.filter(f => isVisible(user, f) !== target);
  try {
    await Promise.all(
      toUpdate.map(field =>
        store.dispatch('jabvoxFieldVisibilities/toggleField', {
          userId: user.id,
          fieldName: field,
          canView: target,
        })
      )
    );
    useAlert(t('JABVOX_FIELD_SECURITY.SAVED'));
  } catch {
    useAlert(t('JABVOX_FIELD_SECURITY.ERROR'));
  }
};

const fieldLabel = field => t(`JABVOX_FIELD_SECURITY.FIELDS.${field}`);
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-7xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div class="flex items-start gap-3 min-w-0">
        <span
          class="i-lucide-shield-check size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('JABVOX_FIELD_SECURITY.TITLE') }}
          </h1>
          <p class="mt-1 max-w-2xl text-sm leading-relaxed text-n-slate-11">
            {{ t('JABVOX_FIELD_SECURITY.DESCRIPTION') }}
          </p>
        </div>
      </div>

      <!-- Loading -->
      <div
        v-if="uiFlags.isFetching"
        class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_FIELD_SECURITY.LOADING') }}
      </div>

      <!-- Empty -->
      <EmptyStateLayout
        v-else-if="!userRows.length"
        :title="t('JABVOX_FIELD_SECURITY.EMPTY_TITLE')"
        :subtitle="t('JABVOX_FIELD_SECURITY.EMPTY')"
      />

      <template v-else>
        <!-- KPIs -->
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <span
              class="i-lucide-users size-8 rounded-lg bg-n-iris-3 p-1.5 text-n-slate-12"
            />
            <div>
              <p class="text-2xl font-semibold text-n-slate-12">
                {{ totalUsers }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_FIELD_SECURITY.KPI_USERS') }}
              </p>
            </div>
          </div>
          <div
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <span
              class="i-lucide-list size-8 rounded-lg bg-n-teal-3 p-1.5 text-n-slate-12"
            />
            <div>
              <p class="text-2xl font-semibold text-n-slate-12">
                {{ totalFields }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_FIELD_SECURITY.KPI_FIELDS') }}
              </p>
            </div>
          </div>
          <div
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <span
              class="i-lucide-eye-off size-8 rounded-lg bg-n-ruby-3 p-1.5 text-n-ruby-11"
            />
            <div>
              <p class="text-2xl font-semibold text-n-slate-12">
                {{ totalRestricted }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_FIELD_SECURITY.KPI_RESTRICTED') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Search -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="w-full sm:w-80">
            <Input
              v-model="search"
              :placeholder="t('JABVOX_FIELD_SECURITY.SEARCH_PLACEHOLDER')"
            >
              <template #prefix>
                <span class="i-lucide-search size-4 text-n-slate-10" />
              </template>
            </Input>
          </div>
          <span class="text-xs text-n-slate-10">
            {{ t('JABVOX_FIELD_SECURITY.COUNT', { count: totalUsers }) }}
          </span>
        </div>

        <!-- No results -->
        <div
          v-if="!filteredRows.length"
          class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_FIELD_SECURITY.NO_RESULTS') }}
        </div>

        <!-- Matrix -->
        <div
          v-else
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
        >
          <div class="overflow-x-auto">
            <table class="w-full text-sm border-collapse">
              <thead>
                <!-- Group header row -->
                <tr class="border-b border-n-weak">
                  <th
                    rowspan="2"
                    class="sticky left-0 z-10 bg-n-solid-1 border-r border-n-weak px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-wide text-n-slate-10 min-w-[200px]"
                  >
                    {{ t('JABVOX_FIELD_SECURITY.USER_COLUMN') }}
                  </th>
                  <th
                    v-for="(group, idx) in GROUPS"
                    :key="group.key"
                    :colspan="group.fields.length"
                    class="px-2 py-2 text-center text-xs font-bold uppercase tracking-wide"
                    :class="[
                      GROUP_TONE[group.key],
                      idx < GROUPS.length - 1
                        ? 'border-r-2 border-r-n-weak'
                        : '',
                    ]"
                  >
                    {{ group.label }}
                  </th>
                </tr>
                <!-- Field name row -->
                <tr class="border-b border-n-weak bg-n-alpha-1">
                  <th
                    v-for="field in ALL_FIELDS"
                    :key="field"
                    class="px-2 py-2 text-center text-xs font-medium text-n-slate-11 whitespace-nowrap min-w-[76px]"
                    :class="{
                      'border-r-2 border-r-n-weak':
                        GROUP_LAST_FIELDS.has(field),
                    }"
                  >
                    {{ fieldLabel(field) }}
                  </th>
                </tr>
              </thead>

              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="user in filteredRows"
                  :key="user.id"
                  class="hover:bg-n-alpha-1 transition-colors"
                >
                  <!-- Sticky user column -->
                  <td
                    class="sticky left-0 z-10 bg-n-solid-1 border-r border-n-weak px-4 py-3 min-w-[200px]"
                  >
                    <div class="flex items-center gap-3 min-w-0">
                      <Avatar
                        :name="user.name || user.email"
                        :src="user.thumbnail || user.avatar_url"
                        :size="32"
                        rounded-full
                      />
                      <div class="flex flex-col min-w-0 flex-1">
                        <span
                          class="text-sm font-medium text-n-slate-12 truncate"
                        >
                          {{ user.name }}
                        </span>
                        <span class="text-xs text-n-slate-10 truncate">
                          {{ user.email }}
                        </span>
                      </div>
                      <Button
                        :icon="
                          allVisible(user) ? 'i-lucide-eye-off' : 'i-lucide-eye'
                        "
                        variant="ghost"
                        color="slate"
                        size="sm"
                        :disabled="uiFlags.isSaving"
                        :title="
                          allVisible(user)
                            ? t('JABVOX_FIELD_SECURITY.HIDE_ALL')
                            : t('JABVOX_FIELD_SECURITY.SHOW_ALL')
                        "
                        @click="toggleRow(user)"
                      />
                    </div>
                  </td>

                  <!-- Field toggles -->
                  <td
                    v-for="field in ALL_FIELDS"
                    :key="field"
                    class="px-2 py-3 text-center"
                    :class="{
                      'border-r-2 border-r-n-weak':
                        GROUP_LAST_FIELDS.has(field),
                    }"
                  >
                    <button
                      class="inline-flex items-center justify-center size-7 rounded-lg transition-colors"
                      :class="
                        isVisible(user, field)
                          ? 'bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4'
                          : 'bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4'
                      "
                      :disabled="uiFlags.isSaving"
                      :title="
                        isVisible(user, field)
                          ? t('JABVOX_FIELD_SECURITY.VISIBLE')
                          : t('JABVOX_FIELD_SECURITY.RESTRICTED')
                      "
                      @click="toggle(user.id, field, isVisible(user, field))"
                    >
                      <span
                        class="size-4 block"
                        :class="
                          isVisible(user, field)
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
            class="flex items-center gap-5 border-t border-n-weak px-5 py-3 text-xs text-n-slate-10"
          >
            <span class="flex items-center gap-1.5">
              <span
                class="inline-flex items-center justify-center size-5 rounded bg-n-teal-3 text-n-teal-11"
              >
                <span class="i-lucide-eye size-3 block" />
              </span>
              {{ t('JABVOX_FIELD_SECURITY.VISIBLE') }}
            </span>
            <span class="flex items-center gap-1.5">
              <span
                class="inline-flex items-center justify-center size-5 rounded bg-n-ruby-3 text-n-ruby-11"
              >
                <span class="i-lucide-eye-off size-3 block" />
              </span>
              {{ t('JABVOX_FIELD_SECURITY.RESTRICTED_HINT') }}
            </span>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
