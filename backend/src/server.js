const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const query = (text, params) => pool.query(text, params);

// AUTH
app.post('/api/auth/login', async (req, res) => {
  try {
    const { pin } = req.body;
    const r = await query('SELECT id,nome,pin,cargo,img FROM staff WHERE pin=$1 AND ativo=true', [pin]);
    if (!r.rows.length) return res.status(401).json({ error: 'PIN incorreto' });
    const u = r.rows[0];
    const token = jwt.sign({ id:u.id, nome:u.nome, cargo:u.cargo }, process.env.JWT_SECRET, { expiresIn:'12h' });
    res.json({ token, user: { id:u.id, nome:u.nome, cargo:u.cargo, img:u.img } });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

const auth = (req, res, next) => {
  const t = req.headers.authorization?.split(' ')[1];
  if(!t) return res.status(401).json({ error:'Token necessario' });
  try { req.user = jwt.verify(t, process.env.JWT_SECRET); next(); }
  catch { res.status(401).json({ error:'Token invalido' }); }
};
const gerente = (req,res,next) => { if(req.user.cargo!=='gerente') return res.status(403).json({error:'Acesso negado'}); next(); };

// STAFF
app.get('/api/staff', auth, async(req,res) => {
  try { const r = await query('SELECT id,nome,cargo,img,ativo FROM staff ORDER BY id'); res.json(r.rows); }
  catch(e) { res.status(500).json({error:e.message}); }
});

// CARDAPIO
app.get('/api/cardapio', async(req,res) => {
  try { const r = await query('SELECT c.*,cat.nome as categoria FROM cardapio c JOIN categorias cat ON c.categoria_id=cat.id WHERE c.ativo=true ORDER BY cat.ordem,c.nome'); res.json(r.rows); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.post('/api/cardapio', auth, gerente, async(req,res) => {
  try { const{nome,preco,categoria_id,emoji,foto}=req.body; const r=await query('INSERT INTO cardapio(nome,preco,categoria_id,emoji,foto) VALUES($1,$2,$3,$4,$5) RETURNING *',[nome,preco,categoria_id,emoji||'🍽️',foto]); res.json(r.rows[0]); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.put('/api/cardapio/:id', auth, gerente, async(req,res) => {
  try { const{nome,preco,emoji,foto}=req.body; const r=await query('UPDATE cardapio SET nome=$1,preco=$2,emoji=$3,foto=$4 WHERE id=$5 RETURNING *',[nome,preco,emoji,foto,req.params.id]); res.json(r.rows[0]); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.delete('/api/cardapio/:id', auth, gerente, async(req,res) => {
  try { await query('UPDATE cardapio SET ativo=false WHERE id=$1',[req.params.id]); res.json({ok:true}); }
  catch(e) { res.status(500).json({error:e.message}); }
});

// MESAS
app.get('/api/mesas', auth, async(req,res) => {
  try { const r=await query('SELECT m.*,c.id as conta_id,c.cliente,c.aberta_em,c.status as conta_status,s.nome as garcom_nome FROM mesas m LEFT JOIN contas c ON c.mesa_id=m.id AND c.status=$$aberta$$ LEFT JOIN staff s ON c.garcom_id=s.id ORDER BY m.numero'); res.json(r.rows); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.post('/api/mesas/:numero/abrir', auth, async(req,res) => {
  try {
    const{cliente,garcom_id}=req.body;
    const m=await query('SELECT id FROM mesas WHERE numero=$1',[req.params.numero]);
    if(!m.rows.length) return res.status(404).json({error:'Mesa nao encontrada'});
    await query('UPDATE mesas SET status=$1 WHERE numero=$2',['ocupada',req.params.numero]);
    const c=await query('INSERT INTO contas(mesa_id,garcom_id,cliente) VALUES($1,$2,$3) RETURNING *',[m.rows[0].id,garcom_id,cliente]);
    res.json(c.rows[0]);
  } catch(e) { res.status(500).json({error:e.message}); }
});

// PEDIDOS
app.get('/api/contas/:id/pedidos', auth, async(req,res) => {
  try { const r=await query('SELECT * FROM pedidos WHERE conta_id=$1 ORDER BY criado_em',[req.params.id]); res.json(r.rows); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.post('/api/contas/:id/pedidos', auth, async(req,res) => {
  try {
    const{cardapio_id,nome_item,preco_unit,quantidade}=req.body;
    const hora=new Date().toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});
    const r=await query('INSERT INTO pedidos(conta_id,cardapio_id,nome_item,preco_unit,quantidade,hora) VALUES($1,$2,$3,$4,$5,$6) RETURNING *',[req.params.id,cardapio_id,nome_item,preco_unit,quantidade,hora]);
    await query('UPDATE contas SET subtotal=(SELECT COALESCE(SUM(preco_unit*quantidade),0) FROM pedidos WHERE conta_id=$1),taxa_servico=(SELECT COALESCE(SUM(preco_unit*quantidade),0)*0.10 FROM pedidos WHERE conta_id=$1),total=(SELECT COALESCE(SUM(preco_unit*quantidade),0)*1.10 FROM pedidos WHERE conta_id=$1) WHERE id=$1',[req.params.id]);
    res.json(r.rows[0]);
  } catch(e) { res.status(500).json({error:e.message}); }
});
app.delete('/api/pedidos/:id', auth, async(req,res) => {
  try {
    const p=await query('SELECT conta_id FROM pedidos WHERE id=$1',[req.params.id]);
    await query('DELETE FROM pedidos WHERE id=$1',[req.params.id]);
    if(p.rows.length){const cid=p.rows[0].conta_id; await query('UPDATE contas SET subtotal=(SELECT COALESCE(SUM(preco_unit*quantidade),0) FROM pedidos WHERE conta_id=$1),taxa_servico=(SELECT COALESCE(SUM(preco_unit*quantidade),0)*0.10 FROM pedidos WHERE conta_id=$1),total=(SELECT COALESCE(SUM(preco_unit*quantidade),0)*1.10 FROM pedidos WHERE conta_id=$1) WHERE id=$1',[cid]);}
    res.json({ok:true});
  } catch(e) { res.status(500).json({error:e.message}); }
});
app.post('/api/contas/:id/cozinha', auth, async(req,res) => {
  try { const{descricao}=req.body; await query('INSERT INTO cozinha_envios(conta_id,descricao) VALUES($1,$2)',[req.params.id,descricao]); await query("UPDATE pedidos SET status='preparando' WHERE conta_id=$1 AND status='pendente'",[req.params.id]); res.json({ok:true}); }
  catch(e) { res.status(500).json({error:e.message}); }
});

// FECHAR CONTA
app.post('/api/contas/:id/fechar', auth, gerente, async(req,res) => {
  try {
    const{forma_pagamento}=req.body;
    const c=await query('SELECT c.*,m.numero as mesa_numero,s.nome as garcom_nome FROM contas c JOIN mesas m ON c.mesa_id=m.id JOIN staff s ON c.garcom_id=s.id WHERE c.id=$1',[req.params.id]);
    if(!c.rows.length) return res.status(404).json({error:'Conta nao encontrada'});
    const ct=c.rows[0]; const ps=await query('SELECT nome_item as name,quantidade as qty,preco_unit as price FROM pedidos WHERE conta_id=$1',[req.params.id]);
    const codigo='#'+(1000+Math.floor(Math.random()*9000)); const hora=new Date().toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});
    await query('INSERT INTO historico_vendas(codigo,mesa_numero,cliente_nome,garcom_nome,forma_pagamento,subtotal,taxa_servico,total,itens,hora) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',[codigo,ct.mesa_numero,ct.cliente,ct.garcom_nome,forma_pagamento,ct.subtotal,ct.taxa_servico,ct.total,JSON.stringify(ps.rows),hora]);
    await query("UPDATE contas SET status='fechada',forma_pagamento=$1,fechada_em=NOW() WHERE id=$2",[forma_pagamento,req.params.id]);
    await query("UPDATE mesas SET status='livre' WHERE id=$1",[ct.mesa_id]);
    res.json({codigo,total:ct.total});
  } catch(e) { res.status(500).json({error:e.message}); }
});

// RESERVAS
app.get('/api/reservas', auth, async(req,res) => {
  try { const r=await query('SELECT r.*,m.numero as mesa_numero FROM reservas r JOIN mesas m ON r.mesa_id=m.id WHERE r.data_reserva=CURRENT_DATE ORDER BY r.hora'); res.json(r.rows); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.post('/api/reservas', auth, async(req,res) => {
  try { const{nome,mesa_id,hora,pessoas,telefone,observacoes}=req.body; const r=await query('INSERT INTO reservas(nome,mesa_id,hora,pessoas,telefone,observacoes) VALUES($1,$2,$3,$4,$5,$6) RETURNING *',[nome,mesa_id,hora,pessoas||2,telefone,observacoes]); await query("UPDATE mesas SET status='reservada' WHERE id=$1",[mesa_id]); res.json(r.rows[0]); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.put('/api/reservas/:id/confirmar', auth, async(req,res) => {
  try { await query('UPDATE reservas SET confirmada=true WHERE id=$1',[req.params.id]); res.json({ok:true}); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.delete('/api/reservas/:id', auth, async(req,res) => {
  try { const rv=await query('SELECT mesa_id FROM reservas WHERE id=$1',[req.params.id]); await query('DELETE FROM reservas WHERE id=$1',[req.params.id]); if(rv.rows.length) await query("UPDATE mesas SET status='livre' WHERE id=$1",[rv.rows[0].mesa_id]); res.json({ok:true}); }
  catch(e) { res.status(500).json({error:e.message}); }
});

// RELATORIOS
app.get('/api/relatorios/hoje', auth, gerente, async(req,res) => {
  try {
    const vendas=await query("SELECT * FROM historico_vendas WHERE data_venda=CURRENT_DATE ORDER BY criado_em DESC");
    const total=await query("SELECT COALESCE(SUM(total),0) as total,COUNT(*) as contas FROM historico_vendas WHERE data_venda=CURRENT_DATE");
    const pgto=await query("SELECT forma_pagamento,SUM(total) as total FROM historico_vendas WHERE data_venda=CURRENT_DATE GROUP BY forma_pagamento");
    const garcom=await query("SELECT garcom_nome,SUM(total) as total,COUNT(*) as qtd FROM historico_vendas WHERE data_venda=CURRENT_DATE GROUP BY garcom_nome");
    const mesa=await query("SELECT mesa_numero,SUM(total) as total FROM historico_vendas WHERE data_venda=CURRENT_DATE GROUP BY mesa_numero ORDER BY total DESC LIMIT 5");
    res.json({vendas:vendas.rows,resumo:total.rows[0],porPagamento:pgto.rows,porGarcom:garcom.rows,porMesa:mesa.rows});
  } catch(e) { res.status(500).json({error:e.message}); }
});
app.get('/api/relatorios/cliente/:nome', auth, gerente, async(req,res) => {
  try { const r=await query("SELECT * FROM historico_vendas WHERE cliente_nome=$1 ORDER BY criado_em DESC",[req.params.nome]); res.json(r.rows); }
  catch(e) { res.status(500).json({error:e.message}); }
});

// CLIENTES
app.get('/api/clientes', auth, async(req,res) => {
  try { const r=await query('SELECT * FROM clientes ORDER BY total_gasto DESC'); res.json(r.rows); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.post('/api/clientes', auth, async(req,res) => {
  try { const{nome,telefone,email,cpf}=req.body; const r=await query('INSERT INTO clientes(nome,telefone,email,cpf) VALUES($1,$2,$3,$4) RETURNING *',[nome,telefone,email,cpf]); res.json(r.rows[0]); }
  catch(e) { res.status(500).json({error:e.message}); }
});

// COZINHA
app.get('/api/cozinha', auth, async(req,res) => {
  try { const r=await query("SELECT p.*,c.cliente,m.numero as mesa_numero,s.nome as garcom_nome FROM pedidos p JOIN contas c ON p.conta_id=c.id JOIN mesas m ON c.mesa_id=m.id JOIN staff s ON c.garcom_id=s.id WHERE c.status='aberta' AND p.status IN('pendente','preparando') ORDER BY p.criado_em"); res.json(r.rows); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.put('/api/cozinha/:id/pronto', auth, async(req,res) => {
  try { await query("UPDATE pedidos SET status='pronto' WHERE id=$1",[req.params.id]); res.json({ok:true}); }
  catch(e) { res.status(500).json({error:e.message}); }
});

// CONFIG
app.get('/api/config', auth, async(req,res) => {
  try { const r=await query('SELECT chave,valor FROM config'); const cfg={}; r.rows.forEach(x=>cfg[x.chave]=x.valor); res.json(cfg); }
  catch(e) { res.status(500).json({error:e.message}); }
});
app.put('/api/config', auth, gerente, async(req,res) => {
  try { for(const[k,v] of Object.entries(req.body)) await query('INSERT INTO config(chave,valor) VALUES($1,$2) ON CONFLICT(chave) DO UPDATE SET valor=$2,atualizado_em=NOW()',[k,v]); res.json({ok:true}); }
  catch(e) { res.status(500).json({error:e.message}); }
});

// HEALTH
app.get('/api/health', async(req,res) => {
  try { await query('SELECT 1'); res.json({status:'ok',db:'connected',time:new Date().toISOString()}); }
  catch(e) { res.json({status:'error',db:'disconnected'}); }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log('PDV API rodando na porta ' + PORT));
