import { mount } from '@vue/test-utils';
import ComponentPropsEditor from '../ComponentPropsEditor.vue';
import { createComponentInstance } from '../../componentCatalog';

describe('ComponentPropsEditor', () => {
  it('renders the text field for a TextHeading and emits update on input', async () => {
    const component = createComponentInstance('TextHeading', 'cmp_1');
    const wrapper = mount(ComponentPropsEditor, {
      props: { component, screens: [], currentScreenId: 'welcome' },
    });
    const textarea = wrapper.find('textarea');
    await textarea.setValue('Hola mundo');
    expect(wrapper.emitted('update')[0][0]).toEqual({ text: 'Hola mundo' });
  });

  it('renders name/label/required fields for a TextInput', () => {
    const component = createComponentInstance('TextInput', 'cmp_1');
    const wrapper = mount(ComponentPropsEditor, {
      props: { component, screens: [], currentScreenId: 'welcome' },
    });
    expect(wrapper.findAll('input').length).toBeGreaterThanOrEqual(2);
    expect(wrapper.find('input[type="checkbox"]').exists()).toBe(true);
  });

  it('adds and removes options for a RadioButtonsGroup data_source', async () => {
    const component = createComponentInstance('RadioButtonsGroup', 'cmp_1');
    const wrapper = mount(ComponentPropsEditor, {
      props: { component, screens: [], currentScreenId: 'welcome' },
    });
    const addOptionBtn = wrapper
      .findAll('button')
      .find(b =>
        b
          .text()
          .includes(wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.PROPS.ADD_OPTION'))
      );
    await addOptionBtn.trigger('click');
    expect(wrapper.emitted('update')[0][0].data_source).toEqual([
      { id: '', title: '' },
    ]);
  });

  it('renders the action selector for a Footer and lets picking "complete"', async () => {
    const component = createComponentInstance('Footer', 'cmp_1');
    const wrapper = mount(ComponentPropsEditor, {
      props: {
        component,
        screens: [],
        currentScreenId: 'comment',
        otherScreens: [],
      },
    });
    const select = wrapper.find('select');
    await select.setValue('complete');
    expect(wrapper.emitted('update')[0][0]).toEqual({
      action: { name: 'complete', next: '' },
    });
  });

  it('shows the screen selector for navigate action, listing otherScreens', () => {
    const component = createComponentInstance('Footer', 'cmp_1');
    const wrapper = mount(ComponentPropsEditor, {
      props: {
        component,
        screens: [],
        currentScreenId: 'welcome',
        otherScreens: [{ id: 'rating', title: 'Calificación' }],
      },
    });
    expect(wrapper.text()).toContain('Calificación');
  });

  it('shows a field error message when fieldErrors includes that field', () => {
    const component = createComponentInstance('TextInput', 'cmp_1');
    const wrapper = mount(ComponentPropsEditor, {
      props: {
        component,
        screens: [],
        currentScreenId: 'welcome',
        fieldErrors: [{ field: 'name', message: 'El nombre es obligatorio' }],
      },
    });
    expect(wrapper.text()).toContain('El nombre es obligatorio');
  });
});
