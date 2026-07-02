<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { aiChatStoragesAPI } from 'dashboard/api/jabvox/aiChat';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Self-contained manager for the shared storage buckets (JabvoxAudioStorage).
// These are the same buckets Audio Analysis uses; managing them here keeps a
// single source of truth. Emits `changed` after any create/update/delete so the
// parent can refresh its storage list.
const emit = defineEmits(['changed']);

const { t } = useI18n();

const open = ref(false);
const loading = ref(false);
const saving = ref(false);
const storages = ref([]);
// The storage being created/edited (null = list view).
const editing = ref(null);

const blankStorage = () => ({
  id: null,
  name: '',
  bucket_name: '',
  bucket_region: 'us-east-1',
  endpoint: '',
  access_key: '',
  secret_key: '',
  path_prefix: '',
});

const load = async () => {
  loading.value = true;
  try {
    const { data } = await aiChatStoragesAPI.getAll();
    storages.value = data.storages || [];
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  } finally {
    loading.value = false;
  }
};

const openDialog = async () => {
  open.value = true;
  editing.value = null;
  await load();
};

const close = () => {
  open.value = false;
  editing.value = null;
};

const startCreate = () => {
  editing.value = blankStorage();
};

const startEdit = storage => {
  // secret_key stays blank on edit; leaving it blank keeps the stored one.
  editing.value = { ...storage, secret_key: '' };
};

const save = async () => {
  if (!editing.value.name?.trim()) {
    useAlert(t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.NAME_REQUIRED'));
    return;
  }
  saving.value = true;
  try {
    const payload = { ...editing.value };
    if (payload.id) {
      await aiChatStoragesAPI.update(payload.id, payload);
    } else {
      await aiChatStoragesAPI.create(payload);
    }
    useAlert(t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.SAVED'));
    editing.value = null;
    await load();
    emit('changed');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  } finally {
    saving.value = false;
  }
};

const testConnection = async () => {
  try {
    const { data } = await aiChatStoragesAPI.test(editing.value);
    useAlert(
      data.success
        ? t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.TEST_OK')
        : data.message || t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.TEST_FAIL')
    );
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  }
};

const remove = async storage => {
  try {
    await aiChatStoragesAPI.destroy(storage.id);
    await load();
    emit('changed');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_AI_CHAT.ERROR'));
  }
};

defineExpose({ openDialog });
</script>

<template>
  <teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
      @click.self="close"
    >
      <div
        class="flex flex-col w-full max-w-2xl max-h-[85vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-lg overflow-hidden"
      >
        <!-- Header -->
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <h3 class="text-base font-semibold text-n-slate-12">
            {{ t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.TITLE') }}
          </h3>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            @click="close"
          />
        </div>

        <!-- Body -->
        <div class="flex-1 overflow-y-auto px-5 py-4">
          <div v-if="loading" class="flex items-center justify-center py-16">
            <Spinner :size="24" />
          </div>

          <!-- List -->
          <template v-else-if="!editing">
            <div class="flex justify-end mb-3">
              <Button
                :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.NEW')"
                icon="i-lucide-plus"
                size="sm"
                @click="startCreate"
              />
            </div>
            <div
              v-if="!storages.length"
              class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
            >
              {{ t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.EMPTY') }}
            </div>
            <div
              v-else
              class="rounded-xl border border-n-weak divide-y divide-n-weak overflow-hidden"
            >
              <div
                v-for="s in storages"
                :key="s.id"
                class="flex items-center gap-3 px-4 py-3"
              >
                <span
                  class="i-lucide-database size-4 text-n-slate-10 shrink-0"
                />
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-n-slate-12 truncate">
                    {{ s.name }}
                  </p>
                  <p class="text-xs text-n-slate-10 truncate">
                    {{ s.bucket_name || '—' }}
                  </p>
                </div>
                <Button
                  icon="i-lucide-pencil"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="startEdit(s)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  @click="remove(s)"
                />
              </div>
            </div>
          </template>

          <!-- Editor -->
          <template v-else>
            <div class="flex flex-col gap-4">
              <Input
                v-model="editing.name"
                :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.NAME')"
              />
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <Input
                  v-model="editing.bucket_name"
                  :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.BUCKET')"
                />
                <Input
                  v-model="editing.bucket_region"
                  :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.REGION')"
                  placeholder="us-east-1"
                />
                <div class="sm:col-span-2">
                  <Input
                    v-model="editing.endpoint"
                    :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.ENDPOINT')"
                  />
                </div>
                <Input
                  v-model="editing.access_key"
                  :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.ACCESS_KEY')"
                  custom-input-class="font-mono"
                />
                <Input
                  v-model="editing.secret_key"
                  type="password"
                  :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.SECRET_KEY')"
                  :placeholder="
                    editing.id
                      ? t('JABVOX_AI_CHAT.DOCUMENTS.SECRET_KEY_PLACEHOLDER')
                      : ''
                  "
                  custom-input-class="font-mono"
                />
              </div>
              <Input
                v-model="editing.path_prefix"
                :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.PATH_PREFIX')"
              />
            </div>
          </template>
        </div>

        <!-- Footer -->
        <div
          class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak"
        >
          <template v-if="editing">
            <Button
              :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.TEST')"
              icon="i-lucide-plug-zap"
              variant="outline"
              color="slate"
              size="sm"
              @click="testConnection"
            />
            <Button
              :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.CANCEL')"
              variant="ghost"
              color="slate"
              size="sm"
              @click="editing = null"
            />
            <Button
              :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.SAVE')"
              size="sm"
              :is-loading="saving"
              @click="save"
            />
          </template>
          <Button
            v-else
            :label="t('JABVOX_AI_CHAT.DOCUMENTS.STORAGES.CLOSE')"
            variant="outline"
            color="slate"
            size="sm"
            @click="close"
          />
        </div>
      </div>
    </div>
  </teleport>
</template>
