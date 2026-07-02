import { computed } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';

/**
 * Front-end mirror of the backend `JabvoxPermissions` concern: a capability is
 * granted when the current account user is an administrator OR their custom
 * role includes the permission key. Used to show/hide Jabvox sidebar entries
 * and settings so the UI matches what the backend actually authorizes.
 *
 * @returns {{ jabvoxCan: (key: string) => boolean }}
 */
export function useJabvoxPermissions() {
  const getters = useStoreGetters();

  const isAdmin = computed(
    () => getters.getCurrentRole.value === 'administrator'
  );

  const permissions = computed(() =>
    getUserPermissions(
      getters.getCurrentUser.value,
      getters.getCurrentAccountId.value
    )
  );

  // Admins pass everything; otherwise the custom role must grant the key.
  const jabvoxCan = key => isAdmin.value || permissions.value.includes(key);

  return { jabvoxCan };
}
