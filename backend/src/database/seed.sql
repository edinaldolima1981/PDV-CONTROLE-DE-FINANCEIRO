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
