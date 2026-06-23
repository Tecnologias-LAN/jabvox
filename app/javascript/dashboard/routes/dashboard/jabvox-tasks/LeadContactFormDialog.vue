<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  contact: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();

const name = ref('');
const role = ref('');
const email = ref('');
const phone = ref('');
const description = ref('');

const isEdit = computed(() => Boolean(props.contact));

watch(
  () => props.contact,
  value => {
    name.value = value?.nameJabvox || '';
    role.value = value?.roleJabvox || '';
    email.value = value?.emailJabvox || '';
    phone.value = value?.phoneJabvox || '';
    description.value = value?.descriptionJabvox || '';
  },
  { immediate: true }
);

const onSubmit = () => {
  if (!name.value.trim()) return;
  emit('submit', {
    name_jabvox: name.value.trim(),
    role_jabvox: role.value,
    email_jabvox: email.value,
    phone_jabvox: phone.value,
    description_jabvox: description.value,
  });
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-3"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-md rounded-xl bg-n-solid-1 border border-n-weak shadow-lg max-h-[90vh] flex flex-col"
    >
      <div class="px-5 py-4 border-b border-n-weak shrink-0">
        <h2 class="text-base font-semibold text-n-slate-12">
          {{
            isEdit
              ? t('JABVOX_TASKS.CONTACTS.FORM.EDIT_TITLE')
              : t('JABVOX_TASKS.CONTACTS.FORM.CREATE_TITLE')
          }}
        </h2>
      </div>

      <form
        class="px-5 py-4 space-y-4 overflow-y-auto"
        @submit.prevent="onSubmit"
      >
        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.CONTACTS.FORM.NAME') }}
          </label>
          <input
            v-model="name"
            type="text"
            :placeholder="t('JABVOX_TASKS.CONTACTS.FORM.NAME_PLACEHOLDER')"
            class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
          />
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.CONTACTS.FORM.ROLE') }}
          </label>
          <input
            v-model="role"
            type="text"
            :placeholder="t('JABVOX_TASKS.CONTACTS.FORM.ROLE_PLACEHOLDER')"
            class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
          />
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.CONTACTS.FORM.EMAIL') }}
          </label>
          <input
            v-model="email"
            type="email"
            :placeholder="t('JABVOX_TASKS.CONTACTS.FORM.EMAIL_PLACEHOLDER')"
            class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
          />
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.CONTACTS.FORM.PHONE') }}
          </label>
          <input
            v-model="phone"
            type="tel"
            :placeholder="t('JABVOX_TASKS.CONTACTS.FORM.PHONE_PLACEHOLDER')"
            class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
          />
        </div>

        <div class="space-y-1">
          <label class="block text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_TASKS.CONTACTS.FORM.DESCRIPTION') }}
          </label>
          <textarea
            v-model="description"
            rows="3"
            :placeholder="
              t('JABVOX_TASKS.CONTACTS.FORM.DESCRIPTION_PLACEHOLDER')
            "
            class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
          />
        </div>

        <div class="flex items-center justify-end gap-2 pt-2">
          <button
            type="button"
            class="px-3 py-2 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
            @click="emit('close')"
          >
            {{ t('JABVOX_TASKS.CONTACTS.FORM.CANCEL') }}
          </button>
          <button
            type="submit"
            class="px-3 py-2 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
            :disabled="!name.trim()"
          >
            {{ t('JABVOX_TASKS.CONTACTS.FORM.SAVE') }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
