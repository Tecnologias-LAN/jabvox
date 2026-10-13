import campaigns from '../campaigns';
import ApiClient from '../ApiClient';

describe('#CampaignAPI', () => {
  it('creates correct instance', () => {
    expect(campaigns).toBeInstanceOf(ApiClient);
    expect(campaigns).toHaveProperty('get');
  });
});
