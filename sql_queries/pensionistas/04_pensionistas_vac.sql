/***********************************************************************************************
  PROJETO: AtuarialEventosBiometricos (RPPS)
  LAYOUT: 04 - Pensionistas Cessados / Vacanciados (Desde 01/01/2015)
  ENGINE: Microsoft SQL Server (T-SQL)
  
  ARQUITETURA & PERFORMANCE TUNING:
  - Isolamento READ UNCOMMITTED e NOCOUNT ON para evitar Shared Locks e overhead de rede.
  - Pipeline de CTEs Modulares com Semi-Joins encadeados (WHERE EXISTS) a partir do Driver.
  - Conversão segura via TRY_CONVERT (Style 103) para filtragem temporal em colunas legadas.
  - Nota LGPD: Esquemas e views corporativas substituídos por aliases públicos padronizados.
***********************************************************************************************/

-- =============================================================================================
-- MÓDULO 1: DIRETIVAS DE SESSÃO E ISOLAMENTO DE CONCORRÊNCIA
-- =============================================================================================
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- =============================================================================================
-- MÓDULO 2: CTE DRIVER PRINCIPAL (PENSIONISTAS COM BENEFÍCIO ENCERRADO >= 2015)
-- =============================================================================================
WITH CTE_Driver_Pensionista AS (
    SELECT 
        v.NUMFUNC,
        v.NUMVINC,
        v.EMP_CODIGO,
        v.FORMAVAC,
        v.DTVAC,
        v.DTEXERC,
        v.TIPOVINC,
        TRY_CONVERT(DATETIME, v.DTVAC, 103) AS DTVAC_DATE
    FROM rpps_dw.tbl_historico_vinculos v
    WHERE v.EMP_CODIGO = 6
      -- Filtro restritivo de data retroativa a 01/01/2015 sobre campo textual
      AND TRY_CONVERT(DATETIME, v.DTVAC, 103) >= '2015-01-01'
      -- Domínio homologado de motivos de cessação (exclui 'NULO / INDEFERIDO' e 'INCLUSAO INDEVIDA')
      AND v.FORMAVAC IN (
          'FALECIMENTO', 'DECURSO DE PRAZO', 'IMPL. 21 ANOS-MANUAL', 
          'IMPLEMENTO 21 ANOS', 'RENUNCIA EXPRESSA', 'ATESTADO FACULDA...', 
          'EMANCIPACAO', 'CASAMENTO', 'INVAL / INCAP', 'OUTROS MOTIVOS', 
          'DECISAO JUDICIAL', 'PERDA COND BENEF', 'IMPLEMENTO 25 ANOS', 
          'CONCLUSAO CURSO', 'UNIAO ESTAVEL', 'OPCAO OUTRA PENSAO'
      )
),

-- =============================================================================================
-- MÓDULO 3: CTEs SECUNDÁRIAS (PONTES DE RELACIONAMENTO E CADASTRO VIA SEMI-JOIN)
-- =============================================================================================

-- 3.1 Dados Pessoais e Condição de Deficiência do Pensionista
CTE_Dados_Funcionario AS (
    SELECT 
        f.NUMERO,
        f.SEXO,
        f.DTNASC,
        f.DEFICIENTE
    FROM rpps_dw.tbl_cadastro_pessoas f
    WHERE EXISTS (
        SELECT 1 
        FROM CTE_Driver_Pensionista d 
        WHERE d.NUMFUNC = f.NUMERO
    )
),

-- 3.2 Tabela Intermediária de Beneficiários (Vínculo Pensão x Parentesco)
CTE_Iprem_Pensionistas AS (
    SELECT 
        p.NUM_PEN_FUNC,
        p.NUM_PEN_VINC,
        p.NUM_PENSAO,
        p.PARENTESCO
    FROM rpps_dw.tbl_beneficiarios_previdenciarios p
    WHERE EXISTS (
        SELECT 1 
        FROM CTE_Driver_Pensionista d 
        WHERE p.NUM_PEN_FUNC = d.NUMFUNC 
          AND p.NUM_PEN_VINC = d.NUMVINC
    )
),

-- 3.3 Tabela do Instituidor / Legador (Matrícula e Óbito do Segurado Original)
CTE_Iprem_Legador AS (
    SELECT 
        l.NUM_PENSAO,
        l.NUM_MATRICULA_LEGADOR,
        l.DATA_OBITO
    FROM rpps_dw.tbl_instituidor_legador l
    WHERE EXISTS (
        SELECT 1 
        FROM CTE_Iprem_Pensionistas p 
        WHERE l.NUM_PENSAO = p.NUM_PENSAO
    )
)

-- =============================================================================================
-- MÓDULO 4: PROJEÇÃO FINAL E REGRAS DE CLASSIFICAÇÃO PREVIDENCIÁRIA
-- =============================================================================================
SELECT 
    -- Dados do Instituidor (Legador)
    leg.NUM_MATRICULA_LEGADOR AS [ID_INSTITUIDOR_MATRICULA],
    leg.DATA_OBITO            AS [DT_OBITO_INSTITUIDOR],
    
    -- Composição da Massa
    '1'                       AS [CO_COMP_MASSA],
    
    -- Identificação e Datas do Pensionista
    CONCAT(drv.NUMFUNC, drv.NUMVINC) AS [ID_PENSIONISTA_MATRICULA],
    
    CASE 
        WHEN func.SEXO = 'F' THEN '1'
        WHEN func.SEXO = 'M' THEN '2'
        ELSE NULL 
    END                       AS [CO_SEXO_PENSIONISTA],
    
    func.DTNASC               AS [DT_NASC_PENSIONISTA],
    drv.DTEXERC               AS [DT_INICIO_PENSAO],
    drv.DTVAC                 AS [DT_FIM_PENSAO],
    
    -- Data de Óbito condicional à vacância por falecimento
    CASE 
        WHEN drv.FORMAVAC = 'FALECIMENTO' THEN drv.DTVAC 
        ELSE NULL 
    END                       AS [DT_OBITO_PENSIONISTA],
    
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

FROM CTE_Driver_Pensionista drv
LEFT JOIN CTE_Dados_Funcionario func
    ON drv.NUMFUNC = func.NUMERO
LEFT JOIN CTE_Iprem_Pensionistas pens 
    ON drv.NUMFUNC = pens.NUM_PEN_FUNC 
   AND drv.NUMVINC = pens.NUM_PEN_VINC
LEFT JOIN CTE_Iprem_Legador leg 
    ON pens.NUM_PENSAO = leg.NUM_PENSAO;
