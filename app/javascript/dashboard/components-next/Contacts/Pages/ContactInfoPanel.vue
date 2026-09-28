<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactLabels from 'dashboard/components-next/Contacts/ContactLabels/ContactLabels.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import contactDetailAPI from 'dashboard/api/jabvox/contactDetail';
import { stageClass } from 'dashboard/helper/jabvox/lifecycleStage';

// Columna izquierda de la ficha: los datos del contacto en una sola pasada, compacta y con
// scroll propio.
//
// Reemplaza a ContactDetails.vue en esta pantalla. Aquél está pensado para la vista ancha:
// avatar de 72px, gap-8 entre bloques y un bloque de borrado que aquí ya vive en la cabecera.
// Aquí el espacio es una columna estrecha al lado del chat, así que se aprieta todo y se
// añade lo que la ficha unificada necesita: etapa del ciclo de vida y campos personalizados.
//
// Orden deliberado: identidad → datos → etapa → campos personalizados → redes sociales.
// Las redes van al final porque son lo que menos se consulta al gestionar un contacto.
const props = defineProps({
  selectedContact: { type: Object, required: true },
  customFieldDefs: { type: Array, default: () => [] },
  // Etapas que ofrece la cuenta, tal como las sirve el backend: no se duplica la lista aquí
  // para que añadir una etapa no obligue a tocar el frontend.
  lifecycleStages: { type: Array, default: () => [] },
  lifecycleStage: { type: String, default: '' },
  customFields: { type: Object, default: () => ({}) },
  // Responsable del contacto tal como lo sirve el backend: {id, name} o null.
  assignee: { type: Object, default: null },
});

const emit = defineEmits(['jabvoxUpdated']);

const { t } = useI18n();
const store = useStore();

const contactsFormRef = ref(null);
const avatarUrl = ref('');
const isUpdating = ref(false);
const isSavingJabvox = ref(false);

// Copia local editable de lo propio de Jabvox: se guarda con su propio botón para no
// mezclarlo con el update de contacto de Chatwoot, que no conoce estas columnas.
const stage = ref(props.lifecycleStage);
const fields = ref({ ...props.customFields });
const assigneeId = ref(props.assignee?.id ?? '');

watch(
  () => [props.lifecycleStage, props.customFields, props.assignee],
  ([newStage, newFields, newAssignee]) => {
    stage.value = newStage;
    fields.value = { ...newFields };
    assigneeId.value = newAssignee?.id ?? '';
  }
);

// Los agentes de la cuenta, para el selector de responsable. Nadie más los pide en esta
// pantalla, así que se cargan aquí.
const agents = useMapGetter('agents/getAgents');
onMounted(() => store.dispatch('agents/get'));

const agentOptions = computed(() =>
  (agents.value || []).map(a => ({ value: a.id, label: a.name }))
);

const contactData = ref({ ...props.selectedContact });
watch(
  () => props.selectedContact,
  value => {
    contactData.value = { ...value };
  }
);

const isFormInvalid = computed(() => contactsFormRef.value?.isFormInvalid);
const avatarSrc = computed(
  () => avatarUrl.value || contactData.value?.thumbnail
);

const createdAt = computed(() =>
  contactData.value?.createdAt ? dynamicTime(contactData.value.createdAt) : ''
);
const lastActivityAt = computed(() =>
  contactData.value?.lastActivityAt
    ? dynamicTime(contactData.value.lastActivityAt)
    : ''
);

const stageOptions = computed(() =>
  props.lifecycleStages.map(s => ({ value: s.id, label: s.name }))
);

// Cambió algo de lo propio de Jabvox respecto a lo que trajo el servidor.
const hasJabvoxChanges = computed(() => {
  if (stage.value !== props.lifecycleStage) return true;
  if (assigneeId.value !== (props.assignee?.id ?? '')) return true;
  // Un multiselect guarda una lista: comparar por referencia siempre daría "cambió".
  return props.customFieldDefs.some(def => {
    const actual = fields.value[def.key] ?? '';
    const original = props.customFields[def.key] ?? '';
    if (Array.isArray(actual) || Array.isArray(original)) {
      return JSON.stringify(actual) !== JSON.stringify(original);
    }
    return String(actual) !== String(original);
  });
});

// Un multiselect guarda una lista; el resto, un valor suelto.
const isChecked = (key, option) => {
  const value = fields.value[key];
  return Array.isArray(value) ? value.includes(option) : false;
};

