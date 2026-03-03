#!/bin/bash
echo "=========================================="
echo "  MIGRAÇÃO: Multi-Empresa (SaaS)"
echo "=========================================="

cd /var/www/PDV-CONTROLE-DE-FINANCEIRO

# 1. Rodar migração no PostgreSQL
echo "[1/3] Rodando migração no banco..."
docker exec -i pdv_postgres psql -U pdv_admin -d pdv_restaurante << 'SQLEOF'
CREATE TABLE IF NOT EXISTS empresas (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    slug VARCHAR(50) UNIQUE,
    senha VARCHAR(255) NOT NULL,
    logo VARCHAR(10) DEFAULT '🍽️',
    cor_tema VARCHAR(7) DEFAULT '#f97316',
    telefone VARCHAR(30),
    endereco TEXT,
    ativo BOOLEAN DEFAULT true,
    criado_em TIMESTAMP DEFAULT NOW()
);
ALTER TABLE staff ADD COLUMN IF NOT EXISTS empresa_id INT REFERENCES empresas(id);
ALTER TABLE categorias ADD COLUMN IF NOT EXISTS empresa_id INT REFERENCES empresas(id);
ALTER TABLE cardapio ADD COLUMN IF NOT EXISTS empresa_id INT REFERENCES empresas(id);
ALTER TABLE mesas ADD COLUMN IF NOT EXISTS empresa_id INT REFERENCES empresas(id);
ALTER TABLE contas ADD COLUMN IF NOT EXISTS empresa_id INT REFERENCES empresas(id);
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS empresa_id INT REFERENCES empresas(id);
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS empresa_id INT REFERENCES empresas(id);
ALTER TABLE historico_vendas ADD COLUMN IF NOT EXISTS empresa_id INT REFERENCES empresas(id);
ALTER TABLE config ADD COLUMN IF NOT EXISTS empresa_id INT REFERENCES empresas(id);
CREATE INDEX IF NOT EXISTS idx_staff_empresa ON staff(empresa_id);
CREATE INDEX IF NOT EXISTS idx_cardapio_empresa ON cardapio(empresa_id);
CREATE INDEX IF NOT EXISTS idx_mesas_empresa ON mesas(empresa_id);
CREATE INDEX IF NOT EXISTS idx_contas_empresa ON contas(empresa_id);
CREATE INDEX IF NOT EXISTS idx_historico_empresa ON historico_vendas(empresa_id);
CREATE INDEX IF NOT EXISTS idx_config_empresa ON config(empresa_id);
ALTER TABLE config DROP CONSTRAINT IF EXISTS config_chave_key;
DO $$ BEGIN ALTER TABLE config ADD CONSTRAINT config_chave_empresa_unique UNIQUE(chave, empresa_id); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
INSERT INTO empresas (nome, slug, senha, logo, cor_tema) VALUES ('Restaurante Demo', 'demo', '$2b$10$8K1p/a0dL1LXMIgoEDFrwOeyuN.SJ8MQsSoMXTnMLLQ6K6V5JGxK.', '🍺', '#f97316') ON CONFLICT (slug) DO NOTHING;
UPDATE staff SET empresa_id = 1 WHERE empresa_id IS NULL;
UPDATE categorias SET empresa_id = 1 WHERE empresa_id IS NULL;
UPDATE cardapio SET empresa_id = 1 WHERE empresa_id IS NULL;
UPDATE mesas SET empresa_id = 1 WHERE empresa_id IS NULL;
UPDATE contas SET empresa_id = 1 WHERE empresa_id IS NULL;
UPDATE reservas SET empresa_id = 1 WHERE empresa_id IS NULL;
UPDATE clientes SET empresa_id = 1 WHERE empresa_id IS NULL;
UPDATE historico_vendas SET empresa_id = 1 WHERE empresa_id IS NULL;
UPDATE config SET empresa_id = 1 WHERE empresa_id IS NULL;
SQLEOF
echo "[OK] Migração concluída"

# 2. Atualizar server.js
echo "[2/3] Atualizando API..."
cat > backend/src/server.js << 'SRVEOF'
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const query = (text, params) => pool.query(text, params);

