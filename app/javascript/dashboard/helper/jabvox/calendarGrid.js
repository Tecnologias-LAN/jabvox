// Coloca los eventos en la rejilla horaria del calendario (vistas de semana y día).
//
// Antes no existía: las dos vistas apilaban los eventos como una lista dentro de la celda
// del día, así que la hora se mostraba como texto pero no situaba nada. De ahí que "los
// días se vieran bien y las horas no".
//
// Todo se calcula en minutos desde medianoche LOCAL. El backend manda ISO-8601 con zona,
// así que `new Date()` ya devuelve la hora local del navegador; aquí no se vuelve a
// convertir nada.

export const MINUTES_IN_DAY = 1440;

// Alto de una hora en píxeles. Con 72px una cita de 30 min mide 36px: caben dos líneas
// (título y hora) sin recortar, que es lo que se quiere leer de un vistazo.
export const HOUR_HEIGHT = 72;

export const DAY_HEIGHT = 24 * HOUR_HEIGHT;

// Alto mínimo de una tarjeta: una cita de 10 minutos tiene que seguir siendo pulsable con
// el dedo, no solo con el ratón.
const MIN_EVENT_HEIGHT = 26;

// Cuánto invade cada tarjeta la pista de su derecha (1.7 = un 70% más de su reparto).
// Sin esto, cuatro citas simultáneas quedan en columnas ilegibles.
const OVERLAP_FACTOR = 1.7;

export const HOURS = Array.from({ length: 24 }, (_, h) => h);

export const minutesFromMidnight = date =>
  date.getHours() * 60 + date.getMinutes();

const sameDay = (a, b) =>
  a.getFullYear() === b.getFullYear() &&
  a.getMonth() === b.getMonth() &&
  a.getDate() === b.getDate();

// Recorta el evento al día que se está pintando: uno que empieza ayer y acaba hoy se
// dibuja desde las 00:00, y uno que sigue mañana llega hasta el final de la columna.
const clampToDay = (event, day) => {
  const start = new Date(event.start_at);
  const end = new Date(event.end_at);
  return {
    startMinute: sameDay(start, day) ? minutesFromMidnight(start) : 0,
    endMinute: sameDay(end, day) ? minutesFromMidnight(end) : MINUTES_IN_DAY,
  };
};

// Los eventos que se solapan se reparten el ancho de la columna en vez de taparse.
// `column` es la pista que le toca y `columns` cuántas hay en ese grupo.
const assignColumns = positioned => {
  const sorted = [...positioned].sort(
    (a, b) => a.startMinute - b.startMinute || b.endMinute - a.endMinute
  );
  let cluster = [];
  let clusterEnd = -1;

  const closeCluster = () => {
    cluster.forEach(item => {
      item.columns = cluster.reduce(
        (max, other) => Math.max(max, other.column + 1),
        1
      );
    });
    cluster = [];
  };

  sorted.forEach(item => {
    if (item.startMinute >= clusterEnd && cluster.length) closeCluster();

    const taken = new Set(
      cluster
        .filter(other => other.endMinute > item.startMinute)
        .map(o => o.column)
    );
    let column = 0;
    while (taken.has(column)) column += 1;

    item.column = column;
    cluster.push(item);
    clusterEnd = Math.max(clusterEnd, item.endMinute);
  });

  if (cluster.length) closeCluster();
  return sorted;
};

// Reparto del ancho entre eventos que coinciden.
//
// A partes iguales y pegados, con cuatro solapados cada tarjeta queda tan estrecha que no
// se lee nada. Se hace lo que hacen las agendas reales: las tarjetas se escalonan y se
// solapan un poco, de modo que la última ocupa hasta el borde y las de debajo asoman por
// la izquierda lo justo para verse y poder pulsarlas.
const eventStyle = item => {
  const { column, columns } = item;
  const isLast = column === columns - 1;
  // Con una sola columna la tarjeta ocupa todo; a partir de dos, cada una arranca un poco
  // antes de donde acabaría su reparto exacto.
  const slot = 100 / columns;
  // La última arranca más a la izquierda de lo que le tocaría para no quedarse ella con
  // la tira más fina: es la que está encima y la que se lee entera.
  const raw = column * slot;
  const left =
    isLast && columns > 1 ? Math.max(100 - slot * OVERLAP_FACTOR, 0) : raw;
  const width = isLast ? 100 - left : slot * OVERLAP_FACTOR;

  return {
    top: `${item.top}px`,
    height: `${item.height}px`,
    left: `${left}%`,
    width: `${Math.min(width, 100 - left)}%`,
    // La de más a la derecha queda encima: es la que se ve entera.
    zIndex: 10 + column,
  };
};

// Eventos con hora de un día, ya posicionados y repartidos. Los de todo el día quedan
// fuera: van en su propio carril sobre la rejilla, como en cualquier agenda.
export const positionedEvents = (events, day) => {
  const timed = (events || []).filter(event => !event.all_day);
  const positioned = timed.map(event => {
    const { startMinute, endMinute } = clampToDay(event, day);
    const top = (startMinute / MINUTES_IN_DAY) * DAY_HEIGHT;
    const rawHeight = ((endMinute - startMinute) / MINUTES_IN_DAY) * DAY_HEIGHT;
    return {
      event,
      startMinute,
      endMinute,
      top,
      height: Math.max(rawHeight, MIN_EVENT_HEIGHT),
    };
  });

  return assignColumns(positioned).map(item => ({
    ...item,
    style: eventStyle(item),
  }));
};

export const allDayEvents = events => (events || []).filter(e => e.all_day);

// Posición de la línea de "ahora", solo si el día pintado es hoy.
export const nowOffset = day => {
  const now = new Date();
  if (!sameDay(now, day)) return null;

  return (minutesFromMidnight(now) / MINUTES_IN_DAY) * DAY_HEIGHT;
};

export const formatHour = hour => `${String(hour).padStart(2, '0')}:00`;
