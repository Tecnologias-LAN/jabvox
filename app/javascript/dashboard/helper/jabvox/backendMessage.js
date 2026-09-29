// Mensaje de error del backend, listo para `useAlert`.
//
// useAlert pasa el texto por vue-i18n, que interpreta `{...}` como placeholder y lanza
// "Not allowed nest placeholder" si el mensaje trae llaves —un campo JSON, un hash en un
// error de validación—. Esa excepción rompía la acción entera en vez de mostrar el aviso,
// así que las llaves se retiran antes de entregarlo.
//
// Devuelve null si la respuesta no trae mensaje, para que quien llame use su texto por
// defecto traducido.
export const backendMessage = error => {
  const data = error?.response?.data;
  const raw =
    data?.message ||
    data?.error ||
    (Array.isArray(data?.errors) ? data.errors.join(', ') : null);

  return raw ? String(raw).replace(/[{}]/g, '') : null;
};

export default backendMessage;