app.post('/api/auth/admin', async (req, res) => {
  try {
    const { senha } = req.body;
    const empresas = await query('SELECT id,nome,slug,senha,logo,cor_tema FROM empresas WHERE ativo=true');
    let found = null;
    for (const emp of empresas.rows) { if (await bcrypt.compare(senha, emp.senha)) { found = emp; break; } }
    if (!found) return res.status(401).json({ error: 'Senha incorreta' });
    const token = jwt.sign({ empresa_id:found.id, nome:found.nome, tipo:'admin' }, process.env.JWT_SECRET, { expiresIn:'12h' });
    res.json({ token, empresa:{id:found.id,nome:found.nome,logo:found.logo,cor_tema:found.cor_tema}, user:{id:0,nome:'Administrador',cargo:'gerente',img:'👔'} });
  } catch(e) { res.status(500).json({error:e.message}); }
});

app.post('/api/auth/colab', async (req, res) => {
  try {
    const { pin } = req.body;
    const r = await query('SELECT s.id,s.nome,s.pin,s.cargo,s.img,s.empresa_id,e.nome as empresa_nome,e.logo,e.cor_tema FROM staff s JOIN empresas e ON s.empresa_id=e.id WHERE s.pin=$1 AND s.ativo=true AND e.ativo=true', [pin]);
    if (!r.rows.length) return res.status(401).json({ error: 'PIN incorreto' });
    const u = r.rows[0];
    const token = jwt.sign({ id:u.id, nome:u.nome, cargo:u.cargo, empresa_id:u.empresa_id, tipo:'colab' }, process.env.JWT_SECRET, { expiresIn:'12h' });
    res.json({ token, empresa:{id:u.empresa_id,nome:u.empresa_nome,logo:u.logo,cor_tema:u.cor_tema}, user:{id:u.id,nome:u.nome,cargo:u.cargo,img:u.img} });
  } catch(e) { res.status(500).json({error:e.message}); }
});

const auth = (req,res,next) => {
  const t = req.headers.authorization?.split(' ')[1];
  if(!t) return res.status(401).json({error:'Token necessario'});
  try { req.user = jwt.verify(t, process.env.JWT_SECRET); req.empresa_id = req.user.empresa_id; next(); }
  catch { res.status(401).json({error:'Token invalido'}); }
};
const admin = (req,res,next) => { if(req.user.tipo!=='admin'&&req.user.cargo!=='gerente') return res.status(403).json({error:'Acesso negado'}); next(); };

app.get('/api/staff', auth, async(req,res)=>{ try{const r=await query('SELECT id,nome,cargo,img,pin,ativo FROM staff WHERE empresa_id=$1 ORDER BY id',[req.empresa_id]);res.json(r.rows);}catch(e){res.status(500).json({error:e.message});} });
app.post('/api/staff', auth, admin, async(req,res)=>{ try{const{nome,pin,cargo,img}=req.body;const ex=await query('SELECT id FROM staff WHERE pin=$1 AND empresa_id=$2',[pin,req.empresa_id]);if(ex.rows.length)return res.status(400).json({error:'PIN ja existe'});const r=await query('INSERT INTO staff(nome,pin,cargo,img,empresa_id) VALUES($1,$2,$3,$4,$5) RETURNING *',[nome,pin,cargo||'garcom',img||'🧑‍🍳',req.empresa_id]);res.json(r.rows[0]);}catch(e){res.status(500).json({error:e.message});} });
app.put('/api/staff/:id', auth, admin, async(req,res)=>{ try{const{nome,pin,cargo,img,ativo}=req.body;const r=await query('UPDATE staff SET nome=$1,pin=$2,cargo=$3,img=$4,ativo=$5 WHERE id=$6 AND empresa_id=$7 RETURNING *',[nome,pin,cargo,img,ativo,req.params.id,req.empresa_id]);res.json(r.rows[0]);}catch(e){res.status(500).json({error:e.message});} });
app.delete('/api/staff/:id', auth, admin, async(req,res)=>{ try{await query('UPDATE staff SET ativo=false WHERE id=$1 AND empresa_id=$2',[req.params.id,req.empresa_id]);res.json({ok:true});}catch(e){res.status(500).json({error:e.message});} });

