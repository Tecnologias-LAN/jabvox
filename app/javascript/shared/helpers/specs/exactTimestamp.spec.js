import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { exactTimestamp } from 'shared/helpers/timeHelper';

describe('exactTimestamp', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-09-24T16:00:00Z'));
  });
  afterEach(() => vi.useRealTimers());

  it('muestra solo la hora cuando es de hoy', () => {
    const hoy = Math.floor(new Date('2026-09-24T14:30:00Z').getTime() / 1000);
    expect(exactTimestamp(hoy)).toMatch(/^\d{1,2}:\d{2} (AM|PM)$/);
  });

  it('antepone la fecha cuando es de otro dia del mismo anio', () => {
    const ayer = Math.floor(new Date('2026-09-23T22:37:00Z').getTime() / 1000);
    expect(exactTimestamp(ayer)).toMatch(/^Sep 23, \d{1,2}:\d{2} (AM|PM)$/);
  });

  it('incluye el anio cuando es de otro anio', () => {
    const viejo = Math.floor(new Date('2025-01-05T09:15:00Z').getTime() / 1000);
    expect(exactTimestamp(viejo)).toMatch(
      /^Jan 5 2025, \d{1,2}:\d{2} (AM|PM)$/
    );
  });

  it('devuelve cadena vacia sin timestamp', () => {
    expect(exactTimestamp(null)).toBe('');
    expect(exactTimestamp(undefined)).toBe('');
  });
});
