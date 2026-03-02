#!/bin/bash
echo "=========================================="
echo "  PDV Restaurante - Setup Backend"
echo "  Node.js + PostgreSQL + Docker"
echo "=========================================="

cd /var/www/PDV-CONTROLE-DE-FINANCEIRO

# Criar estrutura
mkdir -p backend/src/database

# ── docker-compose.yml ──
cat > docker-compose.yml << 'DCEOF'
version: '3.8'
services:
  db:
    image: postgres:16-alpine
    container_name: pdv_postgres
    restart: always
    environment:
      POSTGRES_DB: pdv_restaurante
      POSTGRES_USER: pdv_admin
      POSTGRES_PASSWORD: PdvR3st@ur4nte2026!
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./backend/src/database/schema.sql:/docker-entrypoint-initdb.d/01-schema.sql
      - ./backend/src/database/seed.sql:/docker-entrypoint-initdb.d/02-seed.sql
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U pdv_admin -d pdv_restaurante"]
      interval: 5s
      timeout: 5s
      retries: 5
  api:
    build: ./backend
    container_name: pdv_api
    restart: always
    environment:
      NODE_ENV: production
      PORT: 3001
      DATABASE_URL: postgresql://pdv_admin:PdvR3st@ur4nte2026!@db:5432/pdv_restaurante
      JWT_SECRET: pdv-secret-key-2026-restaurante
    ports:
      - "3001:3001"
    depends_on:
      db:
        condition: service_healthy
volumes:
  pgdata:
DCEOF
echo "[OK] docker-compose.yml"

# ── Dockerfile ──
cat > backend/Dockerfile << 'DKEOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY src/ ./src/
EXPOSE 3001
CMD ["node", "src/server.js"]
DKEOF
echo "[OK] Dockerfile"

# ── package.json ──
cat > backend/package.json << 'PKEOF'
{
  "name": "pdv-restaurante-api",
  "version": "1.0.0",
  "description": "API do PDV Restaurante",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "node --watch src/server.js"
  },
  "dependencies": {
    "express": "^4.21.0",
    "pg": "^8.13.0",
    "cors": "^2.8.5",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "dotenv": "^16.4.5"
  }
}
PKEOF
echo "[OK] package.json"

