# 🧬 Linhagem de Dados (*Data Lineage*) — Ponta a Ponta

**Projeto:** AtuarialEventosBiometricos (RPPS)  
**Data-Base Cadastral:** 31/05/2026  
**Janela Histórica de Aderência:** 01/01/2015 a 31/05/2026  
**Objetivo:** Garantir rastreabilidade completa desde as fontes operacionais até os datasets atuariais finais, detalhando filtros populacionais, estruturas intermediárias (`#TMP` / `CTEs`) e regras de transformação.

---

## 1. Arquitetura Geral do Fluxo de Dados

Todos os pipelines seguem o padrão **Extract-Filter-Materialize-Project (EFMP)** dentro do SQL Server:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ CAMADA 1: FONTES OPERACIONAIS (rpps_dw.*)                               │
│ tbl_historico_vinculos | tbl_cadastro_pessoas | fato_folha_cabecalho    │
│ tbl_beneficiarios_previdenciarios | tbl_instituidor_legador | Legado    │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ Predication Pushdown (WHERE / EXISTS)
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ CAMADA 2: STAGING INDEXADA & PRE-AGGREGATION (#TMP_* / CTE_*)           │
│ Materialização de chaves únicas + CREATE CLUSTERED INDEX (B-Tree)       │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ Merge Join / Index Seek + CASE Rules
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ CAMADA 3: PROJEÇÃO FINAL & LATE MATERIALIZATION (Granularidade 1:1)     │
│ Conversão TRY_CONVERT(..., 103), De-Para Atuarial e Datasets de Entrega │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Linhagem por Domínio e Layout

### 2.1 Layout 01 — Servidores Ativos Vigentes (`01_ativos_vigentes.sql`)
* **Fonte Driver:** `rpps_dw.tbl_historico_vinculos`
  * *Critério de Corte:* `REGIMEPREV = 'RPPS'`, `EMP_CODIGO IN (1, 2, 8)`, `FORMAVAC IS NULL` e `(DTAPOSENT IS NULL OR TIPOAPOS IS NULL)`.
  * *Staging:* `#TMP_ATIVOS` (~113.922 registros) com índice clusterizado `(NUMFUNC, NUMVINC)`.
* **Enriquecimento 1 (Carreira Atual):** `rpps_dw.fato_folha_cabecalho` (+51M linhas) ➔ `CTE_ULTIMA_COMPETENCIA` (`MAX(MES_ANO)` via `EXISTS`) ➔ `INNER JOIN rpps_dw.dim_carreiras` ➔ `#TMP_CARGOS`.
* **Enriquecimento 2 (Biografia):** `rpps_dw.tbl_cadastro_pessoas` filtrado via `IN (#TMP_ATIVOS)` ➔ `#TMP_FUNCIONARIOS`.
* **Saída (1:1):** `ID_SEGURADO_MATRICULA`, `CO_COMP_MASSA ('1')`, `CO_SEXO_SEGURADO`, `DT_NASC_SEGURADO`, `DT_ING_ENTE` (`DTEXERC`), `NO_CARREIRA`.

---

### 2.2 Layout 01 — Aposentados Vigentes (`01_aposentados_vigentes.sql`)
* **Fonte Driver:** `rpps_dw.tbl_historico_vinculos`
  * *Critério de Corte:* `REGIMEPREV = 'RPPS'`, `EMP_CODIGO IN (2, 8, 91)`, `DTAPOSENT IS NOT NULL` e `(FORMAVAC IS NULL OR LTRIM(RTRIM(FORMAVAC)) = '')`.
  * *Staging:* `#TMP_APOS_BASE` com índice clusterizado `(NUMFUNC, NUMVINC)`.
* **Enriquecimento 1 (Primeiro Ingresso):** `rpps_dw.tbl_historico_vinculos` agrupado por `NUMFUNC` (`MIN(TRY_CONVERT(DATE, DTEXERC, 103))`) ➔ `#TMP_ING_ENTE`.
* **Enriquecimento 2 (Carreira):** `rpps_dw.tbl_evolucao_funcional` + `rpps_dw.dim_carreiras` via `EXISTS` (`MAX(c.NOME)`) ➔ `#TMP_CARGOS`.
* **Enriquecimento 3 (Biografia):** `rpps_dw.tbl_cadastro_pessoas` ➔ `#TMP_FUNCS`.
* **Saída (1:1):** `ID_SEGURADO_MATRICULA`, `CO_COMP_MASSA (2)`, `CO_SEXO_SEGURADO`, `DT_NASC_SEGURADO`, `DT_ING_ENTE`, `DT_APOSENTADORIA_PROGRAMADA` vs. `DT_APOSENTADORIA_POR_INVALIDEZ` (mutuamente exclusivas), `NO_CARREIRA`.

---

### 2.3 Layout 02 — Coorte Histórica de Desligamentos (`02_serv_corte_historico.sql`)
* **Fonte Driver:** `rpps_dw.tbl_historico_vinculos` + `rpps_dw.tbl_detalhe_vacancias` + Lista de Elegíveis `#TMP_RPPS`.
  * *Critério de Corte:* `EMP_CODIGO IN (1, 2, 8, 91)`, `DTVAC BETWEEN '2015-01-01' AND '2026-05-31 23:59:59'` e `FORMAVAC_LIMPO` pertencente aos **49 códigos homologados** (10 de óbito, 38 de exoneração/demissão/vacância em vida e 1 condicional `'VAC EF SUSP REINTEG'`).
  * *Staging:* `#TMP_CORTE_BASE` com índice clusterizado `(NUMFUNC, NUMVINC)`.
* **Enriquecimento 1 (Ingresso):** `MIN(TRY_CONVERT(DATE, DTEXERC, 103))` ➔ `#TMP_ING_ENTE`.
* **Enriquecimento 2 (Dependentes Únicos):** `rpps_dw.tbl_beneficiarios_previdenciarios` agrupado pelo instituidor com `COUNT(DISTINCT NUM_PEN_FUNC)` ➔ `#TMP_PENS_CONTA`.
* **Enriquecimento 3 (Carreira e Biografia):** `#TMP_CARGOS_CORTE` e `#TMP_FUNCS_CORTE`.
* **Saída (1:1 via `GROUP BY NUMFUNC, NUMVINC`):** Aplica precedência biométrica onde `DT_EXONERACAO` é anulada se `DT_OBITO` existir, enquanto `DT_APOSENTADORIA_*` é preservada mesmo em caso de óbito posterior.

---

### 2.4 Layout 03 — Pensionistas Atuais Vigentes (`03_pensionistas_atuais.sql`)
* **Fonte Driver:** `rpps_dw.tbl_historico_vinculos`
  * *Critério de Corte:* `EMP_CODIGO = 6`, `(FORMAVAC IS NULL OR LTRIM(RTRIM(FORMAVAC)) = '')` e `DTVAC IS NULL`.
  * *Staging:* `#TMP_PENS_ATIVOS` com índice clusterizado `(NUMFUNC, NUMVINC)`.
* **Enriquecimento em Cadeia:**
  1. `rpps_dw.tbl_cadastro_pessoas` ➔ `#TMP_PENS_FUNC` (`SEXO`, `DTNASC`, `DEFICIENTE`).
  2. `rpps_dw.tbl_beneficiarios_previdenciarios` ➔ `#TMP_PENS_RELAC` (`NUM_PENSAO`, `PARENTESCO`).
  3. `rpps_dw.tbl_instituidor_legador` ➔ `#TMP_PENS_LEG` (`NUM_MATRICULA_LEGADOR`, `DATA_OBITO`).
* **Saída (1:1):** `ID_INSTITUIDOR_MATRICULA`, `DT_OBITO_INSTITUIDOR`, `CO_COMP_MASSA ('1')`, `ID_PENSIONISTA_MATRICULA`, `CO_SEXO_PENSIONISTA`, `DT_NASC_PENSIONISTA`, `DT_INICIO_PENSAO`, `CO_TIPO_RELACAO` (`1` a `6`), `CO_CONDICAO` (`1` ou `2`), `CO_DURACAO`.

---

### 2.5 Layout 04 — Pensionistas Cessados / Vacanciados (`04_pensionistas_vacancia.sql`)
* **Fonte Driver:** `rpps_dw.tbl_historico_vinculos` (`CTE_Driver_Pensionista`).
  * *Critério de Corte:* `EMP_CODIGO = 6`, `TRY_CONVERT(DATETIME, DTVAC, 103) >= '2015-01-01'` e `FORMAVAC` dentro dos **16 motivos homologados** (excluindo `'NULO / INDEFERIDO'` e `'INCLUSAO INDEVIDA'`).
* **Enriquecimento em Cadeia (Semi-Joins `EXISTS`):** `CTE_Dados_Funcionario` ➔ `CTE_Iprem_Pensionistas` ➔ `CTE_Iprem_Legador`.
* **Saída (1:1):** Mesma estrutura do Layout 03 acrescida de `DT_FIM_PENSAO` (`DTVAC`) e `DT_OBITO_PENSIONISTA` (preenchida com `DTVAC` estritamente quando `FORMAVAC = 'FALECIMENTO'`).

---

### 2.6 Layout 04 — Histórico Legado de Pensionistas e Óbitos (`04_pensionistas_historico_obitos.sql`)
* **Fonte Driver:** `rpps_dw.tbl_historico_beneficiarios_legado` (`CTE_Filtro_Base`).
  * *Critério de Corte:* `BEN_DTCESSA IS NOT NULL` e `BEN_DTCESSA >= '2015-01-01'`.
* **Enriquecimento:** `rpps_dw.tbl_historico_legadores_legado` (`CTE_Secundario_Legador` via `LEG_NUMERO = LEG_REGFUNC`).
* **Saída (1:1):** Segrega `BEN_DTCESSA` entre `DT_OBITO_PENSIONISTA` (quando `BEN_TIPO = '1'`) e `DT_FIM_PENSAO` (quando `BEN_TIPO <> '1'`).
