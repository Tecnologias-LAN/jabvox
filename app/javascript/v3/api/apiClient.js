import axios from 'axios';

const { apiHost = '' } = window.jabvoxConfig || {};
const wootAPI = axios.create({ baseURL: `${apiHost}/` });

export default wootAPI;
