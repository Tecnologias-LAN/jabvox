<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: {
    type: Object,
    required: true,
  },
  isEdit: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const ENGINES = ['postgresql', 'mysql', 'mariadb', 'sqlite', 'sqlserver'];
// Friendly labels for the engine dropdown (value stays the technical key).
const ENGINE_LABELS = {
  postgresql: 'PostgreSQL',
  mysql: 'MySQL',
  mariadb: 'MariaDB',
  sqlite: 'SQLite',
  sqlserver: 'SQL Server',
};
const engineLabel = e => ENGINE_LABELS[e] || e;

const update = (key, value) => {
  emit('update:modelValue', { ...props.modelValue, [key]: value });
};

const isSqlite = computed(() => props.modelValue.engineJabvox === 'sqlite');

// Only the name is truly required to save a draft data source — the user can
// save with or without a working connection. We validate minimally on submit
// and show field errors only after a failed attempt (touched).
const touched = ref(false);

const hasError = field => {
  if (!touched.value) return false;
  const v = props.modelValue[field];
  return !v || String(v).trim() === '';
};

// Minimum to persist: a name. (Connection fields are optional — save anytime.)
const validate = () => {
  touched.value = true;
  return Boolean(props.modelValue.nameJabvox?.trim());
};

const errorFor = field =>
  hasError(field) ? t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.REQUIRED') : '';

const labelClass = 'mb-1 block text-sm font-medium text-n-slate-12';
const inputClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';

defineExpose({ validate });
</script>

<template>
  <div class="flex flex-col gap-4">
    <!-- Name -->
    <div>
      <label class="mb-1 block text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.NAME') }}
      </label>
      <input
        :value="modelValue.nameJabvox"
        type="text"
        :class="inputClass"
        :placeholder="t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.NAME_PLACEHOLDER')"
        @input="update('nameJabvox', $event.target.value)"
      />
      <p v-if="errorFor('nameJabvox')" class="mt-1 text-xs text-n-ruby-11">
        {{ errorFor('nameJabvox') }}
      </p>
    </div>

    <!-- Engine -->
    <div>
      <label :class="labelClass">
        {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.ENGINE') }}
      </label>
      <select
        :value="modelValue.engineJabvox"
        :class="inputClass"
        @change="update('engineJabvox', $event.target.value)"
      >
        <option v-for="engine in ENGINES" :key="engine" :value="engine">
          {{ engineLabel(engine) }}
        </option>
      </select>
    </div>

    <!-- SQLite path -->
    <div v-if="isSqlite">
      <label :class="labelClass">
        {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.SQLITE_PATH') }}
      </label>
      <input
        :value="modelValue.sqlitePathJabvox"
        type="text"
        :class="inputClass"
        @input="update('sqlitePathJabvox', $event.target.value)"
      />
    </div>

    <!-- Connection fields -->
    <template v-else>
      <div class="grid grid-cols-3 gap-3">
        <div class="col-span-2">
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.HOST') }}
          </label>
          <input
            :value="modelValue.hostJabvox"
            type="text"
            :class="inputClass"
            @input="update('hostJabvox', $event.target.value)"
          />
        </div>
        <div>
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.PORT') }}
          </label>
          <input
            :value="modelValue.portJabvox"
            type="number"
            :class="inputClass"
            @input="update('portJabvox', $event.target.value)"
          />
        </div>
      </div>

      <div>
        <label :class="labelClass">
          {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.DATABASE') }}
        </label>
        <input
          :value="modelValue.databaseJabvox"
          type="text"
          :class="inputClass"
          @input="update('databaseJabvox', $event.target.value)"
        />
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.USERNAME') }}
          </label>
          <input
            :value="modelValue.usernameJabvox"
            type="text"
            :class="inputClass"
            @input="update('usernameJabvox', $event.target.value)"
          />
        </div>
        <div>
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.PASSWORD') }}
          </label>
          <input
            :value="modelValue.passwordJabvox"
            type="password"
            autocomplete="new-password"
            :class="inputClass"
            @input="update('passwordJabvox', $event.target.value)"
          />
          <p v-if="isEdit" class="mt-1 text-xs text-n-slate-10">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.PASSWORD_KEEP') }}
          </p>
        </div>
      </div>
    </template>

    <!-- Advanced -->
    <div class="flex flex-col gap-4 border-t border-n-weak pt-4">
      <label class="flex items-start gap-2">
        <input
          type="checkbox"
          class="mt-0.5 size-4 rounded border-n-weak"
          :checked="modelValue.allowPrivateNetworkJabvox"
          @change="update('allowPrivateNetworkJabvox', $event.target.checked)"
        />
        <span>
          <span class="block text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.ALLOW_PRIVATE') }}
          </span>
          <span class="block text-xs text-n-slate-10">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.ALLOW_PRIVATE_HELP') }}
          </span>
        </span>
      </label>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.MAX_ROWS') }}
          </label>
          <input
            :value="modelValue.maxRowsJabvox"
            type="number"
            :class="inputClass"
            @input="update('maxRowsJabvox', $event.target.value)"
          />
        </div>
        <div>
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.TIMEOUT') }}
          </label>
          <input
            :value="modelValue.queryTimeoutMsJabvox"
            type="number"
            :class="inputClass"
            @input="update('queryTimeoutMsJabvox', $event.target.value)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
