<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import TicketBadges from './components/TicketBadges.vue';
import SlaCountdown from './components/SlaCountdown.vue';
import {
  humanizeMinutes,
  minutesSince,
  minutesBetween,
} from './helper/ticketTime';

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
const commentImages = ref([]);
const commentFileInput = ref(null);
const ratingValue = ref(0);
const ratingComment = ref('');
const resolution = ref('');
const resolutionType = ref('solved');
const showResolveBox = ref(false);
const showMergeBox = ref(false);
const mergeTargetId = ref('');

const STATUS_ACTIONS = ['in_progress', 'on_hold', 'closed'];
const RESOLUTION_TYPES = ['solved', 'duplicate', 'rejected'];

// Íconos por acción para el timeline vertical.
const ACTIVITY_ICONS = {
  assigned: 'i-lucide-user-check',
  status_changed: 'i-lucide-refresh-cw',
  resolved: 'i-lucide-check-circle-2',
  reopened: 'i-lucide-rotate-ccw',
  rated: 'i-lucide-star',
  sla_escalated: 'i-lucide-alarm-clock',
  archived: 'i-lucide-archive',
  restored: 'i-lucide-archive-restore',
  merged_into: 'i-lucide-git-merge',
  merge_received: 'i-lucide-git-merge',
  created: 'i-lucide-plus-circle',
};
const activityIcon = action => ACTIVITY_ICONS[action] || 'i-lucide-circle-dot';

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

// Tiempos: abierto desde creación / total de resolución.
const openFor = computed(() =>
  ticket.value
    ? humanizeMinutes(minutesSince(ticket.value.created_at) ?? 0)
    : '—'
);
const resolutionTime = computed(() => {
  if (!ticket.value?.resolved_at) return null;
  const mins = minutesBetween(
    ticket.value.created_at,
    ticket.value.resolved_at
  );
  return mins === null ? null : humanizeMinutes(mins);
});

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
  if (!commentBody.value.trim() && !commentImages.value.length) return;
  await store.dispatch('jabvoxTickets/addComment', {
    ticketId: ticketId.value,
    body: commentBody.value || ' ',
    isPrivate: commentPrivate.value,
    images: commentImages.value,
  });
  commentBody.value = '';
  commentPrivate.value = false;
  commentImages.value = [];
};

