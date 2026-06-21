import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

// Standardised error surfacing for the Analytics module: shows the server-provided
// message when present, otherwise a generic fallback.
export function useAnalyticsError() {
  const { t } = useI18n();

  const showError = (error, fallback) => {
    const serverMessage = error?.response?.data?.error;
    useAlert(serverMessage || fallback || t('JABVOX_ANALYTICS.COMMON.RETRY'));
  };

  return { showError };
}
