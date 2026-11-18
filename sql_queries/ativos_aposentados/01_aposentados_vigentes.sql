/***********************************************************************************************
  PROJETO: AtuarialEventosBiometricos (RPPS)
  LAYOUT: 01 - Aposentados Vigentes (Não Vacanciados)
  ENGINE: Microsoft SQL Server (T-SQL)
  
  ARQUITETURA & PERFORMANCE TUNING:
  - Isolamento READ UNCOMMITTED e NOCOUNT ON para evitar Shared Locks e overhead de rede.
  - Multi-Staging Tables (#TMP) com índices clusterizados explícitos (Merge Join optimization).
  - Semi-Join via EXISTS para Predication Pushdown em views históricas de alta volumetria.
  - Late Materialization: conversões TRY_CONVERT e formatações restritas à projeção final.
  - Nota LGPD: Esquemas e views corporativas substituídos por aliases públicos padronizados.
***********************************************************************************************/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- =============================================================================================
-- MÓDULO 1: LIMPEZA PREVENTIVA DE RECURSOS NO TEMPDB (IDEMPOTÊNCIA)
-- =============================================================================================
IF OBJECT_ID('tempdb..#TMP_APOS_BASE')  IS NOT NULL DROP TABLE #TMP_APOS_BASE;
IF OBJECT_ID('tempdb..#TMP_ING_ENTE')   IS NOT NULL DROP TABLE #TMP_ING_ENTE;
IF OBJECT_ID('tempdb..#TMP_CARGOS')     IS NOT NULL DROP TABLE #TMP_CARGOS;
IF OBJECT_ID('tempdb..#TMP_FUNCS')      IS NOT NULL DROP TABLE #TMP_FUNCS;


-- =============================================================================================
-- MÓDULO 2: MATERIALIZAÇÃO DO MOTOR CENTRAL (APOSENTADOS VIGENTES NÃO VACANCIADOS)
-- Objetivo: Isolar apenas a massa de aposentados ativos no plano de benefícios (RPPS).
-- =============================================================================================
SELECT 
    v.NUMFUNC,
    v.NUMVINC,
    v.DTAPOSENT,
    v.TIPOAPOS
INTO #TMP_APOS_BASE
FROM rpps_dw.tbl_historico_vinculos v
WHERE v.REGIMEPREV = 'RPPS'
  AND v.EMP_CODIGO IN (2, 8, 91)
  AND v.DTAPOSENT IS NOT NULL
  -- Trava de Negócio: Exclui beneficiários que já encerraram/vacanciaram o vínculo
  AND (v.FORMAVAC IS NULL OR LTRIM(RTRIM(v.FORMAVAC)) = '');

CREATE CLUSTERED INDEX IX_TMP_APOS_BASE_CHAVE ON #TMP_APOS_BASE (NUMFUNC, NUMVINC);


-- =============================================================================================
-- MÓDULO 3: DETERMINAÇÃO DA DATA DE INGRESSO NO ENTE (DT_ING_ENTE)
-- Objetivo: Identificar o primeiro exercício histórico do segurado no ente federativo.
-- =============================================================================================
SELECT 
    v.NUMFUNC,
    MIN(TRY_CONVERT(DATE, v.DTEXERC, 103)) AS DT_ING_ENTE
