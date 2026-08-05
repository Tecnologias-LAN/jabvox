<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

// Formulario para registrar un ticket: título, categoría (agrupada por tipo),
// prioridad, descripción y adjuntos. Opcionalmente hereda una conversación.
const props = defineProps({
  conversationId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close', 'created']);

const { t } = useI18n();
const store = useStore();
const categories = useMapGetter('jabvoxTickets/getCategories');
const uiFlags = useMapGetter('jabvoxTickets/getUIFlags');

const form = ref({
  title_jabvox: '',
  ticket_category_id: '',
  priority_jabvox: 'medium',
  description_jabvox: '',
});
const files = ref([]);
const fileInput = ref(null);

const PRIORITIES = ['low', 'medium', 'high', 'urgent'];

// Categorías agrupadas por tipo para el <optgroup>.
const grouped = computed(() => {
  const groups = { incident: [], requirement: [], request: [] };
  (categories.value || []).forEach(c => {
    if (groups[c.category_type]) groups[c.category_type].push(c);
  });
  return groups;
});

const canSubmit = computed(
  () => form.value.title_jabvox.trim() && !uiFlags.value.isCreating
);

const pickFiles = () => fileInput.value?.click();
const onFiles = e => {
  files.value = Array.from(e.target.files || []);
};

const submit = async () => {
  if (!canSubmit.value) return;
  try {
    let payload;
    if (files.value.length) {
      payload = new FormData();
      Object.entries(form.value).forEach(([k, v]) => payload.append(k, v));
      if (props.conversationId)
        payload.append('conversation_id', props.conversationId);
      files.value.forEach(f => payload.append('attachments[]', f));
    } else {
      payload = { ...form.value };
      if (props.conversationId) payload.conversation_id = props.conversationId;
    }
    const ticket = await store.dispatch('jabvoxTickets/createTicket', payload);
    useAlert(t('JABVOX_TICKETS.FORM.CREATED'));
    emit('created', ticket);
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_TICKETS.FORM.ERROR'));
  }
};
</script>

<template>
  <teleport to="body">
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
      @click.self="emit('close')"
    >
      <div
        class="flex flex-col w-full max-w-lg max-h-[88vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-lg overflow-hidden"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <h3 class="text-base font-semibold text-n-slate-12">
            {{ t('JABVOX_TICKETS.FORM.TITLE') }}
          </h3>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            @click="emit('close')"
          />
        </div>

        <div class="flex-1 overflow-y-auto px-5 py-4 flex flex-col gap-4">
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_TICKETS.FORM.FIELD_TITLE') }}
            </span>
            <Input v-model="form.title_jabvox" />
          </label>

          <div class="grid grid-cols-2 gap-3">
            <label class="flex flex-col gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_TICKETS.FORM.CATEGORY') }}
              </span>
              <select
                v-model="form.ticket_category_id"
                class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
              >
                <option value="">
                  {{ t('JABVOX_TICKETS.FORM.NO_CATEGORY') }}
                </option>
                <optgroup
                  v-for="(list, ty) in grouped"
                  v-show="list.length"
                  :key="ty"
                  :label="t(`JABVOX_TICKETS.TYPE.${ty.toUpperCase()}`)"
                >
                  <option v-for="c in list" :key="c.id" :value="c.id">
                    {{ c.name }}
                  </option>
                </optgroup>
              </select>
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('JABVOX_TICKETS.FORM.PRIORITY') }}
              </span>
              <select
                v-model="form.priority_jabvox"
                class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
              >
                <option v-for="pr in PRIORITIES" :key="pr" :value="pr">
                  {{ t(`JABVOX_TICKETS.PRIORITY.${pr.toUpperCase()}`) }}
                </option>
              </select>
            </label>
          </div>

          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_TICKETS.FORM.DESCRIPTION') }}
            </span>
            <textarea
              v-model="form.description_jabvox"
              rows="4"
              class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            />
          </label>

          <div>
            <Button
              :label="t('JABVOX_TICKETS.FORM.ATTACH')"
              icon="i-lucide-paperclip"
              size="xs"
              variant="outline"
              color="slate"
              @click="pickFiles"
            />
            <input
              ref="fileInput"
              type="file"
              multiple
              class="hidden"
              @change="onFiles"
            />
            <span v-if="files.length" class="ml-2 text-xs text-n-slate-11">
              {{ files.length }} {{ t('JABVOX_TICKETS.FORM.FILES') }}
            </span>
          </div>
        </div>

        <div
          class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak"
        >
          <Button
            :label="t('JABVOX_TICKETS.FORM.CANCEL')"
            variant="outline"
            color="slate"
            size="sm"
            @click="emit('close')"
          />
          <Button
            :label="t('JABVOX_TICKETS.FORM.SUBMIT')"
            size="sm"
            :disabled="!canSubmit"
            @click="submit"
          />
        </div>
      </div>
    </div>
  </teleport>
</template>
