<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { setColorTheme } from 'dashboard/helper/themeHelper';
import { normalizeSupportedLocale } from 'dashboard/helper/supportedLocale';

const { t, locale } = useI18n();
const { updateUISettings } = useUISettings();

const currentLanguage = computed(() => normalizeSupportedLocale(locale.value));
const savedTheme = LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';
const isDarkMode = ref(
  savedTheme === 'dark' ||
    (savedTheme === 'auto' &&
      window.matchMedia('(prefers-color-scheme: dark)').matches)
);

const changeLanguage = async language => {
  const saveSucceeded = await updateUISettings({ locale: language });

  if (saveSucceeded === false) {
    useAlert(
      t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.LANGUAGE.UPDATE_ERROR')
    );
    return;
  }

  locale.value = language;
};

const toggleAppearance = () => {
  const theme = isDarkMode.value ? 'light' : 'dark';
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_SCHEME, theme);
  setColorTheme(theme === 'dark');
  isDarkMode.value = theme === 'dark';
};
</script>

<template>
  <div class="flex items-center gap-1">
    <button
      v-for="language in ['es', 'en']"
      :key="language"
      type="button"
      class="grid size-8 place-items-center rounded-lg text-xs font-semibold transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :class="
        currentLanguage === language
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-10'
      "
      :aria-label="language === 'es' ? 'Español' : 'English'"
      :aria-pressed="currentLanguage === language"
      :title="language === 'es' ? 'Español' : 'English'"
      @click="changeLanguage(language)"
    >
      {{ language.toUpperCase() }}
    </button>
    <button
      type="button"
      class="grid size-9 place-items-center rounded-lg border border-n-weak bg-n-background text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-label="
        isDarkMode
          ? t('COMMAND_BAR.COMMANDS.LIGHT_MODE')
          : t('COMMAND_BAR.COMMANDS.DARK_MODE')
      "
      :title="
        isDarkMode
          ? t('COMMAND_BAR.COMMANDS.LIGHT_MODE')
          : t('COMMAND_BAR.COMMANDS.DARK_MODE')
      "
      @click="toggleAppearance"
    >
      <span
        :class="isDarkMode ? 'i-lucide-sun' : 'i-lucide-moon'"
        class="size-4"
        aria-hidden="true"
      />
    </button>
  </div>
</template>
