<script setup>
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SettingsCard from './SettingsCard.vue';

defineProps({
  storages: { type: Array, default: () => [] },
});

const emit = defineEmits(['new', 'edit', 'delete', 'save', 'test', 'cancel']);

// The storage being created/edited (null when listing). It's a v-model so the
// editor inputs can mutate it directly; the parent watches the same object to
// flag unsaved changes.
const editing = defineModel('editing', { type: Object, default: null });

const { t } = useI18n();
</script>

<template>
  <!-- List view -->
  <SettingsCard
    v-if="!editing"
    :title="t('JABVOX_AUDIO.STORAGE.TITLE')"
    :description="t('JABVOX_AUDIO.STORAGE.SUBTITLE')"
    icon="i-lucide-database"
  >
    <template #actions>
      <Button
        :label="t('JABVOX_AUDIO.STORAGE.NEW')"
        icon="i-lucide-plus"
        size="sm"
        @click="emit('new')"
      />
    </template>

    <div v-if="storages.length" class="flex flex-col gap-2">
      <div
        v-for="s in storages"
        :key="s.id"
        class="flex items-center justify-between gap-3 rounded-xl border border-n-weak px-4 py-3 transition-colors hover:bg-n-alpha-1"
      >
        <div class="flex items-center gap-3 min-w-0">
          <span
            class="flex items-center justify-center size-8 rounded-lg bg-n-alpha-2 text-n-slate-11 shrink-0"
          >
            <span class="i-lucide-hard-drive size-4" />
          </span>
          <div class="min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ s.name }}
            </p>
            <p class="text-xs text-n-slate-11 truncate">
              {{ s.bucket_name }}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-1 shrink-0">
          <Button
            icon="i-lucide-pencil"
            variant="ghost"
            color="slate"
            size="sm"
            @click="emit('edit', s)"
          />
          <Button
            icon="i-lucide-trash-2"
            variant="ghost"
            color="ruby"
            size="sm"
            @click="emit('delete', s.id)"
          />
        </div>
      </div>
    </div>

    <EmptyStateLayout
      v-else
      :title="t('JABVOX_AUDIO.STORAGE.EMPTY_TITLE')"
      :subtitle="t('JABVOX_AUDIO.STORAGE.EMPTY')"
      :show-backdrop="false"
    >
      <template #actions>
        <Button
          :label="t('JABVOX_AUDIO.STORAGE.NEW')"
          icon="i-lucide-plus"
          @click="emit('new')"
        />
      </template>
    </EmptyStateLayout>
  </SettingsCard>

  <!-- Editor view -->
  <SettingsCard
    v-else
    :title="
      editing.id
        ? t('JABVOX_AUDIO.STORAGE.EDIT_TITLE')
        : t('JABVOX_AUDIO.STORAGE.NEW')
    "
    icon="i-lucide-database"
  >
    <div class="flex flex-col gap-5">
      <Input
        v-model="editing.name"
        :label="t('JABVOX_AUDIO.STORAGE.NAME')"
        :placeholder="t('JABVOX_AUDIO.STORAGE.NAME')"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Input
          v-model="editing.bucket_name"
          :label="t('JABVOX_AUDIO.STORAGE.BUCKET')"
          :placeholder="t('JABVOX_AUDIO.STORAGE.BUCKET')"
        />
        <Input
          v-model="editing.bucket_region"
          :label="t('JABVOX_AUDIO.STORAGE.REGION')"
          placeholder="us-east-1"
        />
        <div class="sm:col-span-2">
          <Input
            v-model="editing.endpoint"
            :label="t('JABVOX_AUDIO.STORAGE.ENDPOINT')"
            :placeholder="t('JABVOX_AUDIO.STORAGE.ENDPOINT')"
          />
        </div>
        <Input
          v-model="editing.access_key"
          :label="t('JABVOX_AUDIO.STORAGE.ACCESS_KEY')"
          :placeholder="t('JABVOX_AUDIO.STORAGE.ACCESS_KEY')"
        />
        <Input
          v-model="editing.secret_key"
          type="password"
          :label="t('JABVOX_AUDIO.STORAGE.SECRET_KEY')"
          :placeholder="t('JABVOX_AUDIO.STORAGE.SECRET_KEY')"
        />
      </div>

      <Input
        v-model="editing.path_prefix"
        :label="t('JABVOX_AUDIO.STORAGE.PATH_PREFIX')"
        :placeholder="t('JABVOX_AUDIO.STORAGE.PATH_PREFIX')"
      />

      <div class="flex items-center gap-2 pt-1">
        <Button :label="t('JABVOX_AUDIO.SAVE')" @click="emit('save')" />
        <Button
          :label="t('JABVOX_AUDIO.TEST')"
          variant="outline"
          color="slate"
          icon="i-lucide-plug-zap"
          @click="emit('test')"
        />
        <Button
          :label="t('JABVOX_AUDIO.CANCEL')"
          variant="ghost"
          color="slate"
          @click="emit('cancel')"
        />
      </div>
    </div>
  </SettingsCard>
</template>
