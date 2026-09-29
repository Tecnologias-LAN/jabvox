<script setup>
// Full lead info for a contact, shown in the conversation sidebar: the same
// "Información" + custom "Leads" fields as the lead detail page, resolved from
// the contact behind the conversation. Reuses the leads detail_for_contact
// endpoint, which returns the complete shape (contact fields, lead fields,
// inbox, and custom lead fields with label/type/formatted value).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import leadsAPI from 'dashboard/api/jabvox/leads';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const detail = ref(null);
const loading = ref(false);
const errored = ref(false);
const fieldSearch = ref('');

const load = async () => {
  detail.value = null;
  errored.value = false;
  if (!props.contactId) return;
  loading.value = true;
  try {
    const { data } = await leadsAPI.detailForContact(props.contactId);
    detail.value = data;
  } catch {
    errored.value = true;
  } finally {
    loading.value = false;
  }
};

watch(() => props.contactId, load, { immediate: true });

const contact = computed(() => detail.value?.contact || {});
const lead = computed(() => detail.value?.lead || {});
const customFields = computed(() => detail.value?.custom_fields || []);

const dateFmt = new Intl.DateTimeFormat('es-CO', { dateStyle: 'short' });
const fmtDate = v => (v ? dateFmt.format(new Date(v)) : null);
const contactTypeLabel = computed(() =>
  contact.value.contact_type === 'empresa'
    ? t('JABVOX_LEAD_INFO.TYPE_COMPANY')
    : t('JABVOX_LEAD_INFO.TYPE_PERSON')
);

// Filas fijas de "Información". Cada una se pinta siempre (con "—" si está vacía); las
// marcadas `wide` ocupan todo el ancho para que un valor largo no se corte.
//
// NO se repiten nombre, teléfono ni email: la cabecera del panel (ContactInfo) ya los
// muestra arriba, y además allí son EDITABLES y llevan enlace mailto:/tel:. Aquí solo va lo
// que esa cabecera no cubre.
const infoRows = computed(() => [
  {
    label: t('JABVOX_LEAD_INFO.DOCUMENT'),
    value: contact.value.identification,
  },
  { label: t('JABVOX_LEAD_INFO.CONTACT_TYPE'), value: contactTypeLabel.value },
  { label: t('JABVOX_LEAD_INFO.COUNTRY'), value: contact.value.country },
  { label: t('JABVOX_LEAD_INFO.CAMPAIGN'), value: lead.value.campaign_name },
  {
    label: t('JABVOX_LEAD_INFO.AFFILIATE'),
    value: lead.value.affiliate_name || t('JABVOX_LEAD_INFO.AFFILIATE_OWN'),
  },
  { label: t('JABVOX_LEAD_INFO.INBOX'), value: detail.value?.inbox_name },
  { label: t('JABVOX_LEAD_INFO.ASSIGNEE'), value: lead.value.assignee_name },
  {
    label: t('JABVOX_LEAD_INFO.REGISTERED_AT'),
    value: fmtDate(lead.value.created_at),
  },
  { label: t('JABVOX_LEAD_INFO.BIO'), value: contact.value.bio, wide: true },
]);

// Custom lead fields filtered by the search box.
const filteredCustomFields = computed(() => {
  const q = fieldSearch.value.trim().toLowerCase();
  if (!q) return customFields.value;
  return customFields.value.filter(f => f.label.toLowerCase().includes(q));
});
</script>

<template>
  <div class="flex flex-col gap-3 text-xs">
    <p v-if="loading" class="py-3 text-center text-n-slate-10">
      {{ t('JABVOX_LEAD_INFO.LOADING') }}
    </p>
    <p v-else-if="errored" class="py-3 text-center text-n-ruby-11">
      {{ t('JABVOX_LEAD_INFO.ERROR') }}
    </p>
    <p v-else-if="!detail" class="py-3 text-center text-n-slate-10">
      {{ t('JABVOX_LEAD_INFO.NO_LEAD') }}
    </p>

    <template v-else>
      <!-- Información: grid responsive 2 col (1 en angosto). Cada campo apila
           etiqueta + valor, con el valor en break-words para no perder texto. -->
      <div class="grid grid-cols-2 gap-x-3 gap-y-2">
        <div
          v-for="row in infoRows"
          :key="row.label"
          class="min-w-0 rounded-md bg-n-alpha-1 px-2 py-1.5"
          :class="row.wide ? 'col-span-2' : ''"
        >
          <div
            class="mb-0.5 text-[10px] font-medium uppercase tracking-wide text-n-slate-10"
          >
            {{ row.label }}
          </div>
          <div
            class="text-xs font-medium leading-snug text-n-slate-12 break-words"
          >
            {{ row.value || '—' }}
          </div>
        </div>
      </div>

      <!-- Campos personalizados del lead, con buscador -->
      <div v-if="customFields.length" class="flex flex-col gap-2 pt-1">
        <div class="relative flex items-center">
          <span
            class="i-lucide-search pointer-events-none absolute left-2.5 size-4 text-n-slate-10"
          />
          <input
            v-model="fieldSearch"
            type="search"
            :placeholder="t('JABVOX_LEAD_INFO.SEARCH_FIELD')"
            class="h-8 w-full rounded-md border border-n-weak bg-n-solid-1 pl-8 pr-2.5 text-xs leading-none text-n-slate-12"
          />
        </div>
        <div class="grid grid-cols-2 gap-x-3 gap-y-2">
          <div
            v-for="f in filteredCustomFields"
            :key="f.label"
            class="min-w-0 rounded-md bg-n-alpha-1 px-2 py-1.5"
          >
            <div
              class="mb-0.5 text-[10px] font-medium uppercase tracking-wide text-n-slate-10"
            >
              {{ f.label }}
            </div>
            <div
              class="text-xs font-medium leading-snug text-n-slate-12 break-words"
            >
              {{ f.value || '—' }}
            </div>
          </div>
        </div>
        <p
          v-if="!filteredCustomFields.length"
          class="py-2 text-center text-n-slate-10"
        >
          —
        </p>
      </div>
    </template>
  </div>
</template>