app.get('/api/cardapio', auth, async(req,res)=>{ try{const r=await query('SELECT c.*,cat.nome as categoria FROM cardapio c JOIN categorias cat ON c.categoria_id=cat.id WHERE c.ativo=true AND c.empresa_id=$1 ORDER BY cat.ordem,c.nome',[req.empresa_id]);res.json(r.rows);}catch(e){res.status(500).json({error:e.message});} });
app.post('/api/cardapio', auth, admin, async(req,res)=>{ try{const{nome,preco,categoria_id,emoji,foto}=req.body;const r=await query('INSERT INTO cardapio(nome,preco,categoria_id,emoji,foto,empresa_id) VALUES($1,$2,$3,$4,$5,$6) RETURNING *',[nome,preco,categoria_id,emoji||'🍽️',foto,req.empresa_id]);res.json(r.rows[0]);}catch(e){res.status(500).json({error:e.message});} });
app.put('/api/cardapio/:id', auth, admin, async(req,res)=>{ try{const{nome,preco,emoji,foto}=req.body;const r=await query('UPDATE cardapio SET nome=$1,preco=$2,emoji=$3,foto=$4 WHERE id=$5 AND empresa_id=$6 RETURNING *',[nome,preco,emoji,foto,req.params.id,req.empresa_id]);res.json(r.rows[0]);}catch(e){res.status(500).json({error:e.message});} });
app.delete('/api/cardapio/:id', auth, admin, async(req,res)=>{ try{await query('UPDATE cardapio SET ativo=false WHERE id=$1 AND empresa_id=$2',[req.params.id,req.empresa_id]);res.json({ok:true});}catch(e){res.status(500).json({error:e.message});} });

app.get('/api/mesas', auth, async(req,res)=>{ try{const r=await query('SELECT m.*,c.id as conta_id,c.cliente,c.aberta_em,c.status as conta_status,s.nome as garcom_nome FROM mesas m LEFT JOIN contas c ON c.mesa_id=m.id AND c.status=$1 LEFT JOIN staff s ON c.garcom_id=s.id WHERE m.empresa_id=$2 ORDER BY m.numero',['aberta',req.empresa_id]);res.json(r.rows);}catch(e){res.status(500).json({error:e.message});} });
app.post('/api/mesas/:numero/abrir', auth, async(req,res)=>{ try{const{cliente,garcom_id}=req.body;const m=await query('SELECT id FROM mesas WHERE numero=$1 AND empresa_id=$2',[req.params.numero,req.empresa_id]);if(!m.rows.length)return res.status(404).json({error:'Mesa nao encontrada'});await query('UPDATE mesas SET status=$1 WHERE numero=$2 AND empresa_id=$3',['ocupada',req.params.numero,req.empresa_id]);const c=await query('INSERT INTO contas(mesa_id,garcom_id,cliente,empresa_id) VALUES($1,$2,$3,$4) RETURNING *',[m.rows[0].id,garcom_id,cliente,req.empresa_id]);res.json(c.rows[0]);}catch(e){res.status(500).json({error:e.message});} });

