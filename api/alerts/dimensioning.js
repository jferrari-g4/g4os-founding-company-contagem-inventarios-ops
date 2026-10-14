export default async function handler(req, res) {
  if (req.headers.authorization !== `Bearer ${process.env.CRON_SECRET}`) {
    return res.status(401).json({ error: 'Não autorizado' });
  }
  const base = String(process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const response = await fetch(`${base}/functions/v1/dimensioning-alerts`, {
    method: 'POST',
    headers: { Authorization: req.headers.authorization, 'Content-Type': 'application/json' },
    body: '{}',
  });
  const body = await response.json().catch(() => ({ error: 'Resposta inválida do Supabase' }));
  return res.status(response.status).json(body);
}
