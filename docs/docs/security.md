# Segurança, Privacidade e Boas Práticas

Este documento descreve os controles implementados na arquitetura do **Harpy AI** e as diretrizes obrigatórias para manter a segurança do sistema e de seu repositório público.

---

## 1. Gestão de Credenciais e Segredos

- **Ausência de Segredos no Código-Fonte:** Nenhuma chave de API (Google Gemini, WAHA), senha de banco de dados (Supabase/PostgreSQL) ou token de sessão é armazenada diretamente nos scripts JavaScript do workflow.
- **Cofre de Credenciais do n8n:** Todas as autenticações externas são gerenciadas pelo sistema nativo de credenciais criptografadas do n8n (criptografadas em disco usando a `N8N_ENCRYPTION_KEY` definida no ambiente do servidor).
- **Variáveis de Ambiente:** Configurações sensíveis de infraestrutura ficam restritas ao arquivo `.env` no servidor de produção (nunca versionado no Git).

---

## 2. Segurança de Rede e Infraestrutura

- **Comunicação Interna entre Containers:** As requisições do n8n para o WAHA trafegam exclusivamente pela rede privada do Docker (`http://waha-harpy:3000`), sem passar pela internet pública.
- **Criptografia em Trânsito:** Todas as comunicações externas — tanto com a API do Google Gemini quanto com o banco PostgreSQL no Supabase — utilizam transporte criptografado via TLS/SSL.
- **Controle de Pool de Conexões:** O cliente PostgreSQL no n8n é configurado com limite máximo de conexões (`5`) para evitar exaustão de recursos no banco de dados.

---

## 3. Proteção de Dados Pessoais e Privacidade (LGPD)

Por atuar em uma comunidade real no WhatsApp, o sistema adota princípios de minimização de dados:

- **Buffer Volátil em Memória:** O conteúdo das mensagens comuns trocadas nos grupos é mantido apenas em memória RAM em uma janela circular limitada às últimas 100 mensagens para fins de resumo e contexto imediato, sendo sobrescrito continuamente sem gravação permanente em banco de dados.
- **Persistência Restrita a Infrações:** Apenas eventos que violam efetivamente as regras da comunidade têm seus metadados registrados no PostgreSQL para controle de reincidência.
- **Respeito a Identificadores de Privacidade (`@lid`):** O sistema trata corretamente o padrão de Linked IDs do WhatsApp, evitando exposição indevida ou formatação incorreta de identificadores internos.
- **Opt-out Individual:** Qualquer participante pode desativar a interação do assistente com suas mensagens a qualquer momento via comando direto.

