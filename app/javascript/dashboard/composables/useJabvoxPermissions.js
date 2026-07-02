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

  const permissions = computed(() => {
    const user = getters.getCurrentUser.value;
    const accountId = getters.getCurrentAccountId.value;
    // During an account switch the user/accounts can be momentarily missing;
    // guard so the sidebar never throws (which would blank the whole app).
    if (!user?.accounts || !accountId) return [];

    return getUserPermissions(user, accountId) || [];
  });

  // Admins pass everything; otherwise the custom role must grant the key.
  const jabvoxCan = key => isAdmin.value || permissions.value.includes(key);

  return { jabvoxCan };
}
