import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner } from './helpers.js';

describe('geo (shop location picker)', () => {
  it('searches places by name and turns a pin into an address; needs sign-in', async () => {
    const owner = await createOwner();
    const r = await api().get(`${V}/geo/search`).query({ q: 'karol bagh', lat: 28.63, lng: 77.21 }).set(auth(owner.token)).expect(200);
    expect(r.body.data[0]).toMatchObject({ name: 'Karol Bagh Market', lat: expect.any(Number), lng: expect.any(Number) });
    expect(r.body.data[0].address).toContain('New Delhi');

    const rev = await api().get(`${V}/geo/reverse`).query({ lat: 28.6315, lng: 77.2167 }).set(auth(owner.token)).expect(200);
    expect(rev.body.data.address).toContain('Connaught Place');

    expect((await api().get(`${V}/geo/search`).query({ q: 'k' }).set(auth(owner.token))).status).toBe(400);
    expect((await api().get(`${V}/geo/reverse`).query({ lat: 200, lng: 77 }).set(auth(owner.token))).status).toBe(400);
    expect((await api().get(`${V}/geo/search`).query({ q: 'karol' })).status).toBe(401);
  });
});
