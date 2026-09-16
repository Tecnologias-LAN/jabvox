<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { getComponentMeta } from '../componentCatalog';
import VariablePicker from './VariablePicker.vue';

const props = defineProps({
  component: { type: Object, required: true },
  screens: { type: Array, default: () => [] },
  currentScreenId: { type: String, default: '' },
  isFirstScreen: { type: Boolean, default: false },
  otherScreens: { type: Array, default: () => [] }, // para el selector "next" de acciones
  fieldErrors: { type: Array, default: () => [] }, // [{ field, message }]
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const meta = computed(() => getComponentMeta(props.component.type));

const updateProp = (key, value) => {
  emit('update', { [key]: value });
};

const updateActionField = (key, value) => {
  emit('update', {
    action: { ...(props.component.props.action || {}), [key]: value },
  });
};

const addOption = () => {
  const options = props.component.props.data_source || [];
  updateProp('data_source', [...options, { id: '', title: '' }]);
};

const updateOption = (index, key, value) => {
  const options = [...(props.component.props.data_source || [])];
  options[index] = { ...options[index], [key]: value };
  updateProp('data_source', options);
};

const removeOption = index => {
  const options = [...(props.component.props.data_source || [])];
  options.splice(index, 1);
  updateProp('data_source', options);
};

const insertVariable = (field, reference) => {
  const current = props.component.props[field] || '';
  updateProp(field, `${current}${reference}`);
};

const onImageFile = (field, event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => updateProp(field, reader.result);
  reader.readAsDataURL(file);
};

const errorFor = field =>
  props.fieldErrors.find(e => e.field === field)?.message;
</script>

<template>
  <div v-if="meta" class="flex flex-col gap-3 p-3">
    <div class="flex items-center gap-2">
      <span
        :class="meta.icon"
        class="size-4 text-n-brand shrink-0"
        aria-hidden="true"
      />
      <h4 class="text-sm font-semibold text-n-slate-12">{{ meta.label }}</h4>
    </div>

    <div
      v-for="field in meta.fields"
      :key="field.key"
      class="flex flex-col gap-1"
    >
      <label
        class="text-[11px] font-medium text-n-slate-11 flex items-center gap-1.5"
      >
        {{ field.label }}
        <span v-if="field.required" class="text-n-ruby-11">*</span>
        <VariablePicker
          v-if="field.variableAllowed"
          :screens="screens"
          :current-screen-id="currentScreenId"
          :is-first-screen="isFirstScreen"
          @pick="ref => insertVariable(field.key, ref)"
        />
      </label>

      <!-- text -->
      <input
        v-if="field.kind === 'text'"
        class="reset-base wf-field text-sm"
        :maxlength="field.maxLength || undefined"
        :value="component.props[field.key]"
        @input="updateProp(field.key, $event.target.value)"
      />

      <!-- textarea -->
      <textarea
        v-else-if="field.kind === 'textarea'"
        rows="3"
        class="reset-base wf-field text-sm resize-y"
        :maxlength="field.maxLength || undefined"
        :value="component.props[field.key]"
        @input="updateProp(field.key, $event.target.value)"
      />

      <!-- boolean -->
      <label
        v-else-if="field.kind === 'boolean'"
        class="inline-flex items-center gap-2 text-sm text-n-slate-12"
      >
        <input
          type="checkbox"
          class="size-4 accent-n-brand"
          :checked="component.props[field.key]"
          @change="updateProp(field.key, $event.target.checked)"
        />
        {{ t('JABVOX_WA_FLOWS.BUILDER.PROPS.YES') }}
      </label>

      <!-- select -->
      <select
        v-else-if="field.kind === 'select'"
        class="reset-base wf-field text-sm"
        :value="component.props[field.key]"
        @change="updateProp(field.key, $event.target.value)"
      >
        <option v-for="opt in field.options" :key="opt" :value="opt">
          {{ opt }}
        </option>
      </select>

      <!-- image -->
      <div v-else-if="field.kind === 'image'" class="flex flex-col gap-1.5">
        <input
          type="file"
          accept="image/*"
          class="text-xs"
          @change="onImageFile(field.key, $event)"
        />
        <img
          v-if="component.props[field.key]"
          :src="component.props[field.key]"
          alt=""
          class="max-h-24 rounded-lg border border-n-weak object-contain"
        />
      </div>

      <!-- action (Footer / EmbeddedLink) -->
      <div
        v-else-if="field.kind === 'action'"
        class="flex flex-col gap-1.5 rounded-lg border border-n-weak p-2"
      >
        <select
          class="reset-base wf-field text-sm"
          :value="component.props.action?.name || 'navigate'"
          @change="updateActionField('name', $event.target.value)"
        >
          <option value="navigate">
            {{ t('JABVOX_WA_FLOWS.BUILDER.PROPS.ACTION_NAVIGATE') }}
          </option>
          <option value="complete">
            {{ t('JABVOX_WA_FLOWS.BUILDER.PROPS.ACTION_COMPLETE') }}
          </option>
          <option value="open_url">
            {{ t('JABVOX_WA_FLOWS.BUILDER.PROPS.ACTION_OPEN_URL') }}
          </option>
        </select>

        <select
          v-if="component.props.action?.name === 'navigate'"
          class="reset-base wf-field text-sm"
          :value="component.props.action?.next || ''"
          @change="updateActionField('next', $event.target.value)"
        >
          <option value="">
            {{ t('JABVOX_WA_FLOWS.BUILDER.PROPS.SELECT_SCREEN') }}
          </option>
          <option v-for="s in otherScreens" :key="s.id" :value="s.id">
            {{ s.title }}
          </option>
        </select>

        <input
          v-else-if="component.props.action?.name === 'open_url'"
          class="reset-base wf-field text-sm"
          :placeholder="
            t('JABVOX_WA_FLOWS.BUILDER.SCREEN_EDITOR.URL_PLACEHOLDER')
          "
          :value="component.props.action?.url || ''"
          @input="updateActionField('url', $event.target.value)"
        />
      </div>

      <!-- options (data_source) -->
      <div v-else-if="field.kind === 'options'" class="flex flex-col gap-1.5">
        <div
          v-for="(opt, index) in component.props.data_source || []"
          :key="index"
          class="flex items-center gap-1.5"
        >
          <input
            class="reset-base wf-field text-sm flex-1"
            :placeholder="t('JABVOX_WA_FLOWS.BUILDER.PROPS.OPTION_ID')"
            :value="opt.id"
            @input="updateOption(index, 'id', $event.target.value)"
          />
          <input
            class="reset-base wf-field text-sm flex-1"
            :placeholder="t('JABVOX_WA_FLOWS.BUILDER.PROPS.OPTION_TITLE')"
            :value="opt.title"
            @input="updateOption(index, 'title', $event.target.value)"
          />
          <button
            class="wf-icon-btn-xs hover:!text-n-ruby-11"
            @click="removeOption(index)"
          >
            <span class="i-lucide-x size-3" aria-hidden="true" />
          </button>
        </div>
        <button
          type="button"
          class="self-start text-xs text-n-brand hover:underline"
          :disabled="
            (component.props.data_source || []).length >= (field.max || 200)
          "
          @click="addOption"
        >
          + {{ t('JABVOX_WA_FLOWS.BUILDER.PROPS.ADD_OPTION') }}
        </button>
      </div>

      <p v-if="errorFor(field.key)" class="text-[11px] text-n-ruby-11">
        {{ errorFor(field.key) }}
      </p>
      <p v-else-if="field.hint" class="text-[11px] text-n-slate-9">
        {{ field.hint }}
      </p>
    </div>
  </div>
</template>
