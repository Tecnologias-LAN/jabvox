import { mount } from '@vue/test-utils';
import ReportTable from '../ReportTable.vue';

// vue-i18n's useI18n() is used inside the component; stub it to echo keys.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const global = {
  stubs: {
    Avatar: {
      name: 'Avatar',
      props: ['name', 'src'],
      template: '<div class="avatar-stub" />',
    },
  },
};

const columns = [
  { key: 'created_at', label: 'Fecha', type: 'datetime', sortable: true },
  { key: 'lead', label: 'Lead', type: 'lead' },
  { key: 'content', label: 'Mensaje', type: 'text' },
  { key: 'status', label: 'Estado', type: 'status' },
  { key: 'conversation_url', label: '', type: 'link' },
];

const rows = [
  {
    id: 1,
    created_at: '2026-08-30T12:00:00Z',
    lead: { name: 'Ana', phone: '+57300', avatar_url: '', channel: 'whatsapp' },
    content: 'Hola',
    status: 'read',
    conversation_url: '/app/accounts/1/conversations/9',
  },
];

describe('ReportTable', () => {
  it('renders a header per column definition', () => {
    const wrapper = mount(ReportTable, { global, props: { columns, rows } });
    expect(wrapper.findAll('thead th').length).toBe(columns.length);
  });

  it('renders one row per record with the lead visual', () => {
    const wrapper = mount(ReportTable, { global, props: { columns, rows } });
    expect(wrapper.findAll('tbody tr').length).toBe(1);
    expect(wrapper.find('.avatar-stub').exists()).toBe(true);
    expect(wrapper.text()).toContain('Ana');
  });

  it('opens the conversation link in a new tab safely', () => {
    const wrapper = mount(ReportTable, { global, props: { columns, rows } });
    const link = wrapper.find('a[target="_blank"]');
    expect(link.attributes('href')).toBe('/app/accounts/1/conversations/9');
    expect(link.attributes('rel')).toContain('noopener');
  });

  it('emits sort when a sortable header is clicked', async () => {
    const wrapper = mount(ReportTable, { global, props: { columns, rows } });
    await wrapper.find('thead th button').trigger('click');
    expect(wrapper.emitted('sort')).toBeTruthy();
    expect(wrapper.emitted('sort')[0]).toEqual(['created_at']);
  });

  it('shows the empty state when there are no rows', () => {
    const wrapper = mount(ReportTable, {
      global,
      props: { columns, rows: [] },
    });
    expect(wrapper.text()).toContain('JABVOX_REPORTS.ANALYTICS.EMPTY');
  });

  it('shows the error state with a retry action', async () => {
    const wrapper = mount(ReportTable, {
      global,
      props: { columns, rows: [], error: true },
    });
    expect(wrapper.text()).toContain('JABVOX_REPORTS.ANALYTICS.RECORDS_ERROR');
    // The retry button lives in tbody; the thead also has a sort button.
    await wrapper.find('tbody button').trigger('click');
    expect(wrapper.emitted('retry')).toBeTruthy();
  });

  it('renders a loading skeleton before any rows arrive', () => {
    const wrapper = mount(ReportTable, {
      global,
      props: { columns, rows: [], loading: true },
    });
    expect(wrapper.findAll('.animate-pulse').length).toBeGreaterThan(0);
  });
});
