import types from '../../../mutation-types';
import { mutations } from '../../campaigns';
import campaigns from './fixtures';

describe('#mutations', () => {
  describe('#SET_CAMPAIGNS', () => {
    it('set campaigns records', () => {
      const state = { records: [] };
      mutations[types.SET_CAMPAIGNS](state, campaigns);
      expect(state.records).toEqual(campaigns);
    });
  });
});