app.get('/api/contas/:id/pedidos', auth, async(req,res)=>{ try{const r=await query('SELECT p.* FROM pedidos p JOIN contas c ON p.conta_id=c.id WHERE p.conta_id=$1 AND c.empresa_id=$2 ORDER BY p.criado_em',[req.params.id,req.empresa_id]);res.json(r.rows);}catch(e){res.status(500).json({error:e.message});} });
app.post('/api/contas/:id/pedidos', auth, async(req,res)=>{ try{const{cardapio_id,nome_item,preco_unit,quantidade}=req.body;const hora=new Date().toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});const r=await query('INSERT INTO pedidos(conta_id,cardapio_id,nome_item,preco_unit,quantidade,hora) VALUES($1,$2,$3,$4,$5,$6) RETURNING *',[req.params.id,cardapio_id,nome_item,preco_unit,quantidade,hora]);await query('UPDATE contas SET subtotal=(SELECT COALESCE(SUM(preco_unit*quantidade),0) FROM pedidos WHERE conta_id=$1),taxa_servico=(SELECT COALESCE(SUM(preco_unit*quantidade),0)*0.10 FROM pedidos WHERE conta_id=$1),total=(SELECT COALESCE(SUM(preco_unit*quantidade),0)*1.10 FROM pedidos WHERE conta_id=$1) WHERE id=$1',[req.params.id]);res.json(r.rows[0]);}catch(e){res.status(500).json({error:e.message});} });
app.delete('/api/pedidos/:id', auth, async(req,res)=>{ try{const p=await query('SELECT p.conta_id FROM pedidos p JOIN contas c ON p.conta_id=c.id WHERE p.id=$1 AND c.empresa_id=$2',[req.params.id,req.empresa_id]);await query('DELETE FROM pedidos WHERE id=$1',[req.params.id]);if(p.rows.length){const cid=p.rows[0].conta_id;await query('UPDATE contas SET subtotal=(SELECT COALESCE(SUM(preco_unit*quantidade),0) FROM pedidos WHERE conta_id=$1),taxa_servico=(SELECT COALESCE(SUM(preco_unit*quantidade),0)*0.10 FROM pedidos WHERE conta_id=$1),total=(SELECT COALESCE(SUM(preco_unit*quantidade),0)*1.10 FROM pedidos WHERE conta_id=$1) WHERE id=$1',[cid]);}res.json({ok:true});}catch(e){res.status(500).json({error:e.message});} });
app.post('/api/contas/:id/cozinha', auth, async(req,res)=>{ try{const{descricao}=req.body;await query('INSERT INTO cozinha_envios(conta_id,descricao) VALUES($1,$2)',[req.params.id,descricao]);await query("UPDATE pedidos SET status='preparando' WHERE conta_id=$1 AND status='pendente'",[req.params.id]);res.json({ok:true});}catch(e){res.status(500).json({error:e.message});} });

app.post('/api/contas/:id/fechar', auth, admin, async(req,res)=>{ try{const{forma_pagamento}=req.body;const c=await query('SELECT c.*,m.numero as mesa_numero,s.nome as garcom_nome FROM contas c JOIN mesas m ON c.mesa_id=m.id JOIN staff s ON c.garcom_id=s.id WHERE c.id=$1 AND c.empresa_id=$2',[req.params.id,req.empresa_id]);if(!c.rows.length)return res.status(404).json({error:'Conta nao encontrada'});const ct=c.rows[0];const ps=await query('SELECT nome_item as name,quantidade as qty,preco_unit as price FROM pedidos WHERE conta_id=$1',[req.params.id]);const codigo='#'+(1000+Math.floor(Math.random()*9000));const hora=new Date().toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});await query('INSERT INTO historico_vendas(codigo,mesa_numero,cliente_nome,garcom_nome,forma_pagamento,subtotal,taxa_servico,total,itens,hora,empresa_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',[codigo,ct.mesa_numero,ct.cliente,ct.garcom_nome,forma_pagamento,ct.subtotal,ct.taxa_servico,ct.total,JSON.stringify(ps.rows),hora,req.empresa_id]);await query("UPDATE contas SET status='fechada',forma_pagamento=$1,fechada_em=NOW() WHERE id=$2",[forma_pagamento,req.params.id]);await query("UPDATE mesas SET status='livre' WHERE id=$1",[ct.mesa_id]);res.json({codigo,total:ct.total});}catch(e){res.status(500).json({error:e.message});} });

