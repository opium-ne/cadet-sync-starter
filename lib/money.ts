// Display-side mirror of the SQL function calc_split(). The database is the source of truth;
// this exists so the UI can show the same numbers. Integer paisa avoids floating-point drift.
// Rule: commission = round-half-up(price × rate) to the paisa; author = price − commission.

export const toPaisa = (taka: number | string): number => Math.round(Number(taka) * 100);
export const toTaka = (paisa: number): number => paisa / 100;

export function splitSale(priceTaka: number | string, rateBps = 1000) {
  const price = toPaisa(priceTaka);
  const commission = Math.floor((price * rateBps + 5000) / 10000); // half-up
  const author = price - commission;
  return { price: toTaka(price), commission: toTaka(commission), author: toTaka(author) };
}

export const formatBdt = (taka: number | string) =>
  '৳' + Number(taka).toLocaleString('en-BD', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
