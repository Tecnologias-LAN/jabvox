<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dataExportAPI } from 'dashboard/api/jabvox/dataExport';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();
const apiError = (e, fallback) => e?.response?.data?.error || t(fallback);

const target = ref(null); // the saved target, or null
const editing = ref(null); // the form model when creating/editing
const testResult = ref(null);
const testing = ref(false);
const building = ref(false);
const confirmDialog = ref(null);

const engineOptions = computed(() => [
  { value: 'postgresql', label: 'PostgreSQL' },
  { value: 'mysql', label: 'MySQL' },
  { value: 'mariadb', label: 'MariaDB' },
]);

const load = async () => {
  const { data } = await dataExportAPI.getAll();
  target.value = (data.targets || [])[0] || null;
};

const newTarget = () => ({
  name_jabvox: '',
  engine_jabvox: 'postgresql',
  host_jabvox: '',
  port_jabvox: null,
  database_jabvox: '',
  username_jabvox: '',
  password_jabvox: '',
  ssl_mode_jabvox: 'prefer',
  allow_private_network_jabvox: false,
});

const openNew = () => {
  editing.value = newTarget();
  testResult.value = null;
};
const openEdit = () => {
  editing.value = { ...target.value, password_jabvox: '' };
  testResult.value = null;
};
const cancelEdit = () => {
  editing.value = null;
  testResult.value = null;
};

const testConnection = async () => {
  testing.value = true;
  testResult.value = null;
  try {
    const { data } = await dataExportAPI.test(editing.value);
    testResult.value = data;
  } catch (e) {
    testResult.value = {
      success: false,
      message: apiError(e, 'JABVOX_DATA_EXPORT.TEST_ERROR'),
    };
  } finally {
    testing.value = false;
  }
};

const save = async () => {
  try {
    if (editing.value.id) {
      await dataExportAPI.update(editing.value.id, editing.value);
    } else {
      await dataExportAPI.create(editing.value);
    }
    editing.value = null;
    await load();
    useAlert(t('JABVOX_DATA_EXPORT.SAVED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.SAVE_ERROR'));
  }
};

const remove = () => {
  confirmDialog.value?.open({
    title: t('JABVOX_DATA_EXPORT.DELETE'),
    description: t('JABVOX_DATA_EXPORT.DELETE_CONFIRM'),
    confirmLabel: t('JABVOX_DATA_EXPORT.DELETE'),
    cancelLabel: t('JABVOX_DATA_EXPORT.FORM.CANCEL'),
    data: target.value.id,
  });
};

const doRemove = async id => {
  await dataExportAPI.destroy(id);
  await load();
};

const testSaved = async () => {
  testing.value = true;
  try {
    const { data } = await dataExportAPI.testSaved(target.value.id);
    useAlert(data.success ? t('JABVOX_DATA_EXPORT.TEST_OK') : data.message);
    await load();
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.TEST_ERROR'));
  } finally {
    testing.value = false;
  }
};

