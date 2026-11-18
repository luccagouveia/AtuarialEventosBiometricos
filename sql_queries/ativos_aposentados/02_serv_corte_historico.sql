/***********************************************************************************************
  PROJETO: AtuarialEventosBiometricos (RPPS)
  LAYOUT: 02 - Coorte Histórica de Desligamentos e Eventos Biométricos (2015–2026)
  ENGINE: Microsoft SQL Server (T-SQL)
  
  ARQUITETURA & PERFORMANCE TUNING:
  - Isolamento READ UNCOMMITTED e NOCOUNT ON para leitura sem bloqueios (Zero Shared Locks).
  - Driver Populacional Externo (#TMP_RPPS) + Multi-Staging Tables com CLUSTERED INDEX.
  - Predication Pushdown (EXISTS) nas views de pensionistas e evolução de cargos.
  - Conditional Aggregation (MAX + CASE) no Módulo 7 para garantir granularidade 1:1 
    e precedência estrita entre eventos biométricos (Aposentadoria -> Óbito vs. Exoneração).
  - Nota LGPD: Esquemas, views e matrículas reais substituídos por aliases e exemplos fictícios.
***********************************************************************************************/

-- =============================================================================================
-- MÓDULO 0: CARGA DA LISTA DE CONTROLE DE ELEGIBILIDADE RPPS (#TMP_RPPS)
-- Nota: Em produção, esta tabela recebe a carga em lote (Batch Insert) das chaves elegíveis.
-- =============================================================================================
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#TMP_RPPS') IS NOT NULL DROP TABLE #TMP_RPPS;
CREATE TABLE #TMP_RPPS (
    NUMFUNC INT,
    NUMVINC INT
);

-- Exemplo ilustrativo de carga (chaves reais omitidas por conformidade LGPD)
INSERT INTO #TMP_RPPS (NUMFUNC, NUMVINC) VALUES 
(1000001, 1),
(1000002, 2),
(1000003, 1);

CREATE CLUSTERED INDEX IX_TMP_RPPS_CHAVE ON #TMP_RPPS (NUMFUNC, NUMVINC);


-- =============================================================================================
-- MÓDULO 1: LIMPEZA PREVENTIVA DE RECURSOS NO TEMPDB (IDEMPOTÊNCIA)
-- =============================================================================================
IF OBJECT_ID('tempdb..#TMP_CORTE_BASE')   IS NOT NULL DROP TABLE #TMP_CORTE_BASE;
IF OBJECT_ID('tempdb..#TMP_ING_ENTE')     IS NOT NULL DROP TABLE #TMP_ING_ENTE;
IF OBJECT_ID('tempdb..#TMP_PENS_CONTA')   IS NOT NULL DROP TABLE #TMP_PENS_CONTA;
IF OBJECT_ID('tempdb..#TMP_CARGOS_CORTE') IS NOT NULL DROP TABLE #TMP_CARGOS_CORTE;
IF OBJECT_ID('tempdb..#TMP_FUNCS_CORTE')  IS NOT NULL DROP TABLE #TMP_FUNCS_CORTE;


-- =============================================================================================
-- MÓDULO 2: MOTOR CENTRAL (DRIVERS DE CORTE - VACÂNCIAS HOMOLOGADAS + LISTA RPPS)
-- Objetivo: Filtrar desligamentos ocorridos entre 01/01/2015 e 31/05/2026 com saneamento
--           textual de múltiplos espaços na coluna FORMAVAC.
-- =============================================================================================
SELECT 
    v.NUMFUNC, 
    v.NUMVINC, 
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(v.FORMAVAC, ''), '  ', ' '), '  ', ' '), '  ', ' '))) AS FORMAVAC_LIMPO,
    ISNULL(v.TIPOAPOS, '') AS TIPOAPOS, 
    v.DTAPOSENT,
    v.EMP_CODIGO,
    CAST(vi.DTVAC AS DATE) AS DATA_VACANCIA_FINAL
