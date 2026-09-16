import { describe, it, expect } from 'vitest';
import {
  COMPONENT_TYPES,
  getComponentMeta,
  createComponentInstance,
  isAtLimit,
  countByType,
  MAX_COMPONENTS_PER_SCREEN,
} from '../componentCatalog';

// Sección 2.3 de docs/whatsapp-flows/architecture.md: el builder SOLO puede
// ofrecer estos 15 tipos, ni uno más (PhotoPicker, CalendarPicker,
// NavigationList, ImageCarousel, RichText, If/Switch quedan fuera).
const EXPECTED_TYPES = [
  'TextHeading',
  'TextSubheading',
  'TextBody',
  'TextCaption',
  'TextInput',
  'TextArea',
  'RadioButtonsGroup',
  'CheckboxGroup',
  'Dropdown',
  'ChipsSelector',
  'DatePicker',
  'OptIn',
  'Image',
  'EmbeddedLink',
  'Footer',
];

describe('COMPONENT_TYPES catalog', () => {
  it('expone exactamente los 15 tipos soportados por Meta Flow JSON 7.3, sin agregar otros', () => {
    expect(COMPONENT_TYPES.sort()).toEqual(EXPECTED_TYPES.sort());
  });

  it('cada tipo tiene label, icon y category', () => {
    COMPONENT_TYPES.forEach(type => {
      const meta = getComponentMeta(type);
      expect(meta.label).toBeTruthy();
      expect(meta.icon).toBeTruthy();
      expect(meta.category).toBeTruthy();
    });
  });

  it('respeta los límites por pantalla documentados: Footer=1, Image=3, EmbeddedLink=2, OptIn=5', () => {
    expect(getComponentMeta('Footer').limitPerScreen).toBe(1);
    expect(getComponentMeta('Image').limitPerScreen).toBe(3);
    expect(getComponentMeta('EmbeddedLink').limitPerScreen).toBe(2);
    expect(getComponentMeta('OptIn').limitPerScreen).toBe(5);
  });

  it('MAX_COMPONENTS_PER_SCREEN es 50 (límite duro de Meta)', () => {
    expect(MAX_COMPONENTS_PER_SCREEN).toBe(50);
  });
});

describe('createComponentInstance', () => {
  it('crea una instancia con props por defecto según los fields del catálogo', () => {
    const cmp = createComponentInstance('TextInput', 'cmp_1');
    expect(cmp.id).toBe('cmp_1');
    expect(cmp.type).toBe('TextInput');
    expect(cmp.props.name).toBe('');
    expect(cmp.props.required).toBe(false);
    expect(cmp.props.input_type).toBe('text');
  });

  it('inicializa data_source como array vacío para componentes de opciones', () => {
    const cmp = createComponentInstance('RadioButtonsGroup', 'cmp_1');
    expect(cmp.props.data_source).toEqual([]);
  });

  it('inicializa action con navigate por defecto para Footer', () => {
    const cmp = createComponentInstance('Footer', 'cmp_1');
    expect(cmp.props.action).toEqual({ name: 'navigate', next: '' });
  });

  it('devuelve null para un tipo fuera del catálogo', () => {
    expect(createComponentInstance('PhotoPicker', 'cmp_1')).toBeNull();
  });
});

describe('isAtLimit / countByType', () => {
  it('bloquea agregar un segundo Footer', () => {
    const components = [{ id: 'a', type: 'Footer', props: {} }];
    expect(isAtLimit(components, 'Footer')).toBe(true);
    expect(countByType(components, 'Footer')).toBe(1);
  });

  it('permite hasta 3 Image y bloquea la cuarta', () => {
    const components = [
      { id: 'a', type: 'Image', props: {} },
      { id: 'b', type: 'Image', props: {} },
    ];
    expect(isAtLimit(components, 'Image')).toBe(false);
    const atLimit = [...components, { id: 'c', type: 'Image', props: {} }];
    expect(isAtLimit(atLimit, 'Image')).toBe(true);
  });

  it('componentes sin límite (TextBody) nunca están "at limit"', () => {
    const components = Array.from({ length: 20 }, (_, i) => ({
      id: `t${i}`,
      type: 'TextBody',
      props: {},
    }));
    expect(isAtLimit(components, 'TextBody')).toBe(false);
  });
});
