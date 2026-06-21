import { ref, unref, isRef, watch } from 'vue';
import { useEventListener } from '@vueuse/core';

/**
 * Warns the user before the page is reloaded or closed while a form has
 * unsaved changes. This protects form data against any kind of full reload
 * (session refresh, websocket reconnect, dev HMR, browser tab discarding, etc.)
 * by showing the browser's native "Leave site?" prompt — if the user cancels,
 * the reload is aborted and the data stays.
 *
 * Usage A (reactive flag): pass a ref/computed boolean.
 *   const isDirty = computed(() => !isEqual(form.value, original.value));
 *   useUnsavedChanges(isDirty);
 *
 * Usage B (manual control):
 *   const { markDirty, markClean } = useUnsavedChanges();
 *   // call markDirty() on first edit, markClean() after a successful save.
 *
 * @param {import('vue').Ref<boolean>|boolean} [source] reactive dirty flag (optional)
 * @returns {{ isDirty: import('vue').Ref<boolean>, markDirty: Function, markClean: Function }}
 */
export function useUnsavedChanges(source) {
  // Internal dirty state. If a ref/computed is passed, mirror it.
  const isDirty = ref(false);

  if (isRef(source)) {
    watch(
      source,
      value => {
        isDirty.value = !!value;
      },
      { immediate: true }
    );
  } else if (typeof source === 'boolean') {
    isDirty.value = source;
  }

  const markDirty = () => {
    isDirty.value = true;
  };
  const markClean = () => {
    isDirty.value = false;
  };

  // beforeunload only triggers the native prompt when the event is cancelled.
  // The listener is registered for the lifetime of the calling component and
  // auto-removed on unmount by useEventListener.
  useEventListener(window, 'beforeunload', event => {
    if (!unref(isDirty)) return undefined;
    event.preventDefault();
    // Required by some browsers to actually show the prompt.
    event.returnValue = '';
    return '';
  });

  return { isDirty, markDirty, markClean };
}
