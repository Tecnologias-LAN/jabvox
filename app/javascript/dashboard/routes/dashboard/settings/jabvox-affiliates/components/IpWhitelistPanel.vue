<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import affiliatesAPI from 'dashboard/api/jabvox/affiliates';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  affiliate: { type: Object, required: true },
});

const emit = defineEmits(['requestDelete']);
const { t } = useI18n();

const list = ref([]);
const loading = ref(true);
const adding = ref(false);
const ip = ref('');
const comment = ref('');
const error = ref('');

const IPV4_RE = /^(\d{1,3}\.){3}\d{1,3}$/;

onMounted(async () => {
  try {
    const { data } = await affiliatesAPI.getIpWhitelist(props.affiliate.id);
    list.value = data;
  } finally {
    loading.value = false;
  }
});

const onAdd = async () => {
  const value = ip.value.trim();
  if (!IPV4_RE.test(value)) {
    error.value = t('JABVOX_AFFILIATES.IP.INVALID');
    return;
  }
  error.value = '';
  adding.value = true;
  try {
    const { data } = await affiliatesAPI.addIp(props.affiliate.id, {
      ip: value,
      comment: comment.value.trim() || null,
      is_active: true,
    });
    list.value = [...list.value, data];
    ip.value = '';
    comment.value = '';
    useAlert(t('JABVOX_AFFILIATES.IP.CREATE_SUCCESS'));
  } catch {
    error.value = t('JABVOX_AFFILIATES.IP.ERROR');
  } finally {
    adding.value = false;
  }
};

const onToggle = async entry => {
  try {
    const { data } = await affiliatesAPI.updateIp(
      props.affiliate.id,
      entry.id,
      {
        is_active: !entry.is_active,
      }
    );
    list.value = list.value.map(e => (e.id === entry.id ? data : e));
  } catch {
    useAlert(t('JABVOX_AFFILIATES.IP.ERROR'));
  }
};

// Deletion is confirmed by the parent's dialog; it calls back removeEntry().
const askDelete = entry => {
  emit('requestDelete', {
    affiliateId: props.affiliate.id,
    entry,
    remove: () => {
      list.value = list.value.filter(e => e.id !== entry.id);
    },
  });
};

defineExpose({});
</script>

<template>
  <div class="flex flex-col gap-4">
    <!-- Header -->
    <div class="flex items-start gap-3">
      <span class="i-lucide-shield-check size-4 text-n-brand mt-0.5 shrink-0" />
      <div>
        <p class="text-sm font-semibold text-n-slate-12">
          {{ t('JABVOX_AFFILIATES.IP.TITLE', { name: affiliate.name }) }}
        </p>
        <p class="text-xs text-n-slate-10 mt-0.5 leading-relaxed">
          {{ t('JABVOX_AFFILIATES.IP.HINT') }}
        </p>
      </div>
    </div>

    <div
      v-if="loading"
      class="flex items-center gap-2 py-3 text-xs text-n-slate-10"
    >
      <Spinner :size="14" />
      {{ t('JABVOX_AFFILIATES.LOADING') }}
    </div>

    <template v-else>
      <!-- IP list -->
      <div
        v-if="list.length"
        class="rounded-xl border border-n-weak overflow-hidden divide-y divide-n-weak"
      >
        <div
          v-for="entry in list"
          :key="entry.id"
          class="flex flex-wrap items-center gap-3 px-4 py-2.5 bg-n-solid-1"
        >
          <code class="font-mono text-sm text-n-slate-12 w-32 shrink-0">
            {{ entry.ip }}
          </code>
          <span class="text-xs text-n-slate-10 flex-1 min-w-0 truncate italic">
            {{ entry.comment || '—' }}
          </span>
          <button class="shrink-0" @click="onToggle(entry)">
            <Label
              :label="
                entry.is_active
                  ? t('JABVOX_AFFILIATES.TABLE.ACTIVE')
                  : t('JABVOX_AFFILIATES.TABLE.INACTIVE')
              "
              :color="entry.is_active ? 'teal' : 'slate'"
              compact
            />
          </button>
          <Button
            icon="i-lucide-trash-2"
            variant="ghost"
            color="ruby"
            size="sm"
            @click="askDelete(entry)"
          />
        </div>
      </div>

      <!-- Empty: access blocked -->
      <div
        v-else
        class="flex items-center gap-2 rounded-xl border border-n-ruby-6 bg-n-ruby-2 px-4 py-3"
      >
        <span class="i-lucide-shield-off size-4 text-n-ruby-11 shrink-0" />
        <p class="text-xs text-n-ruby-11">
          {{ t('JABVOX_AFFILIATES.IP.EMPTY') }}
        </p>
      </div>

      <!-- Add IP form (responsive) -->
      <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
        <p class="text-xs font-medium text-n-slate-11 mb-3">
          {{ t('JABVOX_AFFILIATES.IP.ADD') }}
        </p>
        <div class="flex flex-col sm:flex-row sm:items-end gap-2">
          <div class="w-full sm:w-44">
            <Input
              v-model="ip"
              size="sm"
              :placeholder="t('JABVOX_AFFILIATES.IP.ADD_PLACEHOLDER')"
              @keydown.enter="onAdd"
            />
          </div>
          <div class="flex-1">
            <Input
              v-model="comment"
              size="sm"
              :placeholder="t('JABVOX_AFFILIATES.IP.COMMENT_PLACEHOLDER')"
              @keydown.enter="onAdd"
            />
          </div>
          <Button
            :label="
              adding
                ? t('JABVOX_AFFILIATES.IP.ADDING')
                : t('JABVOX_AFFILIATES.IP.ADD')
            "
            icon="i-lucide-plus"
            size="sm"
            :is-loading="adding"
            class="shrink-0"
            @click="onAdd"
          />
        </div>
        <p
          v-if="error"
          class="mt-2 text-xs text-n-ruby-11 flex items-center gap-1"
        >
          <span class="i-lucide-circle-alert size-3" />
          {{ error }}
        </p>
      </div>
    </template>
  </div>
</template>
