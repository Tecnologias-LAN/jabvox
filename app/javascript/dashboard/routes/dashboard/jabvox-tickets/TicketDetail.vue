<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TicketBadges from './components/TicketBadges.vue';
import SlaCountdown from './components/SlaCountdown.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const ticket = useMapGetter('jabvoxTickets/getCurrentTicket');
const comments = useMapGetter('jabvoxTickets/getComments');
const uiFlags = useMapGetter('jabvoxTickets/getUIFlags');
const canResolve = useMapGetter('jabvoxTickets/canResolve');
const currentUserId = useMapGetter('getCurrentUserID');

const ticketId = computed(() => route.params.ticketId);
const commentBody = ref('');
const commentPrivate = ref(false);
const ratingValue = ref(0);
const ratingComment = ref('');
const resolution = ref('');
const resolutionType = ref('solved');
const showResolveBox = ref(false);
const showMergeBox = ref(false);
const mergeTargetId = ref('');

const STATUS_ACTIONS = ['in_progress', 'on_hold', 'closed'];
const RESOLUTION_TYPES = ['solved', 'duplicate', 'rejected'];

const isOwner = computed(
  () => ticket.value?.requester?.id === currentUserId.value
);
const canManage = computed(() => canResolve.value);
const isResolved = computed(() =>
  ['resolved', 'closed'].includes(ticket.value?.status)
);
const canRate = computed(
  () => isOwner.value && isResolved.value && !ticket.value?.satisfaction_rating
);

const load = async () => {
  await store.dispatch('jabvoxTickets/fetchTicket', ticketId.value);
  await store.dispatch('jabvoxTickets/fetchComments', ticketId.value);
};

const runAction = async (type, ...args) => {
  try {
    await store.dispatch('jabvoxTickets/runAction', {
      type,
      id: ticketId.value,
      args,
    });
    await store.dispatch('jabvoxTickets/fetchComments', ticketId.value);
    useAlert(t('JABVOX_TICKETS.DETAIL.UPDATED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_TICKETS.DETAIL.ERROR'));
  }
};

const submitResolve = async () => {
  await runAction('resolve', resolution.value, resolutionType.value);
  showResolveBox.value = false;
};

const submitComment = async () => {
  if (!commentBody.value.trim()) return;
  await store.dispatch('jabvoxTickets/addComment', {
    ticketId: ticketId.value,
    body: commentBody.value,
    isPrivate: commentPrivate.value,
  });
  commentBody.value = '';
  commentPrivate.value = false;
};

const submitRating = async () => {
  if (!ratingValue.value) return;
  await runAction('rate', ratingValue.value, ratingComment.value);
};

const submitMerge = async () => {
  const target = parseInt(mergeTargetId.value, 10);
  if (!target) return;
  try {
    await store.dispatch('jabvoxTickets/mergeTicket', {
      id: ticketId.value,
      targetId: target,
    });
    useAlert(t('JABVOX_TICKETS.MERGE.SUCCESS'));
    showMergeBox.value = false;
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('JABVOX_TICKETS.DETAIL.ERROR'));
  }
};

