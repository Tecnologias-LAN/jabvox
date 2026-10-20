<script>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, helpers } from '@vuelidate/validators';

// El validador `url` de Vuelidate rechaza a propósito las IPs privadas (10.x, 192.168.x,
// 172.16-31.x, 127.x). Jabvox permite webhooks a redes internas/ZeroTier (p. ej. el Hermes
// de la cuenta en 10.147.100.1:8644), así que usamos un validador propio más permisivo:
// exige esquema http(s) y un host (dominio o IP) con puerto y path opcionales.
const permissiveUrl = helpers.regex(
  /^https?:\/\/[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?(?::\d{2,5})?(?:[/?#]\S*)?$/i
);
import wootConstants from 'dashboard/constants/globals';
import { getI18nKey } from 'dashboard/routes/dashboard/settings/helper/settingsHelper';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';
import { useConfig } from 'dashboard/composables/useConfig';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';

const { EXAMPLE_WEBHOOK_URL } = wootConstants;

const SUPPORTED_WEBHOOK_EVENTS = [
  'conversation_created',
  'conversation_status_changed',
  'conversation_updated',
  'message_created',
  'message_updated',
  'webwidget_triggered',
  'contact_created',
  'contact_updated',
  'conversation_typing_on',
  'conversation_typing_off',
];

export default {
  components: {
    NextButton,
  },
  props: {
    value: {
      type: Object,
      default: () => ({}),
    },
    isSubmitting: {
      type: Boolean,
      default: false,
    },
    submitLabel: {
      type: String,
      required: true,
    },
  },
  emits: ['submit', 'cancel'],
  setup() {
    const { markDirty, markClean } = useUnsavedChanges();
    return { v$: useVuelidate(), markDirty, markClean };
  },
  validations: {
    url: {
      required,
      minLength: minLength(7),
      url: permissiveUrl,
    },
    subscriptions: {
      required,
    },
  },
  data() {
    const { inboxEventsEnabled } = useConfig();
    const conditions = this.value.conditions || {};
    const schedule = conditions.schedule || {};
    return {
      url: this.value.url || '',
      name: this.value.name || '',
      subscriptions: this.value.subscriptions || [],
      secretVisible: false,
      supportedWebhookEvents: inboxEventsEnabled
        ? [...SUPPORTED_WEBHOOK_EVENTS, 'inbox_updated']
        : SUPPORTED_WEBHOOK_EVENTS,
      // Reglas de entrega (Jabvox): limitar bandejas, excluir etiquetas, horario propio.
      allowedInboxIds: (conditions.allowed_inbox_ids || []).map(id => Number(id)),
      excludedLabels: conditions.excluded_labels || [],
      // Horario PROPIO de la regla (no el de la bandeja): días + franja.
      scheduleEnabled: !!schedule.enabled,
      scheduleDays:
        Array.isArray(schedule.days) && schedule.days.length
          ? schedule.days.map(d => Number(d))
          : [1, 2, 3, 4, 5],
      scheduleStart: schedule.start || '08:00',
      scheduleEnd: schedule.end || '18:00',
      // Estado de los desplegables de chips.
      inboxPickerOpen: false,
      labelPickerOpen: false,
      weekDays: [
        { value: 1, label: 'LUN' },
        { value: 2, label: 'MAR' },
        { value: 3, label: 'MIÉ' },
        { value: 4, label: 'JUE' },
        { value: 5, label: 'VIE' },
        { value: 6, label: 'SÁB' },
        { value: 0, label: 'DOM' },
      ],
    };
  },
  computed: {
    inboxes() {
      return this.$store.getters['inboxes/getInboxes'] || [];
    },
    labels() {
      return this.$store.getters['labels/getLabels'] || [];
    },
    selectedInboxes() {
      return this.inboxes.filter(i => this.allowedInboxIds.includes(i.id));
    },
    hasSecret() {
      return !!this.value.secret;
    },
    webhookURLInputPlaceholder() {
      return this.$t(
        'INTEGRATION_SETTINGS.WEBHOOK.FORM.END_POINT.PLACEHOLDER',
        {
          webhookExampleURL: EXAMPLE_WEBHOOK_URL,
        }
      );
    },
    webhookNameInputPlaceholder() {
      return this.$t('INTEGRATION_SETTINGS.WEBHOOK.FORM.NAME.PLACEHOLDER');
    },
  },
  mounted() {
    this.$store.dispatch('inboxes/get');
    this.$store.dispatch('labels/get');
    this.$watch(
      () => [
        this.url,
        this.name,
        this.subscriptions,
        this.allowedInboxIds,
        this.excludedLabels,
        this.scheduleEnabled,
        this.scheduleDays,
        this.scheduleStart,
        this.scheduleEnd,
      ],
      () => this.markDirty(),
      { deep: true }
    );
    this.$nextTick(() => this.markClean());
  },
  methods: {
    onSubmit() {
      this.markClean();
      this.$emit('submit', {
        url: this.url,
        name: this.name,
        subscriptions: this.subscriptions,
        conditions: {
          allowed_inbox_ids: this.allowedInboxIds,
          excluded_labels: this.excludedLabels,
          schedule: {
            enabled: this.scheduleEnabled,
            days: [...this.scheduleDays].sort((a, b) => a - b),
            start: this.scheduleStart,
            end: this.scheduleEnd,
          },
        },
      });
    },
    toggleInbox(id) {
      const idx = this.allowedInboxIds.indexOf(id);
      if (idx === -1) this.allowedInboxIds.push(id);
      else this.allowedInboxIds.splice(idx, 1);
    },
    toggleLabel(title) {
      const idx = this.excludedLabels.indexOf(title);
      if (idx === -1) this.excludedLabels.push(title);
      else this.excludedLabels.splice(idx, 1);
    },
    toggleDay(value) {
      const idx = this.scheduleDays.indexOf(value);
      if (idx === -1) this.scheduleDays.push(value);
      else this.scheduleDays.splice(idx, 1);
    },
    labelColor(title) {
      const found = this.labels.find(l => l.title === title);
      return found?.color || '#9CA3AF';
    },
    onCancel() {
      this.markClean();
      this.$emit('cancel');
    },
    async copySecret() {
      await copyTextToClipboard(this.value.secret);
      useAlert(this.$t('INTEGRATION_SETTINGS.WEBHOOK.SECRET.COPY_SUCCESS'));
    },
    getI18nKey,
  },
};
</script>

<template>
  <form class="flex flex-col w-full" @submit.prevent="onSubmit">
    <div class="w-full">
      <label :class="{ error: v$.url.$error }">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.END_POINT.LABEL') }}
        <input
          v-model="url"
          type="text"
          name="url"
          :placeholder="webhookURLInputPlaceholder"
          @input="v$.url.$touch"
        />
        <span v-if="v$.url.$error" class="message">
          {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.END_POINT.ERROR') }}
        </span>
      </label>
      <label>
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.NAME.LABEL') }}
        <input
          v-model="name"
          type="text"
          name="name"
          :placeholder="webhookNameInputPlaceholder"
        />
      </label>
      <label v-if="hasSecret" class="mb-4">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.SECRET.LABEL') }}
        <div class="flex items-center gap-2">
          <input
            :value="
              secretVisible ? value.secret : '••••••••••••••••••••••••••••••••'
            "
            type="text"
            readonly
            class="!mb-0 font-mono"
          />
          <NextButton
            v-tooltip.top="$t('INTEGRATION_SETTINGS.WEBHOOK.SECRET.TOGGLE')"
            type="button"
            :icon="secretVisible ? 'i-lucide-eye-off' : 'i-lucide-eye'"
            slate
            faded
            @click="secretVisible = !secretVisible"
          />
          <NextButton
            v-tooltip.top="$t('INTEGRATION_SETTINGS.WEBHOOK.SECRET.COPY')"
            type="button"
            icon="i-lucide-copy"
            slate
            faded
            @click="copySecret"
          />
        </div>
      </label>
      <label :class="{ error: v$.url.$error }" class="mb-2">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.LABEL') }}
      </label>
      <div class="flex flex-col gap-2.5 mb-4">
        <div
          v-for="event in supportedWebhookEvents"
          :key="event"
          class="flex items-center"
        >
          <input
            :id="event"
            v-model="subscriptions"
            type="checkbox"
            :value="event"
            name="subscriptions"
            class="mr-2"
          />
          <label :for="event" class="text-sm">
            {{
              `${$t(
                getI18nKey(
                  'INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.EVENTS',
                  event
                )
              )} (${event})`
            }}
          </label>
        </div>
      </div>

      <!-- Reglas de entrega (Jabvox): controlan cuándo se dispara este webhook.
           Vacías = se entrega siempre (comportamiento normal). Pensado para el Chat IA (Hermes). -->
      <div
        class="p-4 mt-4 border rounded-xl border-slate-100 dark:border-slate-700/60 bg-slate-25 dark:bg-slate-800/40"
      >
        <div class="flex items-center gap-2 mb-1">
          <span
            class="inline-flex items-center justify-center w-6 h-6 rounded-lg i-lucide-sliders-horizontal text-woot-500 bg-woot-50 dark:bg-woot-800/40"
          />
          <p class="text-sm font-semibold text-slate-800 dark:text-slate-100">
            {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.TITLE') }}
          </p>
        </div>
        <p class="mb-4 text-xs leading-relaxed text-slate-500 dark:text-slate-400">
          {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.DESCRIPTION') }}
        </p>

        <!-- Bandejas: chips + checklist desplegable (una o varias) -->
        <div class="mb-5">
          <p class="mb-1.5 text-sm font-medium text-slate-700 dark:text-slate-200">
            {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.ALLOWED_INBOXES.LABEL') }}
          </p>
          <div class="relative">
            <button
              type="button"
              class="flex flex-wrap items-center w-full gap-1.5 min-h-[40px] px-3 py-2 text-left bg-white border rounded-lg border-slate-200 dark:border-slate-700 dark:bg-slate-900 hover:border-woot-400 transition-colors"
              @click="inboxPickerOpen = !inboxPickerOpen"
            >
              <template v-if="selectedInboxes.length">
                <span
                  v-for="inbox in selectedInboxes"
                  :key="inbox.id"
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-md text-woot-700 bg-woot-50 dark:text-woot-100 dark:bg-woot-800/50"
                >
                  {{ inbox.name }}
                  <span
                    class="cursor-pointer i-lucide-x w-3 h-3 opacity-60 hover:opacity-100"
                    @click.stop="toggleInbox(inbox.id)"
                  />
                </span>
              </template>
              <span v-else class="text-sm text-slate-400">
                {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.ALLOWED_INBOXES.PLACEHOLDER') }}
              </span>
              <span
                class="ml-auto i-lucide-chevron-down w-4 h-4 text-slate-400 shrink-0"
              />
            </button>
            <div
              v-if="inboxPickerOpen"
              class="absolute z-20 w-full mt-1 overflow-y-auto bg-white border rounded-lg shadow-lg max-h-52 border-slate-200 dark:border-slate-700 dark:bg-slate-900"
            >
              <label
                v-for="inbox in inboxes"
                :key="inbox.id"
                class="flex items-center gap-2 px-3 py-2 text-sm cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-800 !mb-0"
              >
                <input
                  type="checkbox"
                  class="!mb-0"
                  :checked="allowedInboxIds.includes(inbox.id)"
                  @change="toggleInbox(inbox.id)"
                />
                <span class="text-slate-700 dark:text-slate-200">{{ inbox.name }}</span>
              </label>
              <p v-if="!inboxes.length" class="px-3 py-2 text-xs text-slate-400">
                {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.ALLOWED_INBOXES.EMPTY') }}
              </p>
            </div>
          </div>
          <span class="block mt-1 text-xs text-slate-500 dark:text-slate-400">
            {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.ALLOWED_INBOXES.HELP') }}
          </span>
        </div>

        <!-- Etiquetas excluidas: chips + checklist desplegable (una o varias) -->
        <div class="mb-5">
          <p class="mb-1.5 text-sm font-medium text-slate-700 dark:text-slate-200">
            {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.EXCLUDED_LABELS.LABEL') }}
          </p>
          <div class="relative">
            <button
              type="button"
              class="flex flex-wrap items-center w-full gap-1.5 min-h-[40px] px-3 py-2 text-left bg-white border rounded-lg border-slate-200 dark:border-slate-700 dark:bg-slate-900 hover:border-woot-400 transition-colors"
              @click="labelPickerOpen = !labelPickerOpen"
            >
              <template v-if="excludedLabels.length">
                <span
                  v-for="title in excludedLabels"
                  :key="title"
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-md text-slate-700 bg-slate-100 dark:text-slate-100 dark:bg-slate-700"
                >
                  <span
                    class="w-2 h-2 rounded-full shrink-0"
                    :style="{ backgroundColor: labelColor(title) }"
                  />
                  {{ title }}
                  <span
                    class="cursor-pointer i-lucide-x w-3 h-3 opacity-60 hover:opacity-100"
                    @click.stop="toggleLabel(title)"
                  />
                </span>
              </template>
              <span v-else class="text-sm text-slate-400">
                {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.EXCLUDED_LABELS.PLACEHOLDER') }}
              </span>
              <span
                class="ml-auto i-lucide-chevron-down w-4 h-4 text-slate-400 shrink-0"
              />
            </button>
            <div
              v-if="labelPickerOpen"
              class="absolute z-20 w-full mt-1 overflow-y-auto bg-white border rounded-lg shadow-lg max-h-52 border-slate-200 dark:border-slate-700 dark:bg-slate-900"
            >
              <label
                v-for="label in labels"
                :key="label.id"
                class="flex items-center gap-2 px-3 py-2 text-sm cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-800 !mb-0"
              >
                <input
                  type="checkbox"
                  class="!mb-0"
                  :checked="excludedLabels.includes(label.title)"
                  @change="toggleLabel(label.title)"
                />
                <span
                  class="w-2.5 h-2.5 rounded-full shrink-0"
                  :style="{ backgroundColor: label.color }"
                />
                <span class="text-slate-700 dark:text-slate-200">{{ label.title }}</span>
              </label>
              <p v-if="!labels.length" class="px-3 py-2 text-xs text-slate-400">
                {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.EXCLUDED_LABELS.EMPTY') }}
              </p>
            </div>
          </div>
          <span class="block mt-1 text-xs text-slate-500 dark:text-slate-400">
            {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.EXCLUDED_LABELS.HELP') }}
          </span>
        </div>

        <!-- Horario propio de la regla: toggle + días + franja -->
        <div
          class="p-3 border rounded-lg border-slate-100 dark:border-slate-700/50"
        >
          <label class="flex items-center gap-2.5 cursor-pointer !mb-0">
            <input
              v-model="scheduleEnabled"
              type="checkbox"
              class="!mb-0"
            />
            <span class="text-sm font-medium text-slate-700 dark:text-slate-200">
              {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.SCHEDULE.LABEL') }}
            </span>
          </label>

          <div v-if="scheduleEnabled" class="mt-3 pl-0.5">
            <!-- Días -->
            <p class="mb-1.5 text-xs font-medium text-slate-500 dark:text-slate-400">
              {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.SCHEDULE.DAYS') }}
            </p>
            <div class="flex flex-wrap gap-1.5 mb-4">
              <button
                v-for="day in weekDays"
                :key="day.value"
                type="button"
                class="w-11 h-9 text-xs font-semibold rounded-lg border transition-colors"
                :class="
                  scheduleDays.includes(day.value)
                    ? 'bg-woot-500 border-woot-500 text-white'
                    : 'bg-white dark:bg-slate-900 border-slate-200 dark:border-slate-700 text-slate-500 dark:text-slate-400 hover:border-woot-400'
                "
                @click="toggleDay(day.value)"
              >
                {{ day.label }}
              </button>
            </div>

            <!-- Franja horaria -->
            <div class="flex items-end gap-3">
              <label class="flex-1 !mb-0">
                <span class="block mb-1 text-xs font-medium text-slate-500 dark:text-slate-400">
                  {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.SCHEDULE.FROM') }}
                </span>
                <input v-model="scheduleStart" type="time" class="!mb-0" />
              </label>
              <span class="pb-2.5 text-slate-400">—</span>
              <label class="flex-1 !mb-0">
                <span class="block mb-1 text-xs font-medium text-slate-500 dark:text-slate-400">
                  {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.SCHEDULE.TO') }}
                </span>
                <input v-model="scheduleEnd" type="time" class="!mb-0" />
              </label>
            </div>
            <span class="block mt-2 text-xs text-slate-500 dark:text-slate-400">
              {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.RULES.SCHEDULE.HELP') }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
      <NextButton
        faded
        slate
        type="reset"
        :label="$t('INTEGRATION_SETTINGS.WEBHOOK.FORM.CANCEL')"
        @click.prevent="onCancel"
      />
      <NextButton
        type="submit"
        :disabled="v$.$invalid || isSubmitting"
        :is-loading="isSubmitting"
        :label="submitLabel"
      />
    </div>
  </form>
</template>
