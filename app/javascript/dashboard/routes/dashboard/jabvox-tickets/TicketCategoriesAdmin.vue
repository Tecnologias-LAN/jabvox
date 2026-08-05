<script setup>
import { ref, onMounted } from 'vue';
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
  active_jabvox: true,
});

const editing = ref(null);
const form = ref(blank());

const startNew = () => {
  editing.value = 'new';
  form.value = blank();
};
const startEdit = c => {
  editing.value = c.id;
  form.value = { ...c };
};
const cancel = () => {
  editing.value = null;
};

const reload = () => store.dispatch('jabvoxTickets/fetchCategories');

const save = async () => {
  try {
    if (editing.value === 'new') {
      await store.dispatch('jabvoxTickets/fetchCategories'); // no-op guard
      await import('dashboard/api/jabvox/tickets').then(m =>
        m.default.createCategory(form.value)
      );
    } else {
      await import('dashboard/api/jabvox/tickets').then(m =>
        m.default.updateCategory(editing.value, form.value)
      );
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
            <tr v-for="c in categories" :key="c.id" class="text-n-slate-12">
              <td class="py-2 px-3">
                <span
                  class="inline-block w-2 h-2 rounded-full mr-2"
                  :style="{ backgroundColor: c.color }"
                />
                {{ c.name }}
              </td>
              <td class="py-2 px-3">
                {{
                  t(
                    `JABVOX_TICKETS.TYPE.${(c.category_type || '').toUpperCase()}`
                  )
                }}
              </td>
              <td class="py-2 px-3 text-n-slate-11">
                {{ `${c.sla_resolution_minutes} min` }}
              </td>
              <td class="py-2 px-3 text-right">
                <Button
                  icon="i-lucide-pencil"
                  size="xs"
                  variant="ghost"
                  color="slate"
                  @click="startEdit(c)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  size="xs"
                  variant="ghost"
                  color="ruby"
                  @click="remove(c)"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
