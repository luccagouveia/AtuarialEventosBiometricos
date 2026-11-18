# 📋 Especificação Técnica de Layout — 02: Coorte Histórica de Desligamentos e Eventos Biométricos

**Script SQL Correspondente:** `sql_queries/ativos_aposentados/02_serv_corte_historico.sql`  
**Granularidade:** `1:1` por vínculo desligado (`NUMFUNC-NUMVINC`)  
**Janela Histórica:** `01/01/2015` a `31/05/2026` (Data-Base Cadastral)  
**Fundamentação Normativa:** Portaria MTP nº 1.467/2022 (Art. 6º; Art. 35, III; Art. 36; Art. 37, § 1º)

---

## 1. Objetivo Atuarial

Construir a base histórica longitudinal de desligamentos, exonerações, aposentadorias e óbitos ocorridos entre 2015 e 2026. Este dataset alimenta os **Testes de Aderência das Hipóteses Biométricas e Demográficas** (tábuas de mortalidade de válidos e inválidos, entrada em invalidez, rotatividade/exoneração e composição familiar média no momento do óbito).

---

## 2. Critérios de Elegibilidade e Saneamento de Motivos

O motor central (`#TMP_CORTE_BASE`) cruza `tbl_historico_vinculos` com `tbl_detalhe_vacancias` e a lista homologada de segurados RPPS (`#TMP_RPPS`), aplicando:

1. **Órgãos Abrangidos:** `EMP_CODIGO IN (1, 2, 8, 91)`.
2. **Janela Temporal:** `DTVAC >= '2015-01-01'` e `DTVAC <= '2026-05-31 23:59:59'`.
3. **Normalização de String (`FORMAVAC_LIMPO`):** Remoção de espaços múltiplos internos e externos (`LTRIM(RTRIM(REPLACE(...)))`) antes da classificação nos **49 códigos homologados**:
   * **Domínio A — Óbito (10 códigos):** `'FALECIMENTO'`, `'FAL VIA SISOBI'`, `'FAL NAO SISOBI'`, `'FAL VIA SIRC'`, `'FAL ANTES SEGREG'`, `'FAL PMSP_DEBITO'`, `'MORTE PRESUMIDA'`, `'FAL EXER ATIV PROF'`, `'DECLARADO VAGO FAL'`, `'APOSEN / FALECIM'`.
   * **Domínio B — Exoneração / Demissão / Vacância em Vida (38 códigos):** Inclui exonerações a pedido, demissões administrativas/judiciais e vacâncias estatutárias. Exclui explicitamente `'EXON CONV ADMINISTR'`.
   * **Domínio C — Condicional (1 código):** `'VAC EF SUSP REINTEG'` (garantido inativo pois `FORMAVAC IS NOT NULL`).

---

## 3. Dicionário de Campos e Regras de Transformação

| Ordem | Campo de Saída | Tipo / Formato | Origem (Alias Público) | Regra de Negócio e Transformação SQL |
| :---: | :--- | :--- | :--- | :--- |
| **1** | `ID_SEGURADO_MATRICULA` | `VARCHAR` (`NUMFUNC-NUMVINC`) | `tbl_historico_vinculos` | Chave composta concatenada na projeção final. |
| **2** | `CO_COMP_MASSA` | `INT` (`1`) | Constante de Negócio | Valor fixo `1` (Massa Civil). |
| **3** | `CO_SEXO_SEGURADO` | `VARCHAR(1)` (`'1'` ou `'2'`) | `tbl_cadastro_pessoas.SEXO` | Tradução de domínio: `'F' -> '1'`, `'M' -> '2'`. |
| **4** | `DT_NASC_SEGURADO` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_cadastro_pessoas.DTNASC` | Formatação via `CONVERT(VARCHAR(10), MAX(f.DTNASC), 103)`. |
| **5** | `DT_ING_ENTE` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_historico_vinculos.DTEXERC` | Primeira data de exercício do servidor (`MIN(TRY_CONVERT(DATE, DTEXERC, 103))`). |
| **6** | `DT_EXONERACAO` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_detalhe_vacancias.DTVAC` | Preenchida com `DATA_VACANCIA_FINAL` se `FORMAVAC_LIMPO` estiver nos Domínios B ou C **E** não houver registro de óbito no vínculo. |
| **7** | `DT_APOSENTADORIA_PROGRAMADA` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_historico_vinculos.DTAPOSENT` | Preenchida quando `(EMP_CODIGO = 91 OR TIPOAPOS <> '')` e não for invalidez (`INV%`, `INC%`, `APOS_INVALIDEZ`). |
| **8** | `DT_APOSENTADORIA_POR_INVALIDEZ` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_historico_vinculos.DTAPOSENT` | Preenchida quando `(EMP_CODIGO = 91 OR TIPOAPOS <> '')` e for invalidez (`INV%`, `INC%`, `APOS_INVALIDEZ`). |
| **9** | `DT_OBITO` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_detalhe_vacancias.DTVAC` | Preenchida com `DATA_VACANCIA_FINAL` quando `FORMAVAC_LIMPO` pertencer ao Domínio A (10 códigos de óbito). |
| **10** | `QTD_PENSIONISTAS` | `INT` (`>= 0`) | `tbl_beneficiarios_previdenciarios` | Contagem de indivíduos únicos dependentes (`ISNULL(COUNT(DISTINCT NUM_PEN_FUNC), 0)`). |
| **11** | `NO_CARREIRA` | `VARCHAR` | `tbl_evolucao_funcional` + `dim_carreiras` | Último cargo ocupado pelo segurado antes do evento biométrico (`MAX(c.NOME)`). |

---

## 4. Regras de Precedência Biométrica (Anti-Duplicidade)

No Módulo 7 (`GROUP BY NUMFUNC, NUMVINC`), a query aplica três regras atuariais de precedência:
1. **Supressão de Exoneração por Óbito:** Se um vínculo apresentar histórico tanto de desligamento administrativo quanto de óbito, `DT_EXONERACAO` é forçada para `NULL`, prevalecendo exclusivamente `DT_OBITO`.
2. **Preservação da Trajetória Aposentadoria ➔ Óbito:** Diferente da exoneração, se o segurado se aposentou (programada ou por invalidez) e faleceu posteriormente, **ambas** as datas (`DT_APOSENTADORIA_*` e `DT_OBITO`) são mantidas preenchidas para permitir o cálculo da taxa de mortalidade de inativos.
3. **Contagem Individual de Dependentes:** `QTD_PENSIONISTAS` contabiliza pessoas distintas (`COUNT(DISTINCT NUM_PEN_FUNC)`), evitando inflar a hipótese de composição familiar caso um mesmo dependente possua múltiplos registros de cota.
