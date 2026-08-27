<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const categories = useMapGetter('jabvoxTickets/getCategories');

const TYPES = ['incident', 'requirement', 'request'];

const blank = () => ({
  name_jabvox: '',
  category_type_jabvox: 'incident',
  color_jabvox: '#1F93FF',
  description_jabvox: '',
  sla_response_minutes_jabvox: 60,
  sla_resolution_minutes_jabvox: 1440,
  parent_id: '',
  active_jabvox: true,
});

const editing = ref(null);
const form = ref(blank());

// Posibles temas padre: solo temas raíz (no subtemas), del mismo tipo, y distinto
// del que se edita (para no auto-referenciar). Jerarquía de un solo nivel.
const parentOptions = computed(() =>
  (categories.value || []).filter(
    c =>
      !c.parent_id &&
      c.category_type === form.value.category_type_jabvox &&
      c.id !== editing.value
  )
);

// Lista agrupada: cada tema raíz con sus subtemas.
const groupedCategories = computed(() => {
  const all = categories.value || [];
  const roots = all.filter(c => !c.parent_id);
  return roots.map(root => ({
    ...root,
    children: all.filter(c => c.parent_id === root.id),
  }));
});

// Al cambiar el tipo, el padre elegido puede dejar de ser válido (otro tipo): límpialo.
watch(
  () => form.value.category_type_jabvox,
  () => {
    form.value.parent_id = '';
  }
);

const startNew = () => {
  editing.value = 'new';
  form.value = blank();
};
const startEdit = c => {
  editing.value = c.id;
  form.value = { ...c, parent_id: c.parent_id || '' };
};
const cancel = () => {
  editing.value = null;
};

const reload = () => store.dispatch('jabvoxTickets/fetchCategories');

const save = async () => {
  // parent_id vacío → null (tema raíz); si tiene valor, es subtema.
  const payload = { ...form.value, parent_id: form.value.parent_id || null };
  try {
    const api = (await import('dashboard/api/jabvox/tickets')).default;
    if (editing.value === 'new') {
      await api.createCategory(payload);
    } else {
      await api.updateCategory(editing.value, payload);
    }
    useAlert(t('JABVOX_TICKETS.CATEGORIES.SAVED'));
    editing.value = null;
    reload();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_TICKETS.CATEGORIES.ERROR'));
  }
};

const remove = async c => {
  try {
    await import('dashboard/api/jabvox/tickets').then(m =>
      m.default.removeCategory(c.id)
    );
    reload();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_TICKETS.CATEGORIES.ERROR'));
  }
};

const goBack = () => router.push({ name: 'jabvox_tickets_index' });

