import {
  positionedEvents,
  allDayEvents,
  nowOffset,
  minutesFromMidnight,
  DAY_HEIGHT,
} from '../jabvox/calendarGrid';

// La rejilla horaria no existía: las vistas de semana y día apilaban los eventos como
// lista, así que la hora se mostraba pero no situaba nada.
describe('calendarGrid', () => {
  const day = new Date(2026, 8, 28); // 28/09/2026, local

  // Se construyen en hora local a propósito: es lo que devuelve `new Date(iso)` en el
  // navegador tras parsear lo que manda el backend.
  const at = (hour, minute = 0) =>
    new Date(2026, 8, 28, hour, minute).toISOString();

  const event = (id, from, to, extra = {}) => ({
    id,
    start_at: from,
    end_at: to,
    all_day: false,
    ...extra,
  });

  describe('posición vertical', () => {
    it('sitúa un evento según su hora de inicio', () => {
      const [item] = positionedEvents([event(1, at(10), at(11))], day);

      // Las 10:00 son 600 de 1440 minutos del día.
      expect(item.top).toBeCloseTo((600 / 1440) * DAY_HEIGHT);
    });

    it('le da altura según su duración', () => {
      const [item] = positionedEvents([event(1, at(10), at(12))], day);

      expect(item.height).toBeCloseTo((120 / 1440) * DAY_HEIGHT);
    });

    it('mantiene pulsable un evento muy corto', () => {
      const [item] = positionedEvents([event(1, at(10), at(10, 5))], day);

      expect(item.height).toBeGreaterThanOrEqual(18);
    });

    it('no coloca a la misma altura dos horas distintas', () => {
      const [uno, dos] = positionedEvents(
        [event(1, at(9), at(10)), event(2, at(15), at(16))],
        day
      );

      expect(uno.top).not.toEqual(dos.top);
    });
  });

  describe('eventos que se solapan', () => {
    it('los reparte en columnas en vez de taparlos', () => {
      const items = positionedEvents(
        [event(1, at(10), at(12)), event(2, at(11), at(13))],
        day
      );

      expect(items.map(i => i.column).sort()).toEqual([0, 1]);
      expect(items.every(i => i.columns === 2)).toBe(true);
    });

    it('deja el ancho completo a los que no se solapan', () => {
      const items = positionedEvents(
        [event(1, at(9), at(10)), event(2, at(11), at(12))],
        day
      );

      expect(items.every(i => i.style.width === '100%')).toBe(true);
    });

    it('reutiliza una pista libre en vez de abrir una nueva', () => {
      const items = positionedEvents(
        [
          event(1, at(9), at(10)),
          event(2, at(9), at(11)),
          event(3, at(10), at(11)),
        ],
        day
      );

      // Tres eventos, pero solo dos coinciden a la vez: el tercero hereda la pista que
      // dejó libre el que ya terminó, así que bastan dos columnas.
      expect(items.every(i => i.columns === 2)).toBe(true);
      const tercero = items.find(i => i.event.id === 3);
      const primero = items.find(i => i.event.id === 1);
      expect(tercero.column).toBe(primero.column);
    });
  });

  describe('reparto del ancho', () => {
    it('da todo el ancho a un evento solo', () => {
      const [item] = positionedEvents([event(1, at(10), at(11))], day);

      expect(item.style.width).toBe('100%');
      expect(item.style.left).toBe('0%');
    });

    // Con cuatro citas a la vez, repartir a partes iguales deja tarjetas ilegibles: se
    // escalonan y se solapan un poco, como en cualquier agenda.
    it('escalona los solapados en vez de dejarlos en tiras finas', () => {
      const items = positionedEvents(
        [
          event(1, at(10), at(12)),
          event(2, at(10), at(12)),
          event(3, at(10), at(12)),
          event(4, at(10), at(12)),
        ],
        day
      );

      const anchos = items.map(i => parseFloat(i.style.width));
      // Cada tarjeta es más ancha que su cuarto exacto (25%).
      expect(anchos.every(w => w > 25)).toBe(true);
    });

    it('la última llega hasta el borde derecho', () => {
      const items = positionedEvents(
        [event(1, at(10), at(12)), event(2, at(10), at(12))],
        day
      );
      const ultima = items.find(i => i.column === i.columns - 1);

      expect(
        parseFloat(ultima.style.left) + parseFloat(ultima.style.width)
      ).toBeCloseTo(100);
    });

    it('apila las tarjetas para que la de la derecha quede encima', () => {
      const items = positionedEvents(
        [event(1, at(10), at(12)), event(2, at(11), at(13))],
        day
      );
      const ordenadas = [...items].sort((a, b) => a.column - b.column);

      expect(ordenadas[1].style.zIndex).toBeGreaterThan(
        ordenadas[0].style.zIndex
      );
    });
  });

  describe('eventos que cruzan la medianoche', () => {
    it('recorta al inicio del día el que viene de ayer', () => {
      const ayer = new Date(2026, 8, 27, 22).toISOString();
      const [item] = positionedEvents([event(1, ayer, at(2))], day);

      expect(item.top).toBe(0);
    });

    it('lo extiende hasta el final si sigue mañana', () => {
      const manana = new Date(2026, 8, 29, 3).toISOString();
      const [item] = positionedEvents([event(1, at(22), manana)], day);

      expect(item.top + item.height).toBeCloseTo(DAY_HEIGHT);
    });
  });

  describe('todo el día', () => {
    it('los saca de la rejilla horaria', () => {
      const items = positionedEvents(
        [event(1, at(0), at(23), { all_day: true }), event(2, at(10), at(11))],
        day
      );

      expect(items).toHaveLength(1);
      expect(items[0].event.id).toBe(2);
    });

    it('los devuelve aparte para su propio carril', () => {
      const todoElDia = event(1, at(0), at(23), { all_day: true });

      expect(allDayEvents([todoElDia, event(2, at(10), at(11))])).toEqual([
        todoElDia,
      ]);
    });
  });

  describe('línea de ahora', () => {
    it('no la dibuja en un día que no es hoy', () => {
      expect(nowOffset(new Date(2020, 0, 1))).toBeNull();
    });

    it('la sitúa según la hora actual', () => {
      const hoy = new Date();
      const esperado = (minutesFromMidnight(hoy) / 1440) * DAY_HEIGHT;

      expect(nowOffset(hoy)).toBeCloseTo(esperado, 0);
    });
  });

  it('tolera una lista vacía o nula', () => {
    expect(positionedEvents([], day)).toEqual([]);
    expect(positionedEvents(null, day)).toEqual([]);
    expect(allDayEvents(null)).toEqual([]);
  });
});
