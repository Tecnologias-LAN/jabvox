<script setup>
import { ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const config = useMapGetter('jabvoxProducts/getIntegrationConfig');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const form = ref({
  company_name_jabvox: '',
  company_nit_jabvox: '',
  company_address_jabvox: '',
  company_phone_jabvox: '',
  company_email_jabvox: '',
  company_website_jabvox: '',
  company_logo_jabvox: '',
});

onMounted(async () => {
  await store.dispatch('jabvoxProducts/fetchIntegrationConfig');
});

watch(
  config,
  val => {
    if (val) {
      form.value.company_name_jabvox = val.company_name_jabvox || '';
      form.value.company_nit_jabvox = val.company_nit_jabvox || '';
      form.value.company_address_jabvox = val.company_address_jabvox || '';
      form.value.company_phone_jabvox = val.company_phone_jabvox || '';
      form.value.company_email_jabvox = val.company_email_jabvox || '';
      form.value.company_website_jabvox = val.company_website_jabvox || '';
      form.value.company_logo_jabvox = val.company_logo_jabvox || '';
    }
  },
  { immediate: true }
);

const onLogoChange = e => {
  const file = e.target.files[0];
  if (!file) return;
  if (file.size > 2 * 1024 * 1024) {
    useAlert(t('JABVOX_PRODUCTS.PDF.LOGO_TOO_LARGE'));
    return;
  }
  const reader = new FileReader();
  reader.onload = ev => {
    form.value.company_logo_jabvox = ev.target.result;
  };
  reader.readAsDataURL(file);
};

const onSave = async () => {
  try {
    await store.dispatch('jabvoxProducts/saveIntegrationConfig', form.value);
    useAlert(t('JABVOX_PRODUCTS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};
</script>

<template>
  <div class="flex gap-8 flex-wrap">
    <div class="flex-1 min-w-[320px] max-w-lg space-y-5">
      <div>
        <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          {{ $t('JABVOX_PRODUCTS.PDF.TITLE') }}
        </h2>
        <p class="text-sm text-slate-500 mt-1">
          {{ $t('JABVOX_PRODUCTS.PDF.DESCRIPTION') }}
        </p>
      </div>

      <div
        v-if="uiFlags.isFetchingConfig"
        class="text-sm text-slate-400 animate-pulse py-6"
      >
        {{ $t('JABVOX_PRODUCTS.LOADING') }}
      </div>

      <div v-else class="space-y-4">
        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >{{ $t('JABVOX_PRODUCTS.PDF.LOGO') }}</label
          >
          <div class="flex items-center gap-3">
            <div
              class="w-16 h-16 rounded-lg border border-slate-200 dark:border-slate-700 flex items-center justify-center overflow-hidden bg-slate-50 dark:bg-slate-800"
            >
              <img
                v-if="form.company_logo_jabvox"
                :src="form.company_logo_jabvox"
                class="w-full h-full object-contain"
                alt="Logo"
              />
              <i v-else class="i-lucide-image text-2xl text-slate-300" />
            </div>
            <div>
              <label
                class="cursor-pointer text-sm text-woot-600 hover:underline"
              >
                {{ $t('JABVOX_PRODUCTS.PDF.CHANGE_LOGO') }}
                <input
                  type="file"
                  accept="image/png,image/jpeg,image/svg+xml"
                  class="hidden"
                  @change="onLogoChange"
                />
              </label>
              <p class="text-xs text-slate-400 mt-0.5">
                {{ $t('JABVOX_PRODUCTS.PDF.LOGO_FORMATS') }}
              </p>
            </div>
          </div>
        </div>

        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >{{ $t('JABVOX_PRODUCTS.PDF.COMPANY_NAME') }}</label
          >
          <input
            v-model="form.company_name_jabvox"
            type="text"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>

        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >{{ $t('JABVOX_PRODUCTS.PDF.NIT') }}</label
          >
          <input
            v-model="form.company_nit_jabvox"
            type="text"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>

        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >{{ $t('JABVOX_PRODUCTS.PDF.ADDRESS') }}</label
          >
          <input
            v-model="form.company_address_jabvox"
            type="text"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>

        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >{{ $t('JABVOX_PRODUCTS.PDF.PHONE') }}</label
          >
          <input
            v-model="form.company_phone_jabvox"
            type="text"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>

        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >{{ $t('JABVOX_PRODUCTS.PDF.WEBSITE') }}</label
          >
          <input
            v-model="form.company_website_jabvox"
            type="url"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>

        <div>
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >{{ $t('JABVOX_PRODUCTS.PDF.EMAIL') }}</label
          >
          <input
            v-model="form.company_email_jabvox"
            type="email"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>

        <Button
          :label="$t('JABVOX_PRODUCTS.SAVE')"
          :is-loading="uiFlags.isSavingConfig"
          @click="onSave"
        />
      </div>
    </div>

    <!-- PDF Preview -->
    <div class="flex-1 min-w-[420px]">
      <p class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-3">
        {{ $t('JABVOX_PRODUCTS.PDF.PREVIEW') }}
      </p>
      <div
        class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 overflow-hidden shadow-sm"
      >
        <!-- Header: Logo | Company info (center) | Doc type (right) -->
        <div
          class="flex items-start gap-4 p-5 border-b border-slate-200 dark:border-slate-700"
        >
          <!-- Logo left -->
          <div
            class="w-16 h-16 rounded border border-slate-200 dark:border-slate-700 flex items-center justify-center overflow-hidden bg-slate-50 dark:bg-slate-800 shrink-0"
          >
            <img
              v-if="form.company_logo_jabvox"
              :src="form.company_logo_jabvox"
              class="w-full h-full object-contain"
            />
            <i v-else class="i-lucide-image text-xl text-slate-300" />
          </div>

          <!-- Company info center -->
          <div
            class="flex-1 text-center leading-snug text-xs text-slate-600 dark:text-slate-300"
          >
            <p
              class="font-bold text-sm text-slate-800 dark:text-slate-100 mb-0.5"
            >
              {{ form.company_name_jabvox || 'Nombre empresa' }}
            </p>
            <p v-if="form.company_nit_jabvox">
              {{ $t('JABVOX_PRODUCTS.PDF.NIT_PREFIX') }}
              {{ form.company_nit_jabvox }}
            </p>
            <p v-if="form.company_address_jabvox">
              {{ form.company_address_jabvox }}
            </p>
            <p v-if="form.company_phone_jabvox">
              {{ form.company_phone_jabvox }}
            </p>
            <p
              v-if="form.company_website_jabvox"
              class="text-blue-600 underline"
            >
              {{ form.company_website_jabvox }}
            </p>
            <p v-if="form.company_email_jabvox">
              {{ form.company_email_jabvox }}
            </p>
          </div>

          <!-- Doc type top-right -->
          <div class="text-right shrink-0">
            <p class="text-xs text-slate-400 uppercase tracking-wide">
              {{ $t('JABVOX_PRODUCTS.PDF.QUOTE_LABEL') }}
            </p>
            <p
              class="text-2xl font-bold text-slate-800 dark:text-slate-100 leading-none mt-0.5"
            >
              {{ $t('JABVOX_PRODUCTS.PDF.QUOTE_NUMBER_PREVIEW') }}
            </p>
          </div>
        </div>

        <!-- Table header placeholder -->
        <div
          class="mx-5 mt-4 mb-2 grid grid-cols-4 gap-2 text-xs font-semibold text-slate-400 border-b border-slate-100 dark:border-slate-700 pb-1.5"
        >
          <span class="col-span-2">Producto / Servicio</span>
          <span class="text-center">Cant.</span>
          <span class="text-right">Total</span>
        </div>

        <!-- Rows placeholder -->
        <div class="mx-5 space-y-2 pb-4">
          <div
            v-for="w in ['3/4', '2/3', '5/6']"
            :key="w"
            class="grid grid-cols-4 gap-2 items-center"
          >
            <div
              class="col-span-2 h-2 bg-slate-100 dark:bg-slate-700 rounded"
            />
            <div class="h-2 bg-slate-100 dark:bg-slate-700 rounded" />
            <div class="h-2 bg-slate-100 dark:bg-slate-700 rounded" />
          </div>
        </div>

        <!-- Total row placeholder -->
        <div
          class="mx-5 mb-4 flex justify-end border-t border-slate-100 dark:border-slate-700 pt-2 gap-4 text-xs"
        >
          <span class="text-slate-400">Total</span>
          <div class="h-2 w-16 bg-slate-200 dark:bg-slate-600 rounded mt-0.5" />
        </div>
      </div>
    </div>
  </div>
</template>
