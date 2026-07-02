/* global axios */
import ApiClient from '../ApiClient';

const cdrClient = new ApiClient('jabvox/cdr', { accountScoped: true });

const base = cdrClient.url;

export const cdrReportsAPI = {
  myAccess: () => axios.get(`${base}/my_access`),
  records: params => axios.get(`${base}/records`, { params }),
  summary: params => axios.get(`${base}/summary`, { params }),
  analyze: data => axios.post(`${base}/analyze`, data),
  getAnalysis: uniqueid =>
    axios.get(`${base}/analysis/${encodeURIComponent(uniqueid)}`),
  analysesBatch: uniqueids =>
    axios.post(`${base}/analyses_batch`, { uniqueids }),
  // Fetches the recording as a blob and returns a one-shot object URL for an
  // <audio> element. The PBX path/credentials never reach the client; the blob
  // URL is local to this tab and should be revoked when playback closes.
  recordingObjectUrl: async uniqueid => {
    const { data } = await axios.get(
      `${base}/analysis/${encodeURIComponent(uniqueid)}/recording`,
      { responseType: 'blob' }
    );
    return URL.createObjectURL(data);
  },
};

export const cdrConfigAPI = {
  get: () => axios.get(`${base}/config`),
  update: config => axios.patch(`${base}/config`, { config }),
  test: config => axios.post(`${base}/config/test`, { config }),
  testSsh: config => axios.post(`${base}/config/test_ssh`, { config }),
};

export const cdrPipelinesAPI = {
  getAll: () => axios.get(`${base}/pipelines`),
  create: pipeline => axios.post(`${base}/pipelines`, { pipeline }),
  update: (id, pipeline) =>
    axios.patch(`${base}/pipelines/${id}`, { pipeline }),
  destroy: id => axios.delete(`${base}/pipelines/${id}`),
};
