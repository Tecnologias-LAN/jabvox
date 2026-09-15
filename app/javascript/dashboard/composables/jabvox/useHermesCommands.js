import { ref, computed } from 'vue';

// Comandos "/" del Chat IA, compartidos por la página completa y la burbuja flotante.
// Jabvox solo intercepta los que crean/detienen sesión en local ("/new", "/reset",
// "/clear", "/stop"); el resto (/model, /status, /retry…) se envían a Hermes tal cual para
// que él los interprete.

export const HERMES_COMMANDS = [
  {
    cmd: '/model',
    desc: 'Cambiar modelo: /model [nombre] [--global] (--global lo hace permanente)',
  },
  { cmd: '/new', desc: 'Sesión nueva (nombre opcional)' },
  { cmd: '/reset', desc: 'Sesión nueva (reinicia el contexto)' },
  { cmd: '/clear', desc: 'Limpiar pantalla e iniciar sesión nueva' },
  { cmd: '/retry', desc: 'Reenviar el último mensaje' },
  {
    cmd: '/steer',
    desc: 'Inyectar un mensaje tras la próxima llamada a herramienta',
  },
  { cmd: '/status', desc: 'Info de la sesión: modelo, tokens y contexto' },
  {
    cmd: '/stop',
    desc: 'Detener la respuesta / matar procesos en segundo plano',
  },
];

const NEW_CHAT_COMMANDS = ['/new', '/reset', '/clear'];

export function useHermesCommands(messageInput) {
  const showCommands = ref(false);
  const commandIndex = ref(0);

  const filteredCommands = computed(() => {
    const text = (messageInput.value || '').trim();
    if (!text.startsWith('/')) return [];
    const q = text.toLowerCase();
    return HERMES_COMMANDS.filter(c => c.cmd.startsWith(q) || q === '/');
  });

  function onInput() {
    const show = filteredCommands.value.length > 0;
    showCommands.value = show;
    if (show) commandIndex.value = 0;
  }

  function applyCommand(cmd) {
    messageInput.value = `${cmd} `;
    showCommands.value = false;
  }

  function closeCommands() {
    showCommands.value = false;
  }

  // Navegación del menú con teclado. Devuelve true si consumió la tecla, para que el
  // componente sepa que no debe además enviar el mensaje.
  function handleCommandKeydown(e) {
    if (!showCommands.value || !filteredCommands.value.length) return false;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      commandIndex.value =
        (commandIndex.value + 1) % filteredCommands.value.length;
      return true;
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      commandIndex.value =
        (commandIndex.value - 1 + filteredCommands.value.length) %
        filteredCommands.value.length;
      return true;
    }
    if (e.key === 'Tab' || (e.key === 'Enter' && !e.shiftKey)) {
      e.preventDefault();
      applyCommand(filteredCommands.value[commandIndex.value].cmd);
      return true;
    }
    if (e.key === 'Escape') {
      showCommands.value = false;
      return true;
    }
    return false;
  }

  const isNewChatCommand = content => NEW_CHAT_COMMANDS.includes(content);
  const isStopCommand = content => content === '/stop';

  // "/model ..." cambia el modelo del lado de Hermes, pero el picker visual no se entera:
  // seguiría mandando su propio llm_model en el siguiente mensaje y pisaría el cambio. Quien
  // envíe este comando debe releer model/options para resincronizarse.
  const isModelCommand = content => /^\/model(\s|$)/.test(content);

  return {
    showCommands,
    commandIndex,
    filteredCommands,
    onInput,
    applyCommand,
    closeCommands,
    handleCommandKeydown,
    isNewChatCommand,
    isStopCommand,
    isModelCommand,
  };
}
