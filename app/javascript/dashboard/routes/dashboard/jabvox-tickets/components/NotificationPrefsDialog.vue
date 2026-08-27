<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

// Preferencias de notificación de tickets del usuario (silenciar in-app / email).
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const prefs = useMapGetter('jabvoxTickets/getNotificationPreferences');

const inApp = ref(true);
const email = ref(true);

onMounted(async () => {
  await store.dispatch('jabvoxTickets/fetchNotificationPreferences');
  inApp.value = prefs.value.in_app;
  email.value = prefs.value.email;
});

const save = async () => {
  await store.dispatch('jabvoxTickets/updateNotificationPreferences', {
    in_app: inApp.value,
    email: email.value,
  });
  useAlert(t('JABVOX_TICKETS.NOTIF_PREFS.SAVED'));
  emit('close');
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    role="dialog"
    aria-modal="true"
    @click.self="emit('close')"
  >
    <div class="w-full max-w-sm rounded-xl bg-n-solid-1 p-6 shadow-xl">
      <h3 class="text-base font-semibold text-n-slate-12 mb-4">
        {{ t('JABVOX_TICKETS.NOTIF_PREFS.TITLE') }}
      </h3>
      <div class="flex flex-col gap-3">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="inApp" type="checkbox" />
          {{ t('JABVOX_TICKETS.NOTIF_PREFS.IN_APP') }}
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="email" type="checkbox" />
          {{ t('JABVOX_TICKETS.NOTIF_PREFS.EMAIL') }}
        </label>
      </div>
      <div class="flex justify-end gap-2 mt-6">
        <Button
          :label="t('JABVOX_TICKETS.FORM.CANCEL')"
          size="sm"
          variant="outline"
          color="slate"
          @click="emit('close')"
        />
        <Button
          :label="t('JABVOX_TICKETS.FORM.SUBMIT')"
          size="sm"
          @click="save"
        />
      </div>
    </div>
  </div>
</template>
