<script setup>
import { ref, reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import affiliatePortalAPI from '../../api/jabvox/affiliatePortal';
import countries from 'shared/constants/countries.js';

const { t } = useI18n();

const isLoading = ref(false);
const successMsg = ref('');
const errorMsg = ref('');

const form = reactive({
  name: '',
  email: '',
  phone_number: '',
  country: '',
});

const resetForm = () => {
  form.name = '';
  form.email = '';
  form.phone_number = '';
  form.country = '';
};

// Prefijo del país elegido. Se muestra al lado del campo de teléfono para
// dejar claro que el número se sube SIN prefijo: lo pone el país.
const dialCode = computed(
  () => countries.find(c => c.id === form.country)?.dial_code ?? ''
);

const onSubmit = async () => {
  errorMsg.value = '';
  successMsg.value = '';
  if (!form.name.trim()) {
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.MANUAL_ERROR_NAME');
    return;
  }
  if (!form.country) {
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.MANUAL_ERROR_COUNTRY');
    return;
  }
  if (!form.phone_number.trim() && !form.email.trim()) {
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.MANUAL_ERROR_IDENTITY');
    return;
  }
  isLoading.value = true;
  try {
    await affiliatePortalAPI.createContact({
      name: form.name.trim(),
      email: form.email.trim() || undefined,
      phone_number: form.phone_number.trim() || undefined,
      country: form.country,
    });
    successMsg.value = t('JABVOX_AFFILIATE_PORTAL.MANUAL_SUCCESS');
    resetForm();
  } catch (err) {
    const code = err.response?.data?.error;
    const known = {
      duplicate_lead: 'MANUAL_ERROR_DUPLICATE',
      country_required: 'MANUAL_ERROR_COUNTRY',
      identity_required: 'MANUAL_ERROR_IDENTITY',
      phone_invalid: 'MANUAL_ERROR_PHONE',
    }[code];
    errorMsg.value = t(
      `JABVOX_AFFILIATE_PORTAL.${known ?? 'MANUAL_ERROR_DEFAULT'}`
    );
  } finally {
    isLoading.value = false;
  }
};
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="p-6 sm:p-8 max-w-xl">
    <h2 class="text-lg font-semibold text-n-slate-12 mb-1">
      {{ t('JABVOX_AFFILIATE_PORTAL.MANUAL_TITLE') }}
    </h2>
    <p class="text-sm text-n-slate-11 mb-6">
      {{ t('JABVOX_AFFILIATE_PORTAL.MANUAL_SUBTITLE') }}
    </p>

    <form class="space-y-4" @submit.prevent="onSubmit">
      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1.5">
          {{ t('JABVOX_AFFILIATE_PORTAL.MANUAL_NAME_LABEL') }}
          <span class="text-n-ruby-9">*</span>
        </label>
        <input
          v-model="form.name"
          type="text"
          :placeholder="t('JABVOX_AFFILIATE_PORTAL.MANUAL_NAME_PLACEHOLDER')"
          class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        />
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1.5">
          {{ t('JABVOX_AFFILIATE_PORTAL.MANUAL_EMAIL_LABEL') }}
        </label>
        <input
          v-model="form.email"
          type="email"
          placeholder="correo@ejemplo.com"
          class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        />
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1.5">
          {{ t('JABVOX_AFFILIATE_PORTAL.MANUAL_PHONE_LABEL') }}
        </label>
        <div class="flex items-center gap-2">
          <span
            class="h-9 px-3 flex items-center rounded-lg border border-n-weak bg-n-surface-2 text-sm text-n-slate-11 shrink-0"
          >
            {{ dialCode || '—' }}
          </span>
          <input
            v-model="form.phone_number"
            type="tel"
            :placeholder="t('JABVOX_AFFILIATE_PORTAL.MANUAL_PHONE_PLACEHOLDER')"
            class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>
        <p class="mt-1 text-xs text-n-slate-10">
          {{ t('JABVOX_AFFILIATE_PORTAL.MANUAL_PHONE_HINT') }}
        </p>
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1.5">
          {{ t('JABVOX_AFFILIATE_PORTAL.MANUAL_COUNTRY_LABEL') }}
        </label>
        <select
          v-model="form.country"
          class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        >
          <option value="" disabled>
            {{ t('JABVOX_AFFILIATE_PORTAL.MANUAL_COUNTRY_PLACEHOLDER') }}
          </option>
          <option v-for="c in countries" :key="c.id" :value="c.id">
            {{ c.emoji }} {{ c.name }} ({{ c.dial_code }})
          </option>
        </select>
      </div>

      <p
        v-if="successMsg"
        class="text-sm text-n-teal-11 rounded-lg bg-n-teal-3 px-3 py-2"
      >
        {{ successMsg }}
      </p>
      <p
        v-if="errorMsg"
        class="text-sm text-n-ruby-9 rounded-lg bg-n-ruby-3 px-3 py-2"
      >
        {{ errorMsg }}
      </p>

      <button
        type="submit"
        :disabled="isLoading"
        class="h-10 px-6 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
      >
        {{
          isLoading
            ? t('JABVOX_AFFILIATE_PORTAL.MANUAL_CREATING')
            : t('JABVOX_AFFILIATE_PORTAL.MANUAL_SUBMIT')
        }}
      </button>
    </form>
  </div>
</template>
