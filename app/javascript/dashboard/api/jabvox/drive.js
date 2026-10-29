/* global axios */
import ApiClient from '../ApiClient';

// Cliente del módulo Jabvox Drive (Drive de archivos por empresa).
// Base: /api/v1/accounts/:accountId/jabvox/drive
class JabvoxDriveAPI extends ApiClient {
  constructor() {
    super('jabvox/drive', { accountScoped: true });
  }

  // --- Carpetas ---

  // Lista carpetas de un nivel (opcionalmente dentro de parent_id o de un contacto).
  // Con `query`, busca carpetas por nombre en toda la cuenta (ignora el nivel).
  getFolders({ parentId = null, contactId = null, query = '' } = {}) {
    return axios.get(`${this.url}/folders`, {
      params: {
        ...(parentId != null ? { parent_id: parentId } : {}),
        ...(contactId != null ? { contact_id: contactId } : {}),
        ...(query ? { query } : {}),
      },
    });
  }

  createFolder({ name, parentId = null }) {
    return axios.post(`${this.url}/folders`, {
      name,
      ...(parentId != null ? { parent_id: parentId } : {}),
    });
  }

  renameFolder(id, name) {
    return axios.patch(`${this.url}/folders/${id}`, { name });
  }

  deleteFolder(id) {
    return axios.delete(`${this.url}/folders/${id}`);
  }

  // --- Archivos ---

  // Lista archivos (paginado) con filtros de tipo, texto y rango de fechas.
  getFiles({
    folderId = null,
    contactId = null,
    query = '',
    type = '',
    from = '',
    to = '',
    page = 1,
  } = {}) {
    return axios.get(`${this.url}/files`, {
      params: {
        ...(folderId != null ? { folder_id: folderId } : {}),
        ...(contactId != null ? { contact_id: contactId } : {}),
        ...(query ? { query } : {}),
        ...(type ? { type } : {}),
        // El backend espera created_after/created_before (filtro por rango de fecha).
        ...(from ? { created_after: from } : {}),
        ...(to ? { created_before: to } : {}),
        page,
      },
    });
  }

  // Sube un archivo (multipart). folderId/contactId opcionales.
  uploadFile({ file, folderId = null, contactId = null }, config = {}) {
    const form = new FormData();
    form.append('file', file);
    if (folderId != null) form.append('folder_id', folderId);
    if (contactId != null) form.append('contact_id', contactId);
    return axios.post(`${this.url}/files`, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
      ...config,
    });
  }

  // Renombra y/o mueve un archivo (folderId=null lo mueve a la raíz).
  updateFile(id, { filename, folderId } = {}) {
    const payload = {};
    if (filename !== undefined) payload.filename = filename;
    if (folderId !== undefined) payload.folder_id = folderId;
    return axios.patch(`${this.url}/files/${id}`, payload);
  }

  // Enviar a la papelera (reversible, no libera espacio aún).
  deleteFile(id) {
    return axios.delete(`${this.url}/files/${id}`);
  }

  // --- Papelera ---

  // Lista los archivos que están en la papelera (borrados, aún no purgados).
  getTrash({ page = 1 } = {}) {
    return axios.get(`${this.url}/files/trash`, { params: { page } });
  }

  // Restaurar un archivo de la papelera (vuelve a estar activo).
  restoreFile(id) {
    return axios.post(`${this.url}/files/${id}/restore`);
  }

  // Eliminar DEFINITIVAMENTE un archivo de la papelera (libera el espacio).
  purgeFile(id) {
    return axios.delete(`${this.url}/files/${id}/purge`);
  }

  // URL de descarga/preview: usar directamente en <img>/<iframe>/<audio>/<video>
  // o en window.open para descargar. El backend responde con redirect a URL
  // firmada corta o con stream.
  downloadUrl(id) {
    return `${this.url}/files/${id}/download`;
  }

  // --- Cuota de almacenamiento ---

  getStorage() {
    return axios.get(`${this.url}/storage`);
  }

  // --- Historial de actividad (auditoría) ---

  getAuditLogs({
    page = 1,
    actionName = null,
    userId = null,
    auditableType = null,
    auditableId = null,
    createdAfter = null,
    createdBefore = null,
  } = {}) {
    const params = { page };
    if (actionName) params.action_name = actionName;
    if (userId) params.user_id = userId;
    if (auditableType) params.auditable_type = auditableType;
    if (auditableId) params.auditable_id = auditableId;
    if (createdAfter) params.created_after = createdAfter;
    if (createdBefore) params.created_before = createdBefore;
    return axios.get(`${this.url}/audit_logs`, { params });
  }
}

export default new JabvoxDriveAPI();
