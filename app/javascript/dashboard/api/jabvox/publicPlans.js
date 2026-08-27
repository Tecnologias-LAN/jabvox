/* global axios */

// Planes públicos (sin autenticación): se muestran en el modal de pago para que el
// admin elija qué plan comprar. Endpoint público /public/plans.
export default {
  getAll: () => axios.get('/public/plans'),
  getBySlug: slug => axios.get(`/public/plans/${slug}`),
};
