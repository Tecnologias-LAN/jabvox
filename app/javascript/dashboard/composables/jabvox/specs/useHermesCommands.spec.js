import { ref } from 'vue';
import { useHermesCommands } from '../useHermesCommands';

describe('useHermesCommands', () => {
  const setup = (initial = '') => {
    const messageInput = ref(initial);
    return { messageInput, ...useHermesCommands(messageInput) };
  };

  describe('filteredCommands', () => {
    it('is empty when the text does not start with a slash', () => {
      const { filteredCommands } = setup('hola');
      expect(filteredCommands.value).toEqual([]);
    });

    it('lists every command for a bare slash', () => {
      const { filteredCommands } = setup('/');
      expect(filteredCommands.value.length).toBeGreaterThan(1);
    });

    it('filters by prefix', () => {
      const { filteredCommands } = setup('/mod');
      expect(filteredCommands.value.map(c => c.cmd)).toEqual(['/model']);
    });
  });

  describe('applyCommand', () => {
    it('writes the command into the input and closes the menu', () => {
      const { messageInput, applyCommand, showCommands } = setup('/mo');
      showCommands.value = true;
      applyCommand('/model');
      expect(messageInput.value).toBe('/model ');
      expect(showCommands.value).toBe(false);
    });
  });

  describe('onInput', () => {
    it('opens the menu while the text matches a command', () => {
      const { messageInput, onInput, showCommands } = setup();
      messageInput.value = '/st';
      onInput();
      expect(showCommands.value).toBe(true);
    });

    it('keeps the menu closed for regular text', () => {
      const { messageInput, onInput, showCommands } = setup();
      messageInput.value = 'hola';
      onInput();
      expect(showCommands.value).toBe(false);
    });
  });

  describe('handleCommandKeydown', () => {
    const keyEvent = key => ({ key, preventDefault: vi.fn() });

    it('ignores keys when the menu is closed', () => {
      const { handleCommandKeydown } = setup('/');
      expect(handleCommandKeydown(keyEvent('ArrowDown'))).toBe(false);
    });

    it('moves the selection down and wraps around', () => {
      const { onInput, handleCommandKeydown, commandIndex, filteredCommands } =
        setup('/');
      onInput();
      const total = filteredCommands.value.length;
      handleCommandKeydown(keyEvent('ArrowDown'));
      expect(commandIndex.value).toBe(1);

      commandIndex.value = total - 1;
      handleCommandKeydown(keyEvent('ArrowDown'));
      expect(commandIndex.value).toBe(0);
    });

    it('wraps around going up from the first item', () => {
      const { onInput, handleCommandKeydown, commandIndex, filteredCommands } =
        setup('/');
      onInput();
      handleCommandKeydown(keyEvent('ArrowUp'));
      expect(commandIndex.value).toBe(filteredCommands.value.length - 1);
    });

    it('completes the highlighted command on Enter', () => {
      const { messageInput, onInput, handleCommandKeydown } = setup('/mod');
      onInput();
      expect(handleCommandKeydown(keyEvent('Enter'))).toBe(true);
      expect(messageInput.value).toBe('/model ');
    });

    it('closes the menu on Escape', () => {
      const { onInput, handleCommandKeydown, showCommands } = setup('/');
      onInput();
      handleCommandKeydown(keyEvent('Escape'));
      expect(showCommands.value).toBe(false);
    });
  });

  // "/new", "/reset" y "/clear" abren sesión nueva en Jabvox y "/stop" corta el streaming:
  // ninguno se envía a Hermes. El resto sí viaja para que Hermes los interprete.
  describe('locally handled commands', () => {
    it('recognises the commands that start a new chat', () => {
      const { isNewChatCommand } = setup();
      expect(isNewChatCommand('/new')).toBe(true);
      expect(isNewChatCommand('/reset')).toBe(true);
      expect(isNewChatCommand('/clear')).toBe(true);
      expect(isNewChatCommand('/model')).toBe(false);
    });

    it('recognises the stop command', () => {
      const { isStopCommand } = setup();
      expect(isStopCommand('/stop')).toBe(true);
      expect(isStopCommand('/status')).toBe(false);
    });

    it('detects new-chat and stop commands by prefix (with arguments)', () => {
      const { isNewChatCommand, isStopCommand } = setup();
      expect(isNewChatCommand('/new mi conversación')).toBe(true);
      expect(isNewChatCommand('/reset  con espacios')).toBe(true);
      expect(isStopCommand('/stop ahora')).toBe(true);
      // No confunde comandos que empiezan igual pero son otra palabra.
      expect(isNewChatCommand('/newsletter')).toBe(false);
      expect(isStopCommand('/stopall')).toBe(false);
    });

    it('extracts the title from "/new <nombre>"', () => {
      const { newChatTitle } = setup();
      expect(newChatTitle('/new Soporte VIP')).toBe('Soporte VIP');
      expect(newChatTitle('/new')).toBe('');
      expect(newChatTitle('/reset  Ventas  ')).toBe('Ventas');
      // No es comando de nueva sesión → sin título.
      expect(newChatTitle('/model glm-5')).toBe('');
    });
  });

  // "/model" sí viaja a Hermes, pero quien lo envíe debe resincronizar el picker: Hermes no
  // anuncia el cambio por el stream y el picker seguiría mandando su propio modelo.
  describe('isModelCommand', () => {
    it('matches the command with and without arguments', () => {
      const { isModelCommand } = setup();
      expect(isModelCommand('/model')).toBe(true);
      expect(isModelCommand('/model glm-5')).toBe(true);
      expect(isModelCommand('/model glm-5 --global')).toBe(true);
    });

    it('does not match other commands or plain text', () => {
      const { isModelCommand } = setup();
      expect(isModelCommand('/models')).toBe(false);
      expect(isModelCommand('/status')).toBe(false);
      expect(isModelCommand('hablemos del model')).toBe(false);
    });
  });
});
