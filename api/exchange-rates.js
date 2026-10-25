module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=900');
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const codes = ['USD', 'THB'];
    const quotes = await Promise.all(codes.map(async (code) => {
      const response = await fetch(`https://api.stock.naver.com/marketindex/exchange/FX_${code}KRW`, {
        headers: { Accept: 'application/json' }
      });
      if (!response.ok) throw new Error(`Naver ${code} rate request failed`);
      const payload = await response.json();
      const quote = payload.exchangeInfo || payload;
      const rate = Number(String(quote.calcPrice || quote.closePrice || '').replace(/,/g, ''));
      if (!Number.isFinite(rate) || rate <= 0) throw new Error(`Invalid Naver ${code} rate`);
      return { code, rate, updatedAt: quote.localTradedAt || '' };
    }));
    return res.status(200).json({
      source: 'Naver Securities · Hana Bank base rate',
      rates: { KRW: 1, USD: quotes.find((x) => x.code === 'USD').rate, THB: quotes.find((x) => x.code === 'THB').rate, USDT: quotes.find((x) => x.code === 'USD').rate },
      updatedAt: quotes.map((x) => x.updatedAt).filter(Boolean).sort()[0] || new Date().toISOString()
    });
  } catch (error) {
    return res.status(502).json({ error: 'Unable to load Naver exchange rates' });
  }
};
