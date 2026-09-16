import { mount } from '@vue/test-utils';
import FlowPreview from '../FlowPreview.vue';

const twoScreenFlow = () => [
  {
    id: 'welcome',
    title: 'Inicio',
    terminal: false,
    order: 0,
    components: [
      { id: 'c1', type: 'TextHeading', props: { text: 'Bienvenido' } },
      {
        id: 'c2',
        type: 'Footer',
        props: {
          label: 'Comenzar',
          action: { name: 'navigate', next: 'rating' },
        },
      },
    ],
  },
  {
    id: 'rating',
    title: 'Calificación',
    terminal: true,
    order: 1,
    components: [
      { id: 'c3', type: 'TextBody', props: { text: '¿Cómo estuvo?' } },
      {
        id: 'c4',
        type: 'Footer',
        props: { label: 'Enviar', action: { name: 'complete' } },
      },
    ],
  },
];

describe('FlowPreview', () => {
  it('shows the empty state when there are no screens', () => {
    const wrapper = mount(FlowPreview, { props: { screens: [] } });
    expect(wrapper.text()).toContain(
      wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.EMPTY')
    );
  });

  it('renders the first screen by order on mount', () => {
    const wrapper = mount(FlowPreview, { props: { screens: twoScreenFlow() } });
    expect(wrapper.text()).toContain('Bienvenido');
    expect(wrapper.text()).not.toContain('¿Cómo estuvo?');
  });

  it('navigates to the next screen when the Footer navigate button is clicked', async () => {
    const wrapper = mount(FlowPreview, { props: { screens: twoScreenFlow() } });
    const footerButton = wrapper
      .findAll('button')
      .find(b => b.text() === 'Comenzar');
    await footerButton.trigger('click');
    expect(wrapper.text()).toContain('¿Cómo estuvo?');
    expect(wrapper.text()).not.toContain('Bienvenido');
  });

  it('shows the completed state after a Footer complete action', async () => {
    const wrapper = mount(FlowPreview, { props: { screens: twoScreenFlow() } });
    await wrapper
      .findAll('button')
      .find(b => b.text() === 'Comenzar')
      .trigger('click');
    await wrapper
      .findAll('button')
      .find(b => b.text() === 'Enviar')
      .trigger('click');
    expect(wrapper.text()).toContain(
      wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.COMPLETED')
    );
  });

  it('can navigate back to the previous screen', async () => {
    const wrapper = mount(FlowPreview, { props: { screens: twoScreenFlow() } });
    await wrapper
      .findAll('button')
      .find(b => b.text() === 'Comenzar')
      .trigger('click');
    expect(wrapper.text()).toContain('¿Cómo estuvo?');

    await wrapper.find('.i-lucide-chevron-left').trigger('click');
    expect(wrapper.text()).toContain('Bienvenido');
  });

  it('restarts the simulation when the restart button is clicked', async () => {
    const wrapper = mount(FlowPreview, { props: { screens: twoScreenFlow() } });
    await wrapper
      .findAll('button')
      .find(b => b.text() === 'Comenzar')
      .trigger('click');
    expect(wrapper.text()).toContain('¿Cómo estuvo?');

    const restartBtn = wrapper
      .findAll('button')
      .find(
        b =>
          b.attributes('title') ===
          wrapper.vm.$t('JABVOX_WA_FLOWS.BUILDER.PREVIEW.RESTART')
      );
    await restartBtn.trigger('click');
    expect(wrapper.text()).toContain('Bienvenido');
  });

  it('renders a RadioButtonsGroup and lets the test user pick an option', async () => {
    const screens = [
      {
        id: 'rating',
        title: 'Calificación',
        terminal: true,
        order: 0,
        components: [
          {
            id: 'c1',
            type: 'RadioButtonsGroup',
            props: {
              name: 'calificacion',
              label: '¿Cómo calificas?',
              data_source: [
                { id: 'excelente', title: 'Excelente' },
                { id: 'malo', title: 'Malo' },
              ],
            },
          },
        ],
      },
    ];
    const wrapper = mount(FlowPreview, { props: { screens } });
    expect(wrapper.text()).toContain('Excelente');
    expect(wrapper.text()).toContain('Malo');
    const radios = wrapper.findAll('input[type="radio"]');
    expect(radios).toHaveLength(2);
  });
});
