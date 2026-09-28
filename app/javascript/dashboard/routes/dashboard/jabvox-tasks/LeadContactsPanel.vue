<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';
import LeadContactFormDialog from './LeadContactFormDialog.vue';
import LeadSelect from './components/LeadSelect.vue';
import TasksEmptyState from './components/TasksEmptyState.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();
const store = useTasksStore();

const showDialog = ref(false);
const editingContact = ref(null);
const selectedLeadId = ref(null);
const confirmDialog = ref(null);

// Cerrado por defecto: son notas de referencia, no lo que se viene a hacer al tablero, y
// abierto se comía 320px de ancho todo el tiempo. La preferencia se recuerda por navegador
// para que quien sí lo use no tenga que abrirlo cada vez.
const STORAGE_KEY = 'jabvox_tasks_contacts_panel_open';
const isOpen = ref(false);

try {
  isOpen.value = window.localStorage.getItem(STORAGE_KEY) === 'true';
} catch {
  // Sin acceso a localStorage (ventana privada, cookies bloqueadas): queda cerrado.
}

const togglePanel = () => {
  isOpen.value = !isOpen.value;
  try {
    window.localStorage.setItem(STORAGE_KEY, String(isOpen.value));
  } catch {
    // No poder recordarlo no debe impedir abrirlo.
  }
};

const contacts = computed(() => store.contactList);
const isLoading = computed(() => store.uiFlags.fetchingContacts);
const hasLead = computed(() => Boolean(selectedLeadId.value));

const onLeadChange = async leadId => {
  selectedLeadId.value = leadId ? Number(leadId) : null;
  if (selectedLeadId.value) {
    try {
      await store.fetchLeadContacts(selectedLeadId.value);
    } catch {
      useAlert(t('JABVOX_TASKS.CONTACTS.ERROR'));
    }
  } else {
    store.clearLeadContacts();
  }
};

const openCreate = () => {
  editingContact.value = null;
  showDialog.value = true;
};

const openEdit = contact => {
  editingContact.value = contact;
  showDialog.value = true;
};

const onSubmit = async payload => {
  try {
    if (editingContact.value) {
      await store.updateLeadContact(editingContact.value.id, payload);
      useAlert(t('JABVOX_TASKS.CONTACTS.UPDATED'));
    } else {
      await store.createLeadContact({
        ...payload,
        jabvox_lead_id: Number(selectedLeadId.value),
      });
      useAlert(t('JABVOX_TASKS.CONTACTS.CREATED'));
    }
    showDialog.value = false;
    editingContact.value = null;
  } catch {
    useAlert(t('JABVOX_TASKS.CONTACTS.ERROR'));
  }
};

const onDelete = contact => {
  confirmDialog.value?.open({
    title: t('JABVOX_TASKS.CONTACTS.DELETE'),
    description: t('JABVOX_TASKS.CONTACTS.DELETE_CONFIRM'),
    data: contact.id,
  });
};

const doDelete = async contactId => {
  try {
    await store.deleteLeadContact(contactId);
    useAlert(t('JABVOX_TASKS.CONTACTS.DELETED'));
  } catch {
    useAlert(t('JABVOX_TASKS.CONTACTS.ERROR'));
  }
};
</script>

