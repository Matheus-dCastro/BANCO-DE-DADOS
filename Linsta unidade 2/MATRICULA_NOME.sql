-- S Conhecendo a base 
-- Resolva cada item com uma consulta a uma única tabela.
-- Anote em comentário quantas linhas cada consulta devolveu.

-- S (a)
-- Os 5 produtos ativos mais caros, com nome e preço.
SELECT nome, preco
FROM produto
WHERE ativo = true
ORDER BY preco DESC
LIMIT 5;
-- Quantidade de linhas retornadas: 5 linhas (limitado a 5 pelo LIMIT 5).


-- S (b)
-- Quantos clientes estão sem telefone e quantos estão sem cidade, numa consulta só e sem WHERE.
SELECT
    COUNT(*) FILTER (WHERE telefone IS NULL) AS clientes_sem_telefone,
    COUNT(*) FILTER (WHERE cidade IS NULL) AS clientes_sem_cidade
FROM cliente;
-- Quantidade de linhas retornadas: 1 linha contendo as duas contagens agregadas.


-- S (c)
-- Os clientes de Mossoró ou de Caicó cadastrados em 2025.
SELECT *
FROM cliente
WHERE (cidade = 'Mossoró' OR cidade = 'Caicó')
  AND (data_cadastro >= '2025-01-01' AND data_cadastro < '2026-01-01');
-- Quantidade de linhas retornadas: devolve apenas os clientes dessas duas cidades que se cadastraram em 2025.


-- Sem os parênteses, a cláusula ficaria:
--   WHERE cidade = 'Mossoró' OR cidade = 'Caicó' AND data_cadastro >= '2025-01-01' AND data_cadastro < '2026-01-01'
-- Na precedência de operadores da álgebra booleana e do SQL, o operador AND tem precedência sobre o OR.
-- Portanto, o banco avaliaria a consulta como:
--   WHERE cidade = 'Mossoró' OR (cidade = 'Caicó' AND data_cadastro >= '2025-01-01' AND data_cadastro < '2026-01-01')
-- Com isso, a consulta traria TODOS os clientes de Mossoró cadastrados em qualquer época (passado, presente ou futuro),
-- somados aos clientes de Caicó de 2025, resultando em muito mais linhas e trazendo dados incorretos para a análise.


-- S (d)
-- Quantos pedidos de agosto de 2026 não foram cancelados? Lembre que data_pedido é TIMESTAMP.
SELECT COUNT(*) AS total_pedidos_agosto_nao_cancelados
FROM pedido
WHERE data_pedido >= '2026-08-01 00:00:00'
  AND data_pedido < '2026-09-01 00:00:00'
  AND (status IS DISTINCT FROM 'cancelado');
-- Quantidade de linhas retornadas: 1 linha com o valor da contagem total agregada.


-- S (e)
-- Os notebooks (busque pelo nome, sem depender de maiúsculas), com o preço e o valor da parcela em 12 vezes, em centavos.
SELECT
    nome,
    preco,
    ROUND((preco / 12.0) * 100) AS parcela_12x_centavos
FROM produto
WHERE nome ILIKE '%notebook%';
-- Quantidade de linhas retornadas: retorna a quantidade de produtos ativos ou inativos que contenham 'notebook' no nome.


-- P1 A tabela do programa 

-- Criação da tabela fidelidade com restrições e valores padrão
CREATE TABLE fidelidade (
    id_cliente INT PRIMARY KEY,
    nivel VARCHAR(10) NOT NULL DEFAULT 'bronze' CHECK (nivel IN ('bronze', 'prata', 'ouro')),
    pontos INT NOT NULL DEFAULT 0 CHECK (pontos >= 0),
    data_adesao DATE NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT fk_fidelidade_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente) ON DELETE CASCADE
);

-- Adiciona a coluna indicado_por e sua chave estrangeira com ON DELETE SET NULL via ALTER TABLE
ALTER TABLE fidelidade
ADD COLUMN indicado_por INT,
ADD CONSTRAINT fk_fidelidade_indicado_por FOREIGN KEY (indicado_por) REFERENCES cliente(id_cliente) ON DELETE SET NULL;


-- P2 Os primeiros participantes

-- P2 (a)
-- Os fundadores: todos os clientes de Natal cadastrados em 2025, com adesão em 01/10/2026,
-- num único INSERT e sem digitar os ids.
INSERT INTO fidelidade (id_cliente, data_adesao)
SELECT id_cliente, '2026-10-01'::DATE
FROM cliente
WHERE cidade = 'Natal'
  AND (data_cadastro >= '2025-01-01' AND data_cadastro < '2026-01-01')
RETURNING *;


-- P2 (b)
-- Gustavo Batista (cliente 28), indicado por Helena Diniz (29). A adesão é hoje: deixe o padrão agir.
INSERT INTO fidelidade (id_cliente, indicado_por)
VALUES (28, 29)
RETURNING *;


-- P2 (c)
-- Dois INSERT que o banco precisa recusar, por motivos diferentes. Deixe-os comentados, com
-- a mensagem e a restrição que recusou cada um.

