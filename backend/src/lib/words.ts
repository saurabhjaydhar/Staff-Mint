// Amounts in words for salary slips, Indian style (lakh, crore), in English and Hindi.

const EN_ONES = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const EN_TENS = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

// Hindi numbers 1–99 are irregular, so they are listed in full.
const HI_1_99 = (
  'एक दो तीन चार पाँच छह सात आठ नौ दस ग्यारह बारह तेरह चौदह पंद्रह सोलह सत्रह अठारह उन्नीस बीस ' +
  'इक्कीस बाईस तेईस चौबीस पच्चीस छब्बीस सत्ताईस अट्ठाईस उनतीस तीस इकतीस बत्तीस तैंतीस चौंतीस पैंतीस छत्तीस सैंतीस अड़तीस उनतालीस चालीस ' +
  'इकतालीस बयालीस तैंतालीस चवालीस पैंतालीस छियालीस सैंतालीस अड़तालीस उनचास पचास इक्यावन बावन तिरपन चौवन पचपन छप्पन सत्तावन अट्ठावन उनसठ साठ ' +
  'इकसठ बासठ तिरसठ चौंसठ पैंसठ छियासठ सड़सठ अड़सठ उनहत्तर सत्तर इकहत्तर बहत्तर तिहत्तर चौहत्तर पचहत्तर छिहत्तर सतहत्तर अठहत्तर उन्यासी अस्सी ' +
  'इक्यासी बयासी तिरासी चौरासी पचासी छियासी सत्तासी अट्ठासी नवासी नब्बे इक्यानवे बानवे तिरानवे चौरानवे पंचानवे छियानवे सत्तानवे अट्ठानवे निन्यानवे'
).split(' ');

function en99(n: number): string {
  if (n < 20) return EN_ONES[n];
  return [EN_TENS[Math.floor(n / 10)], EN_ONES[n % 10]].filter(Boolean).join('-');
}
const hi99 = (n: number) => (n ? HI_1_99[n - 1] : '');

/** Splits a whole number into crore, lakh, thousand, hundred and the rest. */
function parts(n: number) {
  return { crore: Math.floor(n / 1e7), lakh: Math.floor((n % 1e7) / 1e5), thousand: Math.floor((n % 1e5) / 1e3), hundred: Math.floor((n % 1e3) / 100), rest: n % 100 };
}

export function rupeesInWordsEn(paise: number): string {
  const rupees = Math.floor(Math.abs(paise) / 100);
  const p = Math.round(Math.abs(paise) % 100);
  if (rupees === 0 && p === 0) return 'Rupees Zero Only';
  const x = parts(rupees);
  const words: string[] = [];
  if (x.crore) words.push(`${rupeesInWordsEn(x.crore * 100).replace(/^Rupees | Only$/g, '')} Crore`);
  if (x.lakh) words.push(`${en99(x.lakh)} Lakh`);
  if (x.thousand) words.push(`${en99(x.thousand)} Thousand`);
  if (x.hundred) words.push(`${EN_ONES[x.hundred]} Hundred`);
  if (x.rest) words.push(en99(x.rest));
  const main = words.length ? `Rupees ${words.join(' ')}` : 'Rupees Zero';
  return `${main}${p ? ` and ${en99(p)} Paise` : ''} Only`;
}

export function rupeesInWordsHi(paise: number): string {
  const rupees = Math.floor(Math.abs(paise) / 100);
  const p = Math.round(Math.abs(paise) % 100);
  if (rupees === 0 && p === 0) return 'शून्य रुपये';
  const x = parts(rupees);
  const words: string[] = [];
  if (x.crore) words.push(`${rupeesInWordsHi(x.crore * 100).replace(/ रुपये$/, '')} करोड़`);
  if (x.lakh) words.push(`${hi99(x.lakh)} लाख`);
  if (x.thousand) words.push(`${hi99(x.thousand)} हज़ार`);
  if (x.hundred) words.push(`${hi99(x.hundred)} सौ`);
  if (x.rest) words.push(hi99(x.rest));
  return `${words.join(' ') || 'शून्य'} रुपये${p ? ` ${hi99(p)} पैसे` : ''}`;
}
