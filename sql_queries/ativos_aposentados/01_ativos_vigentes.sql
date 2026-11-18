/***********************************************************************************************
  PROJETO: AtuarialEventosBiometricos (RPPS)
  LAYOUT: 01 - Servidores Ativos Vigentes (Granularidade 1:1)
  ENGINE: Microsoft SQL Server (T-SQL)
  
  ARQUITETURA & PERFORMANCE TUNING:
  - Isolamento READ UNCOMMITTED e NOCOUNT ON para evitar Shared Locks e overhead de rede.
  - Driver Populacional (#TMP_ATIVOS) reduz o escopo para ~113.922 chaves únicas indexadas.
  - CTE de Pré-Agregação + Semi-Join (EXISTS) elimina Full Scan de +51 milhões de linhas.
  - Late Materialization: conversões TRY_CONVERT e formatações restritas à projeção final.
  - Nota LGPD: Esquemas e views corporativas substituídos por aliases públicos padronizados.
***********************************************************************************************/

-- =============================================================================================
-- MÓDULO 1: DIRETIVAS DE SESSÃO E ISOLAMENTO DE CONCORRÊNCIA
-- Objetivo: Blindar o servidor contra travamentos (Locks) e reduzir o overhead de rede.
-- =============================================================================================
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;


-- =============================================================================================
-- MÓDULO 2: ISOLAMENTO DO MOTOR CENTRAL (DRIVER DE FILTRO POPULACIONAL)
-- Objetivo: Identificar a população exata de Ativos Vigentes Efetivos (RPPS).
-- Mecânica: Reduz o universo do banco para ~113.922 chaves únicas guardadas em disco temporário.
-- =============================================================================================
IF OBJECT_ID('tempdb..#TMP_ATIVOS') IS NOT NULL 
    DROP TABLE #TMP_ATIVOS;

SELECT 
    v.NUMFUNC,
    v.NUMVINC,
    v.DTEXERC -- Mantido em formato bruto (varchar) para conversão tardia e segura no SELECT final
INTO #TMP_ATIVOS
FROM rpps_dw.tbl_historico_vinculos v
WHERE v.REGIMEPREV = 'RPPS'                        -- Despreza comissionados exclusivos (RGPS)
  AND v.EMP_CODIGO IN (1, 2, 8)                    -- Código dos órgãos/empresas elegíveis
  AND v.FORMAVAC IS NULL                           -- Sem forma de vacância registrada
  AND (v.DTAPOSENT IS NULL OR v.TIPOAPOS IS NULL); -- Garante exclusão de aposentados

-- Transforma o Heap físico em B-Tree, forçando Index Seek nos cruzamentos seguintes
CREATE CLUSTERED INDEX IX_TMP_ATIVOS_CHAVE ON #TMP_ATIVOS (NUMFUNC, NUMVINC);


-- =============================================================================================
-- MÓDULO 3: RESOLUÇÃO DA GRANULARIDADE HISTÓRICA (CUBO DE CARGOS)
-- Objetivo: Colapsar o histórico de competências mensais (+51 milhões de linhas) para 1:1.
-- Mecânica: CTE de pré-agregação (MAX) filtrada por Predication Pushdown (EXISTS).
-- =============================================================================================
IF OBJECT_ID('tempdb..#TMP_CARGOS') IS NOT NULL 
    DROP TABLE #TMP_CARGOS;

WITH CTE_ULTIMA_COMPETENCIA AS (
    SELECT 
        h.NUMFUNC,
        h.NUMVINC,
        MAX(h.MES_ANO) AS ULTIMO_MES
    FROM rpps_dw.fato_folha_cabecalho h
    WHERE EXISTS (
        SELECT 1 FROM #TMP_ATIVOS i 
        WHERE i.NUMFUNC = h.NUMFUNC AND i.NUMVINC = h.NUMVINC
    ) -- Predication Pushdown composto: evita ler os +51 milhões de registros da fato
    GROUP BY h.NUMFUNC, h.NUMVINC
)
SELECT 
    h.NUMFUNC,
    h.NUMVINC,
    cc.NOME AS NO_CARREIRA
INTO #TMP_CARGOS
FROM rpps_dw.fato_folha_cabecalho h
INNER JOIN CTE_ULTIMA_COMPETENCIA uc ON h.NUMFUNC = uc.NUMFUNC 
                                    AND h.NUMVINC = uc.NUMVINC 
                                    AND h.MES_ANO = uc.ULTIMO_MES
INNER JOIN rpps_dw.dim_carreiras cc  ON h.CARGO = cc.CARGO;

CREATE CLUSTERED INDEX IX_TMP_CARGOS_CHAVE ON #TMP_CARGOS (NUMFUNC, NUMVINC);


-- =============================================================================================
-- MÓDULO 4: ISOLAMENTO DOS DADOS CADASTRAIS (CADASTRO DE SEGURADOS)
-- Objetivo: Capturar sexo e data de nascimento via Predication Pushdown na chave primária.
-- =============================================================================================
IF OBJECT_ID('tempdb..#TMP_FUNCIONARIOS') IS NOT NULL 
    DROP TABLE #TMP_FUNCIONARIOS;

SELECT 
    f.NUMERO,
    f.SEXO,
    f.DTNASC
INTO #TMP_FUNCIONARIOS
FROM rpps_dw.tbl_cadastro_pessoas f
WHERE f.NUMERO IN (SELECT NUMFUNC FROM #TMP_ATIVOS);

CREATE CLUSTERED INDEX IX_TMP_FUNC_CHAVE ON #TMP_FUNCIONARIOS (NUMERO);


-- =============================================================================================
-- MÓDULO 5: PROCESSAMENTO E MONTAGEM DO LAYOUT FINAL (GRANULARIDADE 1:1)
-- Objetivo: Projetar as colunas finais com saneamento tardio (Late Materialization).
-- =============================================================================================
SELECT 
    CAST(i.NUMFUNC AS VARCHAR) + '-' + CAST(i.NUMVINC AS VARCHAR) AS [ID_SEGURADO_MATRICULA],
    '1' AS [CO_COMP_MASSA],
    CASE f.SEXO 
        WHEN 'F' THEN '1'
        WHEN 'M' THEN '2'
        ELSE NULL 
    END AS [CO_SEXO_SEGURADO],
    CONVERT(VARCHAR(10), f.DTNASC, 103) AS [DT_NASC_SEGURADO],
    CONVERT(VARCHAR(10), TRY_CONVERT(DATETIME, i.DTEXERC, 103), 103) AS [DT_ING_ENTE],
    c.NO_CARREIRA AS [NO_CARREIRA]

FROM #TMP_ATIVOS i
LEFT JOIN #TMP_FUNCIONARIOS f ON i.NUMFUNC = f.NUMERO
LEFT JOIN #TMP_CARGOS c       ON i.NUMFUNC = c.NUMFUNC AND i.NUMVINC = c.NUMVINC;


-- =============================================================================================
-- MÓDULO 6: DESALOCAÇÃO EXPLÍCITA DE RECURSOS NO TEMPDB
-- =============================================================================================
DROP TABLE #TMP_ATIVOS;
DROP TABLE #TMP_CARGOS;
DROP TABLE #TMP_FUNCIONARIOS;
