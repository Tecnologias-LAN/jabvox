import { getters } from '../../campaigns';
import campaigns from './fixtures';

describe('#getters', () => {
  it('gets campaigns for conversation filters', () => {
    const state = { records: campaigns };
    expect(getters.getAllCampaigns(state)).toEqual(campaigns);
  });
});