INTO #TMP_CORTE_BASE
FROM rpps_dw.tbl_historico_vinculos v
INNER JOIN (SELECT DISTINCT NUMFUNC, NUMVINC FROM #TMP_RPPS) r
    ON v.NUMFUNC = r.NUMFUNC 
   AND v.NUMVINC = r.NUMVINC
INNER JOIN rpps_dw.tbl_detalhe_vacancias vi 
    ON v.NUMFUNC = vi.NUMFUNC 
   AND v.NUMVINC = vi.NUMVINC
WHERE v.EMP_CODIGO IN (1, 2, 8, 91)
  AND v.FORMAVAC IS NOT NULL
  AND vi.DTVAC IS NOT NULL 
  AND vi.DTVAC >= '2015-01-01'
  AND vi.DTVAC <= '2026-05-31 23:59:59'
  AND LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(v.FORMAVAC, '  ', ' '), '  ', ' '), '  ', ' '))) IN (
        -- A) Domínio de Óbito (10 códigos)
        'FALECIMENTO', 'FAL VIA SISOBI', 'FAL NAO SISOBI', 'FAL VIA SIRC',
        'FAL ANTES SEGREG', 'FAL PMSP_DEBITO', 'MORTE PRESUMIDA',
        'FAL EXER ATIV PROF', 'DECLARADO VAGO FAL', 'APOSEN / FALECIM',

        -- B) Domínio de Exoneração / Desligamento em Vida (38 códigos - exclui 'EXON CONV ADMINISTR')
        'EXON PEDIDO OU CONV', 'EXONERACAO A PEDIDO',
        'EXONERACAO', 'EXON CUMP JUDICIAL', 'EXO/RESC/DISP TRANS',
        'EXO EST PROB L13530', 'EXON TRANSF CARGO', 'EXON/RESC APOS RGPS',
        'EXO_NOM RETROATIVA', 'EXO P_UNI_A194_L8989', 'EXE FATO APO 70 ANOS',
        'DEMISSAO HISTORI', 'DEMIS PA FALTAS', 'DEMISSAO',
        'DEMIS BEM SER PUBL', 'DEMIS_A25_III L13530', 'DEM_A7_15_16 L13530',
        'DEMISS BEM SER PUBL', 'DEM_A140L8989 L13530', 'D_A7_15_16_19 L13530',
        'D188III_178_179L8989', 'DEMIS PERDA FUNC', 'DEM_A184_A188_L8989',
        'DEMISS L16488 A6_IV', 'DEMIS_A28_II L 13530', 'DEMIS/ VAC LIM CASS',
        'DEMIS_A6_IV L 16488', 'D_A188_A178_A179_L89', 'VAC SEM CONTR SMS',
        'VACANCIA HISTORICA', 'VAC SEM CONTR', 'VAC A PEDIDO',
        'VAC EXERC DE FATO', 'VAC LIMINAR CASSADA', 'VAC PORT ANUL EX MED',
        'VAC SUSP LIMINAR', 'VAC COMP MAND SEG', 'VAC NOM ANUL VICIO',

        -- C) Domínio Condicional (1 código - garantido inativo pois FORMAVAC IS NOT NULL)
        'VAC EF SUSP REINTEG'
  );

CREATE CLUSTERED INDEX IX_TMP_CORTE_BASE_CHAVE ON #TMP_CORTE_BASE(NUMFUNC, NUMVINC);


-- =============================================================================================
-- MÓDULO 3: DETERMINAÇÃO DA DATA DE INGRESSO NO ENTE (DT_ING_ENTE)
-- =============================================================================================
SELECT 
    v.NUMFUNC,
    MIN(TRY_CONVERT(DATE, v.DTEXERC, 103)) AS DT_ING_ENTE
