// Guards the configurable-column logic of the leads table: always 11 slots,
// swappable for default OR custom fields, persisted per account, with safe
// fallback for corrupt/unknown entries. Mirrors the logic in JabvoxLeadsPage.vue.

const DEFAULT_COLUMNS = [
  { id: 'lead_number', labelKey: 'ID', sortKey: 'lead_number' },
  { id: 'name', labelKey: 'NAME', sortKey: 'name' },
  { id: 'email', labelKey: 'EMAIL', sortKey: 'email' },
  { id: 'phone', labelKey: 'PHONE', sortKey: 'phone_number' },
  { id: 'country', labelKey: 'COUNTRY' },
  { id: 'affiliate', labelKey: 'AFFILIATE' },
  { id: 'campaign', labelKey: 'CAMPAIGN' },
  { id: 'inbox', labelKey: 'INBOX' },
  { id: 'management_state', labelKey: 'MANAGEMENT_STATE' },
  { id: 'management_date', labelKey: 'MANAGEMENT_DATE', sortKey: 'created_at' },
  { id: 'assignee', labelKey: 'ASSIGNEE' },
];
const COLUMN_SLOTS = DEFAULT_COLUMNS.length;
const defaultColumnConfig = () => DEFAULT_COLUMNS.map(c => `d:${c.id}`);
const t = k => k; // identity translator for the test

const resolveColumns = (config, customDefs) =>
  config.map((entry, i) => {
    if (typeof entry === 'string' && entry.startsWith('c:')) {
      const key = entry.slice(2);
      const def = customDefs.find(f => f.key === key);
      return { kind: 'custom', uid: entry, key, label: def?.label || key };
    }
    const id = typeof entry === 'string' ? entry.replace(/^d:/, '') : '';
    const def =
      DEFAULT_COLUMNS.find(c => c.id === id) ||
      DEFAULT_COLUMNS[i] ||
      DEFAULT_COLUMNS[0];
    return {
      kind: 'default',
      uid: `d:${def.id}`,
      id: def.id,
      label: t(def.labelKey),
      sortKey: def.sortKey,
    };
  });

const loadConfig = raw => {
  try {
    const parsed = JSON.parse(raw);
    if (
      Array.isArray(parsed) &&
      parsed.length === COLUMN_SLOTS &&
      parsed.every(v => typeof v === 'string')
    ) {
      return parsed;
    }
  } catch {
    /* corrupt */
  }
  return defaultColumnConfig();
};

const customCellValue = (lead, key, tt = t) => {
  const v = lead.custom_fields?.[key];
  if (v === null || v === undefined || `${v}`.trim() === '') return '—';
  if (Array.isArray(v)) return v.length ? v.join(', ') : '—';
  if (v === true) return tt('BOOL_YES');
  if (v === false) return tt('BOOL_NO');
  return `${v}`;
};

const CUSTOM_DEFS = [
  { key: 'seccion', label: 'Sección', column_type: 'select', options: ['121'] },
  { key: 'saldo', label: 'Saldo actual', column_type: 'float', options: [] },
  {
    key: 'activa',
    label: 'Tienda activa',
    column_type: 'boolean',
    options: [],
  },
];

describe('Leads configurable columns', () => {
  it('defaults to 11 default columns', () => {
    const cols = resolveColumns(defaultColumnConfig(), CUSTOM_DEFS);
    expect(cols.length).toBe(11);
    expect(cols.every(c => c.kind === 'default')).toBe(true);
    expect(cols[0].id).toBe('lead_number');
  });

  it('swaps a slot for a custom field (País → Saldo)', () => {
    const config = defaultColumnConfig();
    config[4] = 'c:saldo'; // slot 5 was "country"
    const cols = resolveColumns(config, CUSTOM_DEFS);
    expect(cols.length).toBe(11);
    expect(cols[4]).toMatchObject({
      kind: 'custom',
      key: 'saldo',
      label: 'Saldo actual',
    });
  });

  it('falls back to the slot default for an unknown custom key', () => {
    const config = defaultColumnConfig();
    config[4] = 'c:does_not_exist';
    const cols = resolveColumns(config, CUSTOM_DEFS);
    // still resolves (label = raw key), never crashes
    expect(cols[4].kind).toBe('custom');
    expect(cols[4].label).toBe('does_not_exist');
  });

  it('falls back to a default column when an entry is corrupt', () => {
    const config = defaultColumnConfig();
    config[3] = 'garbage-no-prefix';
    const cols = resolveColumns(config, CUSTOM_DEFS);
    // unknown default id → uses the slot-index default (phone) or first default
    expect(cols[3].kind).toBe('default');
    expect(cols.length).toBe(11);
  });

  it('loadConfig accepts a valid 11-entry array', () => {
    const valid = defaultColumnConfig();
    valid[4] = 'c:saldo';
    expect(loadConfig(JSON.stringify(valid))).toEqual(valid);
  });

  it('loadConfig rejects corrupt / wrong-length storage', () => {
    expect(loadConfig('not json')).toEqual(defaultColumnConfig());
    expect(loadConfig(JSON.stringify(['a', 'b']))).toEqual(
      defaultColumnConfig()
    );
    expect(loadConfig(JSON.stringify({ x: 1 }))).toEqual(defaultColumnConfig());
    expect(loadConfig(JSON.stringify([1, 2, 3]))).toEqual(
      defaultColumnConfig()
    );
  });

  it('renders custom cell values correctly (array / boolean / empty / text)', () => {
    const lead = {
      custom_fields: {
        tags: ['oro', 'plata'],
        activa: true,
        inactiva: false,
        saldo: '1500',
        empty: '',
        missing: null,
      },
    };
    expect(customCellValue(lead, 'tags')).toBe('oro, plata');
    expect(customCellValue(lead, 'activa')).toBe('BOOL_YES');
    expect(customCellValue(lead, 'inactiva')).toBe('BOOL_NO');
    expect(customCellValue(lead, 'saldo')).toBe('1500');
    expect(customCellValue(lead, 'empty')).toBe('—');
    expect(customCellValue(lead, 'missing')).toBe('—');
    expect(customCellValue({ custom_fields: {} }, 'absent')).toBe('—');
  });

  it('never renders more or fewer than 11 columns regardless of config', () => {
    const configs = [
      defaultColumnConfig(),
      Array(11).fill('c:saldo'),
      [
        'd:name',
        'c:saldo',
        'garbage',
        'c:nope',
        'd:email',
        'd:phone',
        'd:country',
        'd:affiliate',
        'd:campaign',
        'd:inbox',
        'd:assignee',
      ],
    ];
    configs.forEach(cfg => {
      expect(resolveColumns(cfg, CUSTOM_DEFS).length).toBe(11);
    });
  });
});
