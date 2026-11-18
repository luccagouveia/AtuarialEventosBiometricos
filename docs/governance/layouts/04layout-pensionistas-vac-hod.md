# 📋 Especificação Técnica de Layout — 04: Histórico Legado de Pensionistas Cessados e Óbitos

**Script SQL Correspondente:** `sql_queries/pensionistas/04_pensionistas_historico_obitos.sql`  
**Granularidade:** `1:1` por registro de beneficiário cessado (`LEG_NUMERO-BEN_CODIGO`)  
**Janela Histórica:** A partir de `01/01/2015`  
**Fundamentação Normativa:** Portaria MTP nº 1.467/2022 (Art. 6º; Art. 35, III; Art. 47)

---

## 1. Objetivo Atuarial

Complementar a base de pensionistas cessados a partir da fonte histórica legada (`tbl_historico_beneficiarios_legado` e `tbl_historico_legadores_legado`), assegurando completude cadastral e cobertura de óbitos e encerramentos registrados no sistema legado antes ou em paralelo à base corporativa principal.

---

## 2. Critérios de Elegibilidade e Escopo Populacional

O filtro precoce (`CTE_Filtro_Base`) isola os registros na tabela `rpps_dw.tbl_historico_beneficiarios_legado` que atendem a:

1. **Ocorrência de Cessação:** `BEN_DTCESSA IS NOT NULL`.
2. **Janela Temporal de Aderência:** `BEN_DTCESSA >= '2015-01-01'`.

---

## 3. Dicionário de Campos e Regras de Transformação

| Ordem | Campo de Saída | Tipo / Formato | Origem (Alias Público) | Regra de Negócio e Transformação SQL |
| :---: | :--- | :--- | :--- | :--- |
| **1** | `ID_INSTITUIDOR_MATRICULA` | `INT / BIGINT` | `tbl_historico_legadores_legado.LEG_REGFUNC` | Registro funcional do instituidor ligado via `B.LEG_NUMERO = L.LEG_REGFUNC`. |
| **2** | `DT_OBITO_INSTITUIDOR` | `DATE / DATETIME` | `tbl_historico_legadores_legado.LEG_DTOBITO` | Data de falecimento do segurado instituidor no legado. |
| **3** | `CO_COMP_MASSA` | `INT` (`NULL`) | Tipagem Explícita | Projetado como `CAST(NULL AS INT)` para manter compatibilidade estrutural de schema com os demais layouts de pensionistas. |
| **4** | `ID_PENSIONISTA_MATRICULA` | `VARCHAR` (`LEG_NUMERO-BEN_CODIGO`) | `tbl_historico_beneficiarios_legado` | Chave composta concatenada na projeção final via `CONCAT(B.LEG_NUMERO, '-', B.BEN_CODIGO)`. |
| **5** | `CO_SEXO_PENSIONISTA` | `VARCHAR` | `tbl_historico_beneficiarios_legado.COD_SEXO_BENF` | Código nativo de sexo do beneficiário no sistema legado. |
| **6** | `DT_NASC_PENSIONISTA` | `DATE / DATETIME` | `tbl_historico_beneficiarios_legado.BEN_DATNASC` | Data de nascimento do beneficiário. |
| **7** | `DT_INICIO_PENSAO` | `DATE / DATETIME` | `tbl_historico_beneficiarios_legado.BEN_DTINPEN` | Data de início da concessão da pensão. |
| **8** | `DT_FIM_PENSAO` | `DATE / DATETIME` | `tbl_historico_beneficiarios_legado.BEN_DTCESSA` | Preenchida com `BEN_DTCESSA` **apenas quando `BEN_TIPO <> '1'`** (cessação administrativa/temporal em vida). |
| **9** | `DT_OBITO_PENSIONISTA` | `DATE / DATETIME` | `tbl_historico_beneficiarios_legado.BEN_DTCESSA` | Preenchida com `BEN_DTCESSA` **apenas quando `BEN_TIPO = '1'`** (encerramento motivado por falecimento do pensionista). |
| **10** | `CO_TIPO_RELACAO` | `VARCHAR` | `tbl_historico_beneficiarios_legado.PRT_CODIGO` | Código nativo de parentesco do beneficiário. |
| **11** | `CO_CONDICAO` | `VARCHAR` | `tbl_historico_beneficiarios_legado.BEN_CDINVAL` | Indicador nativo de invalidez do beneficiário. |
| **12** | `CO_DURACAO` | `VARCHAR` | `tbl_historico_beneficiarios_legado.BEN_TIPO` | Tipo de benefício/encerramento no legado. |

---

## 4. Regra de Segregação Mutuamente Exclusiva (`BEN_TIPO`)

Para evitar dupla contagem entre encerramento administrativo e óbito do beneficiário no dataset histórico legado, a coluna `BEN_DTCESSA` é roteada de forma mutuamente exclusiva:
* **`BEN_TIPO = '1'`:** Indica óbito do pensionista ➔ popula `DT_OBITO_PENSIONISTA` e mantém `DT_FIM_PENSAO = NULL`.
* **`BEN_TIPO <> '1'`:** Indica encerramento por outras causas ➔ popula `DT_FIM_PENSAO` e mantém `DT_OBITO_PENSIONISTA = NULL`.
