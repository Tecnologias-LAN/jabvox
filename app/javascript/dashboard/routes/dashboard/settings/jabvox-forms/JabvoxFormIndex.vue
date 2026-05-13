<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
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

onMounted(() => {
  store.dispatch('jabvoxForms/fetchForms');
  store.dispatch('jabvoxForms/fetchFormConfig');
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

const onDelete = async form => {
  if (
    !window.confirm(
      t('JABVOX_FORMS.CONFIRM_DELETE', { name: form.name_jabvox })
    )
  )
    return;
  try {
    await store.dispatch('jabvoxForms/deleteForm', form.id);
    useAlert(t('JABVOX_FORMS.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_FORMS.DELETE_ERROR'));
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
      v-if="showEditor"
      :form="editingForm"
      @saved="onSaved"
      @close="showEditor = false"
    />

    <!-- List view -->
    <div v-else class="w-full h-full overflow-auto p-6">
      <div class="max-w-5xl mx-auto space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold text-slate-800 dark:text-slate-100">
            {{ $t('JABVOX_FORMS.TITLE') }}
          </h1>
          <div class="flex items-center gap-2">
            <button
              class="flex items-center gap-1.5 px-3 py-2 text-sm text-slate-600 dark:text-slate-300 border border-slate-300 dark:border-slate-600 rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
              @click="showConfig = true"
            >
              <span class="i-lucide-settings size-4" />
              {{ $t('JABVOX_FORMS.CONFIGURE') }}
            </button>
            <button
              class="flex items-center gap-1.5 px-3 py-2 text-sm text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors"
              @click="openCreate"
            >
              <span class="i-lucide-plus size-4" />
              {{ $t('JABVOX_FORMS.NEW_FORM') }}
            </button>
          </div>
        </div>

        <div
          v-if="uiFlags.isFetching"
          class="flex items-center justify-center py-16 text-slate-400 text-sm animate-pulse"
        >
          {{ $t('JABVOX_FORMS.LOADING') }}
        </div>

        <div
          v-else-if="forms.length === 0"
          class="flex flex-col items-center justify-center py-16 text-slate-400 gap-3"
        >
          <span class="i-lucide-file-text size-10 opacity-40" />
          <p class="text-sm">{{ $t('JABVOX_FORMS.EMPTY') }}</p>
          <button
            class="px-4 py-2 text-sm text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors"
            @click="openCreate"
          >
            {{ $t('JABVOX_FORMS.CREATE_FIRST') }}
          </button>
        </div>

        <div v-else class="grid gap-4">
          <div
            v-for="form in forms"
            :key="form.id"
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2 mb-1">
                  <h3
                    class="text-sm font-semibold text-slate-800 dark:text-slate-100 truncate"
                  >
                    {{ form.name_jabvox }}
                  </h3>
                  <span
                    class="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium"
                    :class="
                      form.active_jabvox
                        ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                        : 'bg-slate-100 text-slate-500 dark:bg-slate-700 dark:text-slate-400'
                    "
                  >
                    {{
                      form.active_jabvox
                        ? $t('JABVOX_FORMS.ACTIVE')
                        : $t('JABVOX_FORMS.INACTIVE')
                    }}
                  </span>
                </div>
                <div class="flex items-center gap-1 text-xs text-slate-400">
                  <span class="i-lucide-link size-3" />
                  <span class="truncate font-mono">{{ formUrl(form) }}</span>
                  <button
                    class="shrink-0 p-0.5 hover:text-woot-500 transition-colors"
                    @click="copyUrl(form)"
                  >
                    <span class="i-lucide-copy size-3" />
                  </button>
                </div>
              </div>
              <div class="flex items-center gap-1 shrink-0">
                <button
                  class="p-1.5 rounded-lg text-slate-400 hover:text-woot-500 hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors"
                  @click="openEdit(form)"
                >
                  <span class="i-lucide-pencil size-4" />
                </button>
                <button
                  class="p-1.5 rounded-lg text-slate-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                  @click="onDelete(form)"
                >
                  <span class="i-lucide-trash-2 size-4" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <JabvoxFormConfig v-if="showConfig" @close="showConfig = false" />
  </div>
</template>