// Adjuntos de comentario: SOLO imágenes, con preview local.
const pickCommentImages = () => commentFileInput.value?.click();
const onCommentImages = e => {
  const incoming = Array.from(e.target.files || []);
  const images = incoming.filter(f => f.type.startsWith('image/'));
  if (images.length < incoming.length) {
    useAlert(t('JABVOX_TICKETS.WIZARD.ONLY_IMAGES'));
  }
  commentImages.value = [...commentImages.value, ...images];
  e.target.value = '';
};
const removeCommentImage = idx => {
  commentImages.value = commentImages.value.filter((_, i) => i !== idx);
};
const commentPreviewCache = new WeakMap();
const commentPreview = file => {
  if (!commentPreviewCache.has(file))
    commentPreviewCache.set(file, URL.createObjectURL(file));
  return commentPreviewCache.get(file);
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
  <div class="flex flex-col h-full overflow-hidden bg-n-background">
    <div
      v-if="uiFlags.isFetchingOne || !ticket"
      class="flex items-center justify-center py-16"
    >
      <Spinner :size="24" />
    </div>
    <template v-else>
      <!-- Cabecera -->
      <header
        class="flex items-start justify-between gap-3 px-4 sm:px-6 py-4 border-b border-n-weak"
      >
        <div class="min-w-0">
          <button
            class="inline-flex items-center gap-1 text-xs text-n-slate-10 hover:text-n-slate-12 transition-colors mb-1.5 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand rounded"
            @click="goBack"
          >
            <span class="i-lucide-arrow-left w-3.5 h-3.5" aria-hidden="true" />
            {{ t('JABVOX_TICKETS.DETAIL.BACK') }}
          </button>
          <h1
            class="text-lg font-semibold text-n-slate-12 flex items-baseline gap-2"
          >
            <span class="text-n-slate-10 tabular-nums shrink-0">
              {{ `#${ticket.display_id}` }}
            </span>
            <span class="truncate">{{ ticket.title }}</span>
          </h1>
          <div class="flex items-center gap-2 mt-2 flex-wrap">
            <TicketBadges kind="status" :value="ticket.status" />
            <TicketBadges kind="priority" :value="ticket.priority" />
            <TicketBadges kind="type" :value="ticket.category_type" />
            <span
              v-if="ticket.archived"
              class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-1 text-n-slate-10"
            >
              {{ t('JABVOX_TICKETS.ARCHIVED_TAG') }}
            </span>
          </div>
        </div>
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
            icon="i-lucide-check"
            size="xs"
            @click="showResolveBox = true"
          />
          <Button
            v-if="isResolved"
            :label="t('JABVOX_TICKETS.DETAIL.REOPEN')"
            icon="i-lucide-rotate-ccw"
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

      <!-- Caja de fusión -->
      <div
        v-if="showMergeBox && canManage"
        class="px-4 sm:px-6 py-3 border-b border-n-weak flex flex-wrap items-center gap-2 bg-n-alpha-1"
      >
        <span class="text-sm text-n-slate-11">
          {{ t('JABVOX_TICKETS.MERGE.HINT') }}
        </span>
        <input
          v-model="mergeTargetId"
          type="number"
          :placeholder="t('JABVOX_TICKETS.MERGE.PLACEHOLDER')"
          class="text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-n-slate-12 w-40 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
        />
        <Button
          :label="t('JABVOX_TICKETS.MERGE.ACTION')"
          size="xs"
          @click="submitMerge"
        />
      </div>

      <div
        class="flex-1 overflow-y-auto px-4 sm:px-6 py-5 grid lg:grid-cols-3 gap-5"
      >
        <!-- ===== Columna principal ===== -->
        <div class="lg:col-span-2 flex flex-col gap-5">
          <!-- Descripción -->
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
          >
            <h4
              class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2"
            >
              <span
                class="i-lucide-align-left w-3.5 h-3.5"
                aria-hidden="true"
              />
              {{ t('JABVOX_TICKETS.FORM.DESCRIPTION') }}
            </h4>
            <p
              class="text-sm text-n-slate-12 whitespace-pre-wrap leading-relaxed"
            >
              {{ ticket.description || '—' }}
            </p>
            <ul
              v-if="ticket.attachments?.length"
              class="flex flex-wrap gap-2 mt-4"
            >
              <li v-for="att in ticket.attachments" :key="att.id">
                <a
                  :href="att.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-n-alpha-1 text-xs text-n-slate-11 hover:text-n-slate-12 transition-colors"
                >
                  <span
                    class="i-lucide-paperclip w-3.5 h-3.5"
                    aria-hidden="true"
                  />
                  {{ att.filename }}
                </a>
              </li>
            </ul>
          </section>

          <!-- Caja de resolución -->
          <section
            v-if="showResolveBox"
            class="rounded-2xl border border-n-brand/30 bg-n-brand/5 p-5 flex flex-col gap-3 tk-fade"
          >
            <h4 class="text-sm font-semibold text-n-slate-12">
              {{ t('JABVOX_TICKETS.DETAIL.RESOLVE') }}
            </h4>
            <select
              v-model="resolutionType"
              class="text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12"
            >
              <option v-for="rt in RESOLUTION_TYPES" :key="rt" :value="rt">
                {{ t(`JABVOX_TICKETS.RESOLUTION_TYPE.${rt.toUpperCase()}`) }}
              </option>
            </select>
            <textarea
              v-model="resolution"
              rows="3"
              :placeholder="t('JABVOX_TICKETS.DETAIL.RESOLUTION_PLACEHOLDER')"
              class="text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
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
            class="rounded-2xl border border-n-amber-6/40 bg-n-amber-2/50 p-5 flex flex-col gap-3 tk-fade"
          >
            <h4 class="text-sm font-semibold text-n-slate-12">
              {{ t('JABVOX_TICKETS.DETAIL.RATE_TITLE') }}
            </h4>
            <div class="flex items-center gap-1" role="radiogroup">
              <button
                v-for="n in 5"
                :key="n"
                class="transition-transform hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand rounded"
                :class="n <= ratingValue ? 'text-n-amber-11' : 'text-n-slate-8'"
                :aria-label="`${n}/5`"
                :aria-checked="n === ratingValue"
                role="radio"
                @click="ratingValue = n"
              >
                <span class="i-lucide-star w-6 h-6" aria-hidden="true" />
              </button>
            </div>
            <textarea
              v-model="ratingComment"
              rows="2"
              :placeholder="t('JABVOX_TICKETS.DETAIL.RATE_COMMENT')"
              class="text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12"
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
            <h4
              class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
            >
              <span
                class="i-lucide-messages-square w-4 h-4"
                aria-hidden="true"
              />
              {{ t('JABVOX_TICKETS.DETAIL.COMMENTS') }}
            </h4>
            <div
              v-for="c in comments"
              :key="c.id"
              class="flex gap-3 rounded-2xl border p-3.5"
              :class="
                c.private
                  ? 'border-n-amber-6/50 bg-n-amber-2/40'
                  : 'border-n-weak bg-n-solid-1'
              "
            >
              <Avatar :name="c.user?.name || '?'" :size="30" class="shrink-0" />
              <div class="min-w-0 flex-1">
                <div class="flex items-center justify-between gap-2 text-xs">
                  <span class="font-medium text-n-slate-12">
                    {{ c.user?.name }}
                  </span>
                  <span
                    class="flex items-center gap-1 text-n-slate-10 shrink-0"
                  >
                    <span
                      v-if="c.private"
                      class="inline-flex items-center gap-0.5 text-n-amber-11 font-medium"
                    >
                      <span class="i-lucide-lock w-3 h-3" aria-hidden="true" />
                      {{ t('JABVOX_TICKETS.DETAIL.INTERNAL_NOTE') }}
                    </span>
                    {{ fmtDate(c.created_at) }}
                  </span>
                </div>
                <p
                  class="text-sm text-n-slate-12 mt-1 whitespace-pre-wrap leading-relaxed"
                >
                  {{ c.body }}
                </p>
                <div
                  v-if="c.attachments?.length"
                  class="flex flex-wrap gap-2 mt-2"
                >
                  <a
                    v-for="att in c.attachments"
                    :key="att.id"
                    :href="att.url"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="block w-20 h-20 rounded-lg overflow-hidden border border-n-weak hover:ring-2 hover:ring-n-brand/40 transition-all"
                  >
                    <img
                      :src="att.url"
                      :alt="att.filename"
                      class="w-full h-full object-cover"
                    />
                  </a>
                </div>
              </div>
            </div>

            <!-- Nuevo comentario -->
            <div
              class="flex flex-col gap-2 rounded-2xl border border-n-weak bg-n-solid-1 p-3.5"
              :class="commentPrivate ? 'ring-1 ring-n-amber-6/40' : ''"
            >
              <textarea
                v-model="commentBody"
                rows="2"
                :placeholder="
                  commentPrivate
                    ? t('JABVOX_TICKETS.DETAIL.PRIVATE_PLACEHOLDER')
                    : t('JABVOX_TICKETS.DETAIL.COMMENT_PLACEHOLDER')
                "
                class="text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand/40"
              />

              <!-- Preview de imágenes a adjuntar -->
              <ul v-if="commentImages.length" class="flex flex-wrap gap-2">
                <li
                  v-for="(img, idx) in commentImages"
                  :key="`${img.name}-${idx}`"
                  class="relative group w-16 h-16 rounded-lg overflow-hidden border border-n-weak"
                >
                  <img
                    :src="commentPreview(img)"
                    :alt="img.name"
                    class="w-full h-full object-cover"
                  />
                  <button
                    type="button"
                    class="absolute top-0.5 right-0.5 flex items-center justify-center w-4 h-4 rounded-full bg-n-alpha-black2 text-white opacity-0 group-hover:opacity-100 transition-opacity"
                    :aria-label="t('JABVOX_TICKETS.FORM.CANCEL')"
                    @click="removeCommentImage(idx)"
                  >
                    <span class="i-lucide-x w-2.5 h-2.5" aria-hidden="true" />
                  </button>
                </li>
              </ul>

              <div class="flex items-center justify-between gap-2">
                <div class="flex items-center gap-3">
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 text-xs text-n-slate-11 hover:text-n-slate-12 transition-colors"
                    @click="pickCommentImages"
                  >
                    <span
                      class="i-lucide-image-plus w-3.5 h-3.5"
                      aria-hidden="true"
                    />
                    {{ t('JABVOX_TICKETS.DETAIL.ATTACH_IMAGE') }}
                  </button>
                  <input
                    ref="commentFileInput"
                    type="file"
                    accept="image/*"
                    multiple
                    class="hidden"
                    @change="onCommentImages"
                  />
                  <label
                    v-if="canManage"
                    class="flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer"
                  >
                    <input v-model="commentPrivate" type="checkbox" />
                    <span class="i-lucide-lock w-3 h-3" aria-hidden="true" />
                    {{ t('JABVOX_TICKETS.DETAIL.PRIVATE_NOTE') }}
                  </label>
                </div>
                <Button
                  :label="t('JABVOX_TICKETS.DETAIL.ADD_COMMENT')"
                  icon="i-lucide-send"
                  size="xs"
                  :disabled="!commentBody.trim() && !commentImages.length"
                  @click="submitComment"
                />
              </div>
            </div>
          </section>
        </div>

        <!-- ===== Columna lateral ===== -->
        <div class="flex flex-col gap-4">
          <!-- SLA countdown grande -->
          <SlaCountdown
            :status="ticket.sla_status"
            :minutes="ticket.minutes_to_due"
            size="lg"
          />

          <!-- Metadatos -->
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 text-sm shadow-sm"
          >
            <dl class="flex flex-col gap-3">
              <div class="flex items-center justify-between gap-2">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.COLS.REQUESTER') }}
                </dt>
                <dd class="flex items-center gap-1.5 text-n-slate-12 min-w-0">
                  <Avatar
                    :name="ticket.requester?.name || '?'"
                    :src="ticket.requester?.avatar_url"
                    :size="20"
                  />
                  <span class="truncate">{{ ticket.requester?.name }}</span>
                </dd>
              </div>
              <div
                v-if="ticket.account?.name"
                class="flex items-center justify-between gap-2"
              >
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.DETAIL.SOURCE_ACCOUNT') }}
                </dt>
                <dd class="flex items-center gap-1.5 text-n-slate-12 min-w-0">
                  <span
                    class="i-lucide-building-2 w-3.5 h-3.5 text-n-slate-9"
                    aria-hidden="true"
                  />
                  <span class="truncate">{{ ticket.account.name }}</span>
                </dd>
              </div>
              <div class="flex items-center justify-between gap-2">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.COLS.ASSIGNEE') }}
                </dt>
                <dd
                  v-if="ticket.assignee"
                  class="flex items-center gap-1.5 text-n-slate-12 min-w-0"
                >
                  <Avatar
                    :name="ticket.assignee.name"
                    :src="ticket.assignee.avatar_url"
                    :size="20"
                  />
                  <span class="truncate">{{ ticket.assignee.name }}</span>
                </dd>
                <dd v-else class="text-n-slate-9">
                  {{ t('JABVOX_TICKETS.UNASSIGNED') }}
                </dd>
              </div>
              <div class="flex justify-between gap-2">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.DETAIL.CATEGORY') }}
                </dt>
                <dd class="text-n-slate-12 truncate">
                  {{ ticket.category?.name || '—' }}
                </dd>
              </div>
              <div class="flex justify-between gap-2">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.TIME.OPEN_LABEL') }}
                </dt>
                <dd class="text-n-slate-12">{{ openFor }}</dd>
              </div>
              <div v-if="resolutionTime" class="flex justify-between gap-2">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.TIME.RESOLUTION_LABEL') }}
                </dt>
                <dd class="text-n-teal-11 font-medium">{{ resolutionTime }}</dd>
              </div>
              <div class="flex justify-between gap-2">
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.DETAIL.DUE') }}
                </dt>
                <dd class="text-n-slate-12">{{ fmtDate(ticket.due_at) }}</dd>
              </div>
              <div
                v-if="ticket.satisfaction_rating"
                class="flex justify-between gap-2"
              >
                <dt class="text-n-slate-10">
                  {{ t('JABVOX_TICKETS.DETAIL.SATISFACTION') }}
                </dt>
                <dd class="text-n-amber-11 font-medium">
                  {{ `${ticket.satisfaction_rating}/5` }}
                </dd>
              </div>
            </dl>
          </section>

          <!-- Timeline vertical -->
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <h4
              class="flex items-center gap-2 text-sm font-semibold text-n-slate-12 mb-3"
            >
              <span class="i-lucide-history w-4 h-4" aria-hidden="true" />
              {{ t('JABVOX_TICKETS.DETAIL.TIMELINE') }}
            </h4>
            <ol class="relative flex flex-col gap-4">
              <li
                v-for="a in ticket.activities"
                :key="a.id"
                class="relative flex gap-3 pl-1"
              >
                <span
                  class="flex items-center justify-center w-7 h-7 rounded-full bg-n-alpha-2 text-n-slate-11 shrink-0 z-10"
                  aria-hidden="true"
                >
                  <span :class="`${activityIcon(a.action)} w-3.5 h-3.5`" />
                </span>
                <div class="min-w-0 pb-1">
                  <p class="text-xs text-n-slate-12">
                    <span class="font-medium">
                      {{ a.user_name || t('JABVOX_TICKETS.DETAIL.SYSTEM') }}
                    </span>
                    {{
                      t(
                        `JABVOX_TICKETS.ACTIVITY.${a.action.toUpperCase()}`,
                        a.action
                      )
                    }}
                  </p>
                  <p class="text-xs text-n-slate-9 mt-0.5">
                    {{ fmtDate(a.created_at) }}
                  </p>
                </div>
                <!-- Línea conectora -->
                <span
                  class="tk-connector absolute left-[15px] top-7 bottom-[-16px] w-px bg-n-weak"
                  aria-hidden="true"
                />
              </li>
            </ol>
          </section>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.tk-fade {
  animation: tk-fade 0.22s ease-out;
}
@keyframes tk-fade {
  from {
    opacity: 0;
    transform: translateY(-4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
/* La última entrada del timeline no dibuja conector. */
li:last-child .tk-connector {
  display: none;
}
@media (prefers-reduced-motion: reduce) {
  .tk-fade {
    animation: none;
  }
}
</style>