INTO #TMP_ING_ENTE
FROM rpps_dw.tbl_historico_vinculos v
WHERE v.NUMFUNC IN (SELECT NUMFUNC FROM #TMP_CORTE_BASE)
GROUP BY v.NUMFUNC;

CREATE CLUSTERED INDEX IX_TMP_ING_ENTE_CHAVE ON #TMP_ING_ENTE(NUMFUNC);


-- =============================================================================================
-- MÓDULO 4: CONTAGEM DE PENSIONISTAS POR VÍNCULO DO INSTITUIDOR (QTD_PENSIONISTAS)
-- Regra Atuarial: Contagem por indivíduo único (COUNT DISTINCT), nunca por benefício/processo.
-- =============================================================================================
SELECT 
    p.NUM_MATRICULA_LEGADOR AS NUMFUNC,
    p.NUM_VINCULO_LEGADOR   AS NUMVINC,
    COUNT(DISTINCT p.NUM_PEN_FUNC) AS QTD_REAL_PENSIONISTAS
INTO #TMP_PENS_CONTA
FROM rpps_dw.tbl_beneficiarios_previdenciarios p
WHERE EXISTS (
    SELECT 1 
    FROM #TMP_CORTE_BASE c 
    WHERE p.NUM_MATRICULA_LEGADOR = c.NUMFUNC 
      AND p.NUM_VINCULO_LEGADOR = c.NUMVINC
)
GROUP BY p.NUM_MATRICULA_LEGADOR, p.NUM_VINCULO_LEGADOR;

CREATE CLUSTERED INDEX IX_TMP_PENS_CONTA_CHAVE ON #TMP_PENS_CONTA(NUMFUNC, NUMVINC);


-- =============================================================================================
-- MÓDULO 5: HISTÓRICO DE CARGOS / CARREIRA (NO_CARREIRA)
-- =============================================================================================
SELECT 
    e.NUMFUNC,
    e.NUMVINC,
    MAX(c.NOME) AS NOME_CARREIRA
INTO #TMP_CARGOS_CORTE
FROM rpps_dw.tbl_evolucao_funcional e
INNER JOIN rpps_dw.dim_carreiras c 
    ON e.CARGO = c.CARGO
WHERE EXISTS (
    SELECT 1 
    FROM #TMP_CORTE_BASE a 
    WHERE a.NUMFUNC = e.NUMFUNC 
      AND a.NUMVINC = e.NUMVINC
)
GROUP BY e.NUMFUNC, e.NUMVINC;

CREATE CLUSTERED INDEX IX_TMP_CARGOS_CORTE_CHAVE ON #TMP_CARGOS_CORTE(NUMFUNC, NUMVINC);


-- =============================================================================================
-- MÓDULO 6: DADOS CADASTRAIS DO SEGURADO (SEXO E DATA DE NASCIMENTO)
-- =============================================================================================
SELECT 
    f.NUMERO,
    f.SEXO,
    f.DTNASC
INTO #TMP_FUNCS_CORTE
FROM rpps_dw.tbl_cadastro_pessoas f
WHERE f.NUMERO IN (SELECT NUMFUNC FROM #TMP_CORTE_BASE);

CREATE CLUSTERED INDEX IX_TMP_FUNCS_CORTE_CHAVE ON #TMP_FUNCS_CORTE(NUMERO);


-- =============================================================================================
-- MÓDULO 7: PROJEÇÃO FINAL (PRECEDÊNCIA DE EVENTOS BIOMÉTRICOS E GRANULARIDADE 1:1)
-- =============================================================================================
SELECT 
    CAST(i.NUMFUNC AS VARCHAR(20)) + '-' + CAST(i.NUMVINC AS VARCHAR(10)) AS [ID_SEGURADO_MATRICULA],
    1 AS [CO_COMP_MASSA], 
    
    CASE MAX(f.SEXO)
        WHEN 'F' THEN '1'
        WHEN 'M' THEN '2'
        ELSE NULL 
    END AS [CO_SEXO_SEGURADO],
    
    CONVERT(VARCHAR(10), MAX(f.DTNASC), 103) AS [DT_NASC_SEGURADO],
    CONVERT(VARCHAR(10), MAX(ing.DT_ING_ENTE), 103) AS [DT_ING_ENTE],
    
    -- Exclusividade Mútua: Preenche DT_EXONERACAO apenas se NÃO houver óbito no vínculo
    CASE 
        WHEN MAX(CASE WHEN i.FORMAVAC_LIMPO IN (
                'FALECIMENTO', 'FAL VIA SISOBI', 'FAL NAO SISOBI', 'FAL VIA SIRC',
                'FAL ANTES SEGREG', 'FAL PMSP_DEBITO', 'MORTE PRESUMIDA',
                'FAL EXER ATIV PROF', 'DECLARADO VAGO FAL', 'APOSEN / FALECIM'
            ) THEN i.DATA_VACANCIA_FINAL ELSE NULL END) IS NOT NULL 
        THEN NULL
        ELSE CONVERT(VARCHAR(10), MAX(
            CASE 
                WHEN i.FORMAVAC_LIMPO IN (
                    'EXON PEDIDO OU CONV', 'EXONERACAO A PEDIDO',
                    'EXONERACAO', 'EXON CUMP JUDICIAL', 'EXO/RESC/DISP TRANS',
                    'EXO EST PROB L13530', 'EXON TRANSF CARGO', 'EXON/RESC APOS RGPS',
                    'EXO_NOM RETROATIVA', 'EXO P_UNI_A194_L8989', 'EXE FATO APO 70 ANOS',
                    'DEMISSAO HISTORI', 'DEMIS PA FALTAS', 'DEMISSAO',
                    'DEMIS BEM SER PUBL', 'DEMIS_A25_III L13530', 'DEM_A7_15_16 L13530',
                    'DEMISS BEM SER PUBL', 'DEM_A140L8989 L13530', 'D_A7_15_16_19 L13530',
                    'D188III_178_179L8989', 'DEMIS PERDA FUNC', 'DEM_A184_A188_L8989',
                    'DEMISS L16488 A6_IV', 'DEMIS_A28_II L 13530', 'DEMIS/ VAC LIM CASS',
                    'DEMIS_A6_IV L 16488', 'D_A188_A178_A179_L89', 'VAC SEM CONTR SMS',
                    'VACANCIA HISTORICA', 'VAC SEM CONTR', 'VAC A PEDIDO',
                    'VAC EXERC DE FATO', 'VAC LIMINAR CASSADA', 'VAC PORT ANUL EX MED',
                    'VAC SUSP LIMINAR', 'VAC COMP MAND SEG', 'VAC NOM ANUL VICIO',
                    'VAC EF SUSP REINTEG'
                ) THEN i.DATA_VACANCIA_FINAL
                ELSE NULL
            END
        ), 103)
    END AS [DT_EXONERACAO],
    
    -- Aposentadoria Programada (preservada mesmo se houver óbito posterior)
    CONVERT(VARCHAR(10), MAX(
        CASE 
            WHEN (i.EMP_CODIGO = 91 OR i.TIPOAPOS <> '')
             AND i.TIPOAPOS NOT LIKE 'INV%' 
             AND i.TIPOAPOS NOT LIKE 'INC%' 
             AND i.TIPOAPOS <> 'APOS_INVALIDEZ'
            THEN TRY_CONVERT(DATETIME, i.DTAPOSENT, 103)
            ELSE NULL 
        END
    ), 103) AS [DT_APOSENTADORIA_PROGRAMADA],
    
    -- Aposentadoria por Invalidez (preservada mesmo se houver óbito posterior)
    CONVERT(VARCHAR(10), MAX(
        CASE 
            WHEN (i.EMP_CODIGO = 91 OR i.TIPOAPOS <> '')
             AND (i.TIPOAPOS LIKE 'INV%' OR i.TIPOAPOS LIKE 'INC%' OR i.TIPOAPOS = 'APOS_INVALIDEZ')
            THEN TRY_CONVERT(DATETIME, i.DTAPOSENT, 103)
            ELSE NULL 
        END
    ), 103) AS [DT_APOSENTADORIA_POR_INVALIDEZ],
    
    -- Data de Óbito (Domínio A)
    CONVERT(VARCHAR(10), MAX(
        CASE
            WHEN i.FORMAVAC_LIMPO IN (
                'FALECIMENTO', 'FAL VIA SISOBI', 'FAL NAO SISOBI', 'FAL VIA SIRC',
                'FAL ANTES SEGREG', 'FAL PMSP_DEBITO', 'MORTE PRESUMIDA',
                'FAL EXER ATIV PROF', 'DECLARADO VAGO FAL', 'APOSEN / FALECIM'
            ) THEN i.DATA_VACANCIA_FINAL
            ELSE NULL
        END
    ), 103) AS [DT_OBITO],
    
    ISNULL(MAX(p.QTD_REAL_PENSIONISTAS), 0) AS [QTD_PENSIONISTAS],
    MAX(c.NOME_CARREIRA) AS [NO_CARREIRA]

FROM #TMP_CORTE_BASE i
LEFT JOIN #TMP_FUNCS_CORTE f      ON i.NUMFUNC = f.NUMERO
LEFT JOIN #TMP_ING_ENTE ing       ON i.NUMFUNC = ing.NUMFUNC
LEFT JOIN #TMP_CARGOS_CORTE c     ON i.NUMFUNC = c.NUMFUNC AND i.NUMVINC = c.NUMVINC
LEFT JOIN #TMP_PENS_CONTA p       ON i.NUMFUNC = p.NUMFUNC AND i.NUMVINC = p.NUMVINC
GROUP BY i.NUMFUNC, i.NUMVINC;


-- =============================================================================================
-- MÓDULO 8: DESALOCAÇÃO DE RECURSOS NO TEMPDB
-- =============================================================================================
IF OBJECT_ID('tempdb..#TMP_CORTE_BASE')   IS NOT NULL DROP TABLE #TMP_CORTE_BASE;
IF OBJECT_ID('tempdb..#TMP_ING_ENTE')     IS NOT NULL DROP TABLE #TMP_ING_ENTE;
IF OBJECT_ID('tempdb..#TMP_PENS_CONTA')   IS NOT NULL DROP TABLE #TMP_PENS_CONTA;
IF OBJECT_ID('tempdb..#TMP_CARGOS_CORTE') IS NOT NULL DROP TABLE #TMP_CARGOS_CORTE;
IF OBJECT_ID('tempdb..#TMP_FUNCS_CORTE')  IS NOT NULL DROP TABLE #TMP_FUNCS_CORTE;
IF OBJECT_ID('tempdb..#TMP_RPPS')         IS NOT NULL DROP TABLE #TMP_RPPS;