const toggleMulti = (key, option) => {
  const current = Array.isArray(fields.value[key])
    ? [...fields.value[key]]
    : [];
  const idx = current.indexOf(option);
  if (idx === -1) current.push(option);
  else current.splice(idx, 1);
  fields.value = { ...fields.value, [key]: current };
};

const fieldClass =
  'w-full h-8 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2';

const handleFormUpdate = updated => {
  Object.assign(contactData.value, updated);
};

const updateContact = async () => {
  isUpdating.value = true;
  try {
    const { customAttributes, ...basic } = contactData.value;
    await store.dispatch('contacts/update', basic);
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.ERROR_MESSAGE'));
  } finally {
    isUpdating.value = false;
  }
};

const saveJabvoxFields = async () => {
  isSavingJabvox.value = true;
  try {
    const { data } = await contactDetailAPI.updateCustomFields(
      props.selectedContact.id,
      {
        customFields: fields.value,
        lifecycleStage: stage.value,
        // Cadena vacía = desasignar; el backend distingue "no mandado" de "vacío".
        assigneeId: assigneeId.value === '' ? null : assigneeId.value,
      }
    );
    emit('jabvoxUpdated', data.contact);
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.ERROR_MESSAGE'));
  } finally {
    isSavingJabvox.value = false;
  }
};

