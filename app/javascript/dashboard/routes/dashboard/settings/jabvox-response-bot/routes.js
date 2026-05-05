import ResponseBotSettings from './ResponseBotSettings.vue';

export const routes = [
  {
    path: 'jabvox/response-bot',
    name: 'jabvox_response_bot_settings',
    component: ResponseBotSettings,
    meta: { permissions: ['administrator'] },
  },
];
