import axios from 'axios';
import { actions } from '../../campaigns';
import * as types from '../../../mutation-types';
import campaignList from './fixtures';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#get', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue({ data: campaignList });
      await actions.get({ commit }, { inboxId: 23 });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CAMPAIGNS, campaignList],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.get({ commit }, { inboxId: 23 });
      expect(commit).not.toHaveBeenCalled();
    });
  });
});
