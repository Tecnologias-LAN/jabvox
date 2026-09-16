import { mount } from '@vue/test-utils';
import ScreenList from '../ScreenList.vue';

const screens = () => [
  { id: 'welcome', title: 'Inicio', terminal: false, order: 0, components: [] },
  {
    id: 'rating',
    title: 'Calificación',
    terminal: false,
    order: 1,
    components: [{ id: 'c1' }],
  },
  {
    id: 'comment',
    title: 'Comentario',
    terminal: true,
    order: 2,
    components: [],
  },
];

describe('ScreenList', () => {
  it('renders every screen with its title', () => {
    const wrapper = mount(ScreenList, { props: { screens: screens() } });
    expect(wrapper.text()).toContain('Inicio');
    expect(wrapper.text()).toContain('Calificación');
    expect(wrapper.text()).toContain('Comentario');
  });

  it('shows the empty state when there are no screens', () => {
    const wrapper = mount(ScreenList, { props: { screens: [] } });
    expect(wrapper.text()).toContain(
      wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.SCREENS.EMPTY')
    );
  });

  it('emits "select" with the screen id when clicked', async () => {
    const wrapper = mount(ScreenList, { props: { screens: screens() } });
    const items = wrapper.findAll('.wf-screen-item');
    await items[1].trigger('click');
    expect(wrapper.emitted('select')[0]).toEqual(['rating']);
  });

  it('emits "add" when the add button is clicked', async () => {
    const wrapper = mount(ScreenList, { props: { screens: screens() } });
    await wrapper.find('button[title]').trigger('click');
    expect(wrapper.emitted('add')).toBeTruthy();
  });

  it('emits "remove" with the screen id from the trash icon', async () => {
    const wrapper = mount(ScreenList, { props: { screens: screens() } });
    const removeBtn = wrapper
      .findAll('button')
      .find(
        b =>
          b.attributes('title') ===
          wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.SCREENS.REMOVE')
      );
    await removeBtn.trigger('click');
    expect(wrapper.emitted('remove')).toBeTruthy();
  });

  it('emits "duplicate" with the screen id', async () => {
    const wrapper = mount(ScreenList, { props: { screens: screens() } });
    const dupBtn = wrapper
      .findAll('button')
      .find(
        b =>
          b.attributes('title') ===
          wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.SCREENS.DUPLICATE')
      );
    await dupBtn.trigger('click');
    expect(wrapper.emitted('duplicate')[0][0]).toBe('welcome');
  });

  it('emits "move-up" and "move-down"', async () => {
    const wrapper = mount(ScreenList, { props: { screens: screens() } });
    const upButtons = wrapper
      .findAll('button')
      .filter(
        b =>
          b.attributes('title') ===
          wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.SCREENS.MOVE_UP')
      );
    // El segundo screen (rating) sí puede subir.
    await upButtons[1].trigger('click');
    expect(wrapper.emitted('move-up')[0]).toEqual(['rating']);
  });

  it('marks the active screen with the active class', () => {
    const wrapper = mount(ScreenList, {
      props: { screens: screens(), selectedScreenId: 'rating' },
    });
    const items = wrapper.findAll('.wf-screen-item');
    expect(items[1].classes()).toContain('wf-screen-item-active');
    expect(items[0].classes()).not.toContain('wf-screen-item-active');
  });

  it('shows the start and terminal badges correctly', () => {
    const wrapper = mount(ScreenList, { props: { screens: screens() } });
    expect(wrapper.text()).toContain(
      wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.SCREENS.START_BADGE')
    );
    expect(wrapper.text()).toContain(
      wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.SCREENS.TERMINAL_BADGE')
    );
  });

  it('hides action buttons in readonly mode', () => {
    const wrapper = mount(ScreenList, {
      props: { screens: screens(), readonly: true },
    });
    expect(
      wrapper
        .findAll('button')
        .some(
          b =>
            b.attributes('title') ===
            wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.SCREENS.ADD')
        )
    ).toBe(false);
  });

  it('shows an error icon for screens listed in errorScreenIds', () => {
    const wrapper = mount(ScreenList, {
      props: { screens: screens(), errorScreenIds: ['rating'] },
    });
    expect(wrapper.find('.i-lucide-alert-triangle').exists()).toBe(true);
  });
});
