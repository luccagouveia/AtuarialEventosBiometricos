# 🛠️ Guia de Troubleshooting e Resolução de Incidentes (SQL Server)

**Projeto:** AtuarialEventosBiometricos (RPPS)  
**Engine Alvo:** Microsoft SQL Server (SSMS / T-SQL)  
**Objetivo:** Documentar o diagnóstico de causa raiz e as soluções de engenharia aplicadas para mitigar falhas de execução, erros de rede e anomalias de dados legados durante o processamento das bases atuariais.

---

## 1. Falha de Transporte de Rede e Timeout (`Erro 10053`)

* **Sintoma:** Durante a execução de consultas monolíticas de longa duração (~45 minutos), a conexão entre o cliente (SSMS) e o servidor SQL Server era interrompida abruptamente com o erro:  
  `A transport-level error has occurred when receiving results from the server. (provider: TCP Provider, error: 0 - An established connection was aborted by the software in your host machine / Erro 10053)`.
* **Causa Raiz:** O processamento prolongado de *Full Scans* sobre tabelas históricas massivas (+51 milhões de registros) combinado com o tráfego excessivo de pacotes de controle (`DONE_IN_PROC`) mantinha o socket TCP ocioso/bloqueado por tempo superior ao limite de *timeout* de firewall/rede.
* **Solução Aplicada:**
  1. Inclusão de `SET NOCOUNT ON;` e `SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;` no início de todos os scripts.
  2. Quebra do fluxo monolítico em **Multi-Staging Tables (`#TMP`) indexadas**, reduzindo o tempo total de execução de ~45 min para ~1 min e eliminando a ociosidade de rede.

---

## 2. Estouro de `TempDB` e *Spills* em Disco

* **Sintoma:** Degradação severa de I/O e alertas de crescimento excessivo do `TempDB` durante junções entre vínculos, histórico de cargos e beneficiários.
* **Causa Raiz:** 
  1. Estimativas incorretas de cardinalidade geravam *Memory Grants* subdimensionados, forçando operações de *Hash Match* e *Sort* a despejarem dados temporários em disco (*TempDB Spills*).
  2. Reexecuções consecutivas na mesma sessão sem desalocação explícita mantinham tabelas temporárias residuais alocadas.
* **Solução Aplicada:**
  1. Materialização apenas das colunas estritamente necessárias nas `#TMP` (projeção enxuta), seguida de `CREATE CLUSTERED INDEX` para fornecer estatísticas exatas ao otimizador.
  2. Blocos de limpeza idempotentes (`IF OBJECT_ID('tempdb..#TMP_*') IS NOT NULL DROP TABLE ...`) tanto na abertura (Módulo 1) quanto no encerramento (Módulo Final) de todos os scripts.

---

## 3. Erro de Conversão em Datas Legadas (`Msg 241`)

* **Sintoma:** Aborto imediato da query com a mensagem `Conversion failed when converting date and/or time from character string` ao filtrar ou projetar colunas como `DTEXERC`, `DTAPOSENT` e `DTVAC`.
* **Causa Raiz:** Sistemas legados armazenam datas em colunas do tipo `VARCHAR` no padrão brasileiro (`DD/MM/AAAA`), contendo registros sujos (`'00/00/0000'`, strings vazias ou datas inválidas como `'31/02/2018'`). O uso de `CAST` ou `CONVERT` padrão interrompe todo o lote diante de um único registro inválido.
* **Solução Aplicada:** Substituição integral por `TRY_CONVERT(DATE, col, 103)` e `TRY_CONVERT(DATETIME, col, 103)`, que converte datas válidas no formato `DD/MM/AAAA` (Style `103`) e retorna `NULL` de forma segura para registros corrompidos sem abortar o processamento.

---

## 4. Falha na Classificação de Motivos de Vacância (`FORMAVAC`)

* **Sintoma:** Segurados desligados por óbito ou exoneração deixavam de ser capturados na coorte histórica (`02_serv_corte_historico.sql`) ou tinham a data de desligamento classificada incorretamente.
* **Causa Raiz:** A coluna `FORMAVAC` apresentava espaços em branco duplicados ou triplicados no meio e nas extremidades das strings (ex.: `'FAL  VIA   SISOBI '`), falhando nas comparações exatas da cláusula `IN (...)`.
* **Solução Aplicada:** Higienização em cascata via `LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(v.FORMAVAC, ''), '  ', ' '), '  ', ' '), '  ', ' ')))` antes da avaliação dos 49 códigos homologados.

---

## 5. Multiplicação de Linhas (`1:N`) na Saída dos Layouts

* **Sintoma:** Retorno de múltiplas linhas para o mesmo vínculo (`NUMFUNC-NUMVINC`) devido a múltiplos registros de evolução de cargo (`tbl_evolucao_funcional`) ou múltiplas cotas de pensão vinculadas ao mesmo instituidor.
* **Causa Raiz:** Junções diretas (`LEFT JOIN`) com tabelas históricas de cardinalidade `1:N` sem pré-agregação ou critério de desempate.
* **Solução Aplicada:**
  1. **Cargos Ativos:** Pré-agregação via CTE (`MAX(MES_ANO)`) antes de cruzar com `dim_carreiras`.
  2. **Cargos Aposentados/Corte:** Agrupamento `GROUP BY NUMFUNC, NUMVINC` com `MAX(c.NOME)` na staging `#TMP_CARGOS`.
  3. **Contagem de Pensionistas:** Uso de `COUNT(DISTINCT p.NUM_PEN_FUNC)` agrupado pelo instituidor, contabilizando indivíduos únicos e não processos/cotas.
  4. **Precedência na Coorte Histórica:** Uso de `GROUP BY i.NUMFUNC, i.NUMVINC` com agregação condicional (`MAX(CASE WHEN ... END)`) garantindo estritamente 1 linha por vínculo na saída final.

---

## 6. Falso Positivo de Aposentados Vigentes (Beneficiários já Falecidos)

* **Sintoma:** Inclusão de ex-aposentados já falecidos ou desligados na extração de aposentados vigentes (`01_aposentados_vigentes.sql`).
* **Causa Raiz:** Filtrar apenas por `DTAPOSENT IS NOT NULL` capturava todo o histórico de aposentadorias concedidas, incluindo beneficiários cuja vacância posterior já havia sido registrada.
* **Solução Aplicada:** Adição da trava de vigência no Módulo 2: `AND (v.FORMAVAC IS NULL OR LTRIM(RTRIM(v.FORMAVAC)) = '')`, isolando estritamente os beneficiários ativos no plano.
