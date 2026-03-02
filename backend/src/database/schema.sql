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
