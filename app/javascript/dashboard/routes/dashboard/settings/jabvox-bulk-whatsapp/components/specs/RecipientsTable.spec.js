import { mount } from '@vue/test-utils';
import RecipientsTable from '../RecipientsTable.vue';

const baseRecipient = {
  id: 1,
  name: 'Estrada',
  phone_number: '573001112233',
  template_name: 'formulario_de_intencion',
  status: 'sent',
  delivered: true,
  delivered_at: '2026-09-15T16:55:53Z',
  read: true,
  read_at: '2026-09-15T16:55:58Z',
  replied: true,
  replied_at: '2026-09-15T16:56:05Z',
  reply_time_seconds: 12,
  reply_text: 'Rating: Excelente\nComments: Muy bueno',
  reply_source: 'flow',
  error_code: null,
  error_message: null,
  sent_at: '2026-09-15T16:55:53Z',
};

describe('RecipientsTable', () => {
  it('shows the empty state when there are no recipients', () => {
    const wrapper = mount(RecipientsTable, {
      props: { recipients: [], loading: false },
    });

    expect(wrapper.text()).toContain(
      wrapper.vm.$t('JABVOX_BULK_WA.REPORT.EMPTY')
    );
  });

  it('shows a spinner while loading, before the empty state', () => {
    const wrapper = mount(RecipientsTable, {
      props: { recipients: [], loading: true },
    });

    expect(wrapper.findComponent({ name: 'Spinner' }).exists()).toBe(true);
    expect(wrapper.text()).not.toContain(
      wrapper.vm.$t('JABVOX_BULK_WA.REPORT.EMPTY')
    );
  });

  it('renders the reply text column with the actual answer received', () => {
    const wrapper = mount(RecipientsTable, {
      props: { recipients: [baseRecipient], loading: false },
    });

    expect(wrapper.text()).toContain('Rating: Excelente');
    expect(wrapper.text()).toContain('Comments: Muy bueno');
  });

  it('renders the reply time formatted as short human text', () => {
    const wrapper = mount(RecipientsTable, {
      props: { recipients: [baseRecipient], loading: false },
    });

    expect(wrapper.text()).toContain('12s');
  });

  it('shows Sí/No for replied depending on the flag', () => {
    const replied = mount(RecipientsTable, {
      props: { recipients: [baseRecipient], loading: false },
    });
    const notReplied = mount(RecipientsTable, {
      props: {
        recipients: [{ ...baseRecipient, replied: false, replied_at: null }],
        loading: false,
      },
    });

    expect(replied.text()).toContain(
      replied.vm.$t('JABVOX_BULK_WA.REPORT.REPLIED_YES')
    );
    expect(notReplied.text()).toContain(
      notReplied.vm.$t('JABVOX_BULK_WA.REPORT.REPLIED_NO')
    );
  });

  it('hides the Template column unless showTemplate is set (per-batch dialog use)', () => {
    const withoutTemplate = mount(RecipientsTable, {
      props: { recipients: [baseRecipient], loading: false },
    });
    const withTemplate = mount(RecipientsTable, {
      props: {
        recipients: [baseRecipient],
        loading: false,
        showTemplate: true,
      },
    });

    expect(withoutTemplate.text()).not.toContain('formulario_de_intencion');
    expect(withTemplate.text()).toContain('formulario_de_intencion');
  });

  it('shows delivered/read ticks only when the flag is true', () => {
    const wrapper = mount(RecipientsTable, {
      props: {
        recipients: [
          {
            ...baseRecipient,
            delivered: false,
            delivered_at: null,
            read: false,
            read_at: null,
          },
        ],
        loading: false,
      },
    });

    // Neither the single-check nor double-check WhatsApp glyphs should appear
    // for a recipient with delivered/read both false.
    expect(wrapper.text()).not.toContain('✓');
  });

  it('shows a badge naming how the reply was matched (flow/button/message)', () => {
    const flow = mount(RecipientsTable, {
      props: { recipients: [{ ...baseRecipient, reply_source: 'flow' }] },
    });
    const button = mount(RecipientsTable, {
      props: { recipients: [{ ...baseRecipient, reply_source: 'button' }] },
    });
    const message = mount(RecipientsTable, {
      props: { recipients: [{ ...baseRecipient, reply_source: 'message' }] },
    });

    expect(flow.text()).toContain(
      flow.vm.$t('JABVOX_BULK_WA.REPORT.REPLY_SOURCE.FLOW')
    );
    expect(button.text()).toContain(
      button.vm.$t('JABVOX_BULK_WA.REPORT.REPLY_SOURCE.BUTTON')
    );
    expect(message.text()).toContain(
      message.vm.$t('JABVOX_BULK_WA.REPORT.REPLY_SOURCE.MESSAGE')
    );
  });

  it('shows no badge when there is no reply_source (not replied)', () => {
    const wrapper = mount(RecipientsTable, {
      props: {
        recipients: [{ ...baseRecipient, reply_source: null }],
        loading: false,
      },
    });

    expect(wrapper.text()).not.toContain(
      wrapper.vm.$t('JABVOX_BULK_WA.REPORT.REPLY_SOURCE.FLOW')
    );
    expect(wrapper.text()).not.toContain(
      wrapper.vm.$t('JABVOX_BULK_WA.REPORT.REPLY_SOURCE.BUTTON')
    );
    expect(wrapper.text()).not.toContain(
      wrapper.vm.$t('JABVOX_BULK_WA.REPORT.REPLY_SOURCE.MESSAGE')
    );
  });

  it('renders error code/message when the send failed', () => {
    const wrapper = mount(RecipientsTable, {
      props: {
        recipients: [
          {
            ...baseRecipient,
            status: 'failed',
            replied: false,
            replied_at: null,
            reply_text: null,
            error_code: '131009',
            error_message: 'Parameter value is not valid',
          },
        ],
        loading: false,
      },
    });

    expect(wrapper.text()).toContain('131009');
    expect(wrapper.text()).toContain('Parameter value is not valid');
  });
});
