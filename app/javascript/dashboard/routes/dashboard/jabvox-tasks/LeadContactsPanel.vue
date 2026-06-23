<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';
import LeadContactFormDialog from './LeadContactFormDialog.vue';
import LeadSelect from './components/LeadSelect.vue';
import TasksEmptyState from './components/TasksEmptyState.vue';

const { t } = useI18n();
const store = useTasksStore();

const showDialog = ref(false);
const editingContact = ref(null);
const selectedLeadId = ref(null);

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

const onDelete = async contact => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('JABVOX_TASKS.CONTACTS.DELETE_CONFIRM'))) return;
  try {
    await store.deleteLeadContact(contact.id);
    useAlert(t('JABVOX_TASKS.CONTACTS.DELETED'));
  } catch {
    useAlert(t('JABVOX_TASKS.CONTACTS.ERROR'));
  }
};
</script>

<template>
  <aside
    class="hidden xl:flex flex-col w-80 shrink-0 h-full border-l border-n-weak bg-n-solid-1"
  >
    <div class="px-4 py-3 border-b border-n-weak shrink-0 space-y-2">
      <div>
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('JABVOX_TASKS.CONTACTS.HEADER') }}
        </h3>
        <p class="text-[11px] text-n-slate-10 mt-0.5">
          {{ t('JABVOX_TASKS.CONTACTS.SUBTITLE') }}
        </p>
      </div>
      <LeadSelect
        :model-value="selectedLeadId"
        @update:model-value="onLeadChange"
      />
    </div>

    <div class="flex-1 min-h-0 overflow-y-auto p-3 space-y-2">
      <TasksEmptyState
        v-if="!hasLead"
        icon="i-lucide-user-search"
        :body="t('JABVOX_TASKS.CONTACTS.SELECT_LEAD')"
      />

      <p v-else-if="isLoading" class="text-sm text-n-slate-10 px-1">
        {{ t('JABVOX_TASKS.CONTACTS.LOADING') }}
      </p>

      <template v-else>
        <button
          type="button"
          class="flex items-center justify-center gap-1 w-full py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3"
          @click="openCreate"
        >
          <span class="i-lucide-plus size-4" aria-hidden="true" />
          {{ t('JABVOX_TASKS.CONTACTS.ADD') }}
        </button>

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
              <p v-if="contact.roleJabvox" class="text-[11px] text-n-slate-10">
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

    <LeadContactFormDialog
      v-if="showDialog"
      :contact="editingContact"
      @submit="onSubmit"
      @close="showDialog = false"
    />
  </aside>
</template>
