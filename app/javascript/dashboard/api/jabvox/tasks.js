// Barrel for the Tasks (kanban) API clients. Each resource lives in its own file
// under api/jabvox/tasks/ (one class per file); this re-exports them under the
// names the stores and components import.
import tasksBoardsAPI from './tasks/boards';
import tasksAPI from './tasks/tasks';
import taskLeadContactsAPI from './tasks/leadContacts';
import taskStageAutomationsAPI from './tasks/automations';

export {
  tasksBoardsAPI,
  tasksAPI,
  taskLeadContactsAPI,
  taskStageAutomationsAPI,
};
