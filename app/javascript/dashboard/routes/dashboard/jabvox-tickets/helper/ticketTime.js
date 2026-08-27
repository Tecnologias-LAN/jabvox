// Formateo de tiempos en formato humano compacto para el módulo de tickets:
// "2h 15m", "3d 4h", "5m". Sin dependencias externas.

// Convierte una cantidad de minutos (>=0) a texto compacto tipo "3d 4h" / "2h 15m".
export function humanizeMinutes(totalMinutes) {
  const mins = Math.max(0, Math.round(totalMinutes));
  if (mins === 0) return '0m';

  const days = Math.floor(mins / 1440);
  const hours = Math.floor((mins % 1440) / 60);
  const minutes = mins % 60;

  const parts = [];
  if (days > 0) parts.push(`${days}d`);
  if (hours > 0) parts.push(`${hours}h`);
  // Solo mostramos minutos si no hay días (para no saturar en rangos largos).
  if (minutes > 0 && days === 0) parts.push(`${minutes}m`);
  return parts.slice(0, 2).join(' ') || '0m';
}

// Minutos transcurridos desde una fecha ISO hasta ahora.
export function minutesSince(iso) {
  if (!iso) return null;
  return Math.round((Date.now() - new Date(iso).getTime()) / 60000);
}

// Minutos entre dos fechas ISO (b - a). Útil para tiempo de resolución.
export function minutesBetween(aIso, bIso) {
  if (!aIso || !bIso) return null;
  return Math.round(
    (new Date(bIso).getTime() - new Date(aIso).getTime()) / 60000
  );
}

// Texto de tiempo transcurrido desde creación: "hace 2h 15m".
export function elapsedLabel(iso, t) {
  const mins = minutesSince(iso);
  if (mins === null) return '—';
  return t('JABVOX_TICKETS.TIME.AGO', { time: humanizeMinutes(mins) });
}
