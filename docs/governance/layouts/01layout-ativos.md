# 📋 Especificação Técnica de Layout — 01: Servidores Ativos Vigentes

**Script SQL Correspondente:** `sql_queries/ativos_aposentados/01_ativos_vigentes.sql`  
**Granularidade:** `1:1` por vínculo funcional ativo (`NUMFUNC-NUMVINC`)  
**Volumetria Estimada:** ~113.922 registros únicos elegíveis  
**Fundamentação Normativa:** Portaria MTP nº 1.467/2022 (Art. 2º, III; Art. 3º; Art. 47)

---

## 1. Objetivo Atuarial

Extrair a base cadastral e funcional limpa dos servidores públicos titulares de cargo efetivo em atividade vinculados ao Regime Próprio de Previdência Social (RPPS). Este dataset subsidia o cálculo do custo normal, das provisões matemáticas de benefícios a conceder e das projeções de elegibilidade à aposentadoria.

---

## 2. Critérios de Elegibilidade e Escopo Populacional

Para compor a tabela temporária motora (`#TMP_ATIVOS`), o vínculo na fonte `rpps_dw.tbl_historico_vinculos` deve atender simultaneamente às seguintes condições:

1. **Filiação Previdenciária:** `REGIMEPREV = 'RPPS'` (exclui agentes ocupantes exclusivamente de cargos em comissão, temporários ou empregos públicos vinculados ao RGPS).
2. **Órgãos/Entidades Abrangidos:** `EMP_CODIGO IN (1, 2, 8)`.
3. **Condição de Atividade:** `FORMAVAC IS NULL` (ausência de desligamento, exoneração, demissão ou óbito).
4. **Exclusão de Inativos:** `(DTAPOSENT IS NULL OR TIPOAPOS IS NULL)` (assegura que servidores já aposentados não sejam duplicados na massa ativa).

---

## 3. Dicionário de Campos e Regras de Transformação

| Ordem | Campo de Saída | Tipo / Formato | Origem (Alias Público) | Regra de Negócio e Transformação SQL |
| :---: | :--- | :--- | :--- | :--- |
| **1** | `ID_SEGURADO_MATRICULA` | `VARCHAR` (`NUMFUNC-NUMVINC`) | `tbl_historico_vinculos` | Concatenação tardia (`CAST(NUMFUNC AS VARCHAR) + '-' + CAST(NUMVINC AS VARCHAR)`) executada apenas na projeção final. |
| **2** | `CO_COMP_MASSA` | `VARCHAR(1)` (`'1'`) | Constante de Negócio | Valor fixo `'1'` representando a Massa Civil / Fundo em Capitalização/Geral conforme parametrização atuarial. |
| **3** | `CO_SEXO_SEGURADO` | `VARCHAR(1)` (`'1'` ou `'2'`) | `tbl_cadastro_pessoas.SEXO` | Tradução de domínio: `'F' -> '1'`, `'M' -> '2'`, demais casos `NULL`. Obrigatório para tábuas biométricas segregadas por sexo. |
| **4** | `DT_NASC_SEGURADO` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_cadastro_pessoas.DTNASC` | Formatação padrão brasileiro via `CONVERT(VARCHAR(10), f.DTNASC, 103)`. |
| **5** | `DT_ING_ENTE` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_historico_vinculos.DTEXERC` | Conversão segura de string legada para data via `CONVERT(VARCHAR(10), TRY_CONVERT(DATETIME, i.DTEXERC, 103), 103)`. |
| **6** | `NO_CARREIRA` | `VARCHAR` | `fato_folha_cabecalho` + `dim_carreiras` | Recupera a denominação atual do cargo (`dim_carreiras.NOME`) referente à última competência financeira do vínculo (`MAX(MES_ANO)`). |

---

## 4. Garantias de Qualidade e Integridade (`1:1`)

* **Resolução de Duplicidade Histórica de Cargos:** O cubo `fato_folha_cabecalho` possui mais de 51 milhões de registros mensais. O pipeline utiliza uma CTE de pré-agregação (`CTE_ULTIMA_COMPETENCIA`) filtrada por `EXISTS` para isolar exatamente o último `MES_ANO` de cada vínculo ativo antes de cruzar com `dim_carreiras`.
* **Blindagem de Conversão:** O uso de `TRY_CONVERT(..., 103)` impede falhas de execução (*runtime errors*) diante de datas inconsistentes armazenadas como texto no sistema legado.
