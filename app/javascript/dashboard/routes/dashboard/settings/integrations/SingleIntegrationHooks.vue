<script setup>
import { computed } from 'vue';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import { useBranding } from 'shared/composables/useBranding';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  integrationId: {
    type: String,
    required: true,
  },
});

defineEmits(['add', 'delete']);

const { integration, hasConnectedHooks } = useIntegrationHook(
  props.integrationId
);

const { replaceInstallationName } = useBranding();

// Settings of the connected hook, shown as read-only chips so the user can see
// what provider/model is active without opening anything.
const connectedSettings = computed(() => {
  const hook = integration.value?.hooks?.[0];
  const s = hook?.settings || {};
  const rows = [];
  if (s.base_url) rows.push({ label: 'URL base', value: s.base_url });
  if (s.model) rows.push({ label: 'Modelo', value: s.model });
  if (s.api_key) rows.push({ label: 'API Key', value: '••••••••' });
  return rows;
});
</script>

<template>
  <div
    class="outline outline-n-container outline-1 bg-n-card rounded-xl flex-grow overflow-auto p-4"
  >
    <div class="flex items-center justify-center">
      <div class="flex h-16 w-16 items-center justify-center">
        <img
          :src="`/dashboard/images/integrations/${integrationId}.png`"
          class="max-w-full rounded-md border border-n-weak shadow-sm block dark:hidden bg-n-alpha-3 dark:bg-n-alpha-2"
        />
        <img
          :src="`/dashboard/images/integrations/${integrationId}-dark.png`"
          class="max-w-full rounded-md border border-n-weak shadow-sm hidden dark:block bg-n-alpha-3 dark:bg-n-alpha-2"
        />
      </div>
      <div class="flex flex-col justify-center m-0 mx-4 flex-1 min-w-0">
        <div class="flex items-center gap-2 mb-1">
          <h3 class="text-heading-1 text-n-slate-12">
            {{ integration.name }}
          </h3>
          <!-- Estado de conexión explícito -->
          <span
            v-if="hasConnectedHooks"
            class="inline-flex items-center gap-1 rounded-full bg-n-teal-3 px-2 py-0.5 text-xs font-medium text-n-teal-11"
          >
            <span class="i-lucide-check-circle-2 size-3.5" />
            {{ $t('INTEGRATION_APPS.STATUS.CONNECTED') }}
          </span>
          <span
            v-else
            class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
          >
            <span class="i-lucide-circle-dashed size-3.5" />
            {{ $t('INTEGRATION_APPS.STATUS.DISCONNECTED') }}
          </span>
        </div>
        <p class="text-n-slate-11 text-body-main">
          {{ replaceInstallationName(integration.description) }}
        </p>
      </div>
      <div class="flex justify-center items-center mb-0 shrink-0">
        <div v-if="hasConnectedHooks">
          <div @click="$emit('delete', integration.hooks[0])">
            <Button
              ruby
              faded
              :label="$t('INTEGRATION_APPS.DISCONNECT.BUTTON_TEXT')"
            />
          </div>
        </div>
        <div v-else>
          <Button
            blue
            faded
            :label="$t('INTEGRATION_APPS.CONNECT.BUTTON_TEXT')"
            @click="$emit('add')"
          />
        </div>
      </div>
    </div>

    <!-- Datos de la conexión activa (solo lectura) -->
    <div
      v-if="hasConnectedHooks && connectedSettings.length"
      class="mt-4 grid grid-cols-1 sm:grid-cols-3 gap-2 border-t border-n-weak pt-3"
    >
      <div
        v-for="row in connectedSettings"
        :key="row.label"
        class="min-w-0 rounded-md bg-n-alpha-1 px-2.5 py-1.5"
      >
        <div
          class="text-[10px] font-medium uppercase tracking-wide text-n-slate-10"
        >
          {{ row.label }}
        </div>
        <div class="text-xs font-medium text-n-slate-12 break-words">
          {{ row.value }}
        </div>
      </div>
    </div>
  </div>
</template>
