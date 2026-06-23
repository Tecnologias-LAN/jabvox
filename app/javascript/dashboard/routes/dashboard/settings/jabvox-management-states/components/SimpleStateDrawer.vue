<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SideDrawer from './SideDrawer.vue';

// Reusable drawer for App states (name + color + active) and Campaigns
// (name only). `fields` controls which controls render.
const props = defineProps({
  isSaving: { type: Boolean, default: false },
  withColor: { type: Boolean, default: true },
  withActive: { type: Boolean, default: true },
  nameField: { type: String, default: 'name' },
  colorField: { type: String, default: 'color' },
  activeField: { type: String, default: 'is_active' },
  newLabel: { type: String, default: '' },
  editLabel: { type: String, default: '' },
});

const emit = defineEmits(['submit']);
const { t } = useI18n();

const open = ref(false);
const editingId = ref(null);
const form = ref({});

const title = computed(() =>
  editingId.value ? props.editLabel : props.newLabel
);
const name = computed({
  get: () => form.value[props.nameField] ?? '',
  set: v => {
    form.value[props.nameField] = v;
  },
});
const color = computed({
  get: () => form.value[props.colorField] ?? '#64748b',
  set: v => {
    form.value[props.colorField] = v;
  },
});
const active = computed({
  get: () => form.value[props.activeField] ?? true,
  set: v => {
    form.value[props.activeField] = v;
  },
});
const isValid = computed(() => String(name.value).trim().length > 0);

const buildEmpty = () => {
  const f = { [props.nameField]: '' };
  if (props.withColor) f[props.colorField] = '#64748b';
  if (props.withActive) f[props.activeField] = true;
  return f;
};

const openNew = () => {
  editingId.value = null;
  form.value = buildEmpty();
  open.value = true;
};

const openEdit = item => {
  editingId.value = item.id;
  const f = { [props.nameField]: item[props.nameField] ?? '' };
  if (props.withColor)
    f[props.colorField] = item[props.colorField] || '#64748b';
  if (props.withActive) f[props.activeField] = item[props.activeField] ?? true;
  form.value = f;
  open.value = true;
};

const close = () => {
  open.value = false;
};

const handleSubmit = () => {
  if (!isValid.value) return;
  emit('submit', { id: editingId.value, form: { ...form.value } });
};

defineExpose({ openNew, openEdit, close });
</script>

<template>
  <SideDrawer v-model:open="open" :title="title">
    <div class="flex flex-col gap-8">
      <!-- Live preview (color tabs only) -->
      <div
        v-if="withColor"
        class="flex items-center justify-between gap-3 rounded-2xl border border-n-weak bg-n-alpha-1 px-4 py-4"
      >
        <span class="text-xs font-medium text-n-slate-10">
          {{ t('JABVOX_MANAGEMENT_STATES.DRAWER.PREVIEW_TITLE') }}
        </span>
        <span
          class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-sm font-medium"
          :style="{ backgroundColor: `${color}1a`, color }"
        >
          <span
            class="size-2 rounded-full"
            :style="{ backgroundColor: color }"
          />
          {{ name || t('JABVOX_MANAGEMENT_STATES.FORM.NAME') }}
        </span>
      </div>

      <section class="flex flex-col gap-4">
        <Input
          v-model="name"
          :label="t('JABVOX_MANAGEMENT_STATES.FORM.NAME')"
          :placeholder="t('JABVOX_MANAGEMENT_STATES.FORM.NAME_PLACEHOLDER')"
          autofocus
        />

        <div v-if="withColor" class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_MANAGEMENT_STATES.FORM.COLOR') }}
          </label>
          <div class="flex items-center gap-2">
            <input
              v-model="color"
              type="color"
              class="w-10 h-9 rounded-lg cursor-pointer border border-n-weak p-0.5 bg-n-solid-1 shrink-0"
              :aria-label="t('JABVOX_MANAGEMENT_STATES.FORM.COLOR')"
            />
            <div class="flex-1">
              <Input v-model="color" size="sm" custom-input-class="font-mono" />
            </div>
          </div>
        </div>

        <div
          v-if="withActive"
          class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
        >
          <div class="flex flex-col">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_MANAGEMENT_STATES.FORM.ACTIVE') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('JABVOX_MANAGEMENT_STATES.DRAWER.ACTIVE_HINT') }}
            </span>
          </div>
          <Switch v-model="active" />
        </div>
      </section>
    </div>

    <template #footer>
      <div class="flex items-center justify-end gap-2">
        <Button
          :label="t('JABVOX_MANAGEMENT_STATES.COMMON.CANCEL')"
          variant="outline"
          color="slate"
          @click="close"
        />
        <Button
          :label="t('JABVOX_MANAGEMENT_STATES.SAVE')"
          :is-loading="isSaving"
          :disabled="!isValid"
          @click="handleSubmit"
        />
      </div>
    </template>
  </SideDrawer>
</template>
