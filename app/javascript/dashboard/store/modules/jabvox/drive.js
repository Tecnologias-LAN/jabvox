import driveAPI from '../../../api/jabvox/drive';

// Normaliza respuestas que pueden venir como { payload: [...] } o como [...].
const normalizeList = data => {
  if (Array.isArray(data?.payload)) return data.payload;
  if (Array.isArray(data)) return data;
  return [];
};

const normalizeObject = data => {
  if (data?.payload && !Array.isArray(data.payload)) return data.payload;
  return data;
};

const state = {
  folders: [],
  files: [],
  storage: null,
  meta: {
    currentPage: 1,
    totalPages: 1,
    totalCount: 0,
  },
  uiFlags: {
    isFetchingFolders: false,
    isFetchingFiles: false,
    isFetchingStorage: false,
    isUploading: false,
  },
};

export const getters = {
  getFolders: _state => _state.folders,
  getFiles: _state => _state.files,
  getStorage: _state => _state.storage,
  getMeta: _state => _state.meta,
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  // --- Carpetas ---
  fetchFolders: async ({ commit }, params = {}) => {
    commit('SET_UI_FLAG', { isFetchingFolders: true });
    try {
      const response = await driveAPI.getFolders(params);
      commit('SET_FOLDERS', normalizeList(response.data));
      return response.data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isFetchingFolders: false });
    }
  },

  createFolder: async ({ commit }, payload) => {
    const response = await driveAPI.createFolder(payload);
    const folder = normalizeObject(response.data);
    commit('ADD_FOLDER', folder);
    return folder;
  },

  renameFolder: async ({ commit }, { id, name }) => {
    const response = await driveAPI.renameFolder(id, name);
    const folder = normalizeObject(response.data);
    commit('UPDATE_FOLDER', folder);
    return folder;
  },

  deleteFolder: async ({ commit }, id) => {
    await driveAPI.deleteFolder(id);
    commit('REMOVE_FOLDER', id);
  },

  // --- Archivos ---
  fetchFiles: async ({ commit }, params = {}) => {
    commit('SET_UI_FLAG', { isFetchingFiles: true });
    try {
      const response = await driveAPI.getFiles(params);
      commit('SET_FILES', normalizeList(response.data));
      // El backend puede devolver meta de paginación en data.meta.
      const meta = response.data?.meta;
      if (meta) {
        commit('SET_META', {
          currentPage: meta.current_page || params.page || 1,
          totalPages: meta.total_pages || 1,
          totalCount: meta.total_count || 0,
        });
      }
      return response.data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isFetchingFiles: false });
    }
  },

  uploadFile: async ({ commit }, { payload, onUploadProgress }) => {
    commit('SET_UI_FLAG', { isUploading: true });
    try {
      const response = await driveAPI.uploadFile(payload, { onUploadProgress });
      const file = normalizeObject(response.data);
      commit('ADD_FILE', file);
      return file;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isUploading: false });
    }
  },

  updateFile: async ({ commit }, { id, ...data }) => {
    const response = await driveAPI.updateFile(id, data);
    const file = normalizeObject(response.data);
    commit('UPDATE_FILE', file);
    return file;
  },

  deleteFile: async ({ commit }, id) => {
    await driveAPI.deleteFile(id);
    commit('REMOVE_FILE', id);
  },

  // Borrado masivo: borra en serie y refleja en el estado.
  bulkDeleteFiles: async ({ commit }, ids) => {
    await Promise.all(ids.map(id => driveAPI.deleteFile(id)));
    ids.forEach(id => commit('REMOVE_FILE', id));
  },

  // Movimiento masivo de archivos a una carpeta (folderId=null => raíz).
  bulkMoveFiles: async ({ commit }, { ids, folderId }) => {
    await Promise.all(ids.map(id => driveAPI.updateFile(id, { folderId })));
    // Los archivos movidos salen de la vista actual de la carpeta.
    ids.forEach(id => commit('REMOVE_FILE', id));
  },

  // --- Cuota ---
  fetchStorage: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetchingStorage: true });
    try {
      const response = await driveAPI.getStorage();
      commit('SET_STORAGE', normalizeObject(response.data));
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isFetchingStorage: false });
    }
  },
};

export const mutations = {
  SET_UI_FLAG(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },

  SET_FOLDERS(_state, folders) {
    _state.folders = folders;
  },

  ADD_FOLDER(_state, folder) {
    _state.folders.push(folder);
  },

  UPDATE_FOLDER(_state, updated) {
    const idx = _state.folders.findIndex(f => f.id === updated.id);
    if (idx !== -1) _state.folders.splice(idx, 1, updated);
  },

  REMOVE_FOLDER(_state, id) {
    _state.folders = _state.folders.filter(f => f.id !== id);
  },

  SET_FILES(_state, files) {
    _state.files = files;
  },

  ADD_FILE(_state, file) {
    _state.files.unshift(file);
  },

  UPDATE_FILE(_state, updated) {
    const idx = _state.files.findIndex(f => f.id === updated.id);
    if (idx !== -1) _state.files.splice(idx, 1, updated);
  },

  REMOVE_FILE(_state, id) {
    _state.files = _state.files.filter(f => f.id !== id);
  },

  SET_META(_state, meta) {
    _state.meta = { ..._state.meta, ...meta };
  },

  SET_STORAGE(_state, storage) {
    _state.storage = storage;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
