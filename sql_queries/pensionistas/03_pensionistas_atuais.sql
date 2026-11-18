/***********************************************************************************************
  PROJETO: AtuarialEventosBiometricos (RPPS)
  LAYOUT: 03 - Pensionistas Atuais Vigentes (Granularidade 1:1 por Beneficiário)
  ENGINE: Microsoft SQL Server (T-SQL)
  
  ARQUITETURA & PERFORMANCE TUNING:
  - Isolamento READ UNCOMMITTED e NOCOUNT ON para leitura sem bloqueios (Zero Shared Locks).
  - Multi-Staging Tables (#TMP) com CLUSTERED INDEX nas chaves compostas (NUMFUNC, NUMVINC) 
    e na chave de pensão (NUM_PENSAO), forçando Merge Joins ordenados.
  - Predication Pushdown (EXISTS) nas tabelas de cadastro, beneficiários e instituidores.
  - Late Materialization: concatenação de chaves e traduções de domínio na projeção final.
  - Nota LGPD: Esquemas e views corporativas substituídos por aliases públicos padronizados.
***********************************************************************************************/

-- =============================================================================================
-- MÓDULO 1: DIRETIVAS DE SESSÃO E ISOLAMENTO DE CONCORRÊNCIA
-- =============================================================================================
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- Limpeza preventiva de recursos no TempDB (Idempotência)
IF OBJECT_ID('tempdb..#TMP_PENS_ATIVOS') IS NOT NULL DROP TABLE #TMP_PENS_ATIVOS;
IF OBJECT_ID('tempdb..#TMP_PENS_FUNC')   IS NOT NULL DROP TABLE #TMP_PENS_FUNC;
IF OBJECT_ID('tempdb..#TMP_PENS_RELAC')  IS NOT NULL DROP TABLE #TMP_PENS_RELAC;
IF OBJECT_ID('tempdb..#TMP_PENS_LEG')    IS NOT NULL DROP TABLE #TMP_PENS_LEG;


-- =============================================================================================
-- MÓDULO 2: ISOLAMENTO DO MOTOR CENTRAL (DRIVER DE PENSIONISTAS VIGENTES)
-- Objetivo: Filtrar vínculos exclusivos de pensionistas (EMP_CODIGO = 6) ativos no plano.
-- =============================================================================================
SELECT 
    v.NUMFUNC,
    v.NUMVINC,
    v.EMP_CODIGO,
    v.DTEXERC,
    v.TIPOVINC
INTO #TMP_PENS_ATIVOS
FROM rpps_dw.tbl_historico_vinculos v
WHERE v.EMP_CODIGO = 6
  -- Trava de Vigência: Apenas beneficiários sem vacância ou data de encerramento registrada
  AND (v.FORMAVAC IS NULL OR LTRIM(RTRIM(v.FORMAVAC)) = '')
  AND v.DTVAC IS NULL;

CREATE CLUSTERED INDEX IX_TMP_PENS_ATIVOS_CHAVE ON #TMP_PENS_ATIVOS (NUMFUNC, NUMVINC);


-- =============================================================================================
-- MÓDULO 3: DADOS CADASTRAIS E BIOGRÁFICOS DO PENSIONISTA (PREDICATION PUSHDOWN)
-- =============================================================================================
SELECT 
    f.NUMERO,
    f.SEXO,
    f.DTNASC,
    f.DEFICIENTE
INTO #TMP_PENS_FUNC
FROM rpps_dw.tbl_cadastro_pessoas f
WHERE EXISTS (
    SELECT 1 
    FROM #TMP_PENS_ATIVOS d 
    WHERE d.NUMFUNC = f.NUMERO
);

CREATE CLUSTERED INDEX IX_TMP_PENS_FUNC_CHAVE ON #TMP_PENS_FUNC (NUMERO);


-- =============================================================================================
-- MÓDULO 4: RELAÇÃO DE DEPENDÊNCIA / PARENTESCO (PONTE DE PENSÃO)
-- =============================================================================================
SELECT 
    p.NUM_PEN_FUNC,
    p.NUM_PEN_VINC,
    p.NUM_PENSAO,
    p.PARENTESCO
INTO #TMP_PENS_RELAC
FROM rpps_dw.tbl_beneficiarios_previdenciarios p
WHERE EXISTS (
    SELECT 1 
    FROM #TMP_PENS_ATIVOS d 
    WHERE p.NUM_PEN_FUNC = d.NUMFUNC 
      AND p.NUM_PEN_VINC = d.NUMVINC
);

CREATE CLUSTERED INDEX IX_TMP_PENS_RELAC_CHAVE ON #TMP_PENS_RELAC (NUM_PEN_FUNC, NUM_PEN_VINC);