app.get('/api/reservas', auth, async(req,res)=>{ try{const r=await query('SELECT r.*,m.numero as mesa_numero FROM reservas r JOIN mesas m ON r.mesa_id=m.id WHERE r.data_reserva=CURRENT_DATE AND r.empresa_id=$1 ORDER BY r.hora',[req.empresa_id]);res.json(r.rows);}catch(e){res.status(500).json({error:e.message});} });
app.post('/api/reservas', auth, async(req,res)=>{ try{const{nome,mesa_id,hora,pessoas,telefone,observacoes}=req.body;const r=await query('INSERT INTO reservas(nome,mesa_id,hora,pessoas,telefone,observacoes,empresa_id) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *',[nome,mesa_id,hora,pessoas||2,telefone,observacoes,req.empresa_id]);await query("UPDATE mesas SET status='reservada' WHERE id=$1 AND empresa_id=$2",[mesa_id,req.empresa_id]);res.json(r.rows[0]);}catch(e){res.status(500).json({error:e.message});} });
app.put('/api/reservas/:id/confirmar', auth, async(req,res)=>{ try{await query('UPDATE reservas SET confirmada=true WHERE id=$1 AND empresa_id=$2',[req.params.id,req.empresa_id]);res.json({ok:true});}catch(e){res.status(500).json({error:e.message});} });
app.delete('/api/reservas/:id', auth, async(req,res)=>{ try{const rv=await query('SELECT mesa_id FROM reservas WHERE id=$1 AND empresa_id=$2',[req.params.id,req.empresa_id]);await query('DELETE FROM reservas WHERE id=$1 AND empresa_id=$2',[req.params.id,req.empresa_id]);if(rv.rows.length) await query("UPDATE mesas SET status='livre' WHERE id=$1",[rv.rows[0].mesa_id]);res.json({ok:true});}catch(e){res.status(500).json({error:e.message});} });

app.get('/api/relatorios/hoje', auth, admin, async(req,res)=>{ try{const vendas=await query("SELECT * FROM historico_vendas WHERE data_venda=CURRENT_DATE AND empresa_id=$1 ORDER BY criado_em DESC",[req.empresa_id]);const total=await query("SELECT COALESCE(SUM(total),0) as total,COUNT(*) as contas FROM historico_vendas WHERE data_venda=CURRENT_DATE AND empresa_id=$1",[req.empresa_id]);const pgto=await query("SELECT forma_pagamento,SUM(total) as total FROM historico_vendas WHERE data_venda=CURRENT_DATE AND empresa_id=$1 GROUP BY forma_pagamento",[req.empresa_id]);const garcom=await query("SELECT garcom_nome,SUM(total) as total,COUNT(*) as qtd FROM historico_vendas WHERE data_venda=CURRENT_DATE AND empresa_id=$1 GROUP BY garcom_nome",[req.empresa_id]);const mesa=await query("SELECT mesa_numero,SUM(total) as total FROM historico_vendas WHERE data_venda=CURRENT_DATE AND empresa_id=$1 GROUP BY mesa_numero ORDER BY total DESC LIMIT 5",[req.empresa_id]);res.json({vendas:vendas.rows,resumo:total.rows[0],porPagamento:pgto.rows,porGarcom:garcom.rows,porMesa:mesa.rows});}catch(e){res.status(500).json({error:e.message});} });
app.get('/api/relatorios/cliente/:nome', auth, admin, async(req,res)=>{ try{const r=await query("SELECT * FROM historico_vendas WHERE cliente_nome=$1 AND empresa_id=$2 ORDER BY criado_em DESC",[req.params.nome,req.empresa_id]);res.json(r.rows);}catch(e){res.status(500).json({error:e.message});} });

app.get('/api/clientes', auth, async(req,res)=>{ try{const r=await query('SELECT * FROM clientes WHERE empresa_id=$1 ORDER BY total_gasto DESC',[req.empresa_id]);res.json(r.rows);}catch(e){res.status(500).json({error:e.message});} });
app.post('/api/clientes', auth, async(req,res)=>{ try{const{nome,telefone,email,cpf}=req.body;const r=await query('INSERT INTO clientes(nome,telefone,email,cpf,empresa_id) VALUES($1,$2,$3,$4,$5) RETURNING *',[nome,telefone,email,cpf,req.empresa_id]);res.json(r.rows[0]);}catch(e){res.status(500).json({error:e.message});} });