const handleAvatarUpload = async ({ file, url }) => {
  avatarUrl.value = url;
  try {
    await store.dispatch('contacts/update', {
      ...contactsFormRef.value?.state,
      avatar: file,
      isFormData: true,
    });
    useAlert(t('CONTACTS_LAYOUT.DETAILS.AVATAR.UPLOAD.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('CONTACTS_LAYOUT.DETAILS.AVATAR.UPLOAD.ERROR_MESSAGE'));
  }
};

const handleAvatarDelete = async () => {
  try {
    await store.dispatch('contacts/deleteAvatar', props.selectedContact.id);
    avatarUrl.value = '';
    contactData.value.thumbnail = null;
    useAlert(t('CONTACTS_LAYOUT.DETAILS.AVATAR.DELETE.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(
      error.message || t('CONTACTS_LAYOUT.DETAILS.AVATAR.DELETE.ERROR_MESSAGE')
    );
  }
};
</script>

<template>
  <div class="flex flex-col gap-4 p-3">
    <!-- Identidad: avatar y nombre en fila, no apilados, para ganar alto -->
    <div class="flex items-start gap-3">
      <Avatar
        :src="avatarSrc || ''"
        :name="selectedContact?.name || ''"
        :size="48"
        allow-upload
        class="flex-shrink-0"
        @upload="handleAvatarUpload"
        @delete="handleAvatarDelete"
      />
      <div class="flex flex-col min-w-0 gap-0.5">
        <h3 class="text-sm font-semibold text-n-slate-12 break-words">
          {{ selectedContact?.name }}
        </h3>
        <span
          v-if="selectedContact?.identifier"
          class="text-xs text-n-slate-11 truncate"
        >
          {{ selectedContact.identifier }}
        </span>
        <span class="text-[11px] text-n-slate-10 leading-tight">
          {{ t('CONTACTS_LAYOUT.DETAILS.CREATED_AT', { date: createdAt }) }}
        </span>
        <span class="text-[11px] text-n-slate-10 leading-tight">
          {{
            t('CONTACTS_LAYOUT.DETAILS.LAST_ACTIVITY', {
              date: lastActivityAt,
            })
          }}
        </span>
      </div>
    </div>

    <ContactLabels :contact-id="selectedContact?.id" />

    <!-- Etapa del ciclo de vida: sustituye la distinción "es lead / no es lead" -->
    <div class="flex flex-col gap-1">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('JABVOX_CONTACTS.COLUMNS.STAGE') }}
      </label>
      <select
        v-model="stage"
        :class="stageClass(stage || 'prospecto')"
        class="w-full h-8 rounded-lg border text-sm font-medium px-2"
      >
        <option v-for="opt in stageOptions" :key="opt.value" :value="opt.value">
          {{ opt.label }}
        </option>
      </select>
    </div>

    <!-- Responsable del contacto -->
    <div class="flex flex-col gap-1">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('JABVOX_CONTACTS.COLUMNS.ASSIGNEE') }}
      </label>
      <select
        v-model="assigneeId"
        class="w-full h-8 rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2"
      >
        <option value="">
          {{ t('JABVOX_CONTACTS.DETAIL.UNASSIGNED') }}
        </option>
        <option v-for="opt in agentOptions" :key="opt.value" :value="opt.value">
          {{ opt.label }}
        </option>
      </select>
    </div>

    <!-- Datos del contacto. Los campos personalizados entran por el slot del formulario, que
         los coloca justo antes de las redes sociales: el orden que pidió el usuario. -->
    <div class="flex flex-col gap-3">
      <ContactsForm
        ref="contactsFormRef"
        :contact-data="contactData"
        is-details-view
        class="[&_.grid]:!grid-cols-1"
        @update="handleFormUpdate"
      >
        <template #before-social>
          <div
            v-if="customFieldDefs.length"
            class="flex flex-col items-start w-full gap-2"
          >
            <span class="py-1 text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_CONTACTS.DETAIL.CUSTOM_FIELDS') }}
            </span>
            <div
              v-for="def in customFieldDefs"
              :key="def.key"
              class="flex flex-col w-full gap-1"
            >
              <label class="text-xs text-n-slate-11">{{ def.label }}</label>

              <!-- Cada tipo de columna con su control: una fecha se elige en un
                   calendario, un sí/no con un desplegable y una lista con sus opciones.
                   Antes todos salían como texto salvo un tipo "number" inexistente. -->
              <select
                v-if="def.column_type === 'select'"
                v-model="fields[def.key]"
                :class="fieldClass"
              >
                <option value="">
                  {{ t('JABVOX_CONTACTS.DETAIL.CUSTOM_FIELD_NONE') }}
                </option>
                <option v-for="o in def.options" :key="o" :value="o">
                  {{ o }}
                </option>
              </select>

              <div
                v-else-if="def.column_type === 'multiselect'"
                class="flex flex-wrap gap-2"
              >
                <label
                  v-for="o in def.options"
                  :key="o"
                  class="flex items-center gap-1.5 text-sm text-n-slate-12 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    class="rounded accent-n-brand"
                    :checked="isChecked(def.key, o)"
                    @change="toggleMulti(def.key, o)"
                  />
                  {{ o }}
                </label>
              </div>

              <select
                v-else-if="def.column_type === 'boolean'"
                v-model="fields[def.key]"
                :class="fieldClass"
              >
                <option value="">
                  {{ t('JABVOX_CONTACTS.DETAIL.CUSTOM_FIELD_NONE') }}
                </option>
                <option value="true">
                  {{ t('JABVOX_CONTACTS.DETAIL.CUSTOM_FIELD_YES') }}
                </option>
                <option value="false">
                  {{ t('JABVOX_CONTACTS.DETAIL.CUSTOM_FIELD_NO') }}
                </option>
              </select>

              <input
                v-else-if="def.column_type === 'date'"
                v-model="fields[def.key]"
                type="date"
                :class="fieldClass"
              />

              <input
                v-else-if="def.column_type === 'integer'"
                v-model="fields[def.key]"
                type="number"
                step="1"
                :class="fieldClass"
              />

              <input
                v-else-if="def.column_type === 'float'"
                v-model="fields[def.key]"
                type="number"
                step="any"
                :class="fieldClass"
              />

              <textarea
                v-else-if="def.column_type === 'textarea'"
                v-model="fields[def.key]"
                rows="3"
                class="w-full rounded-lg border border-n-weak bg-n-alpha-2 dark:bg-n-solid-2 text-sm text-n-slate-12 px-2 py-1.5 resize-y"
              />

              <input
                v-else
                v-model="fields[def.key]"
                type="text"
                :class="fieldClass"
              />
            </div>
          </div>
        </template>
      </ContactsForm>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          :label="t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.UPDATE_BUTTON')"
          size="sm"
          :is-loading="isUpdating"
          :disabled="isUpdating || isFormInvalid"
          @click="updateContact"
        />
        <Button
          v-if="hasJabvoxChanges"
          :label="t('JABVOX_CONTACTS.DETAIL.SAVE_JABVOX')"
          size="sm"
          variant="faded"
          :is-loading="isSavingJabvox"
          @click="saveJabvoxFields"
        />
      </div>
    </div>
  </div>
</template>