const fmtDate = iso => (iso ? new Date(iso).toLocaleString() : '—');
const goBack = () => router.push({ name: 'jabvox_tickets_index' });

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <div
      v-if="uiFlags.isFetchingOne || !ticket"
      class="flex items-center justify-center py-16"
    >
      <Spinner :size="24" />
    </div>
    <template v-else>
      <!-- Cabecera -->
      <header
        class="flex items-start justify-between px-6 py-4 border-b border-n-weak"
      >
        <div class="min-w-0">
          <button
            class="text-xs text-n-slate-10 hover:underline"
            @click="goBack"
          >
            {{ `← ${t('JABVOX_TICKETS.DETAIL.BACK')}` }}
          </button>
          <h1 class="text-lg font-semibold text-n-slate-12 mt-1">
            {{ `#${ticket.display_id} · ${ticket.title}` }}
          </h1>
          <div class="flex items-center gap-2 mt-2 flex-wrap">
            <TicketBadges kind="status" :value="ticket.status" />
            <TicketBadges kind="priority" :value="ticket.priority" />
            <TicketBadges kind="type" :value="ticket.category_type" />
            <SlaCountdown
              :status="ticket.sla_status"
              :minutes="ticket.minutes_to_due"
            />
            <span
              v-if="ticket.archived"
              class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-1 text-n-slate-10"
            >
              {{ t('JABVOX_TICKETS.ARCHIVED_TAG') }}
            </span>
          </div>
        </div>
        <!-- Acciones de gestión -->
        <div
          v-if="canManage"
          class="flex flex-wrap items-center gap-1 justify-end"
        >
          <Button
            v-for="st in STATUS_ACTIONS"
            :key="st"
            :label="t(`JABVOX_TICKETS.STATUS.${st.toUpperCase()}`)"
            size="xs"
            variant="outline"
            color="slate"
            @click="runAction('changeStatus', st)"
          />
          <Button
            v-if="!isResolved"
            :label="t('JABVOX_TICKETS.DETAIL.RESOLVE')"
            size="xs"
            @click="showResolveBox = true"
          />
          <Button
            v-if="isResolved"
            :label="t('JABVOX_TICKETS.DETAIL.REOPEN')"
            size="xs"
            variant="outline"
            color="ruby"
            @click="runAction('reopen')"
          />
          <Button
            :label="t('JABVOX_TICKETS.MERGE.ACTION')"
            icon="i-lucide-git-merge"
            size="xs"
            variant="outline"
            color="slate"
            @click="showMergeBox = !showMergeBox"
          />
        </div>
      </header>

      <!-- Caja de fusión (duplicados) -->
      <div
        v-if="showMergeBox && canManage"
        class="px-6 py-3 border-b border-n-weak flex flex-wrap items-center gap-2 bg-n-alpha-1"
      >
        <span class="text-sm text-n-slate-11">
          {{ t('JABVOX_TICKETS.MERGE.HINT') }}
        </span>
        <input
          v-model="mergeTargetId"
          type="number"
          :placeholder="t('JABVOX_TICKETS.MERGE.PLACEHOLDER')"
          class="text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-n-slate-12 w-40"
        />
        <Button
          :label="t('JABVOX_TICKETS.MERGE.ACTION')"
          size="xs"
          @click="submitMerge"
        />
      </div>

      <div class="flex-1 overflow-y-auto px-6 py-4 grid md:grid-cols-3 gap-6">
        <!-- Columna principal -->
        <div class="md:col-span-2 flex flex-col gap-5">
          <section class="rounded-lg border border-n-weak p-4">
            <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
              {{ ticket.description || '—' }}
            </p>
          </section>

          <!-- Caja de resolución -->
          <section
            v-if="showResolveBox"
            class="rounded-lg border border-n-weak p-4 flex flex-col gap-2"
          >
            <select
              v-model="resolutionType"
              class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            >
              <option v-for="rt in RESOLUTION_TYPES" :key="rt" :value="rt">
                {{ t(`JABVOX_TICKETS.RESOLUTION_TYPE.${rt.toUpperCase()}`) }}
              </option>
            </select>
            <textarea
              v-model="resolution"
              rows="3"
              :placeholder="t('JABVOX_TICKETS.DETAIL.RESOLUTION_PLACEHOLDER')"
              class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            />
            <div class="flex justify-end gap-2">
              <Button
                :label="t('JABVOX_TICKETS.FORM.CANCEL')"
                size="xs"
                variant="outline"
                color="slate"
                @click="showResolveBox = false"
              />
              <Button
                :label="t('JABVOX_TICKETS.DETAIL.RESOLVE')"
                size="xs"
                @click="submitResolve"
              />
            </div>
          </section>

          <!-- Encuesta de satisfacción -->
          <section
            v-if="canRate"
            class="rounded-lg border border-n-weak p-4 flex flex-col gap-2"
          >
            <h4 class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_TICKETS.DETAIL.RATE_TITLE') }}
            </h4>
            <div class="flex items-center gap-1">
              <button
                v-for="n in 5"
                :key="n"
                class="text-xl"
                :class="n <= ratingValue ? 'text-n-amber-11' : 'text-n-slate-8'"
                @click="ratingValue = n"
              >
                {{ '★' }}
              </button>
            </div>
            <textarea
              v-model="ratingComment"
              rows="2"
              :placeholder="t('JABVOX_TICKETS.DETAIL.RATE_COMMENT')"
              class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            />
            <div class="flex justify-end">
              <Button
                :label="t('JABVOX_TICKETS.DETAIL.SEND_RATING')"
                size="xs"
                :disabled="!ratingValue"
                @click="submitRating"
              />
            </div>
          </section>

          <!-- Comentarios -->
          <section class="flex flex-col gap-3">
            <h4 class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_TICKETS.DETAIL.COMMENTS') }}
            </h4>
            <div
              v-for="c in comments"
              :key="c.id"
              class="rounded-lg border p-3"
              :class="
                c.private ? 'border-n-amber-6 bg-n-amber-2' : 'border-n-weak'
              "
            >
              <div
                class="flex items-center justify-between text-xs text-n-slate-10"
              >
                <span class="font-medium text-n-slate-12">{{
                  c.user?.name
                }}</span>
                <span>
                  <span v-if="c.private" class="text-n-amber-11 mr-1">
                    {{ t('JABVOX_TICKETS.DETAIL.INTERNAL_NOTE') }}
                  </span>
                  {{ fmtDate(c.created_at) }}
                </span>
              </div>
              <p class="text-sm text-n-slate-12 mt-1 whitespace-pre-wrap">
                {{ c.body }}
              </p>
            </div>

            <div
              class="flex flex-col gap-2 rounded-lg border border-n-weak p-3"
            >
              <textarea
                v-model="commentBody"
                rows="2"
                :placeholder="t('JABVOX_TICKETS.DETAIL.COMMENT_PLACEHOLDER')"
                class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
              />
              <div class="flex items-center justify-between">
                <label
                  v-if="canManage"
                  class="flex items-center gap-1 text-xs text-n-slate-11"
                >
                  <input v-model="commentPrivate" type="checkbox" />
                  {{ t('JABVOX_TICKETS.DETAIL.PRIVATE_NOTE') }}
                </label>
                <Button
                  :label="t('JABVOX_TICKETS.DETAIL.ADD_COMMENT')"
                  size="xs"
                  :disabled="!commentBody.trim()"
                  @click="submitComment"
                />
              </div>
            </div>
          </section>
        </div>

        <!-- Columna lateral: datos + timeline -->
        <div class="flex flex-col gap-4">
          <section class="rounded-lg border border-n-weak p-4 text-sm">
            <dl class="flex flex-col gap-2">
              <div class="flex justify-between">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.COLS.REQUESTER') }}
                </dt>
                <dd class="text-n-slate-12">{{ ticket.requester?.name }}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.COLS.ASSIGNEE') }}
                </dt>
                <dd class="text-n-slate-12">
                  {{ ticket.assignee?.name || '—' }}
                </dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.DETAIL.CATEGORY') }}
                </dt>
                <dd class="text-n-slate-12">
                  {{ ticket.category?.name || '—' }}
                </dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.DETAIL.DUE') }}
                </dt>
                <dd class="text-n-slate-12">{{ fmtDate(ticket.due_at) }}</dd>
              </div>
              <div
                v-if="ticket.satisfaction_rating"
                class="flex justify-between"
              >
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.DETAIL.SATISFACTION') }}
                </dt>
                <dd class="text-n-amber-11">
                  {{ `${ticket.satisfaction_rating}/5` }}
                </dd>
              </div>
            </dl>
          </section>

          <section class="rounded-lg border border-n-weak p-4">
            <h4 class="text-sm font-medium text-n-slate-12 mb-2">
              {{ t('JABVOX_TICKETS.DETAIL.TIMELINE') }}
            </h4>
            <ul class="flex flex-col gap-2 text-xs">
              <li
                v-for="a in ticket.activities"
                :key="a.id"
                class="text-n-slate-11"
              >
                <span class="text-n-slate-12">{{
                  a.user_name || t('JABVOX_TICKETS.DETAIL.SYSTEM')
                }}</span>
                —
                {{
                  t(
                    `JABVOX_TICKETS.ACTIVITY.${a.action.toUpperCase()}`,
                    a.action
                  )
                }}
                <span class="text-n-slate-9">
                  {{ `· ${fmtDate(a.created_at)}` }}
                </span>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </template>
  </div>
</template>
