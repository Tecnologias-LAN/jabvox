<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import JabvoxFormEditor from './JabvoxFormEditor.vue';
import JabvoxFormConfig from './JabvoxFormConfig.vue';

const store = useStore();
const { t } = useI18n();

const forms = computed(() => store.getters['jabvoxForms/getForms']);
const formConfig = computed(() => store.getters['jabvoxForms/getFormConfig']);
const uiFlags = computed(() => store.getters['jabvoxForms/getUIFlags']);

const editingForm = ref(null);
const showEditor = ref(false);
const showConfig = ref(false);
const search = ref('');

const deleteDialogRef = ref(null);
const formToDelete = ref(null);

onMounted(() => {
  store.dispatch('jabvoxForms/fetchForms');
  store.dispatch('jabvoxForms/fetchFormConfig');
});

const filteredForms = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return forms.value;
  return forms.value.filter(
    f =>
      f.name_jabvox?.toLowerCase().includes(q) ||
      f.slug_jabvox?.toLowerCase().includes(q)
  );
});

const openCreate = () => {
  editingForm.value = null;
  showEditor.value = true;
};

const openEdit = form => {
  editingForm.value = form;
  showEditor.value = true;
};

const onSaved = () => {
  showEditor.value = false;
  editingForm.value = null;
};

const askDelete = form => {
  formToDelete.value = form;
  deleteDialogRef.value?.open();
};

const onConfirmDelete = async () => {
  const form = formToDelete.value;
  if (!form) return;
  try {
    await store.dispatch('jabvoxForms/deleteForm', form.id);
    useAlert(t('JABVOX_FORMS.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_FORMS.DELETE_ERROR'));
  } finally {
    deleteDialogRef.value?.close();
    formToDelete.value = null;
  }
};

const accountId = computed(() => store.getters.getCurrentAccountId);
const baseUrl = computed(
  () => formConfig.value?.base_url_jabvox || window.location.origin
);

const formUrl = form =>
  `${baseUrl.value}/f/${accountId.value}/${form.slug_jabvox}`;

const copyUrl = form => {
  navigator.clipboard.writeText(formUrl(form));
  useAlert(t('JABVOX_FORMS.URL_COPIED'));
};
</script>

<template>
  <div class="w-full h-full">
    <!-- Full-page form editor -->
    <JabvoxFormEditor
      v-show="showEditor"
      :form="editingForm"
      @saved="onSaved"
      @close="showEditor = false"
    />

    <!-- List view -->
    <div v-show="!showEditor" class="w-full h-full overflow-auto">
      <div
        class="mx-auto w-full max-w-[1600px] flex flex-col gap-6 p-4 sm:p-6 lg:p-8"
      >
        <!-- Header -->
        <div
          class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
        >
          <div class="min-w-0">
            <h1 class="text-xl font-semibold text-n-slate-12">
              {{ t('JABVOX_FORMS.TITLE') }}
            </h1>
            <p class="mt-1 text-sm text-n-slate-11 max-w-2xl">
              {{ t('JABVOX_FORMS.SUBTITLE') }}
            </p>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <Button
              icon="i-lucide-settings"
              :label="t('JABVOX_FORMS.CONFIGURE')"
              variant="outline"
              color="slate"
              size="sm"
              @click="showConfig = true"
            />
            <Button
              icon="i-lucide-plus"
              :label="t('JABVOX_FORMS.NEW_FORM')"
              size="sm"
              @click="openCreate"
            />
          </div>
        </div>

        <!-- Loading -->
        <div
          v-if="uiFlags.isFetching"
          class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
        >
          <Spinner :size="18" />
          {{ t('JABVOX_FORMS.LOADING') }}
        </div>

        <!-- Empty -->
        <EmptyStateLayout
          v-else-if="forms.length === 0"
          :title="t('JABVOX_FORMS.EMPTY')"
          :subtitle="t('JABVOX_FORMS.SUBTITLE')"
        >
          <template #actions>
            <Button
              icon="i-lucide-plus"
              :label="t('JABVOX_FORMS.CREATE_FIRST')"
              size="sm"
              @click="openCreate"
            />
          </template>
        </EmptyStateLayout>

        <template v-else>
          <!-- Search + count -->
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="relative w-full sm:w-64">
              <Input
                v-model="search"
                :placeholder="t('JABVOX_FORMS.SEARCH_PLACEHOLDER')"
                custom-input-class="!pl-9"
              >
                <template #prefix>
                  <span
                    class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                  />
                </template>
              </Input>
            </div>
            <span class="text-xs text-n-slate-10">
              {{ t('JABVOX_FORMS.COUNT', { count: forms.length }) }}
            </span>
          </div>

          <!-- No search results -->
          <div
            v-if="!filteredForms.length"
            class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_FORMS.NO_RESULTS') }}
          </div>

          <!-- Cards grid -->
          <div
            v-else
            class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
          >
            <div
              v-for="form in filteredForms"
              :key="form.id"
              class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 transition-shadow hover:shadow-sm"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="flex items-center gap-2 min-w-0">
                  <span
                    class="i-lucide-file-text size-4 text-n-slate-10 shrink-0"
                  />
                  <h3 class="text-sm font-semibold text-n-slate-12 truncate">
                    {{ form.name_jabvox }}
                  </h3>
                </div>
                <Label
                  :label="
                    form.active_jabvox
                      ? t('JABVOX_FORMS.ACTIVE')
                      : t('JABVOX_FORMS.INACTIVE')
                  "
                  :color="form.active_jabvox ? 'teal' : 'slate'"
                  compact
                />
              </div>

              <!-- URL -->
              <div
                class="flex items-center gap-1.5 text-xs text-n-slate-10 min-w-0"
              >
                <span class="i-lucide-link size-3 shrink-0" />
                <span class="truncate font-mono">{{ formUrl(form) }}</span>
                <button
                  class="shrink-0 p-0.5 hover:text-n-brand transition-colors"
                  @click="copyUrl(form)"
                >
                  <span class="i-lucide-copy size-3" />
                </button>
              </div>

              <div
                class="flex items-center justify-end gap-1 pt-2 border-t border-n-weak"
              >
                <Button
                  icon="i-lucide-pencil"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="openEdit(form)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  @click="askDelete(form)"
                />
              </div>
            </div>
          </div>
        </template>
      </div>
    </div>

    <JabvoxFormConfig v-if="showConfig" @close="showConfig = false" />

    <!-- Delete confirmation -->
    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('JABVOX_FORMS.DELETE')"
      :description="
        t('JABVOX_FORMS.CONFIRM_DELETE', {
          name: formToDelete?.name_jabvox || '',
        })
      "
      :confirm-button-label="t('JABVOX_FORMS.DELETE')"
      :cancel-button-label="t('JABVOX_FORMS.CANCEL')"
      @confirm="onConfirmDelete"
    />
  </div>
</template>
