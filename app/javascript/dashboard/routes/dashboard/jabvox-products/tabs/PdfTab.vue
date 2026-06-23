<script setup>
import { ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SectionCard from '../components/SectionCard.vue';

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

onMounted(() => store.dispatch('jabvoxProducts/fetchIntegrationConfig'));

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
  <!-- eslint-disable vue/no-bare-strings-in-template -- preview mockup labels -->
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
    <!-- Form -->
    <SectionCard
      :title="t('JABVOX_PRODUCTS.TABS.PDF')"
      :description="t('JABVOX_PRODUCTS.PDF.SECTION_DESC')"
      icon="i-lucide-file-text"
    >
      <div class="flex flex-col gap-4">
        <!-- Logo -->
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_PRODUCTS.PDF.LOGO') }}
          </label>
          <div class="flex items-center gap-3">
            <div
              class="size-16 shrink-0 rounded-xl border border-n-weak bg-n-alpha-1 flex items-center justify-center overflow-hidden"
            >
              <img
                v-if="form.company_logo_jabvox"
                :src="form.company_logo_jabvox"
                alt=""
                class="size-full object-contain"
              />
              <span v-else class="i-lucide-image size-6 text-n-slate-9" />
            </div>
            <label
              class="inline-flex items-center gap-1.5 cursor-pointer rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
            >
              <span class="i-lucide-upload size-4" />
              {{ t('JABVOX_PRODUCTS.PDF.LOGO') }}
              <input
                type="file"
                accept="image/png,image/jpeg,image/svg+xml"
                class="hidden"
                @change="onLogoChange"
              />
            </label>
          </div>
        </div>

        <Input
          v-model="form.company_name_jabvox"
          :label="t('JABVOX_PRODUCTS.PDF.COMPANY_NAME')"
        />
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model="form.company_nit_jabvox"
            :label="t('JABVOX_PRODUCTS.PDF.NIT')"
          />
          <Input
            v-model="form.company_phone_jabvox"
            :label="t('JABVOX_PRODUCTS.PDF.PHONE')"
          />
        </div>
        <Input
          v-model="form.company_address_jabvox"
          :label="t('JABVOX_PRODUCTS.PDF.ADDRESS')"
        />
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model="form.company_email_jabvox"
            type="email"
            :label="t('JABVOX_PRODUCTS.PDF.EMAIL')"
          />
          <Input
            v-model="form.company_website_jabvox"
            type="url"
            :label="t('JABVOX_PRODUCTS.PDF.WEBSITE')"
          />
        </div>
      </div>

      <template #footer>
        <div class="flex justify-end">
          <Button
            :label="t('JABVOX_PRODUCTS.SAVE')"
            :is-loading="uiFlags.isSavingConfig"
            @click="onSave"
          />
        </div>
      </template>
    </SectionCard>

    <!-- Live preview -->
    <div class="flex flex-col gap-2">
      <p class="text-xs font-medium uppercase tracking-wide text-n-slate-10">
        {{ t('JABVOX_PRODUCTS.PDF.PREVIEW_TITLE') }}
      </p>
      <div
        class="rounded-2xl border border-n-weak bg-white shadow-sm overflow-hidden"
      >
        <!-- Document header -->
        <div class="flex items-start gap-4 p-5 border-b border-slate-200">
          <div
            class="size-14 shrink-0 rounded-lg bg-slate-50 border border-slate-200 flex items-center justify-center overflow-hidden"
          >
            <img
              v-if="form.company_logo_jabvox"
              :src="form.company_logo_jabvox"
              alt=""
              class="size-full object-contain"
            />
            <span v-else class="i-lucide-image size-5 text-slate-300" />
          </div>
          <div class="flex-1 min-w-0 text-center">
            <p class="text-sm font-bold text-slate-800 truncate">
              {{ form.company_name_jabvox || '—' }}
            </p>
            <div class="text-[10px] leading-snug text-slate-500">
              <p v-if="form.company_nit_jabvox">
                NIT {{ form.company_nit_jabvox }}
              </p>
              <p v-if="form.company_address_jabvox">
                {{ form.company_address_jabvox }}
              </p>
              <p v-if="form.company_phone_jabvox || form.company_email_jabvox">
                {{ form.company_phone_jabvox }}
                <span v-if="form.company_email_jabvox">
                  · {{ form.company_email_jabvox }}
                </span>
              </p>
            </div>
          </div>
          <div class="shrink-0 text-right">
            <span
              class="inline-block rounded bg-slate-100 px-2 py-0.5 text-[10px] font-semibold text-slate-500"
            >
              COTIZACIÓN
            </span>
          </div>
        </div>
        <!-- Placeholder table -->
        <div class="p-5 flex flex-col gap-2">
          <div class="grid grid-cols-4 gap-2">
            <div class="col-span-2 h-2 rounded bg-slate-200" />
            <div class="h-2 rounded bg-slate-100" />
            <div class="h-2 rounded bg-slate-100" />
          </div>
          <div v-for="n in 3" :key="n" class="grid grid-cols-4 gap-2">
            <div class="col-span-2 h-2 rounded bg-slate-100" />
            <div class="h-2 rounded bg-slate-100" />
            <div class="h-2 rounded bg-slate-100" />
          </div>
          <div class="flex justify-end pt-2">
            <div class="h-3 w-20 rounded bg-slate-200" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
