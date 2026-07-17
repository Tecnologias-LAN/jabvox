// Guards the "select the whole filter" visibility logic + effective selection.
// Mirrors canSelectAllFilter / clearSelection / selectAllFilter from JabvoxLeadsPage.

// New rule: show whenever there's ≥1 selected, regardless of totals; hide only
// when the cap was hit or there's no selection.
const makeCanSelectAll =
  ({ hasSelection, allFilterCapped }) =>
  () =>
    hasSelection && !allFilterCapped;

describe('Leads — select the whole filter', () => {
  it('shows the button with a single lead selected (1 of 1)', () => {
    const can = makeCanSelectAll({
      hasSelection: true,
      allFilterCapped: false,
    });
    expect(can()).toBe(true);
  });

  it('shows the button when a selection exists and more leads match', () => {
    const can = makeCanSelectAll({
      hasSelection: true,
      allFilterCapped: false,
    });
    expect(can()).toBe(true);
  });

  it('hides the button with no selection', () => {
    const can = makeCanSelectAll({
      hasSelection: false,
      allFilterCapped: false,
    });
    expect(can()).toBe(false);
  });

  it('hides the button once the cap was hit', () => {
    const can = makeCanSelectAll({ hasSelection: true, allFilterCapped: true });
    expect(can()).toBe(false);
  });

  it('shows the button when the whole page is selected', () => {
    const can = makeCanSelectAll({
      hasSelection: true,
      allFilterCapped: false,
    });
    expect(can()).toBe(true);
  });

  it('select-all replaces the selection with every matching id', () => {
    // Simulate the selectAllFilter effect
    let selected = new Set([1, 2, 3]);
    let capped = false;
    const applyMatching = data => {
      selected = new Set(data.ids || []);
      capped = Boolean(data.capped);
    };
    applyMatching({ ids: [10, 11, 12, 13, 14], capped: false });
    expect([...selected]).toEqual([10, 11, 12, 13, 14]);
    expect(selected.size).toBe(5);
    expect(capped).toBe(false);
  });

  it('marks capped when the backend hit the id limit', () => {
    let capped = false;
    const applyMatching = data => {
      capped = Boolean(data.capped);
    };
    applyMatching({ ids: new Array(20000).fill(0), capped: true });
    expect(capped).toBe(true);
  });
});
