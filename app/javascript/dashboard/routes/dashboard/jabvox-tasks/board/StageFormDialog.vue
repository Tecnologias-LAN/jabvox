<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  stage: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();

const name = ref('');
const color = ref('#3b82f6');
// Papel de la columna en el flujo. Vacío = columna intermedia normal. Solo puede haber
// una de cada por tablero, y el backend lo rechaza si se duplica.
const STAGE_ROLES = ['initial', 'done', 'inactive'];
const role = ref('');

const isEdit = computed(() => Boolean(props.stage));

watch(
  () => props.stage,
  value => {
    name.value = value?.nameJabvox || '';
    color.value = value?.colorJabvox || '#3b82f6';
    role.value = value?.roleJabvox || '';
  },
  { immediate: true }
);

const onSubmit = () => {
  if (!name.value.trim()) return;
  emit('submit', {
    name_jabvox: name.value.trim(),
    color_jabvox: color.value,
    role_jabvox: role.value || null,
  });
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-3"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-md rounded-xl bg-n-solid-1 border border-n-weak shadow-lg"
    >
      <div class="px-5 py-4 border-b border-n-weak">
        <h2 class="text-base font-semibold text-n-slate-12">
          {{
            isEdit
              ? t('JABVOX_TASKS.STAGE.FORM.EDIT_TITLE')
              : t('JABVOX_TASKS.STAGE.FORM.CREATE_TITLE')
          }}
        </h2>
      </div>

      <form class="px-5 py-4 space-y-4" @submit.prevent="onSubmit">
        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.STAGE.FORM.NAME') }}
          </label>
          <input
            v-model="name"
            type="text"
            :placeholder="t('JABVOX_TASKS.STAGE.FORM.NAME_PLACEHOLDER')"
            class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
          />
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.STAGE.FORM.COLOR') }}
          </label>
          <input
            v-model="color"
            type="color"
            class="h-9 w-16 rounded-lg bg-n-alpha-1 border border-n-weak"
          />
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.STAGE_ROLE.LABEL') }}
          </label>
          <select
            v-model="role"
            class="w-full h-9 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2"
          >
            <option value="">
              {{ t('JABVOX_TASKS.STAGE_ROLE.NONE') }}
            </option>
            <option v-for="r in STAGE_ROLES" :key="r" :value="r">
              {{ t(`JABVOX_TASKS.STAGE_ROLE.${r}`) }}
            </option>
          </select>
          <p class="text-[11px] text-n-slate-10">
            {{ t('JABVOX_TASKS.STAGE_ROLE.HELP') }}
          </p>
        </div>

        <div class="flex items-center justify-end gap-2 pt-2">
          <button
            type="button"
            class="px-3 py-2 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
            @click="emit('close')"
          >
            {{ t('JABVOX_TASKS.STAGE.FORM.CANCEL') }}
          </button>
          <button
            type="submit"
            class="px-3 py-2 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
            :disabled="!name.trim()"
          >
            {{ t('JABVOX_TASKS.STAGE.FORM.SAVE') }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