<template>
  <aside
    class="hidden xl:flex flex-col shrink-0 h-full border-l border-n-weak bg-n-solid-1 transition-[width] duration-200"
    :class="isOpen ? 'w-80' : 'w-11'"
  >
    <!-- Cerrado: solo la pestaña para abrirlo, en vertical para no robar ancho. -->
    <button
      v-if="!isOpen"
      type="button"
      class="flex flex-col items-center gap-2 w-full py-3 text-n-slate-11 hover:bg-n-alpha-1"
      :title="t('JABVOX_TASKS.CONTACTS.HEADER')"
      @click="togglePanel"
    >
      <span class="i-lucide-chevron-left size-4" aria-hidden="true" />
      <span class="i-lucide-users size-4" aria-hidden="true" />
    </button>

    <template v-else>
      <div class="px-4 py-3 border-b border-n-weak shrink-0 space-y-2">
        <div class="flex items-start justify-between gap-2">
          <div class="min-w-0">
            <h3 class="text-sm font-semibold text-n-slate-12">
              {{ t('JABVOX_TASKS.CONTACTS.HEADER') }}
            </h3>
            <p class="text-[11px] text-n-slate-10 mt-0.5">
              {{ t('JABVOX_TASKS.CONTACTS.SUBTITLE') }}
            </p>
          </div>
          <button
            type="button"
            class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 shrink-0"
            :title="t('JABVOX_TASKS.CONTACTS.COLLAPSE')"
            @click="togglePanel"
          >
            <span class="i-lucide-chevron-right size-4" aria-hidden="true" />
          </button>
        </div>
        <LeadSelect
          :model-value="selectedLeadId"
          @update:model-value="onLeadChange"
        />
      </div>

      <div class="flex-1 min-h-0 overflow-y-auto p-3 space-y-2">
        <button
          type="button"
          class="flex items-center justify-center gap-1 w-full py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 disabled:opacity-40 disabled:cursor-not-allowed"
          :disabled="!hasLead"
          :title="!hasLead ? t('JABVOX_TASKS.CONTACTS.SELECT_LEAD') : undefined"
          @click="openCreate"
        >
          <span class="i-lucide-plus size-4" aria-hidden="true" />
          {{ t('JABVOX_TASKS.CONTACTS.ADD') }}
        </button>

        <TasksEmptyState
          v-if="!hasLead"
          icon="i-lucide-user-search"
          :body="t('JABVOX_TASKS.CONTACTS.SELECT_LEAD')"
        />

        <p v-else-if="isLoading" class="text-sm text-n-slate-10 px-1">
          {{ t('JABVOX_TASKS.CONTACTS.LOADING') }}
        </p>

        <template v-else>
          <TasksEmptyState
            v-if="contacts.length === 0"
            icon="i-lucide-users"
            :body="t('JABVOX_TASKS.CONTACTS.EMPTY')"
          />

          <div
            v-for="contact in contacts"
            :key="contact.id"
            class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak space-y-1"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="text-sm font-medium text-n-slate-12 truncate">
                  {{ contact.nameJabvox }}
                </p>
                <p
                  v-if="contact.roleJabvox"
                  class="text-[11px] text-n-slate-10"
                >
                  {{ contact.roleJabvox }}
                </p>
              </div>
              <div class="flex items-center gap-1 shrink-0">
                <button
                  type="button"
                  class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                  @click="openEdit(contact)"
                >
                  <span class="i-lucide-pencil size-4" aria-hidden="true" />
                </button>
                <button
                  type="button"
                  class="p-1 rounded text-n-ruby-11 hover:bg-n-alpha-2"
                  @click="onDelete(contact)"
                >
                  <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
                </button>
              </div>
            </div>
            <p
              v-if="contact.emailJabvox"
              class="flex items-center gap-1.5 text-[11px] text-n-slate-11"
            >
              <span class="i-lucide-mail size-4 scale-75" aria-hidden="true" />
              {{ contact.emailJabvox }}
            </p>
            <p
              v-if="contact.phoneJabvox"
              class="flex items-center gap-1.5 text-[11px] text-n-slate-11"
            >
              <span class="i-lucide-phone size-4 scale-75" aria-hidden="true" />
              {{ contact.phoneJabvox }}
            </p>
            <p
              v-if="contact.descriptionJabvox"
              class="text-[11px] text-n-slate-10"
            >
              {{ contact.descriptionJabvox }}
            </p>
          </div>
        </template>
      </div>
    </template>

    <LeadContactFormDialog
      v-if="showDialog"
      :contact="editingContact"
      @submit="onSubmit"
      @close="showDialog = false"
    />

    <ConfirmDialog ref="confirmDialog" @confirm="doDelete" />
  </aside>
</template>
