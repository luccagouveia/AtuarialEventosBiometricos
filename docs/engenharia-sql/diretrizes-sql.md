# 🛠️ Diretrizes e Padrões de Engenharia T-SQL

**Projeto:** AtuarialEventosBiometricos (RPPS)  
**Engine Alvo:** Microsoft SQL Server (T-SQL)  
**Objetivo:** Estabelecer os padrões arquiteturais, convenções de código, controle de concorrência e regras de qualidade obrigatórias para todos os pipelines de extração do projeto.

---

## 1. Arquitetura Modular de Scripts

Todo script `.sql` na camada `sql_queries/` segue uma estrutura determinística dividida em módulos numerados:

1. **Cabeçalho Técnico:** Documenta o objetivo do layout, técnicas de tuning aplicadas e conformidade LGPD.
2. **Módulo 1 — Diretivas de Sessão e Higiene (`TempDB`):** Configuração de isolamento e limpeza preventiva (`IF OBJECT_ID('tempdb..#TMP_*') IS NOT NULL DROP TABLE ...`) garantindo idempotência em reexecuções.
3. **Módulo 2 — Motor Central (*Driver Populacional*):** Isola estritamente a população elegível (`NUMFUNC`, `NUMVINC`) antes de qualquer cruzamento secundário.
4. **Módulos Intermediários — Enriquecimento e Pré-Agregação:** Extrai atributos biográficos, funcionais e previdenciários via *Semi-Joins* (`EXISTS`), colapsando cardinalidades `1:N` para `1:1`.
5. **Módulo Final — Projeção e *Late Materialization*:** Aplica conversões de formato (`DD/MM/AAAA`), concatenação de chaves e regras de precedência atuarial.
6. **Módulo de Encerramento — Desalocação Explícita:** `DROP TABLE` explícito de todas as estruturas temporárias alocadas na sessão.

---

## 2. Regras Obrigatórias de Desenvolvimento T-SQL

### 2.1 Controle de Concorrência e Rede
* **Isolamento `READ UNCOMMITTED`:** Obrigatório no topo de todas as consultas analíticas (`SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;`) para evitar a aquisição de *Shared Locks (S)* sobre views corporativas e eliminar riscos de *Deadlock* com rotinas transacionais de folha.
* **Supressão de Contadores (`SET NOCOUNT ON`):** Reduz pacotes de controle (*DONE_IN_PROC*) trafegados na rede entre o SQL Server e o cliente, mitigando falhas de transporte em conexões de longa duração.

### 2.2 Tipagem Segura e Saneamento de Dados Legados
* **Uso Obrigatório de `TRY_CONVERT`:** Colunas de data armazenadas como texto (`VARCHAR`) em sistemas legados nunca devem ser convertidas com `CAST` ou `CONVERT` direto. Utiliza-se `TRY_CONVERT(DATE, col, 103)` ou `TRY_CONVERT(DATETIME, col, 103)` para evitar abortos de execução (*Msg 241 — Conversion failed*) diante de datas inválidas.
* **Higienização de Strings (`FORMAVAC`):** Antes de validar domínios textuais, aplica-se `LTRIM(RTRIM(REPLACE(...)))` para eliminar espaços duplos e caracteres invisíveis.

### 2.3 Preservação de Granularidade `1:1`
* **Proibição de `SELECT DISTINCT` Genérico na Saída:** O uso de `DISTINCT` no `SELECT` final para mascarar duplicidades de `JOIN` é proibido, pois oculta erros de modelagem e consome memória excessiva em operações de *Sort*.
* **Resolução na Origem:** Cardinalidades `1:N` (como múltiplos cargos ou múltiplas cotas de pensão) são resolvidas antes da projeção final utilizando:
  * **Pré-agregação com `MAX(MES_ANO)`** em CTEs dedicadas (`01_ativos_vigentes.sql`);
  * **Contagem individual `COUNT(DISTINCT NUM_PEN_FUNC)`** (`02_serv_corte_historico.sql`);
  * **Agregação Condicional (`MAX(CASE WHEN ... END)`)** agrupada pela chave primária do vínculo (`GROUP BY NUMFUNC, NUMVINC`).

---

## 3. Checklist de Anti-Patterns Proibidos (Code Review)

| Anti-Pattern | Risco Técnico | Padrão Adotado no Projeto |
| :--- | :--- | :--- |
| **Concatenação de chaves no `JOIN`** (`CAST(a.ID AS VARCHAR) = b.ID`) | Quebra a *SARGability* e força *Index/Table Scan*. | Junção feita exclusivamente sobre chaves numéricas nativas (`NUMFUNC`, `NUMVINC`), concatenando apenas no `SELECT` final. |
| **Subqueries escalares no `SELECT`** | Execução linha a linha (*RBAR — Row-By-Agonizing-Row*), degradando o tempo exponencialmente. | Extração em lote via tabelas `#TMP` indexadas ou CTEs com `EXISTS` e junção final via `LEFT JOIN`. |
| **Leitura irrestrita de Fatos Históricas** | Varredura de dezenas de milhões de linhas (+51M no cubo de cargos). | *Predication Pushdown* filtrando primeiro a população elegível (~113k registros) antes de tocar nas tabelas fato. |
| **Exposição de objetos reais no Git** | Violação de segurança da informação e LGPD. | Abstração completa sob o schema `rpps_dw` e aliases públicos homologados. |
