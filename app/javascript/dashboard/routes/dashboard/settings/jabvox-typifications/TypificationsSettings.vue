<script setup>
import { ref, onMounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';

const { t } = useI18n();

// Warn before reload/close while editing a typification with unsaved changes.
const { markDirty, markClean } = useUnsavedChanges();

const items = ref([]);
const editing = ref(null);

watch(editing, () => markDirty(), { deep: true });

const load = async () => {
  const { data } = await typificationsAPI.getAll(false);
  items.value = data.typifications || [];
};

const startCreate = () => {
  editing.value = { name: '', description: '', is_active: true };
};

const cancelEdit = async () => {
  editing.value = null;
  await nextTick();
  markClean();
};

const save = async () => {
  if (!editing.value.name) {
    useAlert(t('JABVOX_CLICK_TO_CALL.SETTINGS.NAME_REQUIRED'));
    return;
  }
  try {
    if (editing.value.id)
      await typificationsAPI.update(editing.value.id, editing.value);
    else await typificationsAPI.create(editing.value);
    editing.value = null;
    await load();
    await nextTick();
    markClean();
    useAlert(t('JABVOX_CLICK_TO_CALL.SETTINGS.SAVED'));
  } catch (e) {
    useAlert(t('JABVOX_CLICK_TO_CALL.SETTINGS.SAVE_ERROR'));
  }
};

const remove = async id => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('JABVOX_CLICK_TO_CALL.SETTINGS.CONFIRM_DELETE')))
    return;
  await typificationsAPI.destroy(id);
  await load();
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col flex-1 overflow-auto p-6 max-w-2xl">
    <h1 class="text-xl font-medium text-n-slate-12 mb-1">
      {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.TITLE') }}
    </h1>
    <p class="text-sm text-n-slate-11 mb-4">
      {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.SUBTITLE') }}
    </p>

    <div v-if="!editing">
      <button
        class="mb-4 px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
        @click="startCreate"
      >
        {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.NEW') }}
      </button>
      <div
        v-for="tp in items"
        :key="tp.id"
        class="flex items-center justify-between p-3 mb-2 rounded-lg bg-n-alpha-2"
      >
        <div>
          <span class="font-medium text-n-slate-12">{{ tp.name }}</span>
          <span v-if="!tp.is_active" class="ml-2 text-xs text-n-slate-10">
            {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.INACTIVE') }}
          </span>
          <p v-if="tp.description" class="text-xs text-n-slate-11">
            {{ tp.description }}
          </p>
        </div>
        <div class="flex gap-2">
          <button class="text-sm text-n-slate-11" @click="editing = { ...tp }">
            {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.EDIT') }}
          </button>
          <button class="text-sm text-n-ruby-11" @click="remove(tp.id)">
            {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.DELETE') }}
          </button>
        </div>
      </div>
      <p v-if="!items.length" class="text-sm text-n-slate-11">
        {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.EMPTY') }}
      </p>
    </div>

    <div v-else class="space-y-3">
      <input
        v-model="editing.name"
        class="reset-base text-sm w-full"
        :placeholder="t('JABVOX_CLICK_TO_CALL.SETTINGS.NAME')"
      />
      <input
        v-model="editing.description"
        class="reset-base text-sm w-full"
        :placeholder="t('JABVOX_CLICK_TO_CALL.SETTINGS.DESCRIPTION')"
      />
      <label class="flex items-center gap-2 text-sm text-n-slate-11">
        <input v-model="editing.is_active" type="checkbox" />
        {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.ACTIVE') }}
      </label>
      <div class="flex gap-3">
        <button
          class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
          @click="save"
        >
          {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.SAVE') }}
        </button>
        <button
          class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
          @click="cancelEdit"
        >
          {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.CANCEL') }}
        </button>
      </div>
    </div>
  </div>
</template>
