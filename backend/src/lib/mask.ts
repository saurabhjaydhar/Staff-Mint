/** PAN shown on slips and screens: AB XXXXX 4F (first 2 and last 3 kept). */
export const maskPan = (pan: string) => (pan.length === 10 ? `${pan.slice(0, 2)}XXXXX${pan.slice(7)}` : 'XXXXXXXXXX');
