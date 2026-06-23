import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const TasksLayout = () => import('./TasksLayout.vue');
const TasksBoardView = () => import('./TasksBoardView.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.JABVOX_TASKS,
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/tasks'),
    component: TasksLayout,
    children: [
      {
        path: '',
        name: 'jabvox_tasks_index',
        meta,
        component: TasksBoardView,
      },
      {
        path: ':boardId',
        name: 'jabvox_tasks_board',
        meta,
        component: TasksBoardView,
      },
    ],
  },
];
