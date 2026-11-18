# 📋 Especificação Técnica de Layout — 01: Aposentados Vigentes

**Script SQL Correspondente:** `sql_queries/ativos_aposentados/01_aposentados_vigentes.sql`  
**Granularidade:** `1:1` por benefício de aposentadoria vigente (`NUMFUNC-NUMVINC`)  
**Fundamentação Normativa:** Portaria MTP nº 1.467/2022 (Art. 2º, IV; Art. 5º; Art. 30, I e II; Art. 47)

---

## 1. Objetivo Atuarial

Consolidar a base cadastral dos beneficiários em gozo de aposentadoria (programada, compulsória, especial ou por incapacidade permanente) ativos na folha de pagamento do RPPS, segregando a natureza da concessão para o correto dimensionamento do passivo matemático de benefícios concedidos.

---

## 2. Critérios de Elegibilidade e Escopo Populacional

Para compor o motor central (`#TMP_APOS_BASE`), o registro na fonte `rpps_dw.tbl_historico_vinculos` deve satisfazer:

1. **Filiação Previdenciária:** `REGIMEPREV = 'RPPS'`.
2. **Órgãos/Entidades Abrangidos:** `EMP_CODIGO IN (2, 8, 91)`.
3. **Condição de Inatividade Remunerada:** `DTAPOSENT IS NOT NULL`.
4. **Trava de Vigência (Exclusão de Vacanciados/Falecidos):** `(FORMAVAC IS NULL OR LTRIM(RTRIM(FORMAVAC)) = '')`. Garante que aposentados já falecidos ou com benefício cessado não constem na folha ativa.

---

## 3. Dicionário de Campos e Regras de Transformação

| Ordem | Campo de Saída | Tipo / Formato | Origem (Alias Público) | Regra de Negócio e Transformação SQL |
| :---: | :--- | :--- | :--- | :--- |
| **1** | `ID_SEGURADO_MATRICULA` | `VARCHAR` (`NUMFUNC-NUMVINC`) | `tbl_historico_vinculos` | Chave composta concatenada na projeção final (`NUMFUNC-NUMVINC`). |
| **2** | `CO_COMP_MASSA` | `INT` (`2`) | Constante de Negócio | Valor fixo `2` atribuído à massa de aposentados vigentes. |
| **3** | `CO_SEXO_SEGURADO` | `VARCHAR(1)` (`'1'` ou `'2'`) | `tbl_cadastro_pessoas.SEXO` | Tradução de domínio: `'F' -> '1'`, `'M' -> '2'`. |
| **4** | `DT_NASC_SEGURADO` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_cadastro_pessoas.DTNASC` | Formatação via `CONVERT(VARCHAR(10), f.DTNASC, 103)`. |
| **5** | `DT_ING_ENTE` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_historico_vinculos.DTEXERC` | Reconstrói a cronologia funcional do servidor (`NUMFUNC`), capturando o primeiro exercício histórico (`MIN(TRY_CONVERT(DATE, DTEXERC, 103))`). |
| **6** | `DT_APOSENTADORIA_PROGRAMADA` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_historico_vinculos.DTAPOSENT` | Preenchida quando `TIPOAPOS` **não** inicia com `'INV%'`, `'INC%'` e é diferente de `'APOS_INVALIDEZ'`. |
| **7** | `DT_APOSENTADORIA_POR_INVALIDEZ` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_historico_vinculos.DTAPOSENT` | Preenchida estritamente quando `TIPOAPOS LIKE 'INV%'`, `TIPOAPOS LIKE 'INC%'` ou `TIPOAPOS = 'APOS_INVALIDEZ'`. |
| **8** | `NO_CARREIRA` | `VARCHAR` | `tbl_evolucao_funcional` + `dim_carreiras` | Denominação da carreira (`MAX(c.NOME)`) agrupada por `(NUMFUNC, NUMVINC)` para eliminar duplicidades de máscara textual. |

---

## 4. Regras Críticas de Negócio

* **Exclusividade Mútua de Concessão:** As colunas `DT_APOSENTADORIA_PROGRAMADA` e `DT_APOSENTADORIA_POR_INVALIDEZ` são mutuamente exclusivas. O mesmo registro nunca terá ambas preenchidas simultaneamente, atendendo à distinção entre benefícios programáveis (regime de capitalização) e riscos não programáveis (Art. 30 da Portaria MTP nº 1.467/2022).
* **Data de Ingresso no Ente (`NUMFUNC`):** Diferente do layout de ativos (que lê o `DTEXERC` do vínculo atual), nos aposentados o cálculo da data de ingresso varre todos os vínculos anteriores do mesmo `NUMFUNC` para capturar a primeira entrada no serviço público do ente.
