-- Estrutura relacional do sistema de moderação - Harpy AI (JLP)
-- Contém apenas definição de schema e tabelas (sem dados reais)

CREATE SCHEMA IF NOT EXISTS jlp_moderacao;

CREATE TABLE IF NOT EXISTS jlp_moderacao.participantes (
  id SERIAL PRIMARY KEY,
  telefone_e164 VARCHAR(30) UNIQUE NOT NULL,
  nome_exibicao VARCHAR(150),
  total_infracoes INTEGER NOT NULL DEFAULT 0,
  status VARCHAR(30) NOT NULL DEFAULT 'ativo',
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS jlp_moderacao.infracoes (
  id SERIAL PRIMARY KEY,
  participante_id INTEGER NOT NULL REFERENCES jlp_moderacao.participantes(id) ON DELETE CASCADE,
  message_id VARCHAR(120) UNIQUE NOT NULL,
  grupo_id VARCHAR(100) NOT NULL,
  grupo_nome VARCHAR(150),
  categoria VARCHAR(60) NOT NULL,
  nivel INTEGER NOT NULL,
  motivo TEXT,
  acao_tomada VARCHAR(60),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_infracoes_participante
  ON jlp_moderacao.infracoes(participante_id);
