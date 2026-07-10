<script setup>
// Resolves the lead that backs a contact, then shows that lead's multi-row
// custom tables (Asesorías, Casos…). Lets Kanban / Conversations / Dialer —
// which only know the contact — reuse the shared JabvoxLeadTableRows panel.
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import leadsAPI from 'dashboard/api/jabvox/leads';
import JabvoxLeadTableRows from './JabvoxLeadTableRows.vue';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const leadId = ref(null);
const resolving = ref(false);

const resolve = async () => {
  leadId.value = null;
  if (!props.contactId) return;
  resolving.value = true;
  try {
    const { data } = await leadsAPI.forContact(props.contactId);
    leadId.value = data?.id || null;
  } catch {
    leadId.value = null;
  } finally {
    resolving.value = false;
  }
};

watch(() => props.contactId, resolve, { immediate: true });
</script>

<template>
  <div>
    <p v-if="resolving" class="text-sm text-n-slate-10 py-6 text-center">
      {{ t('JABVOX_CUSTOMIZATION.LOADING') }}
    </p>
    <p v-else-if="!leadId" class="text-sm text-n-slate-10 py-6 text-center">
      {{ t('JABVOX_CUSTOMIZATION.LEAD_ROWS.NO_LEAD') }}
    </p>
    <JabvoxLeadTableRows v-else :lead-id="leadId" />
  </div>
</template>