# ── Schema SQL ──
cat > backend/src/database/schema.sql << 'SQLEOF'
CREATE TABLE staff (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    pin VARCHAR(10) NOT NULL UNIQUE,
    cargo VARCHAR(20) NOT NULL CHECK (cargo IN ('gerente', 'garcom', 'cozinha')),
    img VARCHAR(10) DEFAULT '🧑‍🍳',
    ativo BOOLEAN DEFAULT true,
    criado_em TIMESTAMP DEFAULT NOW()
);
CREATE TABLE categorias (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL UNIQUE,
    ordem INT DEFAULT 0
);
CREATE TABLE cardapio (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    preco DECIMAL(10,2) NOT NULL,
    categoria_id INT REFERENCES categorias(id) ON DELETE CASCADE,
    emoji VARCHAR(10) DEFAULT '🍽️',
    foto TEXT,
    ativo BOOLEAN DEFAULT true,
    criado_em TIMESTAMP DEFAULT NOW()
);
CREATE TABLE mesas (
    id SERIAL PRIMARY KEY,
    numero INT NOT NULL UNIQUE,
    status VARCHAR(20) DEFAULT 'livre' CHECK (status IN ('livre', 'ocupada', 'reservada')),
    capacidade INT DEFAULT 4
);
CREATE TABLE contas (
    id SERIAL PRIMARY KEY,
    mesa_id INT REFERENCES mesas(id),
    garcom_id INT REFERENCES staff(id),
    cliente VARCHAR(100),
    status VARCHAR(20) DEFAULT 'aberta' CHECK (status IN ('aberta', 'fechada', 'cancelada')),
    aberta_em TIMESTAMP DEFAULT NOW(),
    fechada_em TIMESTAMP,
    subtotal DECIMAL(10,2) DEFAULT 0,
    taxa_servico DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) DEFAULT 0,
    forma_pagamento VARCHAR(30),
    observacoes TEXT
);
CREATE TABLE pedidos (
    id SERIAL PRIMARY KEY,
    conta_id INT REFERENCES contas(id) ON DELETE CASCADE,
    cardapio_id INT REFERENCES cardapio(id),
    nome_item VARCHAR(100) NOT NULL,
    preco_unit DECIMAL(10,2) NOT NULL,
    quantidade INT NOT NULL DEFAULT 1,
    hora VARCHAR(10),
    status VARCHAR(20) DEFAULT 'pendente' CHECK (status IN ('pendente', 'preparando', 'pronto', 'entregue')),
    criado_em TIMESTAMP DEFAULT NOW()
);
CREATE TABLE cozinha_envios (
    id SERIAL PRIMARY KEY,
    conta_id INT REFERENCES contas(id) ON DELETE CASCADE,
    descricao TEXT NOT NULL,
    enviado_em TIMESTAMP DEFAULT NOW()
);
CREATE TABLE reservas (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    mesa_id INT REFERENCES mesas(id),
    hora VARCHAR(10) NOT NULL,
    pessoas INT DEFAULT 2,
    telefone VARCHAR(30),
    observacoes TEXT,
    confirmada BOOLEAN DEFAULT false,
    data_reserva DATE DEFAULT CURRENT_DATE,
    criado_em TIMESTAMP DEFAULT NOW()
);
CREATE TABLE clientes (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    telefone VARCHAR(30),
    email VARCHAR(100),
    cpf VARCHAR(14),
    pontos_fidelidade INT DEFAULT 0,
    total_gasto DECIMAL(12,2) DEFAULT 0,
    visitas INT DEFAULT 0,
    criado_em TIMESTAMP DEFAULT NOW(),
    ultima_visita TIMESTAMP
);
CREATE TABLE historico_vendas (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(20) NOT NULL,
    mesa_numero INT,
    cliente_nome VARCHAR(100),
    garcom_nome VARCHAR(100),
    forma_pagamento VARCHAR(30),
    subtotal DECIMAL(10,2),
    taxa_servico DECIMAL(10,2),
    total DECIMAL(10,2),
    itens JSONB,
    hora VARCHAR(10),
    data_venda DATE DEFAULT CURRENT_DATE,
    criado_em TIMESTAMP DEFAULT NOW()
);
CREATE TABLE config (
    id SERIAL PRIMARY KEY,
    chave VARCHAR(50) NOT NULL DEFAULT 'config' UNIQUE,
    valor TEXT NOT NULL,
    atualizado_em TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_contas_mesa ON contas(mesa_id);
CREATE INDEX idx_contas_status ON contas(status);
CREATE INDEX idx_pedidos_conta ON pedidos(conta_id);
CREATE INDEX idx_historico_data ON historico_vendas(data_venda);
CREATE INDEX idx_historico_cliente ON historico_vendas(cliente_nome);
CREATE INDEX idx_clientes_nome ON clientes(nome);
SQLEOF
echo "[OK] schema.sql"

# ── Seed SQL ──
cat > backend/src/database/seed.sql << 'SEEDEOF'
INSERT INTO staff (nome, pin, cargo, img) VALUES
('Admin', '0000', 'gerente', '👔'),
('João', '1234', 'garcom', '🧑‍🍳'),
('Ana', '2345', 'garcom', '👩‍🍳'),
('Carlos', '3456', 'garcom', '🧑‍🍳'),
('Maria', '4567', 'garcom', '👩‍🍳'),
('Pedro', '5678', 'garcom', '🧑‍🍳'),
('Cozinha', '9999', 'cozinha', '🍳');
INSERT INTO categorias (nome, ordem) VALUES ('Pratos', 1), ('Bebidas', 2), ('Petiscos', 3);
INSERT INTO cardapio (nome, preco, categoria_id, emoji) VALUES
('Feijoada', 29.90, 1, '🍛'), ('Strogonoff', 32.00, 1, '🍲'), ('Salada', 18.00, 1, '🥗'),
('Picanha', 45.00, 1, '🥩'), ('Frango Grelhado', 28.00, 1, '🍗'), ('Parmegiana', 35.00, 1, '🧀'),
('Cerveja', 8.00, 2, '🍺'), ('Caipirinha', 15.00, 2, '🍹'), ('Refrigerante', 6.00, 2, '🥤'),
('Suco Natural', 10.00, 2, '🧃'), ('Agua', 4.00, 2, '💧'), ('Vinho Tinto', 25.00, 2, '🍷'),
('Batata Frita', 22.00, 3, '🍟'), ('Bolinho Bacalhau', 28.00, 3, '🧆'), ('Coxinha', 8.00, 3, '🥟'),
('Pastel', 10.00, 3, '🥮'), ('Torresmo', 18.00, 3, '🥓'), ('Isca de Peixe', 30.00, 3, '🐟');
INSERT INTO mesas (numero) VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18),(19),(20);
INSERT INTO config (chave, valor) VALUES
('pix_key', 'restaurante@pix.com.br'), ('pix_nome', 'Restaurante Sabor e Arte'),
('pix_cidade', 'Sao Paulo'), ('taxa_servico', '10');
SEEDEOF
echo "[OK] seed.sql"

# ── Server.js ──
cat > backend/src/server.js << 'SRVEOF'
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
SRVEOF
echo "[OK] server.js"

echo ""
echo "=========================================="
echo "  Arquivos criados! Subindo Docker..."
echo "=========================================="

# Subir containers
docker compose down 2>/dev/null
docker compose up -d --build

echo ""
echo "Aguardando banco inicializar..."
sleep 10

# Testar
echo ""
echo "Testando API..."
curl -s http://localhost:3001/api/health
echo ""

echo ""
echo "=========================================="
echo "  PRONTO! Backend rodando!"
echo "  API: http://localhost:3001/api/health"
echo "=========================================="
