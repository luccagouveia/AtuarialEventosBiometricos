SELECT TOP 100 * FROM (
    SELECT
        CONCAT(V.id_funcionario, '-', V.id_vinculo) AS ID_SEGURADO_MATRICULA,
        1 AS CO_COMP_MASSA,
        F.sexo AS CO_SEXO_SEGURADO,
        F.data_nascimento AS DT_NASC_SEGURADO,
        I.dt_ingresso_minima AS DT_ING_ENTE,
        COALESCE(TRY_CONVERT(DATE, VI.data_vacancia), TRY_CAST(VI.data_vacancia AS DATE)) AS DT_EXONERACAO,
        NULL AS DT_APOSENTADORIA_PROGRAMADA,
        NULL AS DT_APOSENTADORIA_POR_INVALIDEZ,
        CASE WHEN V.forma_vacancia = 'FALECIMENTO' THEN COALESCE(TRY_CONVERT(DATE, VI.data_vacancia), TRY_CAST(VI.data_vacancia AS DATE)) ELSE NULL END AS DT_OBITO,
        0 AS QTD_PENSIONISTAS,
        NULL AS DT_INICIO_ABONO_PERMANENCIA,
        CAR.nome_carreira AS NO_CARREIRA
    FROM [rpps_dw].[prod].[tbl_historico_vinculos] V
    INNER JOIN [rpps_dw].[prod].[tbl_controle_encerramento] VI ON V.id_funcionario = VI.id_funcionario AND V.id_vinculo = VI.id_vinculo
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
    WHERE V.regime_previdenciario = 'RPPS'
) Res
-- VALIDAÇÃO DA COORTE: Filtra a janela de tempo histórica obrigatória do layout
WHERE Res.DT_EXONERACAO BETWEEN '2015-01-01' AND '2026-05-31';
