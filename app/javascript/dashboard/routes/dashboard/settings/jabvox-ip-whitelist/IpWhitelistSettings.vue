<script setup>
import { ref, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const entries = useMapGetter('jabvoxIpWhitelist/getEntries');
const uiFlags = useMapGetter('jabvoxIpWhitelist/getUIFlags');

const form = ref({ ip: '', comment: '', is_active: true });

onMounted(() => store.dispatch('jabvoxIpWhitelist/fetchEntries'));

const onAdd = async () => {
  if (!form.value.ip.trim()) return;
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

const onDelete = async entry => {
  if (!window.confirm(t('JABVOX_IP_WHITELIST.CONFIRM_DELETE'))) return;
  try {
    await store.dispatch('jabvoxIpWhitelist/deleteEntry', entry.id);
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
  <SettingsLayout>
    <BaseSettingsHeader
      :title="$t('JABVOX_IP_WHITELIST.TITLE')"
      :description="$t('JABVOX_IP_WHITELIST.DESCRIPTION')"
    />

    <div class="mt-8 max-w-3xl mx-auto space-y-6">
      <!-- Add form -->
      <div
        class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 p-6 shadow-sm"
      >
        <h3
          class="text-sm font-semibold text-slate-800 dark:text-slate-100 mb-5"
        >
          {{ $t('JABVOX_IP_WHITELIST.ADD_IP') }}
        </h3>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="space-y-1.5">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400"
            >
              {{ $t('JABVOX_IP_WHITELIST.TABLE.IP') }}
              <span class="text-red-500 ml-0.5">*</span>
            </label>
            <input
              v-model="form.ip"
              type="text"
              :placeholder="$t('JABVOX_IP_WHITELIST.FORM.IP_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent transition"
              @keydown.enter="onAdd"
            />
            <p class="text-xs text-slate-400">
              {{ $t('JABVOX_IP_WHITELIST.FORM.IP_HINT') }}
            </p>
          </div>

          <div class="space-y-1.5">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400"
            >
              {{ $t('JABVOX_IP_WHITELIST.TABLE.COMMENT') }}
            </label>
            <input
              v-model="form.comment"
              type="text"
              :placeholder="$t('JABVOX_IP_WHITELIST.FORM.COMMENT_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent transition"
            />
          </div>
        </div>

        <div class="mt-4 flex items-center justify-between flex-wrap gap-3">
          <label class="flex items-center gap-2 cursor-pointer select-none">
            <input
              id="ip-active"
              v-model="form.is_active"
              type="checkbox"
              class="h-4 w-4 rounded border-slate-300 text-woot-600 focus:ring-woot-500"
            />
            <span class="text-sm text-slate-600 dark:text-slate-300">
              {{ $t('JABVOX_IP_WHITELIST.FORM.ACTIVE_LABEL') }}
            </span>
          </label>

          <Button
            :label="$t('JABVOX_IP_WHITELIST.ADD_IP')"
            :is-loading="uiFlags.isSaving"
            :disabled="uiFlags.isSaving || !form.ip.trim()"
            @click="onAdd"
          />
        </div>
      </div>

      <!-- IP list -->
      <div
        class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 shadow-sm overflow-hidden"
      >
        <div
          class="px-6 py-4 border-b border-slate-100 dark:border-slate-700 flex items-center justify-between"
        >
          <h3 class="text-sm font-semibold text-slate-800 dark:text-slate-100">
            {{ $t('JABVOX_IP_WHITELIST.TABLE.IP') }} ({{ entries.length }})
          </h3>
        </div>

        <div v-if="uiFlags.isFetching" class="px-6 py-10 text-center">
          <div
            class="inline-block w-5 h-5 border-2 border-woot-500 border-t-transparent rounded-full animate-spin"
          />
        </div>

        <div
          v-else-if="entries.length === 0"
          class="px-6 py-12 text-center space-y-2"
        >
          <span
            class="i-ri-shield-check-line text-3xl text-slate-300 block mx-auto"
          />
          <p class="text-sm text-slate-400">
            {{ $t('JABVOX_IP_WHITELIST.EMPTY') }}
          </p>
        </div>

        <div v-else class="divide-y divide-slate-100 dark:divide-slate-700">
          <div
            v-for="entry in entries"
            :key="entry.id"
            class="px-6 py-4 flex items-center gap-4 hover:bg-slate-50 dark:hover:bg-slate-700/30 transition-colors"
          >
            <!-- IP + comment -->
            <div class="flex-1 min-w-0 space-y-0.5">
              <p
                class="font-mono text-sm font-medium text-slate-800 dark:text-slate-100 truncate"
              >
                {{ entry.ip }}
              </p>
              <p v-if="entry.comment" class="text-xs text-slate-400 truncate">
                {{ entry.comment }}
              </p>
            </div>

            <!-- Date -->
            <p class="hidden sm:block text-xs text-slate-400 flex-shrink-0">
              {{ formatDate(entry.created_at) }}
            </p>

            <!-- Status badge -->
            <span
              class="inline-flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full flex-shrink-0"
              :class="
                entry.is_active
                  ? 'bg-green-50 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                  : 'bg-slate-100 text-slate-500 dark:bg-slate-700 dark:text-slate-400'
              "
            >
              <span
                class="w-1.5 h-1.5 rounded-full flex-shrink-0"
                :class="entry.is_active ? 'bg-green-500' : 'bg-slate-400'"
              />
              {{
                entry.is_active
                  ? $t('JABVOX_IP_WHITELIST.STATUS.ACTIVE')
                  : $t('JABVOX_IP_WHITELIST.STATUS.INACTIVE')
              }}
            </span>

            <!-- Actions -->
            <div class="flex items-center gap-1 flex-shrink-0">
              <button
                class="p-1.5 rounded-lg text-slate-400 hover:text-woot-600 hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors"
                :title="
                  entry.is_active
                    ? $t('JABVOX_IP_WHITELIST.STATUS.INACTIVE')
                    : $t('JABVOX_IP_WHITELIST.STATUS.ACTIVE')
                "
                @click="onToggle(entry)"
              >
                <span
                  :class="
                    entry.is_active
                      ? 'i-ri-toggle-fill text-woot-500'
                      : 'i-ri-toggle-line'
                  "
                  class="text-lg block"
                />
              </button>
              <button
                class="p-1.5 rounded-lg text-slate-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                :title="$t('JABVOX_IP_WHITELIST.DELETE')"
                @click="onDelete(entry)"
              >
                <span class="i-ri-delete-bin-line text-lg block" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