-- =============================================================================================
-- MÓDULO 5: DADOS DO INSTITUIDOR / LEGADOR ORIGINAL
-- =============================================================================================
SELECT 
    l.NUM_PENSAO,
    l.NUM_MATRICULA_LEGADOR,
    l.DATA_OBITO
INTO #TMP_PENS_LEG
FROM rpps_dw.tbl_instituidor_legador l
WHERE EXISTS (
    SELECT 1 
    FROM #TMP_PENS_RELAC p 
    WHERE l.NUM_PENSAO = p.NUM_PENSAO
);

CREATE CLUSTERED INDEX IX_TMP_PENS_LEG_CHAVE ON #TMP_PENS_LEG (NUM_PENSAO);


-- =============================================================================================
-- MÓDULO 6: PROJEÇÃO FINAL DO LAYOUT DE PENSIONISTAS VIGENTES (1:1 POR BENEFICIÁRIO)
-- =============================================================================================
SELECT 
    -- Dados do Instituidor (Legador)
    leg.NUM_MATRICULA_LEGADOR AS [ID_INSTITUIDOR_MATRICULA],
    CONVERT(VARCHAR(10), TRY_CONVERT(DATETIME, leg.DATA_OBITO, 103), 103) AS [DT_OBITO_INSTITUIDOR],
    
    -- Composição da Massa
    '1'                       AS [CO_COMP_MASSA],
    
    -- Identificação e Dados Biográficos do Pensionista (Late Materialization)
    CAST(drv.NUMFUNC AS VARCHAR(20)) + '-' + CAST(drv.NUMVINC AS VARCHAR(10)) AS [ID_PENSIONISTA_MATRICULA],
    
    CASE 
        WHEN func.SEXO = 'F' THEN '1'
        WHEN func.SEXO = 'M' THEN '2'
        ELSE NULL 
    END                       AS [CO_SEXO_PENSIONISTA],
    
    CONVERT(VARCHAR(10), func.DTNASC, 103) AS [DT_NASC_PENSIONISTA],
    CONVERT(VARCHAR(10), TRY_CONVERT(DATETIME, drv.DTEXERC, 103), 103) AS [DT_INICIO_PENSAO],
    
    -- De-Para Homologado de Tipo de Relação / Parentesco
    CASE 
        WHEN pens.PARENTESCO = 'FILHO (A)' AND func.DEFICIENTE = 'S' THEN '3'
        WHEN pens.PARENTESCO = 'FILHO (A)' AND (func.DEFICIENTE <> 'S' OR func.DEFICIENTE IS NULL) THEN '2'
        WHEN pens.PARENTESCO IN ('CONJUGE', 'COMPANHEIRO (A)', 'EX ESPOSA') THEN '1'
        WHEN pens.PARENTESCO = 'GENITOR (A)' THEN '4'
        WHEN pens.PARENTESCO = 'IRMAO (A)' THEN '5'
        ELSE '6' -- Outros (Tutelado, Madrasta, Legatário, Enteado, Neto, Menor sob Guarda, etc.)
    END                       AS [CO_TIPO_RELACAO],
    
    -- Condição do Pensionista (2 = Inválido/Deficiente, 1 = Válido)
    CASE 
        WHEN func.DEFICIENTE = 'S' THEN '2'
        ELSE '1'
    END                       AS [CO_CONDICAO],
    
    -- Tipo de Duração do Benefício
    drv.TIPOVINC              AS [CO_DURACAO]

FROM #TMP_PENS_ATIVOS drv
LEFT JOIN #TMP_PENS_FUNC func
    ON drv.NUMFUNC = func.NUMERO
LEFT JOIN #TMP_PENS_RELAC pens 
    ON drv.NUMFUNC = pens.NUM_PEN_FUNC 
   AND drv.NUMVINC = pens.NUM_PEN_VINC
LEFT JOIN #TMP_PENS_LEG leg 
    ON pens.NUM_PENSAO = leg.NUM_PENSAO;


-- =============================================================================================
-- MÓDULO 7: DESALOCAÇÃO EXPLÍCITA DE RECURSOS NO TEMPDB
-- =============================================================================================
IF OBJECT_ID('tempdb..#TMP_PENS_ATIVOS') IS NOT NULL DROP TABLE #TMP_PENS_ATIVOS;
IF OBJECT_ID('tempdb..#TMP_PENS_FUNC')   IS NOT NULL DROP TABLE #TMP_PENS_FUNC;
IF OBJECT_ID('tempdb..#TMP_PENS_RELAC')  IS NOT NULL DROP TABLE #TMP_PENS_RELAC;
IF OBJECT_ID('tempdb..#TMP_PENS_LEG')    IS NOT NULL DROP TABLE #TMP_PENS_LEG;
