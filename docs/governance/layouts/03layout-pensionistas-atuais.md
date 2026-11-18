# 📋 Especificação Técnica de Layout — 03: Pensionistas Atuais Vigentes

**Script SQL Correspondente:** `sql_queries/pensionistas/03_pensionistas_atuais.sql`  
**Granularidade:** `1:1` por beneficiário de pensão vigente (`NUMFUNC-NUMVINC`)  
**Fundamentação Normativa:** Portaria MTP nº 1.467/2022 (Art. 5º; Art. 36; Art. 42; Art. 47)

---

## 1. Objetivo Atuarial

Consolidar a base cadastral e demográfica dos dependentes em gozo ativo de pensão por morte no RPPS, vinculando cada beneficiário ao seu respectivo segurado instituidor (legador). Este layout é utilizado para projetar a extinção futura dos benefícios (por mortalidade ou implemento de idade/condição) e apurar as provisões matemáticas de pensões concedidas.

---

## 2. Critérios de Elegibilidade e Escopo Populacional

Para compor o driver populacional (`#TMP_PENS_ATIVOS`) na fonte `rpps_dw.tbl_historico_vinculos`, o vínculo deve atender simultaneamente a:

1. **Identificador de Pensionista:** `EMP_CODIGO = 6` (código reservado exclusivamente aos vínculos de pensionistas na estrutura funcional).
2. **Trava de Vigência:** `(FORMAVAC IS NULL OR LTRIM(RTRIM(FORMAVAC)) = '')` e `DTVAC IS NULL` (garante que apenas beneficiários com pensão ativa e sem encerramento registrado sejam extraídos).

---

## 3. Dicionário de Campos e Regras de Transformação

| Ordem | Campo de Saída | Tipo / Formato | Origem (Alias Público) | Regra de Negócio e Transformação SQL |
| :---: | :--- | :--- | :--- | :--- |
| **1** | `ID_INSTITUIDOR_MATRICULA` | `INT / BIGINT` | `tbl_instituidor_legador.NUM_MATRICULA_LEGADOR` | Matrícula funcional do segurado falecido originador da pensão, obtida via ponte `NUM_PENSAO`. |
| **2** | `DT_OBITO_INSTITUIDOR` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_instituidor_legador.DATA_OBITO` | Data de falecimento do instituidor formatada via `CONVERT(VARCHAR(10), TRY_CONVERT(DATETIME, DATA_OBITO, 103), 103)`. |
| **3** | `CO_COMP_MASSA` | `VARCHAR(1)` (`'1'`) | Constante de Negócio | Valor fixo `'1'` (Massa Civil / Geral). |
| **4** | `ID_PENSIONISTA_MATRICULA` | `VARCHAR` (`NUMFUNC-NUMVINC`) | `tbl_historico_vinculos` | Chave composta do vínculo do pensionista concatenada na projeção final. |
| **5** | `CO_SEXO_PENSIONISTA` | `VARCHAR(1)` (`'1'` ou `'2'`) | `tbl_cadastro_pessoas.SEXO` | Tradução de domínio: `'F' -> '1'`, `'M' -> '2'`, demais casos `NULL`. |
| **6** | `DT_NASC_PENSIONISTA` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_cadastro_pessoas.DTNASC` | Formatação padrão brasileiro via `CONVERT(VARCHAR(10), func.DTNASC, 103)`. |
| **7** | `DT_INICIO_PENSAO` | `VARCHAR(10)` (`DD/MM/AAAA`) | `tbl_historico_vinculos.DTEXERC` | Data de início de vigência do benefício (`CONVERT(VARCHAR(10), TRY_CONVERT(DATETIME, DTEXERC, 103), 103)`). |
| **8** | `CO_TIPO_RELACAO` | `VARCHAR(1)` (`'1'` a `'6'`) | `tbl_beneficiarios_previdenciarios.PARENTESCO` + `DEFICIENTE` | Tabela de De-Para homologada (detalhada na Seção 4). |
| **9** | `CO_CONDICAO` | `VARCHAR(1)` (`'1'` ou `'2'`) | `tbl_cadastro_pessoas.DEFICIENTE` | `'2'` se `DEFICIENTE = 'S'` (Inválido/Deficiente); `'1'` caso contrário (Válido). |
| **10** | `CO_DURACAO` | `VARCHAR` | `tbl_historico_vinculos.TIPOVINC` | Código nativo indicador da natureza de duração do vínculo (vitalícia ou temporária). |

---

## 4. Tabela de Domínio: Grau de Parentesco (`CO_TIPO_RELACAO`)

A classificação do dependente cruza o grau de parentesco (`PARENTESCO`) com a condição de invalidez (`DEFICIENTE`) para permitir a aplicação das regras de cessação etária vs. vitaliciedade:

| Código | Categoria Atuarial | Regra de Mapeamento SQL |
| :---: | :--- | :--- |
| **`1`** | Cônjuge / Companheiro(a) | `PARENTESCO IN ('CONJUGE', 'COMPANHEIRO (A)', 'EX ESPOSA')` |
| **`2`** | Filho(a) Válido(a) | `PARENTESCO = 'FILHO (A)' AND (DEFICIENTE <> 'S' OR DEFICIENTE IS NULL)` |
| **`3`** | Filho(a) Inválido(a) / Deficiente | `PARENTESCO = 'FILHO (A)' AND DEFICIENTE = 'S'` |
| **`4`** | Genitor(a) (Pai / Mãe) | `PARENTESCO = 'GENITOR (A)'` |
| **`5`** | Irmão(ã) | `PARENTESCO = 'IRMAO (A)'` |
| **`6`** | Outros Dependentes | Demais casos (`Tutelado`, `Madrasta`, `Legatário`, `Enteado`, `Neto`, `Menor sob Guarda`, etc.) |
