/***********************************************************************************************
  PROJETO: AtuarialEventosBiometricos (RPPS)
  LAYOUT: 04 - Histórico Legado de Pensionistas Cessados e Óbitos (Desde 01/01/2015)
  ENGINE: Microsoft SQL Server (T-SQL)
  
  ARQUITETURA & PERFORMANCE TUNING:
  - Isolamento READ UNCOMMITTED e NOCOUNT ON para leitura sem bloqueios (Zero Shared Locks).
  - Filtro Precoce (CTE_Filtro_Base) + Predication Pushdown na tabela histórica de legadores.
  - Segregação mutuamente exclusiva entre cessação em vida (BEN_TIPO <> '1') e óbito ('1').
  - Late Materialization: concatenação de chaves compostas restrita à projeção final.
  - Nota LGPD: Bancos, esquemas e tabelas legadas substituídos por aliases padronizados.
***********************************************************************************************/

-- =============================================================================================
-- MÓDULO 1: DIRETIVAS DE SESSÃO E ISOLAMENTO DE CONCORRÊNCIA
-- =============================================================================================
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- =============================================================================================
-- MÓDULO 2: FILTRO PRECOCE (DRIVER DE CHAVES CESSADAS >= 2015)
-- =============================================================================================
WITH CTE_Filtro_Base AS (
    SELECT DISTINCT 
        B.LEG_NUMERO
    FROM rpps_dw.tbl_historico_beneficiarios_legado B
    WHERE B.BEN_DTCESSA IS NOT NULL
      AND B.BEN_DTCESSA >= '2015-01-01'
),

-- =============================================================================================
-- MÓDULO 3: EXTRAÇÃO SECUNDÁRIA VIA PREDICATION PUSHDOWN
-- =============================================================================================

-- 3.1 Histórico de Instituidores / Legadores (Apenas chaves filtradas)
CTE_Secundario_Legador AS (
    SELECT 
        L.LEG_REGFUNC,
        L.LEG_DTOBITO
    FROM rpps_dw.tbl_historico_legadores_legado L
    WHERE L.LEG_REGFUNC IN (SELECT LEG_NUMERO FROM CTE_Filtro_Base)
),

-- 3.2 Atributos dos Beneficiários Cessados (Single Scan na janela temporal)
CTE_Secundario_Beneficiario AS (
    SELECT 
        B.LEG_NUMERO,
        B.BEN_CODIGO,
        B.COD_SEXO_BENF,
        B.BEN_DATNASC,
        B.BEN_DTINPEN,
        B.BEN_DTCESSA,
        B.PRT_CODIGO,
        B.BEN_CDINVAL,
        B.BEN_TIPO
    FROM rpps_dw.tbl_historico_beneficiarios_legado B
    WHERE B.LEG_NUMERO IN (SELECT LEG_NUMERO FROM CTE_Filtro_Base)
      AND B.BEN_DTCESSA IS NOT NULL
      AND B.BEN_DTCESSA >= '2015-01-01'
)

-- =============================================================================================
-- MÓDULO 4: PROJEÇÃO FINAL E SEGREGAÇÃO DE EVENTOS DE ENCERRAMENTO
-- =============================================================================================
SELECT
    -- Dados do Instituidor (Legado)
    L.LEG_REGFUNC                               AS [ID_INSTITUIDOR_MATRICULA],
    L.LEG_DTOBITO                               AS [DT_OBITO_INSTITUIDOR],
    
    -- Composição da Massa (Tipagem explícita)
    CAST(NULL AS INT)                           AS [CO_COMP_MASSA], 

    -- Identificação e Dados Biográficos do Pensionista (Late Materialization)
    CONCAT(B.LEG_NUMERO, '-', B.BEN_CODIGO)     AS [ID_PENSIONISTA_MATRICULA],
    B.COD_SEXO_BENF                             AS [CO_SEXO_PENSIONISTA],
    B.BEN_DATNASC                               AS [DT_NASC_PENSIONISTA],
    B.BEN_DTINPEN                               AS [DT_INICIO_PENSAO],
    
    -- Segregação Mutuamente Exclusiva: Encerramento em Vida vs. Óbito do Pensionista
    CASE WHEN B.BEN_TIPO <> '1' THEN B.BEN_DTCESSA ELSE NULL END AS [DT_FIM_PENSAO],
    CASE WHEN B.BEN_TIPO = '1'  THEN B.BEN_DTCESSA ELSE NULL END AS [DT_OBITO_PENSIONISTA],
    
    -- Classificações Previdenciárias
    B.PRT_CODIGO                                AS [CO_TIPO_RELACAO],
    B.BEN_CDINVAL                               AS [CO_CONDICAO],
    B.BEN_TIPO                                  AS [CO_DURACAO]

FROM CTE_Secundario_Beneficiario B
LEFT JOIN CTE_Secundario_Legador L 
    ON B.LEG_NUMERO = L.LEG_REGFUNC;