const buildSchema = async () => {
  building.value = true;
  try {
    await dataExportAPI.buildSchema(target.value.id);
    await load();
    useAlert(t('JABVOX_DATA_EXPORT.SCHEMA_BUILT'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.SCHEMA_ERROR'));
  } finally {
    building.value = false;
  }
};

const toggleEnabled = async value => {
  try {
    const { data } = await dataExportAPI.toggle(target.value.id, value);
    target.value = data;
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.SAVE_ERROR'));
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col flex-1 overflow-auto bg-n-background">
    <div class="w-full max-w-[900px] mx-auto px-6 py-8 flex flex-col gap-6">
      <header>
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ t('JABVOX_DATA_EXPORT.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 mt-1">
          {{ t('JABVOX_DATA_EXPORT.SUBTITLE') }}
        </p>
      </header>

      <!-- Connection form -->
      <section
        v-if="editing"
        class="rounded-2xl bg-n-solid-1 border border-n-weak p-6 flex flex-col gap-4"
      >
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{
            editing.id
              ? t('JABVOX_DATA_EXPORT.FORM.EDIT_TITLE')
              : t('JABVOX_DATA_EXPORT.FORM.NEW_TITLE')
          }}
        </h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model="editing.name_jabvox"
            :label="t('JABVOX_DATA_EXPORT.FORM.NAME')"
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DATA_EXPORT.FORM.ENGINE') }}
            </label>
            <Select v-model="editing.engine_jabvox" :options="engineOptions" />
          </div>
          <Input
            v-model="editing.host_jabvox"
            :label="t('JABVOX_DATA_EXPORT.FORM.HOST')"
          />
          <Input
            v-model="editing.port_jabvox"
            type="number"
            :label="t('JABVOX_DATA_EXPORT.FORM.PORT')"
          />
          <Input
            v-model="editing.database_jabvox"
            :label="t('JABVOX_DATA_EXPORT.FORM.DATABASE')"
          />
          <Input
            v-model="editing.username_jabvox"
            :label="t('JABVOX_DATA_EXPORT.FORM.USERNAME')"
          />
          <Input
            v-model="editing.password_jabvox"
            type="password"
            :label="t('JABVOX_DATA_EXPORT.FORM.PASSWORD')"
            :placeholder="
              editing.has_password
                ? t('JABVOX_DATA_EXPORT.FORM.PASSWORD_KEEP')
                : ''
            "
          />
        </div>

        <div
          v-if="testResult"
          class="text-sm rounded-lg px-3 py-2"
          :class="
            testResult.success
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
        >
          {{ testResult.message }}
        </div>

        <div class="flex items-center gap-2">
          <Button
            :label="t('JABVOX_DATA_EXPORT.FORM.TEST')"
            variant="outline"
            color="slate"
            :is-loading="testing"
            @click="testConnection"
          />
          <Button
            class="ml-auto"
            :label="t('JABVOX_DATA_EXPORT.FORM.SAVE')"
            @click="save"
          />
          <Button
            :label="t('JABVOX_DATA_EXPORT.FORM.CANCEL')"
            variant="ghost"
            color="slate"
            @click="cancelEdit"
          />
        </div>
      </section>

      <!-- No connection yet -->
      <section
        v-else-if="!target"
        class="rounded-2xl border border-dashed border-n-weak p-10 text-center flex flex-col items-center gap-3"
      >
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_DATA_EXPORT.EMPTY') }}
        </p>
        <Button
          :label="t('JABVOX_DATA_EXPORT.NEW')"
          icon="i-lucide-plus"
          @click="openNew"
        />
      </section>

      <!-- Connected -->
      <section
        v-else
        class="rounded-2xl bg-n-solid-1 border border-n-weak p-6 flex flex-col gap-4"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <p class="text-base font-semibold text-n-slate-12">
              {{ target.name_jabvox }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ target.engine_jabvox }} · {{ target.host_jabvox }} ·
              {{ target.database_jabvox }}
            </p>
          </div>
          <label class="flex items-center gap-2 shrink-0">
            <span class="text-sm text-n-slate-11">
              {{ t('JABVOX_DATA_EXPORT.ENABLED') }}
            </span>
            <Switch
              :model-value="target.enabled_jabvox"
              @update:model-value="toggleEnabled"
            />
          </label>
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
          <div>
            <p class="text-n-slate-10 text-xs">
              {{ t('JABVOX_DATA_EXPORT.STATUS') }}
            </p>
            <p class="text-n-slate-12">{{ target.status_jabvox }}</p>
          </div>
          <div>
            <p class="text-n-slate-10 text-xs">
              {{ t('JABVOX_DATA_EXPORT.SCHEMA') }}
            </p>
            <p class="text-n-slate-12">
              {{
                target.schema_built_at_jabvox
                  ? t('JABVOX_DATA_EXPORT.SCHEMA_READY')
                  : t('JABVOX_DATA_EXPORT.SCHEMA_PENDING')
              }}
            </p>
          </div>
          <div>
            <p class="text-n-slate-10 text-xs">
              {{ t('JABVOX_DATA_EXPORT.LAST_EXPORT') }}
            </p>
            <p class="text-n-slate-12">
              {{ target.last_export_at_jabvox || '—' }}
            </p>
          </div>
          <div v-if="target.last_error_jabvox">
            <p class="text-n-slate-10 text-xs">
              {{ t('JABVOX_DATA_EXPORT.LAST_ERROR') }}
            </p>
            <p class="text-n-ruby-11">{{ target.last_error_jabvox }}</p>
          </div>
        </div>

        <div
          class="flex flex-wrap items-center gap-2 pt-2 border-t border-n-weak"
        >
          <Button
            :label="t('JABVOX_DATA_EXPORT.FORM.TEST')"
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-plug-zap"
            :is-loading="testing"
            @click="testSaved"
          />
          <Button
            :label="t('JABVOX_DATA_EXPORT.BUILD_SCHEMA')"
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-table"
            :is-loading="building"
            @click="buildSchema"
          />
          <Button
            :label="t('JABVOX_DATA_EXPORT.FORM.EDIT')"
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-pencil"
            @click="openEdit"
          />
          <Button
            class="ml-auto"
            :label="t('JABVOX_DATA_EXPORT.DELETE')"
            variant="ghost"
            color="ruby"
            size="sm"
            icon="i-lucide-trash-2"
            @click="remove"
          />
        </div>

        <p class="text-xs text-n-slate-10">
          {{ t('JABVOX_DATA_EXPORT.DELETE_HINT') }}
        </p>
      </section>
    </div>

    <ConfirmDialog ref="confirmDialog" @confirm="doRemove" />
  </div>
</template>
