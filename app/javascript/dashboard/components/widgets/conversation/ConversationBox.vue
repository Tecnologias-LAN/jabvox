<script>
import { mapGetters } from 'vuex';
import ConversationHeader from './ConversationHeader.vue';
import DashboardAppFrame from '../DashboardApp/Frame.vue';
import EmptyState from './EmptyState/EmptyState.vue';
import MessagesView from './MessagesView.vue';
import JabvoxConversationProducts from './jabvox/JabvoxConversationProducts.vue';
import JabvoxConversationHistory from './jabvox/JabvoxConversationHistory.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

export default {
  components: {
    ConversationHeader,
    DashboardAppFrame,
    EmptyState,
    MessagesView,
    JabvoxConversationProducts,
    JabvoxConversationHistory,
  },
  props: {
    inboxId: {
      type: [Number, String],
      default: '',
      required: false,
    },
    isInboxView: {
      type: Boolean,
      default: false,
    },
    isContactPanelOpen: {
      type: Boolean,
      default: true,
    },
    isOnExpandedLayout: {
      type: Boolean,
      default: true,
    },
  },
  data() {
    return {
      activeIndex: 0,
      jabvoxTab: 'chat',
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      dashboardApps: 'dashboardApps/getRecords',
      getCurrentAccountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    isJabvoxProductsEnabled() {
      return this.isFeatureEnabledonAccount(
        this.getCurrentAccountId,
        FEATURE_FLAGS.JABVOX_PRODUCTS
      );
    },
    jabvoxTabs() {
      return [
        {
          key: 'chat',
          label: this.$t('JABVOX_PRODUCTS.CONVERSATION.TAB_CHAT'),
          icon: 'i-lucide-message-circle',
        },
        {
          key: 'products',
          label: this.$t('JABVOX_PRODUCTS.CONVERSATION.TAB_PRODUCTS'),
          icon: 'i-lucide-shopping-cart',
        },
        {
          key: 'history',
          label: this.$t('JABVOX_PRODUCTS.CONVERSATION.TAB_HISTORY'),
          icon: 'i-lucide-clock',
        },
      ];
    },
    dashboardAppTabs() {
      return [
        {
          key: 'messages',
          index: 0,
          name: this.$t('CONVERSATION.DASHBOARD_APP_TAB_MESSAGES'),
        },
        ...this.dashboardApps.map((dashboardApp, index) => ({
          key: `dashboard-${dashboardApp.id}`,
          index: index + 1,
          name: dashboardApp.title,
        })),
      ];
    },
    showContactPanel() {
      return this.isContactPanelOpen && this.currentChat.id;
    },
    currentContactId() {
      return this.currentChat?.meta?.sender?.id;
    },
  },
  watch: {
    'currentChat.inbox_id': {
      immediate: true,
      handler(inboxId) {
        if (inboxId) {
          this.$store.dispatch('inboxAssignableAgents/fetch', [inboxId]);
        }
      },
    },
    'currentChat.id'() {
      this.fetchLabels();
      this.activeIndex = 0;
      this.jabvoxTab = 'chat';
    },
  },
  mounted() {
    this.fetchLabels();
    this.$store.dispatch('dashboardApps/get');
  },
  methods: {
    fetchLabels() {
      if (!this.currentChat.id) {
        return;
      }
      this.$store.dispatch('conversationLabels/get', this.currentChat.id);
    },
    onDashboardAppTabChange(index) {
      this.activeIndex = index;
    },
  },
};
</script>

<template>
  <div
    class="conversation-details-wrap flex flex-col min-w-0 w-full bg-n-surface-1 relative"
    :class="{
      'border-l rtl:border-l-0 rtl:border-r border-n-weak': !isOnExpandedLayout,
    }"
  >
    <ConversationHeader
      v-if="currentChat.id"
      :chat="currentChat"
      :show-back-button="isOnExpandedLayout && !isInboxView"
      :class="{
        'border-b border-b-n-weak !pt-2': !dashboardApps.length,
      }"
    />

    <!-- Jabvox product tabs: Chat | Products | History -->
    <div
      v-if="isJabvoxProductsEnabled && currentChat.id"
      class="flex shrink-0 border-b border-slate-200 dark:border-slate-700 overflow-x-auto"
    >
      <button
        v-for="tab in jabvoxTabs"
        :key="tab.key"
        class="flex items-center gap-1.5 px-5 py-2.5 text-sm font-medium border-b-2 whitespace-nowrap transition-colors"
        :class="[
          jabvoxTab === tab.key
            ? 'border-woot-600 text-woot-600'
            : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300',
        ]"
        @click="jabvoxTab = tab.key"
      >
        <i :class="tab.icon" />
        {{ tab.label }}
      </button>
    </div>

    <!-- Chat tab (or full chat when jabvox not enabled) -->
    <template v-if="!isJabvoxProductsEnabled || jabvoxTab === 'chat'">
      <woot-tabs
        v-if="dashboardApps.length && currentChat.id"
        :index="activeIndex"
        class="h-10"
        @change="onDashboardAppTabChange"
      >
        <woot-tabs-item
          v-for="tab in dashboardAppTabs"
          :key="tab.key"
          :index="tab.index"
          :name="tab.name"
          :show-badge="false"
          is-compact
        />
      </woot-tabs>
      <div v-show="!activeIndex" class="flex h-full min-h-0 m-0">
        <MessagesView
          v-if="currentChat.id"
          :inbox-id="inboxId"
          :is-inbox-view="isInboxView"
        />
        <EmptyState
          v-if="!currentChat.id && !isInboxView"
          :is-on-expanded-layout="isOnExpandedLayout"
        />
        <slot />
      </div>
      <DashboardAppFrame
        v-for="(dashboardApp, index) in dashboardApps"
        v-show="activeIndex - 1 === index"
        :key="currentChat.id + '-' + dashboardApp.id"
        :is-visible="activeIndex - 1 === index"
        :config="dashboardApps[index].content"
        :position="index"
        :current-chat="currentChat"
      />
    </template>

    <!-- Products tab -->
    <JabvoxConversationProducts
      v-else-if="jabvoxTab === 'products'"
      :contact-id="currentContactId"
      :conversation-id="currentChat.id"
    />

    <!-- History tab -->
    <JabvoxConversationHistory
      v-else-if="jabvoxTab === 'history'"
      :contact-id="currentContactId"
      :conversation-id="currentChat.id"
    />
  </div>
</template>