app.get('/api/cozinha', auth, async(req,res)=>{ try{const r=await query("SELECT p.*,c.cliente,m.numero as mesa_numero,s.nome as garcom_nome FROM pedidos p JOIN contas c ON p.conta_id=c.id JOIN mesas m ON c.mesa_id=m.id JOIN staff s ON c.garcom_id=s.id WHERE c.status='aberta' AND c.empresa_id=$1 AND p.status IN('pendente','preparando') ORDER BY p.criado_em",[req.empresa_id]);res.json(r.rows);}catch(e){res.status(500).json({error:e.message});} });
app.put('/api/cozinha/:id/pronto', auth, async(req,res)=>{ try{await query("UPDATE pedidos SET status='pronto' WHERE id=$1",[req.params.id]);res.json({ok:true});}catch(e){res.status(500).json({error:e.message});} });

app.get('/api/config', auth, async(req,res)=>{ try{const r=await query('SELECT chave,valor FROM config WHERE empresa_id=$1',[req.empresa_id]);const cfg={};r.rows.forEach(x=>cfg[x.chave]=x.valor);res.json(cfg);}catch(e){res.status(500).json({error:e.message});} });
app.put('/api/config', auth, admin, async(req,res)=>{ try{for(const[k,v] of Object.entries(req.body)) await query('INSERT INTO config(chave,valor,empresa_id) VALUES($1,$2,$3) ON CONFLICT(chave,empresa_id) DO UPDATE SET valor=$2,atualizado_em=NOW()',[k,v,req.empresa_id]);res.json({ok:true});}catch(e){res.status(500).json({error:e.message});} });

app.post('/api/super/empresas', async(req,res)=>{ try{const{master_key,nome,senha,logo,cor_tema,num_mesas}=req.body;if(master_key!==process.env.JWT_SECRET)return res.status(403).json({error:'Acesso negado'});const slug=nome.toLowerCase().replace(/[^a-z0-9]/g,'-').replace(/-+/g,'-');const hash=await bcrypt.hash(senha,10);const emp=await query('INSERT INTO empresas(nome,slug,senha,logo,cor_tema) VALUES($1,$2,$3,$4,$5) RETURNING *',[nome,slug,hash,logo||'🍽️',cor_tema||'#f97316']);const eid=emp.rows[0].id;await query("INSERT INTO categorias(nome,ordem,empresa_id) VALUES('Pratos',1,$1),('Bebidas',2,$1),('Petiscos',3,$1)",[eid]);const tm=num_mesas||20;for(let i=1;i<=tm;i++)await query('INSERT INTO mesas(numero,empresa_id) VALUES($1,$2)',[i,eid]);await query("INSERT INTO config(chave,valor,empresa_id) VALUES('pix_key','',$1),('pix_nome',$2,$1),('pix_cidade','',$1),('taxa_servico','10',$1)",[eid,nome]);res.json({empresa:emp.rows[0],message:'Empresa criada com '+tm+' mesas'});}catch(e){res.status(500).json({error:e.message});} });
app.get('/api/super/empresas', async(req,res)=>{ try{const{master_key}=req.query;if(master_key!==process.env.JWT_SECRET)return res.status(403).json({error:'Acesso negado'});const r=await query('SELECT id,nome,slug,logo,ativo,criado_em FROM empresas ORDER BY id');res.json(r.rows);}catch(e){res.status(500).json({error:e.message});} });

app.get('/api/health', async(req,res)=>{ try{await query('SELECT 1');const e=await query('SELECT COUNT(*) as total FROM empresas WHERE ativo=true');res.json({status:'ok',db:'connected',empresas:e.rows[0].total,time:new Date().toISOString()});}catch(e){res.json({status:'error',db:'disconnected'});} });

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log('PDV API SaaS rodando na porta ' + PORT));
SRVEOF
echo "[OK] API atualizada"

# 3. Rebuild Docker
echo "[3/3] Reconstruindo containers..."
docker compose up -d --build

sleep 5
echo ""
echo "Testando API..."
curl -s http://localhost:3001/api/health
echo ""
echo ""
echo "=========================================="
echo "  MIGRAÇÃO CONCLUÍDA!"
echo "  Empresa demo: senha 'admin123'"
echo "=========================================="
