# 📋 Especificação Técnica de Layout — 04: Pensionistas Cessados / Vacanciados

**Script SQL Correspondente:** `sql_queries/pensionistas/04_pensionistas_vacancia.sql`  
**Granularidade:** `1:1` por beneficiário cessado (`NUMFUNCNUMVINC`)  
**Janela Histórica:** A partir de `01/01/2015`  
**Fundamentação Normativa:** Portaria MTP nº 1.467/2022 (Art. 6º; Art. 35, III; Art. 36)

---

## 1. Objetivo Atuarial

Mapear o histórico de encerramento de pensões por morte ocorridas a partir de `01/01/2015`, distinguindo as cessações por **óbito do pensionista** daquelas decorrentes de **extinção legal/administrativa em vida** (maioridade, casamento, renúncia, decisão judicial). Este insumo calibra as tábuas de mortalidade e as taxas de extinção de cotas de pensão.

---

## 2. Critérios de Elegibilidade e Expurgo Administrativo

O motor central (`CTE_Driver_Pensionista`) aplica três filtros restritivos sobre `rpps_dw.tbl_historico_vinculos`:

1. **Identificador de Pensionista:** `EMP_CODIGO = 6`.
2. **Janela Temporal:** `TRY_CONVERT(DATETIME, v.DTVAC, 103) >= '2015-01-01'`.
3. **Domínio Homologado de Cessação (16 motivos válidos):**
   * `'FALECIMENTO'`, `'DECURSO DE PRAZO'`, `'IMPL. 21 ANOS-MANUAL'`, `'IMPLEMENTO 21 ANOS'`, `'RENUNCIA EXPRESSA'`, `'ATESTADO FACULDA...'`, `'EMANCIPACAO'`, `'CASAMENTO'`, `'INVAL / INCAP'`, `'OUTROS MOTIVOS'`, `'DECISAO JUDICIAL'`, `'PERDA COND BENEF'`, `'IMPLEMENTO 25 ANOS'`, `'CONCLUSAO CURSO'`, `'UNIAO ESTAVEL'`, `'OPCAO OUTRA PENSAO'`.
   * *Expurgo de Qualidade:* Exclui explicitamente `'NULO / INDEFERIDO'` e `'INCLUSAO INDEVIDA'`, pois representam anulações cadastrais e não eventos biométricos ou demográficos reais.

---

## 3. Dicionário de Campos e Regras de Transformação

| Ordem | Campo de Saída | Tipo / Formato | Origem (Alias Público) | Regra de Negócio e Transformação SQL |
| :---: | :--- | :--- | :--- | :--- |
| **1** | `ID_INSTITUIDOR_MATRICULA` | `INT / BIGINT` | `tbl_instituidor_legador.NUM_MATRICULA_LEGADOR` | Matrícula funcional do segurado instituidor original. |
| **2** | `DT_OBITO_INSTITUIDOR` | `VARCHAR` | `tbl_instituidor_legador.DATA_OBITO` | Data de falecimento do instituidor. |
| **3** | `CO_COMP_MASSA` | `VARCHAR(1)` (`'1'`) | Constante de Negócio | Valor fixo `'1'` (Massa Civil). |
| **4** | `ID_PENSIONISTA_MATRICULA` | `VARCHAR` | `tbl_historico_vinculos` | Concatenação `CONCAT(drv.NUMFUNC, drv.NUMVINC)`. |
| **5** | `CO_SEXO_PENSIONISTA` | `VARCHAR(1)` (`'1'` ou `'2'`) | `tbl_cadastro_pessoas.SEXO` | Tradução de domínio: `'F' -> '1'`, `'M' -> '2'`. |
| **6** | `DT_NASC_PENSIONISTA` | `VARCHAR` | `tbl_cadastro_pessoas.DTNASC` | Data de nascimento do pensionista. |
| **7** | `DT_INICIO_PENSAO` | `VARCHAR` | `tbl_historico_vinculos.DTEXERC` | Data de concessão/início do benefício. |
| **8** | `DT_FIM_PENSAO` | `VARCHAR` | `tbl_historico_vinculos.DTVAC` | Data de vacância/encerramento do benefício (`DTVAC`). |
| **9** | `DT_OBITO_PENSIONISTA` | `VARCHAR` | `tbl_historico_vinculos.DTVAC` | Preenchida com `DTVAC` **estritamente** quando `FORMAVAC = 'FALECIMENTO'`; caso contrário `NULL`. |
| **10** | `CO_TIPO_RELACAO` | `VARCHAR(1)` (`'1'` a `'6'`) | `tbl_beneficiarios_previdenciarios.PARENTESCO` + `DEFICIENTE` | Mesmo mapeamento homologado (`1`=Cônjuge, `2`=Filho Válido, `3`=Filho Deficiente, `4`=Genitor, `5`=Irmão, `6`=Outros). |
| **11** | `CO_CONDICAO` | `VARCHAR(1)` (`'1'` ou `'2'`) | `tbl_cadastro_pessoas.DEFICIENTE` | `'2'` se `DEFICIENTE = 'S'`; `'1'` caso contrário. |
| **12** | `CO_DURACAO` | `VARCHAR` | `tbl_historico_vinculos.TIPOVINC` | Código nativo de duração do vínculo. |
