# Stack Tecnológica e Responsabilidades

A escolha das ferramentas priorizou baixo custo operacional, facilidade de manutenção, execução isolada em servidor cloud e capacidade multimodal nativa.

---

## 1. Orquestração e Automação: n8n (Self-Hosted)

- **Papel:** Cérebro operacional da aplicação. Gerencia o ciclo de vida de cada evento recebido do WhatsApp, roteamento condicional, tratamento de falhas (*Retry On Fail*) e integração entre APIs.
- **Decisões Técnicas:**
  - Uso de nós **`Code` (JavaScript)** para regras que exigem determinismo e baixa latência (parsing de `@lid`/`@c.us`, expressões regulares de URLs, normalização anti-evasão e buffer circular em memória), evitando gasto desnecessário de tokens de IA em mensagens comuns.
  - Configuração de **Retry On Fail** nos nós de chamada ao Gemini para absorver oscilações temporárias de disponibilidade (`503 Service Unavailable`) na API externa.

---

## 2. Gateway WhatsApp: WAHA (WhatsApp HTTP API)

- **Papel:** Interface de comunicação entre o protocolo do WhatsApp e a arquitetura HTTP REST utilizada pelo n8n.
- **Responsabilidades:**
  - Disparo de webhooks em tempo real para mensagens recebidas.
  - Consulta de metadados de grupos (`/api/default/groups/{chatId}`) para resolução dinâmica de administradores e números de telefone vinculados a `@lid`.
  - Download de arquivos de mídia (imagens e áudios) para análise multimodal.
  - Execução de ações de moderação (remoção de mensagens) e envio de respostas citadas (`reply_to`).

---

## 3. Inteligência Artificial: Google Gemini API

- **Modelo utilizado:** `models/gemini-3.5-flash-lite`
- **Responsabilidades:**
  - **Moderação Contextual de Texto:** Classificação semântica estruturada capaz de distinguir debate político acalorado (permitido pela comunidade) de assédio, discurso de ódio ou ameaças contra participantes.
  - **Visão Computacional:** Análise direta de imagens enviadas nos grupos sem necessidade de serviços externos de OCR ou classificação visual separados.
  - **Processamento de Áudio:** Compreensão nativa de mensagens de voz para atendimento acessível no WhatsApp.
  - **Síntese e Atendimento:** Geração de respostas alinhadas às diretrizes da JLP e sumarização das últimas mensagens armazenadas no buffer.

---

## 4. Banco de Dados Relacional: PostgreSQL (Supabase)

- **Papel:** Camada de persistência durável para histórico disciplinar e dados institucionais.
- **Decisões Técnicas:**
  - **Schema dedicado (`jlp_moderacao`):** Isolamento lógico das tabelas da aplicação (`participantes` e `infracoes`).
  - **Idempotência:** Uso de chave única (`message_id`) na tabela `infracoes` com `ON CONFLICT DO NOTHING` para impedir contagem duplicada de advertências caso o webhook seja reenviado.
  - **Session Pooler (`port 5432`) com TLS:** Conexão otimizada para ambientes serverless/workflow com limite controlado de conexões simultâneas.

---

## 5. Infraestrutura e Conteinerização: Docker + AWS Lightsail

- **Papel:** Hospedagem contínua (24/7) da pilha de automação e mensageria.
- **Decisões Técnicas:**
  - Execução do `n8n` e do `waha` em containers Docker isolados na mesma rede virtual, permitindo tráfego interno de alta velocidade e menor superfície de exposição externa.
  - Volumes persistentes mapeados no host Linux para preservar credenciais criptografadas do n8n, workflows publicados e dados de sessão do WhatsApp entre reinicializações.