onMounted(reload);
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <header
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <div>
        <button class="text-xs text-n-slate-10 hover:underline" @click="goBack">
          {{ `← ${t('JABVOX_TICKETS.DETAIL.BACK')}` }}
        </button>
        <h1 class="text-lg font-semibold text-n-slate-12 mt-1">
          {{ t('JABVOX_TICKETS.CATEGORIES.TITLE') }}
        </h1>
      </div>
      <Button
        :label="t('JABVOX_TICKETS.CATEGORIES.NEW')"
        icon="i-lucide-plus"
        size="sm"
        @click="startNew"
      />
    </header>

    <div class="flex-1 overflow-y-auto px-6 py-4 flex flex-col gap-4">
      <!-- Editor -->
      <section
        v-if="editing"
        class="rounded-lg border border-n-weak p-4 flex flex-col gap-3"
      >
        <div class="grid grid-cols-2 gap-3">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{
              t('JABVOX_TICKETS.CATEGORIES.NAME')
            }}</span>
            <Input v-model="form.name_jabvox" />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{
              t('JABVOX_TICKETS.CATEGORIES.TYPE')
            }}</span>
            <select
              v-model="form.category_type_jabvox"
              class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            >
              <option v-for="ty in TYPES" :key="ty" :value="ty">
                {{ t(`JABVOX_TICKETS.TYPE.${ty.toUpperCase()}`) }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1 col-span-2">
            <span class="text-xs text-n-slate-11">
              {{ t('JABVOX_TICKETS.CATEGORIES.PARENT') }}
            </span>
            <select
              v-model="form.parent_id"
              class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            >
              <option value="">
                {{ t('JABVOX_TICKETS.CATEGORIES.NO_PARENT') }}
              </option>
              <option v-for="p in parentOptions" :key="p.id" :value="p.id">
                {{ p.name }}
              </option>
            </select>
            <span class="text-[11px] text-n-slate-9">
              {{ t('JABVOX_TICKETS.CATEGORIES.PARENT_HINT') }}
            </span>
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{
              t('JABVOX_TICKETS.CATEGORIES.SLA_RESPONSE')
            }}</span>
            <Input
              v-model.number="form.sla_response_minutes_jabvox"
              type="number"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{
              t('JABVOX_TICKETS.CATEGORIES.SLA_RESOLUTION')
            }}</span>
            <Input
              v-model.number="form.sla_resolution_minutes_jabvox"
              type="number"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{
              t('JABVOX_TICKETS.CATEGORIES.COLOR')
            }}</span>
            <input
              v-model="form.color_jabvox"
              type="color"
              class="h-9 w-16 rounded"
            />
          </label>
        </div>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            t('JABVOX_TICKETS.CATEGORIES.DESCRIPTION')
          }}</span>
          <Input v-model="form.description_jabvox" />
        </label>
        <div class="flex justify-end gap-2">
          <Button
            :label="t('JABVOX_TICKETS.FORM.CANCEL')"
            size="sm"
            variant="outline"
            color="slate"
            @click="cancel"
          />
          <Button
            :label="t('JABVOX_TICKETS.CATEGORIES.SAVE')"
            size="sm"
            :disabled="!form.name_jabvox"
            @click="save"
          />
        </div>
      </section>

      <!-- Lista -->
      <div class="overflow-x-auto rounded-lg border border-n-weak">
        <table class="w-full text-sm">
          <thead
            class="bg-n-alpha-1 text-n-slate-11 text-left text-xs uppercase"
          >
            <tr>
              <th class="py-2 px-3">
                {{ t('JABVOX_TICKETS.CATEGORIES.NAME') }}
              </th>
              <th class="py-2 px-3">
                {{ t('JABVOX_TICKETS.CATEGORIES.TYPE') }}
              </th>
              <th class="py-2 px-3">
                {{ t('JABVOX_TICKETS.CATEGORIES.SLA_RESOLUTION') }}
              </th>
              <th class="py-2 px-3" />
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <template v-for="root in groupedCategories" :key="root.id">
              <!-- Tema raíz -->
              <tr class="text-n-slate-12">
                <td class="py-2 px-3">
                  <span
                    class="inline-block w-2 h-2 rounded-full mr-2 align-middle"
                    :style="{ backgroundColor: root.color }"
                  />
                  <span class="font-medium">{{ root.name }}</span>
                </td>
                <td class="py-2 px-3">
                  {{
                    t(
                      `JABVOX_TICKETS.TYPE.${(root.category_type || '').toUpperCase()}`
                    )
                  }}
                </td>
                <td class="py-2 px-3 text-n-slate-11">
                  {{ `${root.sla_resolution_minutes} min` }}
                </td>
                <td class="py-2 px-3 text-right whitespace-nowrap">
                  <Button
                    icon="i-lucide-pencil"
                    size="xs"
                    variant="ghost"
                    color="slate"
                    @click="startEdit(root)"
                  />
                  <Button
                    icon="i-lucide-trash-2"
                    size="xs"
                    variant="ghost"
                    color="ruby"
                    @click="remove(root)"
                  />
                </td>
              </tr>
              <!-- Subtemas -->
              <tr
                v-for="child in root.children"
                :key="child.id"
                class="text-n-slate-11 bg-n-alpha-1/40"
              >
                <td class="py-1.5 px-3 pl-8">
                  <span
                    class="i-lucide-corner-down-right w-3.5 h-3.5 text-n-slate-9 mr-1.5 align-middle inline-block"
                    aria-hidden="true"
                  />
                  <span
                    class="inline-block w-2 h-2 rounded-full mr-2 align-middle"
                    :style="{ backgroundColor: child.color }"
                  />
                  {{ child.name }}
                </td>
                <td class="py-1.5 px-3 text-n-slate-9">
                  {{ t('JABVOX_TICKETS.CATEGORIES.SUBTOPIC') }}
                </td>
                <td class="py-1.5 px-3 text-n-slate-9">
                  {{ `${child.sla_resolution_minutes} min` }}
                </td>
                <td class="py-1.5 px-3 text-right whitespace-nowrap">
                  <Button
                    icon="i-lucide-pencil"
                    size="xs"
                    variant="ghost"
                    color="slate"
                    @click="startEdit(child)"
                  />
                  <Button
                    icon="i-lucide-trash-2"
                    size="xs"
                    variant="ghost"
                    color="ruby"
                    @click="remove(child)"
                  />
                </td>
              </tr>
            </template>
            <tr v-if="!groupedCategories.length">
              <td colspan="4" class="py-8 text-center text-n-slate-10">
                {{ t('JABVOX_TICKETS.CATEGORIES.EMPTY') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
