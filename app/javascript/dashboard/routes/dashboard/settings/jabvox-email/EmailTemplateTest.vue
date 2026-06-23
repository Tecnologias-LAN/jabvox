<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import SectionCard from './components/SectionCard.vue';

const store = useStore();
const { t } = useI18n();

const templates = computed(() => store.getters['jabvoxEmail/getTemplates']);
const uiFlags = computed(() => store.getters['jabvoxEmail/getUIFlags']);

const selectedTemplateId = ref('');
const recipientEmail = ref('');

const templateOptions = computed(() =>
  templates.value.map(tpl => ({ value: tpl.id, label: tpl.name }))
);

watch(
  templates,
  list => {
    if (!selectedTemplateId.value && list?.length) {
      selectedTemplateId.value = list[0].id;
    }
  },
  { immediate: true }
);

const canSend = computed(
  () => selectedTemplateId.value && recipientEmail.value.trim()
);

const onSend = async () => {
  if (!canSend.value) return;
  try {
    await store.dispatch('jabvoxEmail/sendTestTemplate', {
      id: selectedTemplateId.value,
      to: recipientEmail.value.trim(),
    });
    useAlert(t('JABVOX_EMAIL.TEST.SUCCESS'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_EMAIL.TEST.ERROR'));
  }
};
</script>

<template>
  <div class="w-full">
    <SectionCard
      :title="t('JABVOX_EMAIL.TEST.TITLE')"
      :description="t('JABVOX_EMAIL.TEST.DESCRIPTION')"
      icon="i-lucide-send"
    >
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_EMAIL.TEST.TEMPLATE') }}
          </label>
          <Select
            v-model="selectedTemplateId"
            :options="templateOptions"
            :placeholder="t('JABVOX_EMAIL.TEST.TEMPLATE_PLACEHOLDER')"
          />
        </div>
        <Input
          v-model="recipientEmail"
          type="email"
          :label="t('JABVOX_EMAIL.TEST.RECIPIENT')"
          :placeholder="t('JABVOX_EMAIL.TEST.RECIPIENT_PLACEHOLDER')"
        />
      </div>

      <template #footer>
        <div class="flex justify-end">
          <Button
            :label="
              uiFlags.isSendingTest
                ? t('JABVOX_EMAIL.TEST.SENDING')
                : t('JABVOX_EMAIL.TEST.SEND')
            "
            icon="i-lucide-send"
            :is-loading="uiFlags.isSendingTest"
            :disabled="!canSend"
            @click="onSend"
          />
        </div>
      </template>
    </SectionCard>
  </div>
</template>
