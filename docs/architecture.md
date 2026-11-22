# Arquitetura do Sistema — Harpy AI

## 1. Visão Geral da Topologia

A solução adota uma arquitetura orientada a eventos (*Event-Driven Architecture*), desacoplando o transporte de mensagens do WhatsApp (WAHA), a orquestração lógica (n8n), a inferência de modelos fundacionais (Google Gemini) e a persistência de estado (PostgreSQL no Supabase).

### Comunicação entre Componentes

1. **Camada de Mensageria (WAHA Container):** Mantém a sessão ativa do WhatsApp Web/Multi-Device e converte eventos assíncronos (`message`) em requisições HTTP `POST` direcionadas ao webhook interno do n8n.
2. **Rede Interna Docker:** Os containers `n8n` e `waha` comunicam-se dentro da mesma rede Docker na instância AWS Lightsail via DNS interno (`http://waha-harpy:3000`), evitando exposição desnecessária da API de controle do WhatsApp à internet pública.
3. **Camada de Orquestração (n8n):** Recebe o payload JSON, executa regras determinísticas em JavaScript (`Code` nodes), mantém estado volátil de curto prazo (`$getWorkflowStaticData('global')`) para buffer de mensagens/controle de pausa e aciona APIs externas via HTTPS.
4. **Camada de Inteligência (Google Gemini API):** Consumida via HTTPS para tarefas especializadas (classificação JSON estruturada para moderação de texto/imagem, transcrição de áudio e geração de respostas conversacionais).
5. **Camada de Persistência (Supabase PostgreSQL):** Conexão externa via Session Pooler com TLS/SSL para gravação transacional e idempotente de participantes e infrações.

---

## 2. Fluxo Detalhado de Execução (Ponta a Ponta)

### Fase 1: Ingestão e Normalização
1. O WAHA dispara o webhook para o n8n sempre que uma mensagem chega em chat privado (`@c.us`) ou grupo (`@g.us`).
2. O nó **`Filtrar e Analisar Mensagem`** descarta eventos próprios (`fromMe: true`), mensagens de status (`status@broadcast`) ou eventos sem conteúdo útil.
3. O payload é normalizado extraindo `chatId`, `messageId`, `author`, `cleanText`, flags de mídia (`hasMedia`, `mediaType`) e menções ao bot (`@harpy` ou reply a mensagem do bot).
4. O nó **`Gerenciar Histórico e Estatísticas`** atualiza o buffer circular em memória com as últimas **100 mensagens** por grupo (usado tanto para resumos quanto para fornecer contexto de 15 mensagens à moderação).

### Fase 2: Pipeline de Moderação (Apenas em Grupos)
Antes de qualquer resposta conversacional, mensagens enviadas em grupos passam por três verificações sequenciais:

1. **Verificação de Links e Arquivos (`Detectar Links e Executáveis`):**
   - Extrai URLs via expressão regular e valida contra uma *allowlist* de domínios institucionais, jornalísticos e plataformas de vídeo/social permitidas.
   - Bloqueia extensões de risco (`.exe`, `.apk`, `.bat`, `.scr`, etc.) e links externos não autorizados.
2. **Moderação Contextual de Texto (`Suspeita Contextual em Texto?` → `Gemini Moderar Texto Contextual`):**
   - Aplica normalização anti-evasão (remoção de diacríticos, colapso de caracteres repetidos e conversão de *leetspeak* como `4->a`, `3->e`, `1->i`, `0->o`).
   - Se houver termo sensível ou ofensivo, envia a mensagem acompanhada das últimas 15 mensagens do grupo ao Gemini, que classifica a ocorrência em 5 níveis de severidade.
3. **Moderação Visual (`É Imagem no Grupo?` → `Gemini Moderar Imagem`):**
   - Caso a mensagem contenha imagem, faz o download do binário via API interna do WAHA e submete à análise visual do Gemini para detecção de conteúdo proibido.

### Fase 3: Verificação de Privilégios, Persistência e Ação
Quando qualquer camada sinaliza uma violação:

1. **Consulta de Administradores:** O n8n consulta `GET /api/default/groups/{chatId}` no WAHA para obter a lista atualizada de participantes e cruzar o identificador do remetente (`@lid` ou `@c.us`) com o status `isAdmin` / `isSuperAdmin` e o telefone E.164 real.
2. **Isenção de Admins:** Se `isAdmin === true`, o fluxo é encerrado sem apagar a mensagem.
3. **Persistência Transacional (`Persistir Infração e Histórico`):**
   - Executa `UPSERT` na tabela `jlp_moderacao.participantes` e `INSERT ... ON CONFLICT (message_id) DO NOTHING` na tabela `jlp_moderacao.infracoes` dentro de uma transação SQL única, garantindo idempotência contra reenvios de webhook.
4. **Execução das Ações:**
   - Remove a mensagem infratora no grupo via WAHA (`DELETE /api/default/chats/{chatId}/messages/{messageId}`).
   - Calcula o estágio disciplinar (aviso educativo na 1ª ocorrência; advertências progressivas `1/3` a `3/3` ou bloqueio prioritário em casos graves).
   - Envia relatório estruturado ao grupo exclusivo da administração.

### Fase 4: Roteamento Conversacional
Se a mensagem não violar regras e atender aos critérios de acionamento (chat privado ou menção explícita em grupo, respeitando o anti-flood e o opt-out individual do usuário):

- **Texto / Pedido de Resumo:** Encaminhado ao nó **`Gemini Responder Texto`**, que injeta as diretrizes da JLP e o histórico recente do buffer para formular a resposta.
- **Áudio:** Baixado via WAHA e processado pelo nó **`Gemini Interpretar Áudio`**.
- **Entrega:** A resposta final é enviada via `POST /api/sendText` respondendo diretamente ao `messageId` original.

---

## 3. Diagrama de Sequência (Moderação e Resposta)

```mermaid
sequenceDiagram
    autonumber
    actor User as Participante (Grupo)
    participant WAHA as WAHA API (Docker)
    participant N8N as n8n Workflow
    participant Gemini as Google Gemini API
    participant DB as Supabase (PostgreSQL)
    actor Admins as Grupo de Admins

    User->>WAHA: Envia mensagem no grupo
    WAHA->>N8N: POST /webhook (payload JSON)
    N8N->>N8N: Normaliza texto, IDs e atualiza buffer (100 msgs)
    N8N->>Gemini: Analisa contexto/imagem (se acionado)
    Gemini-->>N8N: Retorna JSON {acao, nivel, motivo}

    alt Violação Detectada
        N8N->>WAHA: GET /groups/{chatId} (verifica admins e telefone)
        WAHA-->>N8N: Lista de participantes
        opt Usuário NÃO é Admin
            N8N->>DB: BEGIN; UPSERT participante + INSERT infração; COMMIT
            DB-->>N8N: Total de ocorrências atualizado
            N8N->>WAHA: DELETE /messages/{messageId}
            N8N->>WAHA: POST /sendText (aviso/advertência ao grupo)
            opt Reincidência ou Nível Grave
                N8N->>WAHA: POST /sendText (alerta detalhado)
                WAHA->>Admins: Notifica equipe de moderação
            end
        end
    else Mensagem Segura + Menção ao Bot
        N8N->>Gemini: Gera resposta contextual ou resumo do buffer
        Gemini-->>N8N: Texto da resposta
        N8N->>WAHA: POST /sendText (quotedMessageId)
        WAHA->>User: Entrega resposta no grupo
    end
