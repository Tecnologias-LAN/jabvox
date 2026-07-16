import { mount } from '@vue/test-utils';
import DialerWrapupForm from '../DialerWrapupForm.vue';

// Minimal i18n + child stubs so the SFC mounts without the full app.
const global = {
  mocks: { $t: k => k },
  stubs: {
    ManagementQuestionsForm: {
      name: 'ManagementQuestionsForm',
      props: ['modelValue', 'state'],
      template: '<div class="mqf-stub" />',
    },
  },
};

// vue-i18n's useI18n() is used inside the component; stub it.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const flatStates = [
  { id: 1, name_jabvox: 'Contesta', color_jabvox: '#0a0' },
  { id: 2, name_jabvox: 'No contesta', color_jabvox: '#a00' },
];
const groupedStates = [
  { id: 10, name_jabvox: 'Interesado', state_group_jabvox: 'Venta' },
  { id: 11, name_jabvox: 'Descartado', state_group_jabvox: 'Venta' },
  { id: 12, name_jabvox: 'Buzón', state_group_jabvox: 'Sin contacto' },
];
const typifications = [
  { id: 5, name: 'Efectiva' },
  { id: 6, name: 'No efectiva' },
];

describe('DialerWrapupForm', () => {
  it('renders one button per flat management state', () => {
    const wrapper = mount(DialerWrapupForm, {
      global,
      props: { managementStates: flatStates, typifications },
    });
    const buttons = wrapper.findAll('button');
    expect(buttons.length).toBe(2);
    expect(wrapper.text()).toContain('Contesta');
    expect(wrapper.text()).toContain('No contesta');
  });

  it('emits update:stateId when a state is clicked and toggles off on re-click', async () => {
    const wrapper = mount(DialerWrapupForm, {
      global,
      props: { managementStates: flatStates, typifications, stateId: null },
    });
    await wrapper.findAll('button')[0].trigger('click');
    expect(wrapper.emitted('update:stateId')[0]).toEqual([1]);

    // Re-click the same selected state → toggles to null.
    await wrapper.setProps({ stateId: 1 });
    await wrapper.findAll('button')[0].trigger('click');
    expect(wrapper.emitted('update:stateId')[1]).toEqual([null]);
  });

  it('shows groups first for grouped states and drills into substates', async () => {
    const wrapper = mount(DialerWrapupForm, {
      global,
      props: { managementStates: groupedStates, typifications, group: null },
    });
    // Two group chips: "Venta" and "Sin contacto".
    expect(wrapper.text()).toContain('Venta');
    expect(wrapper.text()).toContain('Sin contacto');

    // Select a group → emits update:group.
    const ventaBtn = wrapper.findAll('button').find(b => b.text() === 'Venta');
    await ventaBtn.trigger('click');
    expect(wrapper.emitted('update:group')[0]).toEqual(['Venta']);

    // With the group set, the substates of that group appear.
    await wrapper.setProps({ group: 'Venta' });
    expect(wrapper.text()).toContain('Interesado');
    expect(wrapper.text()).toContain('Descartado');
    expect(wrapper.text()).not.toContain('Buzón'); // other group
  });

  it('emits a numeric typificationId from the select', async () => {
    const wrapper = mount(DialerWrapupForm, {
      global,
      props: { managementStates: flatStates, typifications },
    });
    const select = wrapper.find('select');
    await select.setValue('6');
    const emitted = wrapper.emitted('update:typificationId');
    expect(emitted[emitted.length - 1]).toEqual([6]);
    expect(typeof emitted[emitted.length - 1][0]).toBe('number');
  });

  it('emits note updates from the textarea', async () => {
    const wrapper = mount(DialerWrapupForm, {
      global,
      props: { managementStates: flatStates, typifications },
    });
    await wrapper.find('textarea').setValue('cliente pidió recontacto');
    const emitted = wrapper.emitted('update:note');
    expect(emitted[emitted.length - 1]).toEqual(['cliente pidió recontacto']);
  });

  it('renders the ManagementQuestionsForm only when a state is selected', async () => {
    const wrapper = mount(DialerWrapupForm, {
      global,
      props: { managementStates: flatStates, typifications, stateId: null },
    });
    expect(wrapper.find('.mqf-stub').exists()).toBe(false);
    await wrapper.setProps({ stateId: 1 });
    expect(wrapper.find('.mqf-stub').exists()).toBe(true);
  });
});
