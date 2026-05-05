<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  provider: { type: Object, default: null },
});
const emit = defineEmits(['save', 'cancel']);

const uiFlags = useMapGetter('jabvoxSms/getUIFlags');

const isEdit = computed(() => !!props.provider);

const form = ref({
  name: '',
  base_url: '',
  api_user: '',
  api_password: '',
  active: true,
});

onMounted(() => {
  if (props.provider) {
    form.value = {
      name: props.provider.name || '',
      base_url: props.provider.base_url || '',
      api_user: props.provider.api_user || '',
      api_password: '',
      active: props.provider.active ?? true,
    };
  }
});

const onSave = () => emit('save', { ...form.value });
</script>

<template>
  <div class="space-y-5">
    <h3 class="text-base font-semibold text-slate-800 dark:text-slate-100">
      {{
        isEdit
          ? $t('JABVOX_SMS.PROVIDERS.EDIT_TITLE')
          : $t('JABVOX_SMS.PROVIDERS.NEW_TITLE')
      }}
    </h3>

    <div class="space-y-4">
      <div class="space-y-1">
        <label
          class="block text-xs font-medium text-slate-600 dark:text-slate-300"
        >
          {{ $t('JABVOX_SMS.PROVIDERS.FORM.NAME') }}
        </label>
        <input
          v-model="form.name"
          type="text"
          :placeholder="$t('JABVOX_SMS.PROVIDERS.FORM.NAME_PLACEHOLDER')"
          class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
        />
      </div>

      <div class="space-y-1">
        <label
          class="block text-xs font-medium text-slate-600 dark:text-slate-300"
        >
          {{ $t('JABVOX_SMS.PROVIDERS.FORM.BASE_URL') }}
        </label>
        <input
          v-model="form.base_url"
          type="text"
          :placeholder="$t('JABVOX_SMS.PROVIDERS.FORM.BASE_URL_PLACEHOLDER')"
          class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
        />
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div class="space-y-1">
          <label
            class="block text-xs font-medium text-slate-600 dark:text-slate-300"
          >
            {{ $t('JABVOX_SMS.PROVIDERS.FORM.API_USER') }}
          </label>
          <input
            v-model="form.api_user"
            type="text"
            :placeholder="$t('JABVOX_SMS.PROVIDERS.FORM.API_USER_PLACEHOLDER')"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
        <div class="space-y-1">
          <label
            class="block text-xs font-medium text-slate-600 dark:text-slate-300"
          >
            {{ $t('JABVOX_SMS.PROVIDERS.FORM.API_PASSWORD') }}
            <template v-if="isEdit">
              <span class="font-normal text-slate-400"
                >({{ $t('JABVOX_SMS.PROVIDERS.FORM.PASSWORD_HINT') }})</span
              >
            </template>
          </label>
          <input
            v-model="form.api_password"
            type="password"
            :placeholder="
              $t('JABVOX_SMS.PROVIDERS.FORM.API_PASSWORD_PLACEHOLDER')
            "
            class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
      </div>

      <label class="flex items-center gap-3 cursor-pointer">
        <input
          v-model="form.active"
          type="checkbox"
          class="rounded border-slate-300 text-woot-600 focus:ring-woot-500"
        />
        <span class="text-sm text-slate-700 dark:text-slate-200">{{
          $t('JABVOX_SMS.PROVIDERS.FORM.ACTIVE')
        }}</span>
      </label>
    </div>

    <div class="flex justify-end gap-3 pt-2">
      <Button
        variant="clear"
        :label="$t('JABVOX_SMS.CANCEL')"
        @click="emit('cancel')"
      />
      <Button
        :label="
          uiFlags.isSaving
            ? $t('JABVOX_PRODUCTS.LOADING')
            : $t('JABVOX_SMS.SAVE')
        "
        :disabled="
          uiFlags.isSaving || !form.name || !form.base_url || !form.api_user
        "
        @click="onSave"
      />
    </div>
  </div>
</template>