INTO #TMP_ING_ENTE
FROM rpps_dw.tbl_historico_vinculos v
WHERE v.NUMFUNC IN (SELECT NUMFUNC FROM #TMP_APOS_BASE)
GROUP BY v.NUMFUNC;

CREATE CLUSTERED INDEX IX_TMP_ING_ENTE_CHAVE ON #TMP_ING_ENTE (NUMFUNC);


-- =============================================================================================
-- MÓDULO 4: HISTÓRICO DE CARGOS - RESOLUÇÃO DE DUPLICIDADE EM MÁSCARA TEXTUAL
-- Objetivo: Recuperar a denominação da carreira vinculada via Semi-Join (EXISTS).
-- =============================================================================================
SELECT 
    e.NUMFUNC,
    e.NUMVINC,
    MAX(c.NOME) AS NOME_CARREIRA
INTO #TMP_CARGOS
FROM rpps_dw.tbl_evolucao_funcional e
INNER JOIN rpps_dw.dim_carreiras c ON e.CARGO = c.CARGO
WHERE EXISTS (
    SELECT 1 FROM #TMP_APOS_BASE a 
    WHERE a.NUMFUNC = e.NUMFUNC AND a.NUMVINC = e.NUMVINC
)
GROUP BY e.NUMFUNC, e.NUMVINC;

CREATE CLUSTERED INDEX IX_TMP_CARGOS_CHAVE ON #TMP_CARGOS (NUMFUNC, NUMVINC);


-- =============================================================================================
-- MÓDULO 5: DADOS CADASTRAIS E BIOGRÁFICOS (SEGURADOS)
-- =============================================================================================
SELECT 
    f.NUMERO,
    f.SEXO,
    f.DTNASC
INTO #TMP_FUNCS
FROM rpps_dw.tbl_cadastro_pessoas f
WHERE f.NUMERO IN (SELECT NUMFUNC FROM #TMP_APOS_BASE);

CREATE CLUSTERED INDEX IX_TMP_FUNCS_CHAVE ON #TMP_FUNCS (NUMERO);


-- =============================================================================================
-- MÓDULO 6: PROJEÇÃO FINAL E SEGREGACÃO DE EVENTOS DE APOSENTADORIA
-- =============================================================================================
SELECT 
    CAST(i.NUMFUNC AS VARCHAR) + '-' + CAST(i.NUMVINC AS VARCHAR) AS [ID_SEGURADO_MATRICULA],
    2 AS [CO_COMP_MASSA],
    CASE f.SEXO 
        WHEN 'F' THEN '1'
        WHEN 'M' THEN '2'
        ELSE NULL 
    END AS [CO_SEXO_SEGURADO],
    CONVERT(VARCHAR(10), f.DTNASC, 103) AS [DT_NASC_SEGURADO],
    CONVERT(VARCHAR(10), e.DT_ING_ENTE, 103) AS [DT_ING_ENTE],
    
    -- Aposentadoria Programada / Voluntária / Compulsória
    CASE 
        WHEN ISNULL(i.TIPOAPOS, '') NOT LIKE 'INV%' 
         AND ISNULL(i.TIPOAPOS, '') NOT LIKE 'INC%' 
         AND ISNULL(i.TIPOAPOS, '') <> 'APOS_INVALIDEZ'
        THEN CONVERT(VARCHAR(10), TRY_CONVERT(DATETIME, i.DTAPOSENT, 103), 103)
        ELSE NULL 
    END AS [DT_APOSENTADORIA_PROGRAMADA],
    
    -- Aposentadoria por Invalidez / Incapacidade Permanente
    CASE 
        WHEN i.TIPOAPOS LIKE 'INV%' 
          OR i.TIPOAPOS LIKE 'INC%' 
          OR i.TIPOAPOS = 'APOS_INVALIDEZ'
        THEN CONVERT(VARCHAR(10), TRY_CONVERT(DATETIME, i.DTAPOSENT, 103), 103)
        ELSE NULL 
    END AS [DT_APOSENTADORIA_POR_INVALIDEZ],
    
    c.NOME_CARREIRA AS [NO_CARREIRA]

FROM #TMP_APOS_BASE i
LEFT JOIN #TMP_FUNCS f    ON i.NUMFUNC = f.NUMERO
LEFT JOIN #TMP_ING_ENTE e ON i.NUMFUNC = e.NUMFUNC
LEFT JOIN #TMP_CARGOS c   ON i.NUMFUNC = c.NUMFUNC AND i.NUMVINC = c.NUMVINC;


-- =============================================================================================
-- MÓDULO 7: DESALOCAÇÃO EXPLÍCITA DE RECURSOS NO TEMPDB
-- =============================================================================================
IF OBJECT_ID('tempdb..#TMP_APOS_BASE')  IS NOT NULL DROP TABLE #TMP_APOS_BASE;
IF OBJECT_ID('tempdb..#TMP_ING_ENTE')   IS NOT NULL DROP TABLE #TMP_ING_ENTE;
IF OBJECT_ID('tempdb..#TMP_CARGOS')     IS NOT NULL DROP TABLE #TMP_CARGOS;
IF OBJECT_ID('tempdb..#TMP_FUNCS')      IS NOT NULL DROP TABLE #TMP_FUNCS;
