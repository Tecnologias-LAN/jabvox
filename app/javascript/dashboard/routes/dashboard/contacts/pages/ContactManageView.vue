<script setup>
import { onMounted, computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';

import contactDetailAPI from 'dashboard/api/jabvox/contactDetail';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Policy from 'dashboard/components/policy.vue';
import ContactNotes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactNotes.vue';
import ContactMedia from 'dashboard/components-next/Contacts/ContactsSidebar/ContactMedia.vue';
import ContactMerge from 'dashboard/components-next/Contacts/ContactsSidebar/ContactMerge.vue';
import ContactCustomAttributes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactCustomAttributes.vue';
import ContactInfoPanel from 'dashboard/components-next/Contacts/Pages/ContactInfoPanel.vue';
import ContactChatPanel from 'dashboard/components-next/Contacts/Pages/ContactChatPanel.vue';
import ContactActivityPanel from 'dashboard/components-next/Contacts/Pages/ContactActivityPanel.vue';
import ContactManagementDialog from 'dashboard/components-next/Contacts/Pages/ContactManagementDialog.vue';
import JabvoxCallButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxCallButton.vue';
import JabvoxSmsButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxSmsButton.vue';
import JabvoxEmailButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxEmailButton.vue';

// Ficha del contacto en tres columnas: datos a la izquierda, chat con sus bandejas en el
// centro y, a la derecha, dos grupos — los datos del contacto (atributos, notas, media,
// combinar) y su actividad (gestiones, productos, registros).
//
// Sustituye a lo que antes estaba repartido entre esta ficha y el detalle de lead.
const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const contact = useMapGetter('contacts/getContactById');
const uiFlags = useMapGetter('contacts/getUIFlags');

const contactMergeRef = ref(null);
// Datos comerciales del contacto (conversaciones, gestiones, pedidos, registros): vienen del
// endpoint propio de Jabvox, no del store de Chatwoot.
const detail = ref({
  contact: null,
  conversations: [],
  managements: [],
  orders: [],
  records: [],
  customFieldDefs: [],
  managementStates: [],
  lifecycleStages: [],
});
const isLoadingDetail = ref(false);
const showManagementDialog = ref(false);

const isFetchingItem = computed(() => uiFlags.value.isFetchingItem);
const isMergingContact = computed(() => uiFlags.value.isMerging);
const selectedContact = computed(() => contact.value(route.params.contactId));
const showSpinner = computed(
  () => isFetchingItem.value || isMergingContact.value
);
const isBlocked = computed(() => Boolean(selectedContact.value?.blocked));

const goToContactsList = () => {
  if (window.history.state?.back || window.history.length > 1) {
    router.back();
  } else {
    router.push(`/app/accounts/${route.params.accountId}/contacts?page=1`);
  }
};

const fetchActiveContact = async () => {
  if (!route.params.contactId) return;

  await store.dispatch('contacts/show', { id: route.params.contactId });
  await store.dispatch(
    'contacts/fetchContactableInbox',
    route.params.contactId
  );
};

// Conversaciones, gestiones, pedidos y registros en una sola llamada.
const fetchDetail = async () => {
  const { contactId } = route.params;
  if (!contactId) return;

  isLoadingDetail.value = true;
  try {
    const { data } = await contactDetailAPI.show(contactId);
    detail.value = {
      contact: data.contact || null,
      conversations: data.conversations || [],
      managements: data.managements || [],
      orders: data.orders || [],
      records: data.records || [],
      customFieldDefs: data.custom_field_defs || [],
      managementStates: data.management_states || [],
      lifecycleStages: data.lifecycle_stages || [],
    };
  } catch {
    // Sin estos datos la ficha sigue mostrando la información básica del contacto.
    detail.value = {
      contact: null,
      conversations: [],
      managements: [],
      orders: [],
      records: [],
      customFieldDefs: [],
      managementStates: [],
      lifecycleStages: [],
    };
  } finally {
    isLoadingDetail.value = false;
  }
};

// Una gestión recién creada se antepone sin recargar: la lista viene ordenada por fecha
// descendente, así que la nueva es siempre la primera.
const onManagementCreated = management => {
  if (management)
    detail.value.managements = [management, ...detail.value.managements];
};

// Tras guardar etapa o campos personalizados se refresca la copia local del detalle, que es
// de donde el panel izquierdo lee sus valores iniciales.
const onJabvoxUpdated = updated => {
  if (updated) detail.value.contact = updated;
};

const toggleContactBlock = async () => {
  const action = isBlocked.value ? 'unblock' : 'block';
  const MESSAGES = {
    block: {
      ok: 'CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_SUCCESS_MESSAGE',
      fail: 'CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_ERROR_MESSAGE',
    },
    unblock: {
      ok: 'CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_SUCCESS_MESSAGE',
      fail: 'CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_ERROR_MESSAGE',
    },
  };

  try {
    await store.dispatch('contacts/update', {
      ...selectedContact.value,
      blocked: !isBlocked.value,
    });
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    useAlert(t(MESSAGES[action].ok));
  } catch (error) {
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    useAlert(t(MESSAGES[action].fail));
  }
};

const deleteContact = async () => {
  try {
    await store.dispatch('contacts/delete', selectedContact.value.id);
    useAlert(t('DELETE_CONTACT.API.SUCCESS_MESSAGE'));
    goToContactsList();
  } catch (error) {
    useAlert(t('DELETE_CONTACT.API.ERROR_MESSAGE'));
  }
};

onMounted(() => {
  fetchActiveContact();
  fetchDetail();
  store.dispatch('contactNotes/get', { contactId: route.params.contactId });
  store.dispatch('contactConversations/get', route.params.contactId);
  store.dispatch('attributes/get');
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-background">
    <!-- Cabecera -->
    <header
      class="flex items-center gap-2 px-4 py-2.5 border-b border-n-weak bg-n-solid-1 flex-shrink-0"
    >
      <Button
        icon="i-lucide-arrow-left"
        variant="ghost"
        size="sm"
        :aria-label="t('JABVOX_CONTACTS.DETAIL.BACK')"
        @click="goToContactsList"
      />
      <h1 class="text-sm font-semibold text-n-slate-12 truncate">
        {{ selectedContact?.name || t('JABVOX_CONTACTS.DETAIL.TITLE') }}
      </h1>
      <div class="flex-1" />

      <!-- Acciones de contacto: llamada por telefonía (click-to-call con su ventana de
           tipificación), SMS y correo. Cada botón se oculta solo si su módulo está apagado
           o si el contacto no tiene el dato que necesita. -->
      <JabvoxCallButton
        v-if="selectedContact?.id"
        :phone="selectedContact.phoneNumber || ''"
        :contact-id="Number(selectedContact.id)"
        :contact-name="selectedContact.name || ''"
        show-label
      />
      <JabvoxSmsButton
        v-if="selectedContact?.id && selectedContact?.phoneNumber"
        :phone="selectedContact.phoneNumber"
        :contact-id="Number(selectedContact.id)"
        show-label
      />
      <JabvoxEmailButton
        v-if="selectedContact?.id && selectedContact?.email"
        :email="selectedContact.email"
        :contact-id="Number(selectedContact.id)"
        show-label
      />

      <!-- Bloquear y eliminar: solo administradores -->
      <Policy :permissions="['administrator']">
        <Button
          :icon="isBlocked ? 'i-lucide-user-check' : 'i-lucide-user-x'"
          variant="ghost"
          size="sm"
          :label="
            isBlocked
              ? t('JABVOX_CONTACTS.DETAIL.UNBLOCK')
              : t('JABVOX_CONTACTS.DETAIL.BLOCK')
          "
          @click="toggleContactBlock"
        />
      </Policy>
      <Policy :permissions="['administrator']">
        <Button
          icon="i-lucide-trash-2"
          variant="ghost"
          color="ruby"
          size="sm"
          :label="t('JABVOX_CONTACTS.DETAIL.DELETE')"
          @click="deleteContact"
        />
      </Policy>
    </header>

    <div v-if="showSpinner" class="flex-1 flex items-center justify-center">
      <Spinner />
    </div>

    <!-- Tres columnas: datos · chat · actividad. Cada una con su propio scroll, para que
         una lista larga de gestiones no empuje al chat fuera de la pantalla. -->
    <div v-else class="flex-1 flex min-h-0 overflow-hidden">
      <aside
        class="hidden lg:flex flex-col w-80 xl:w-96 shrink-0 border-r border-n-weak bg-n-solid-1 overflow-y-auto overflow-x-hidden"
      >
        <ContactInfoPanel
          v-if="selectedContact"
          :selected-contact="selectedContact"
          :custom-field-defs="detail.customFieldDefs"
          :lifecycle-stages="detail.lifecycleStages"
          :lifecycle-stage="detail.contact?.lifecycle_stage || ''"
          :custom-fields="detail.contact?.custom_fields || {}"
          :assignee="detail.contact?.assignee || null"
          @jabvox-updated="onJabvoxUpdated"
        />
      </aside>

      <main class="flex-1 min-w-0 flex flex-col">
        <ContactChatPanel :conversations="detail.conversations" />
      </main>

      <aside
        class="hidden xl:flex flex-col w-80 2xl:w-96 shrink-0 border-l border-n-weak bg-n-solid-1 overflow-hidden"
      >
        <ContactActivityPanel
          :contact-id="route.params.contactId"
          :managements="detail.managements"
          :orders="detail.orders"
          :records="detail.records"
          :is-loading="isLoadingDetail"
          @add-management="showManagementDialog = true"
        >
          <template #attributes>
            <ContactCustomAttributes
              v-if="selectedContact"
              :selected-contact="selectedContact"
            />
          </template>
          <template #notes>
            <ContactNotes />
          </template>
          <template #media>
            <ContactMedia />
          </template>
          <template #merge>
            <ContactMerge
              v-if="selectedContact"
              ref="contactMergeRef"
              :selected-contact="selectedContact"
              @go-to-contacts-list="goToContactsList"
            />
          </template>
        </ContactActivityPanel>
      </aside>
    </div>

    <ContactManagementDialog
      v-if="showManagementDialog"
      :contact-id="route.params.contactId"
      :contact="selectedContact"
      :states="detail.managementStates"
      @created="onManagementCreated"
      @close="showManagementDialog = false"
    />
  </div>
</template>
