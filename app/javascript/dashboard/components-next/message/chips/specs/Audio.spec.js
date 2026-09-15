import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import AudioChip from '../Audio.vue';
import MessageApi from 'dashboard/api/inbox/message';

vi.mock('dashboard/api/inbox/message', () => ({
  default: { transcribeAttachment: vi.fn() },
}));

const mockConversationId = ref(42);
vi.mock('../../provider.js', () => ({
  useMessageContext: () => ({ conversationId: mockConversationId }),
}));

// Un audio real dispara <audio> con loadedmetadata/duración; en jsdom eso no existe, así
// que se stubbea a nivel de prototipo (patrón estándar para HTMLMediaElement en Vitest).
beforeAll(() => {
  window.HTMLMediaElement.prototype.play = vi.fn();
  window.HTMLMediaElement.prototype.pause = vi.fn();
});

describe('AudioChip', () => {
  const baseAttachment = {
    id: 7,
    messageId: 99,
    fileType: 'audio',
    dataUrl: 'https://example.com/audio.mp3',
    extension: 'mp3',
    transcribedText: '',
  };

  beforeEach(() => {
    mockConversationId.value = 42;
    MessageApi.transcribeAttachment.mockReset();
  });

  it('shows "Ver traducción" when there is no transcript yet', () => {
    const wrapper = mount(AudioChip, { props: { attachment: baseAttachment } });

    expect(wrapper.text()).toContain('View translation');
  });

  it('shows the transcript already and skips the button once transcribedText is present', () => {
    const wrapper = mount(AudioChip, {
      props: {
        attachment: { ...baseAttachment, transcribedText: 'hola mundo' },
      },
    });

    expect(wrapper.text()).toContain('hola mundo');
    expect(wrapper.text()).not.toContain('View translation');
  });

  it('does not offer the button without a conversation id (e.g. outside a conversation thread)', () => {
    mockConversationId.value = null;
    const wrapper = mount(AudioChip, { props: { attachment: baseAttachment } });

    expect(wrapper.text()).not.toContain('View translation');
  });

  it('requests the transcription with the conversation, message and attachment ids', async () => {
    MessageApi.transcribeAttachment.mockResolvedValue({});
    const wrapper = mount(AudioChip, { props: { attachment: baseAttachment } });

    await wrapper.find('button.text-n-slate-11').trigger('click');

    expect(MessageApi.transcribeAttachment).toHaveBeenCalledWith(42, 99, 7);
  });

  it('shows "Transcribiendo…" while the request is in flight', async () => {
    let resolveRequest;
    MessageApi.transcribeAttachment.mockReturnValue(
      new Promise(resolve => {
        resolveRequest = resolve;
      })
    );
    const wrapper = mount(AudioChip, { props: { attachment: baseAttachment } });

    await wrapper.find('button.text-n-slate-11').trigger('click');

    expect(wrapper.text()).toContain('Transcribing');

    resolveRequest({});
    await flushPromises();
  });

  it('re-enables the button after a failed request, so the agent can retry', async () => {
    MessageApi.transcribeAttachment.mockRejectedValue(new Error('no se pudo'));
    const wrapper = mount(AudioChip, { props: { attachment: baseAttachment } });

    await wrapper.find('button.text-n-slate-11').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('View translation');
    expect(
      wrapper.find('button.text-n-slate-11').attributes('disabled')
    ).toBeUndefined();
  });

  it('turns off the spinner as soon as the transcript arrives via broadcast (no polling)', async () => {
    MessageApi.transcribeAttachment.mockReturnValue(new Promise(() => {}));
    const wrapper = mount(AudioChip, { props: { attachment: baseAttachment } });

    await wrapper.find('button.text-n-slate-11').trigger('click');
    expect(wrapper.text()).toContain('Transcribing');

    await wrapper.setProps({
      attachment: { ...baseAttachment, transcribedText: 'llegó por broadcast' },
    });

    expect(wrapper.text()).toContain('llegó por broadcast');
  });

  it('ignores a second click while a request is already in flight', async () => {
    MessageApi.transcribeAttachment.mockReturnValue(new Promise(() => {}));
    const wrapper = mount(AudioChip, { props: { attachment: baseAttachment } });

    const button = wrapper.find('button.text-n-slate-11');
    await button.trigger('click');
    await button.trigger('click');
    await button.trigger('click');

    expect(MessageApi.transcribeAttachment).toHaveBeenCalledTimes(1);
  });
});
