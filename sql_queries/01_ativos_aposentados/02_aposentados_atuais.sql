SELECT TOP 100 * FROM (
    SELECT
        CONCAT(V.id_funcionario, '-', V.id_vinculo) AS ID_SEGURADO_MATRICULA,
        1 AS CO_COMP_MASSA,
        F.sexo AS CO_SEXO_SEGURADO,
        F.data_nascimento AS DT_NASC_SEGURADO,
        I.dt_ingresso_minima AS DT_ING_ENTE,
        NULL AS DT_EXONERACAO,
        CASE 
            WHEN (V.forma_vacancia IN ('APOSENTADORIA RPPS', 'EXE FATO APO 70 ANOS', 'APOSEN DEF CUMP JUD', 'APOSEN PROV CUMP JUD', 'APOSEN / CASSACAO')
                OR (V.tipo_aposentadoria IS NOT NULL AND V.tipo_aposentadoria NOT LIKE 'INV%' AND V.tipo_aposentadoria NOT LIKE 'INC%' AND V.tipo_aposentadoria <> 'APOS_INVALIDEZ' AND V.tipo_aposentadoria <> 'CANCEL EFEITOS APOS' AND V.tipo_aposentadoria <> 'CASSACAO APOSENT'))
                AND V.forma_vacancia NOT IN ('INVAL / INCAP', 'APOSENT INV RGPS')
            THEN COALESCE(TRY_CONVERT(DATE, V.dt_aposentadoria_texto, 103), TRY_CONVERT(DATE, V.dt_aposentadoria_texto, 120), TRY_CAST(V.dt_aposentadoria_texto AS DATE))
            ELSE NULL 
        END AS DT_APOSENTADORIA_PROGRAMADA,
        CASE 
            WHEN V.forma_vacancia IN ('INVAL / INCAP', 'APOSENT INV RGPS') OR V.tipo_aposentadoria = 'APOS_INVALIDEZ' OR V.tipo_aposentadoria LIKE 'INV%' OR V.tipo_aposentadoria LIKE 'INC%'
            THEN COALESCE(TRY_CONVERT(DATE, V.dt_aposentadoria_texto, 103), TRY_CONVERT(DATE, V.dt_aposentadoria_texto, 120), TRY_CAST(V.dt_aposentadoria_texto AS DATE))
            ELSE NULL 
        END AS DT_APOSENTADORIA_POR_INVALIDEZ,
        NULL AS DT_OBITO,
        0 AS QTD_PENSIONISTAS, 
        NULL AS DT_INICIO_ABONO_PERMANENCIA,
        CAR.nome_carreira AS NO_CARREIRA
    FROM (
        SELECT id_funcionario, id_vinculo, regime_previdenciario, forma_vacancia, tipo_aposentadoria, dt_aposentadoria_texto, id_empresa
        FROM [rpps_dw].[prod].[tbl_historico_vinculos]
        WHERE regime_previdenciario = 'RPPS'
          AND (
            forma_vacancia IN ('APOSENTADORIA RPPS', 'EXE FATO APO 70 ANOS', 'APOSEN DEF CUMP JUD', 'APOSEN PROV CUMP JUD', 'APOSEN / CASSACAO', 'INVAL / INCAP', 'APOSENT INV RGPS')
            OR (tipo_aposentadoria IS NOT NULL AND tipo_aposentadoria <> '' AND tipo_aposentadoria <> 'CANCEL EFEITOS APOS')
          )
    ) V
    INNER JOIN [rpps_dw].[prod].[tbl_cadastro_biografico] F ON V.id_funcionario = F.id_biografico
    LEFT JOIN (
        SELECT id_funcionario, MIN(CASE WHEN data_exercicio LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' THEN TRY_CONVERT(DATE, data_exercicio, 103) ELSE TRY_CONVERT(DATE, data_exercicio, 120) END) AS dt_ingresso_minima 
        FROM [rpps_dw].[prod].[tbl_historico_vinculos] 
        GROUP BY id_funcionario
    ) I ON V.id_funcionario = I.id_funcionario
    LEFT JOIN (
        SELECT id_funcionario, id_vinculo, nome_carreira 
        FROM (
            SELECT e.id_funcionario, e.id_vinculo, c.nome_cargo AS nome_carreira, 
                   ROW_NUMBER() OVER (PARTITION BY e.id_funcionario, e.id_vinculo ORDER BY CASE WHEN e.data_fim IS NULL THEN 1 ELSE 0 END DESC, e.data_inicio DESC) AS RN 
            FROM [rpps_dw].[prod].[tbl_evolucao_cargos] e 
            INNER JOIN [rpps_dw].[prod].[dim_cargos] c ON e.id_cargo = c.id_cargo
        ) HistCargos WHERE RN = 1
    ) CAR ON V.id_funcionario = CAR.id_funcionario AND V.id_vinculo = CAR.id_vinculo
) Res
-- REGRA DE INTEGRIDADE: Bloqueia e descarta registros que não possuam nenhuma data de aposentadoria convertida com sucesso
WHERE Res.DT_APOSENTADORIA_PROGRAMADA IS NOT NULL OR Res.DT_APOSENTADORIA_POR_INVALIDEZ IS NOT NULL;