-- INSERT 1: Tentativa de inserir nível inválido ('platina')
-- Comando recusado:
-- INSERT INTO fidelidade (id_cliente, nivel) VALUES (1, 'platina');
-- Mensagem de erro:
-- ERROR:  new row for relation "fidelidade" violates check constraint "fidelidade_nivel_check"
-- DETAIL:  Failing row contains (1, platina, 0, 2026-10-21, null).
-- Restrição que recusou: CHECK (nivel IN ('bronze', 'prata', 'ouro'))

-- INSERT 2: Tentativa de inserir pontuação negativa (-50)
-- Comando recusado:
-- INSERT INTO fidelidade (id_cliente, pontos) VALUES (2, -50);
-- Mensagem de erro:
-- ERROR:  new row for relation "fidelidade" violates check constraint "fidelidade_pontos_check"
-- DETAIL:  Failing row contains (2, bronze, -50, 2026-10-21, null).
-- Restrição que recusou: CHECK (pontos >= 0)


-- P3 Pontos da campanha de outubro 

-- P3 (a)
-- Lance os pontos num único comando: quem já participa soma os pontos novos aos que tinha;
-- quem não participa é inscrito. Use RETURNING.
INSERT INTO fidelidade (id_cliente, pontos)
VALUES
    (1, 600),
    (5, 1200),
    (28, 150),
    (3, 300)
ON CONFLICT (id_cliente)
DO UPDATE SET pontos = fidelidade.pontos + EXCLUDED.pontos
RETURNING *;


-- P3 (b)
-- Recalcule o nível de todos (ouro a partir de 1.000 pontos, prata a partir de 500, bronze abaixo disso)
-- e devolva só as linhas que mudaram de nível.
UPDATE fidelidade
SET nivel = CASE
    WHEN pontos >= 1000 THEN 'ouro'
    WHEN pontos >= 500 THEN 'prata'
    ELSE 'bronze'
END
WHERE nivel <> CASE
    WHEN pontos >= 1000 THEN 'ouro'
    WHEN pontos >= 500 THEN 'prata'
    ELSE 'bronze'
END
RETURNING *;


-- P4 O relatório e a saída 

-- P4 (a)
-- O relatório: cliente, nível, pontos, adesão no formato DD/MM/AAAA e quantos pontos faltam
-- para o próximo nível (0 no ouro). Ouro primeiro, depois prata e bronze; dentro do nível, mais pontos primeiro.
SELECT
    c.nome AS cliente,
    f.id_cliente,
    f.nivel,
    f.pontos,
    TO_CHAR(f.data_adesao, 'DD/MM/YYYY') AS adesao,
    CASE
        WHEN f.nivel = 'ouro' THEN 0
        WHEN f.nivel = 'prata' THEN 1000 - f.pontos
        WHEN f.nivel = 'bronze' THEN 500 - f.pontos
    END AS pontos_para_proximo_nivel
FROM fidelidade f
JOIN cliente c ON f.id_cliente = c.id_cliente
ORDER BY
    CASE f.nivel
        WHEN 'ouro' THEN 1
        WHEN 'prata' THEN 2
        WHEN 'bronze' THEN 3
    END ASC,
    f.pontos DESC;


-- P4 (b)
-- Numa consulta só: quantos participantes há e quantos entraram por indicação.
SELECT
    COUNT(*) AS total_participantes,
    COUNT(indicado_por) AS entraram_por_indicacao
FROM fidelidade;


-- P4 (c)
-- Entre BEGIN e ROLLBACK, apague de cliente a 29 e depois o 28, mostrando fidelidade depois de cada DELETE.
-- Explique em comentário por que apagar a cliente 1 não daria certo.
BEGIN;

-- 1. Apaga a cliente Helena Diniz (id_cliente = 29):
DELETE FROM cliente WHERE id_cliente = 29;
-- Visualização: o cliente Gustavo Batista (28), que foi indicado por 29, tem agora indicado_por = NULL (efeito do ON DELETE SET NULL)
SELECT * FROM fidelidade;

-- 2. Apaga o cliente Gustavo Batista (id_cliente = 28):
DELETE FROM cliente WHERE id_cliente = 28;
-- Visualização: o registro do cliente 28 em fidelidade é excluído automaticamente (efeito do ON DELETE CASCADE)
SELECT * FROM fidelidade;

ROLLBACK;

-- Por que apagar a cliente 1 não daria certo?
-- A cliente 1 possui registros associados em outras tabelas da base de dados, como por exemplo na tabela pedido.

-- Por padrão na integridade relacional do PostgreSQL (comportamento ON DELETE RESTRICT ou NO ACTION),
-- não é permitido apagar um registro pai na tabela cliente enquanto existirem registros filhos dependentes na tabela pedido

-- apontando para esse id_cliente. A tentativa resultaria no erro:
-- "ERROR: update or delete on table "cliente" violates foreign key constraint "pedido_id_cliente_fkey" on table pedido.
