<script>
import Avatar from 'next/avatar/Avatar.vue';
import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { mapGetters } from 'vuex';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    Avatar,
    Spinner,
    EmptyState,
    NextButton,
  },
  props: {
    notifications: {
      type: Array,
      default: () => [],
    },
    isLoading: {
      type: Boolean,
      default: false,
    },
    isUpdating: {
      type: Boolean,
      default: false,
    },
    onClickNotification: {
      type: Function,
      default: () => {},
    },
    onMarkAllDoneClick: {
      type: Function,
      default: () => {},
    },
  },
  computed: {
    ...mapGetters({
      notificationMetadata: 'notifications/getMeta',
    }),
    showEmptyResult() {
      return !this.isLoading && this.notifications.length === 0;
    },
  },
  methods: {
    dynamicTime,
    notificationTitle(notification) {
      if (notification.meta?.title) return notification.meta.title;
      const actor = notification.primary_actor;
      return actor
        ? `#${actor.display_id || actor.id}`
        : this.$t('NOTIFICATIONS_PAGE.DELETE_TITLE');
    },
    notificationBody(notification) {
      if (notification.meta?.body) return notification.meta.body;
      if (notification.notification_type === 'jabvox_task_reminder') {
        return (
          notification.push_message_body || notification.push_message_title
        );
      }
      return notification.push_message_title || notification.push_message_body;
    },
    notificationTypeLabel(notification) {
      const key = `NOTIFICATIONS_PAGE.TYPE_LABEL.${notification.notification_type}`;
      // notification_type is a server enum with matching locale keys.
      // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
      const label = this.$t(key);
      return label === key
        ? notification.meta?.module || notification.notification_type
        : label;
    },
  },
};
</script>

<template>
  <section
    class="flex-grow flex-shrink h-full px-4 py-8 overflow-hidden bg-n-background"
  >
    <div class="flex w-full items-center justify-between gap-2 mb-4">
      <h6 class="text-xl font-medium text-n-slate-12">
        {{ $t('NOTIFICATIONS_PAGE.HEADER') }}
      </h6>
      <NextButton
        v-if="notificationMetadata.unreadCount"
        type="submit"
        sm
        :label="$t('NOTIFICATIONS_PAGE.MARK_ALL_DONE')"
        :is-loading="isUpdating"
        @click="onMarkAllDoneClick"
      />
    </div>
    <table class="notifications-table overflow-auto">
      <tbody v-show="!isLoading">
        <tr
          v-for="notificationItem in notifications"
          :key="notificationItem.id"
          :class="{
            'is-unread': notificationItem.read_at === null,
          }"
          class="border-b border-n-weak"
          @click="() => onClickNotification(notificationItem)"
        >
          <td class="p-2.5 text-n-slate-12">
            <div
              class="overflow-hidden flex-view notification-contant--wrap whitespace-nowrap text-ellipsis"
            >
              <div class="flex items-center gap-2">
                <span
                  v-if="notificationItem.meta?.module"
                  class="notification--module"
                >
                  {{ notificationTypeLabel(notificationItem) }}
                </span>
                <h5 class="notification--title">
                  {{
                    notificationTitle(notificationItem) ||
                    `#${
                      notificationItem.primary_actor?.display_id ||
                      notificationItem.primary_actor?.id ||
                      $t('NOTIFICATIONS_PAGE.DELETE_TITLE')
                    }`
                  }}
                </h5>
              </div>
              <span
                class="overflow-hidden notification--message-title whitespace-nowrap text-ellipsis"
              >
                {{ notificationBody(notificationItem) }}
              </span>
            </div>
          </td>
          <td class="text-right">
            <span
              v-if="!notificationItem.meta?.module"
              class="notification--type"
            >
              {{ notificationTypeLabel(notificationItem) }}
            </span>
          </td>
          <td class="thumbnail--column">
            <Avatar
              v-if="notificationItem.primary_actor?.meta?.assignee"
              :src="notificationItem.primary_actor.meta.assignee.thumbnail"
              :size="28"
              :name="notificationItem.primary_actor.meta.assignee.name"
              rounded-full
            />
          </td>
          <td>
            <div class="text-right timestamp--column ltr:mr-2 rtl:ml-2">
              <span class="notification--created-at">
                {{ dynamicTime(notificationItem.last_activity_at) }}
              </span>
            </div>
          </td>
          <td>
            <div
              v-if="!notificationItem.read_at"
              class="notification--unread-indicator"
            />
          </td>
        </tr>
      </tbody>
    </table>
    <EmptyState
      v-if="showEmptyResult"
      :title="$t('NOTIFICATIONS_PAGE.LIST.404')"
    />
    <div v-if="isLoading" class="notifications--loader">
      <Spinner />
      <span>{{ $t('NOTIFICATIONS_PAGE.LIST.LOADING_MESSAGE') }}</span>
    </div>
  </section>
</template>

<style lang="scss" scoped>
.notification--title {
  @apply text-sm m-0 text-n-slate-12;
}

.notification--module {
  @apply inline-flex items-center rounded-full bg-n-brand/10 px-2 py-0.5 text-[10px] font-medium text-n-brand;
}

.notifications-table {
  > tbody {
    > tr {
      @apply cursor-pointer;

      &:hover {
        @apply bg-n-slate-3;
      }

      &.is-active {
        @apply bg-n-slate-4 dark:bg-n-slate-6;
      }

      > td {
        &.conversation-count-item {
          @apply pl-6 rtl:pl-0 rtl:pr-6;
        }
      }

      &:last-child {
        @apply border-b-0;
      }
    }
  }
}

.is-unread {
  @apply font-semibold;
}

.notifications--loader {
  @apply text-base flex items-center justify-center p-10;
}

.notification--unread-indicator {
  @apply w-2.5 h-2.5 rounded-full bg-n-brand;
}

.notification--created-at {
  @apply text-n-slate-11 text-xs;
}

.notification--type {
  @apply text-xs;
}

.thumbnail--column {
  @apply w-[3.25rem];
}

.timestamp--column {
  @apply min-w-[9.125rem] text-right;
}

.notification-contant--wrap {
  @apply flex-col max-w-[31.25rem];
}

.notification--message-title {
  @apply text-n-slate-12;
}
</style>
