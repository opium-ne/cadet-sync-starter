import { describe, it, expect } from 'vitest';
import { splitSale } from '../lib/money';

describe('splitSale (10% commission, half-up to paisa)', () => {
  it('৳100 -> 90 / 10', () => expect(splitSale(100)).toEqual({ price: 100, commission: 10, author: 90 }));
  it('৳250 -> 225 / 25', () => expect(splitSale(250)).toEqual({ price: 250, commission: 25, author: 225 }));
  it('৳99.99 -> commission 10.00, author 89.99', () => expect(splitSale(99.99)).toEqual({ price: 99.99, commission: 10, author: 89.99 }));
  it('parts always add up exactly', () => {
    for (const p of [1, 7, 19.95, 69, 99, 149.5, 333.33, 1000]) {
      const s = splitSale(p);
      expect(Math.round((s.commission + s.author) * 100)).toBe(Math.round(s.price * 100));
    }
  });
});
